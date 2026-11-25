import BatteriesCore
import BatteriesUI
import ServiceManagement
import SwiftUI

/// The app's one window, laid out like System Settings: devices in the sidebar, the selected
/// device's alerts on the right, General last.
struct SettingsView: View {
  enum Pane: Hashable {
    case device(String)
    case general
  }

  @Bindable var monitor: Monitor
  @State var selection: Pane?

  /// The owner's order: drag rows in the sidebar to change it. The widget follows it.
  private var devices: [Known] { monitor.snapshot.devices }

  var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        Section("Devices") {
          ForEach(devices) { known in
            SidebarRow(known: known, alertsOn: monitor.settings.alerts.rules[known.id] != nil)
              .tag(Pane.device(known.id))
          }
          .onMove { monitor.move(from: $0, to: $1) }
        }
        Section {
          Label("General", systemImage: "gearshape").tag(Pane.general)
        }
      }
      .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
    } detail: {
      switch selection {
      case .device(let id):
        if let known = devices.first(where: { $0.id == id }) {
          DeviceDetail(known: known, monitor: monitor).id(id)
        } else {
          ContentUnavailableView("No Device", systemImage: "battery.0percent")
        }
      case .general:
        GeneralPane()
      case nil:
        ContentUnavailableView("No Batteries Yet", systemImage: "battery.100percent",
                               description: Text("Devices appear here once macOS reports their battery."))
      }
    }
    .frame(minWidth: 680, minHeight: 480)
    .onAppear { selection = selection ?? devices.first.map { .device($0.id) } ?? .general }
  }
}

extension PartRole {
  var title: String {
    switch self {
    case .main: "Battery"
    case .left: "Left"
    case .right: "Right"
    case .case: "Case"
    }
  }

  /// For the one-line sidebar summary: "L 77% · R 77% · Case 99%".
  var short: String {
    switch self {
    case .left: "L"
    case .right: "R"
    default: title
    }
  }
}

extension Known {
  /// One item per battery, buds always apart: each has its own rule.
  var items: [BatteryItem] { Snapshot(devices: [self]).items(now: .now, splitBuds: true) }
  var isMultiPart: Bool { device.parts.count > 1 }
}

private struct SidebarRow: View {
  let known: Known
  let alertsOn: Bool

  var body: some View {
    HStack(spacing: 8) {
      if let first = Snapshot(devices: [known]).items(now: .now).first {
        BatteryRing(item: first).frame(width: 24, height: 24)
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(known.device.name).lineLimit(1)
        Text(summary).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
      }
      Spacer(minLength: 0)
      if alertsOn {
        Image(systemName: "bell.fill").font(.caption2).foregroundStyle(.secondary).help("Alerts on")
      }
    }
    .padding(.vertical, 2)
  }

  private var summary: String {
    let values = known.device.parts
      .map { known.isMultiPart ? "\($0.role.short) \($0.percent)%" : "\($0.percent)%" }
      .joined(separator: " · ")
    return known.live ? values : "\(values) · Away"
  }
}

private struct DeviceDetail: View {
  let known: Known
  @Bindable var monitor: Monitor
  @State private var role: PartRole
  @State private var confirmForget = false

  init(known: Known, monitor: Monitor) {
    self.known = known
    self.monitor = monitor
    _role = State(initialValue: known.device.parts.first?.role ?? .main)
  }

  private var rule: Binding<AlertRule> {
    Binding(
      get: { monitor.settings.alerts.rule(device: known.id, role: role) },
      set: { monitor.settings.alerts.setRule($0, device: known.id, role: role) })
  }

  var body: some View {
    Form {
      Section { DeviceHeader(known: known) }
      if known.isMultiPart {
        Section {
          Picker("Battery", selection: $role) {
            ForEach(known.device.parts, id: \.role) { Text($0.role.title).tag($0.role) }
          }
          .pickerStyle(.segmented)
        } footer: {
          Text("Each battery has its own alerts.")
        }
      }
      Section {
        Toggle("Low Battery Alert", isOn: isOn(\.low, start: AlertRule.startLow))
        if rule.wrappedValue.low != nil { LevelPicker(title: "Alert At or Below", value: rule.low) }
      } footer: {
        Text("Alerts when the level falls to this point while discharging.")
      }
      Section {
        Toggle("Charged Alert", isOn: isOn(\.high, start: AlertRule.startHigh))
        if rule.wrappedValue.high != nil { LevelPicker(title: "Alert At or Above", value: rule.high) }
      } footer: {
        Text("Alerts when the level reaches this point while charging.")
      }
      styleSection
      Section {
        Button("Forget This Device…", role: .destructive) { confirmForget = true }
      } footer: {
        Text("Removes its last value and alerts from Batteries only. It stays paired and appears again when it next reports its battery.")
      }
    }
    .formStyle(.grouped)
    .navigationTitle(known.device.name)
    .confirmationDialog("Forget \(known.device.name)?", isPresented: $confirmForget) {
      Button("Forget", role: .destructive) { monitor.forget(known.id) }
    } message: {
      Text("Its last value and alerts are removed from Batteries. It stays paired and appears again when it next reports its battery.")
    }
  }

