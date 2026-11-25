import AppKit
import BatteriesCore
import Observation
import os
import SwiftUI
import WidgetKit

/// The owner's settings, kept as one JSON value in the app's own defaults. Each battery's alert
/// rule, style included, lives in `alerts`; a `style` key saved by the first build is ignored.
struct AppSettings: Codable, Equatable {
  var alerts = AlertSettings()

  private static let key = "settings"

  static func load() -> AppSettings {
    UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? AppSettings()
  }

  func save() {
    UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key)
  }
}

/// Reads every source on its own schedule, keeps the last-known snapshot in the App Group container
/// for the widget, and raises alerts.
/// Power sources: every 60 s. They only report what bluetoothd already holds, so a read costs no radio time.
/// iPhone: every 5 min, over usbmuxd. Both again on wake.
@MainActor @Observable
final class Monitor {
  private(set) var snapshot: Snapshot
  var settings: AppSettings {
    didSet { if persist { settings.save() } }
  }

  @ObservationIgnored private var engine = AlertEngine()
  @ObservationIgnored private let presenter = AlertPresenter()
  @ObservationIgnored private var phoneBusy = false
  /// A phone connected or left while a read was running: read once more when it ends.
  @ObservationIgnored private var phoneAgain = false
  @ObservationIgnored private let log = Logger(subsystem: "com.akim.batteries", category: "monitor")
  /// False for tests: nothing read from or written to the owner's settings and group container.
  @ObservationIgnored private let persist: Bool

  init() {
    snapshot = Snapshot.load(from: Store.snapshotURL)
    settings = AppSettings.load()
    persist = true
  }

  init(snapshot: Snapshot, settings: AppSettings) {
    self.snapshot = snapshot
    self.settings = settings
    persist = false
  }

  func start() {
    // A newly installed widget has no timeline until its app asks for one; values alone may not change.
    if persist { WidgetCenter.shared.reloadAllTimelines() }
    Task {
      while !Task.isCancelled {
        refreshPowerSources()
        try? await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
      }
    }
    Task {
      while !Task.isCancelled {
        await refreshPhone()
        try? await Task.sleep(for: .seconds(300), tolerance: .seconds(30))
      }
    }
    listenForPhones()
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshPowerSources()
        Task { await self?.refreshPhone() }
      }
    }
  }

  func refreshPowerSources() {
    apply(PowerSources.read(), from: .powerSources)
  }

  func refreshPhone() async {
    guard !phoneBusy else {
      phoneAgain = true
      return
    }
    phoneBusy = true
    defer { phoneBusy = false }
    repeat {
      phoneAgain = false
      // Blocking socket reads with 10 s timeouts: keep them off the main thread.
      apply(await Task.detached { IPhoneBattery.read() }.value, from: .iphone)
    } while phoneAgain
  }

  /// usbmuxd announces each iPhone that connects or leaves, by cable or Wi-Fi: read it then,
  /// not only on the 5 min timer, which can keep missing a phone that is reachable most of the time.
  /// One idle local socket on its own thread; reconnects if usbmuxd restarts. Runs for the app's
  /// lifetime, as the monitor does.
  private func listenForPhones() {
    let monitor = self
    let thread = Thread {
      while true {
        do {
          try Usbmux.listen {
            Task { @MainActor in await monitor.refreshPhone() }
          }
        } catch {
          Thread.sleep(forTimeInterval: 10)
        }
      }
    }
    thread.name = "usbmuxd listen"
    thread.start()
  }

  /// The owner dragged a device in the sidebar: the widget shows the same order.
  func move(from source: IndexSet, to destination: Int) {
    snapshot.devices.move(fromOffsets: source, toOffset: destination)
    save(reloadWidget: true)
  }

  /// Drops a device from the last-known list, e.g. a phone that is no longer the owner's.
  func forget(_ id: String) {
    snapshot.devices.removeAll { $0.id == id }
    settings.alerts.rules[id] = nil
    save(reloadWidget: true)
  }

  /// Shows the alert this battery would raise, in its style, at its level (or the level a switched-off
  /// side starts at), so the owner sees the result while configuring.
  func preview(_ device: Device, role: PartRole, kind: AlertKind) {
    let rule = settings.alerts.rule(device: device.id, role: role)
    let percent = kind == .low ? rule.low ?? AlertRule.startLow : rule.high ?? AlertRule.startHigh
    presenter.show(Self.alertItem(device, role: role, percent: percent, charging: kind == .high), kind: kind, style: rule.style)
  }

  private static func alertItem(_ device: Device, role: PartRole, percent: Int, charging: Bool) -> BatteryItem {
    let name = role == .main ? device.name : "\(device.name) \(role.rawValue.capitalized)"
    return BatteryItem(deviceID: device.id, name: name, kind: device.kind, role: role, percent: percent, charging: charging, live: true)
  }

  private func apply(_ readings: [Device], from source: Source) {
    let now = Date.now
    let before = snapshot.items(now: now)
    snapshot.merge(readings, from: source, at: now)
    for device in readings {
      for alert in engine.evaluate(device, settings: settings.alerts) {
        let item = Self.alertItem(device, role: alert.role, percent: alert.percent, charging: device.part(alert.role)?.charging ?? false)
        presenter.show(item, kind: alert.kind, style: alert.style)
      }
    }
    save(reloadWidget: snapshot.items(now: now) != before)
  }

  /// Saved on every read, so the widget can tell a fresh value from one the app stopped refreshing.
  /// The widget itself reloads only when something it draws changed: WidgetKit rations reloads.
  private func save(reloadWidget: Bool) {
    guard persist else { return }
    snapshot.updated = .now
    do {
      try snapshot.save(to: Store.snapshotURL)
    } catch {
      log.error("cannot save snapshot: \(error.localizedDescription, privacy: .public)")
    }
    if reloadWidget { WidgetCenter.shared.reloadAllTimelines() }
  }
}
