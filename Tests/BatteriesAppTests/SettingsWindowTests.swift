import AppKit
import BatteriesCore
@testable import BatteriesApp
import XCTest

/// Lays out the real settings window off screen for each pane. Fails if a pane cannot be drawn.
/// `BATTERIES_RENDER_DIR=/some/dir swift test` also writes PNGs to look at.
@MainActor
final class SettingsWindowTests: XCTestCase {
  func testPanesRender() throws {
    let now = Date.now
    var snapshot = Snapshot()
    snapshot.merge([
      Device(id: "mac", name: "MacBook Pro", kind: .mac, parts: [Part(role: .main, percent: 80, charging: false)]),
      Device(id: "pods", name: "AirPods Pro", kind: .headphones, parts: [
        Part(role: .left, percent: 77, charging: true), Part(role: .right, percent: 75, charging: true),
        Part(role: .case, percent: 99, charging: false)
      ]),
      Device(id: "kb", name: "Keychron K8 HE", kind: .keyboard, parts: [Part(role: .main, percent: 18, charging: false)])
    ], from: .powerSources, at: now)
    snapshot.merge([Device(id: "phone", name: "iPhone", kind: .phone, parts: [Part(role: .main, percent: 54, charging: false)])],
                   from: .iphone, at: now.addingTimeInterval(-7200))
    snapshot.merge([], from: .iphone, at: now)
    var settings = AppSettings()
    settings.alerts.setRule(AlertRule(low: 20, high: 100, style: .circleUntilClicked), device: "pods", role: .left)
    settings.alerts.setRule(AlertRule(low: 10), device: "kb", role: .main)
    let monitor = Monitor(snapshot: snapshot, settings: settings)

    let panes: [(String, SettingsView.Pane)] = [("settings-pods", .device("pods")), ("settings-kb", .device("kb")),
                                                ("settings-phone", .device("phone")), ("settings-general", .general)]
    for (name, pane) in panes {
      let window = AppDelegate.settingsWindow(SettingsView(monitor: monitor, selection: pane))
      // Tests run on the owner's Mac: the window is never ordered in. macOS pulls a window placed
      // off screen back onto a display when it is ordered in. Not ordered in, the sidebar draws
      // no rows; the detail pane is what this checks.
      window.setContentSize(NSSize(width: 720, height: 860))
      window.layoutIfNeeded()
      RunLoop.main.run(until: .now.addingTimeInterval(0.4))
      XCTAssertFalse(window.isVisible, "must never show on screen")
      let view = try XCTUnwrap(window.contentView?.superview)
      let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: rep)
      XCTAssertGreaterThan(rep.pixelsWide, 600, name)
      if let dir = ProcessInfo.processInfo.environment["BATTERIES_RENDER_DIR"] {
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(filePath: dir).appending(path: "\(name).png"))
      }
    }
  }
}
