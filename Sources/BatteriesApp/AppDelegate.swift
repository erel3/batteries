import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  let monitor = Monitor()
  private var window: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
    NSApp.mainMenu = Self.mainMenu()
    monitor.start()
    // Started at login: stay quiet. Started by hand: show where the app is.
    if SMAppService.mainApp.status != .enabled { showSettings() }
  }

  /// Opening the already running app from Finder or Spotlight lands here.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showSettings()
    return false
  }

  private func showSettings() {
    if window == nil {
      let window = Self.settingsWindow(SettingsView(monitor: monitor))
      window.setFrameAutosaveName("Settings")
      self.window = window
    }
    NSApp.activate()
    window?.makeKeyAndOrderFront(nil)
  }

  /// An agent app shows no menu bar, but key equivalents still come from its main menu:
  /// without one, ⌘W and ⌘Q do nothing. ⌘W closes the window and keeps alerts running;
  /// ⌘Q quits, as everywhere else.
  static func mainMenu() -> NSMenu {
    let app = NSMenu()
    app.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    app.addItem(withTitle: "Quit Batteries", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let root = NSMenuItem()
    root.submenu = app
    let menu = NSMenu()
    menu.addItem(root)
    return menu
  }

  static func settingsWindow(_ view: SettingsView) -> NSWindow {
    let window = NSWindow(contentViewController: NSHostingController(rootView: view))
    window.title = "Batteries"
    // System Settings look: sidebar running to the top, title in a unified toolbar.
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
    window.toolbar = NSToolbar()
    window.toolbarStyle = .unified
    window.isReleasedWhenClosed = false
    window.setContentSize(NSSize(width: 720, height: 540))
    window.center()
    return window
  }

  /// An agent app counts as frontmost while its settings window is open; show banners anyway.
  nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                          willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }
}