  private var styleSection: some View {
    let circle = Binding(
      get: { rule.wrappedValue.style != .notification },
      set: { rule.wrappedValue.style = $0 ? .circle : .notification })
    let autoHide = Binding(
      get: { rule.wrappedValue.style == .circle },
      set: { rule.wrappedValue.style = $0 ? .circle : .circleUntilClicked })
    return Section {
      Picker("Show As", selection: circle) {
        Text("Notification").tag(false)
        Text("Circle on Screen").tag(true)
      }
      if circle.wrappedValue {
        Toggle("Hide After 3 Seconds", isOn: autoHide)
      }
      LabeledContent("Preview") {
        HStack {
          Button("Low Battery") { monitor.preview(known.device, role: role, kind: .low) }
          Button("Charged") { monitor.preview(known.device, role: role, kind: .high) }
        }
      }
    } footer: {
      if circle.wrappedValue { Text("A ring in the centre of the screen, red for low, green for charged. A click always closes it.") }
    }
  }

  /// A side's switch: on starts at the usual level, off clears it.
  private func isOn(_ side: WritableKeyPath<AlertRule, Int?>, start: Int) -> Binding<Bool> {
    Binding(
      get: { rule.wrappedValue[keyPath: side] != nil },
      set: { rule.wrappedValue[keyPath: side] = $0 ? start : nil })
  }
}

private struct DeviceHeader: View {
  let known: Known

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 3) {
        Text(known.device.name).font(.title3.weight(.semibold))
        status.font(.callout).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      ForEach(known.items) { item in
        VStack(spacing: 4) {
          BatteryRing(item: item).frame(width: 44, height: 44)
          Text("\(item.percent)%").font(.callout.weight(.medium)).monospacedDigit()
          if known.isMultiPart { Text(item.role.title).font(.caption).foregroundStyle(.secondary) }
        }
      }
    }
    .padding(.vertical, 4)
  }

  private var status: Text {
    guard known.live else {
      return Text("Not connected · seen \(known.seenAt, format: .relative(presentation: .named))")
    }
    if known.device.parts.contains(where: \.charging) { return Text("Charging") }
    return Text(known.device.kind == .mac ? "This Mac" : "Connected")
  }
}

/// A level in steps of 5, as a menu: compact, and every value one click away.
private struct LevelPicker: View {
  let title: String
  @Binding var value: Int?

  var body: some View {
    Picker(title, selection: Binding(get: { value ?? AlertRule.startLow }, set: { value = $0 })) {
      ForEach(Array(stride(from: 5, through: 100, by: 5)), id: \.self) { Text("\($0)%").tag($0) }
    }
    .monospacedDigit()
  }
}

private struct GeneralPane: View {
  @State private var openAtLogin = SMAppService.mainApp.status == .enabled
  @State private var loginError: String?
  @State private var checksForUpdates = Updater.shared.checksAutomatically
  @State private var checking = false

  var body: some View {
    Form {
      Section {
        Toggle("Open at Login", isOn: Binding(get: { openAtLogin }, set: { setLoginItem($0) }))
        if let loginError { Text(loginError).foregroundStyle(.red).font(.callout) }
      } footer: {
        Text("Batteries runs in the background with no menu bar icon. Open it again from Applications to come back here.")
      }
      Section {
        LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
        // Also how appctl finds this app's releases: it reads the repository URL from the binary.
        Link("Source Code on GitHub", destination: URL(string: "https://github.com/Erel3/batteries")!)
      }
      Section {
        Toggle("Check for Updates Automatically", isOn: Binding(get: { checksForUpdates }, set: {
          Updater.shared.checksAutomatically = $0
          checksForUpdates = $0
        }))
        LabeledContent("Updates") {
          Button("Check Now") {
            checking = true
            Task {
              await Updater.shared.check(silent: false)
              checking = false
            }
          }
          .disabled(checking)
        }
      } footer: {
        Text("Looks at GitHub every 12 hours and shows what changed. Nothing installs until you click Install Update.")
      }
      Section {
        Button("Quit Batteries") { NSApp.terminate(nil) }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("General")
  }

  private func setLoginItem(_ enabled: Bool) {
    do {
      if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
      loginError = nil
    } catch {
      loginError = error.localizedDescription
    }
    openAtLogin = SMAppService.mainApp.status == .enabled
  }
}
