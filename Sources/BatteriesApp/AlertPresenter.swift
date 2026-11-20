import AppKit
import BatteriesCore
import BatteriesUI
import os
import SwiftUI
import UserNotifications

/// Shows an alert as a system notification or as a ring in the centre of the screen.
/// Centre alerts queue one at a time, never take focus, and close on a click. `.circle` also
/// closes by itself after 3 s; `.circleUntilClicked` waits for the click.
@MainActor
final class AlertPresenter {
  private struct Pending {
    let item: BatteryItem
    let kind: AlertKind
    let untilClicked: Bool
  }

  private var queue: [Pending] = []
  private var panel: NSPanel?
  private let log = Logger(subsystem: "com.akim.batteries", category: "alerts")

  func show(_ item: BatteryItem, kind: AlertKind, style: AlertStyle) {
    switch style {
    case .notification:
      notify(item, kind: kind)
    case .circle, .circleUntilClicked:
      queue.append(Pending(item: item, kind: kind, untilClicked: style == .circleUntilClicked))
      if panel == nil { showNext() }
    }
  }

  /// Asks for permission the first time a notification is due; later calls return the stored answer.
  private func notify(_ item: BatteryItem, kind: AlertKind) {
    let content = UNMutableNotificationContent()
    content.title = item.name
    content.body = "\(kind == .low ? "Low Battery" : "Charged") · \(item.percent)%"
    content.sound = .default
    // One notification per battery: a newer alert replaces the older one.
    let request = UNNotificationRequest(identifier: item.id, content: content, trigger: nil)
    Task {
      let center = UNUserNotificationCenter.current()
      do {
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
        try await center.add(request)
      } catch {
        log.error("notification not shown: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private func showNext() {
    guard !queue.isEmpty else {
      panel = nil
      return
    }
    let next = queue.removeFirst()
    let panel = makePanel(AlertHUDView(item: next.item, kind: next.kind, untilClicked: next.untilClicked))
    self.panel = panel
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    // The shadow follows the drawn (rounded) shape only once drawn.
    panel.display()
    panel.invalidateShadow()
    NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
    guard !next.untilClicked else { return }
    Task {
      try? await Task.sleep(for: .seconds(3))
      close(panel)
    }
  }

  /// Fades `panel` out and moves on. A click and the timer can both ask; only the first counts.
  private func close(_ panel: NSPanel) {
    guard self.panel === panel, panel.isVisible else { return }
    panel.ignoresMouseEvents = true
    Task {
      await NSAnimationContext.runAnimationGroup { $0.duration = 0.3; panel.animator().alphaValue = 0 }
      panel.orderOut(nil)
      showNext()
    }
  }

  private func makePanel(_ content: some View) -> NSPanel {
    let host = NSHostingView(rootView: content)
    let size = host.fittingSize
    let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    effect.material = .hudWindow
    effect.state = .active
    // A layer corner radius leaves the blur and the window shadow square at the corners;
    // a mask image clips both.
    effect.maskImage = Self.roundedMask(radius: 24)
    host.frame = effect.bounds
    host.autoresizingMask = [.width, .height]
    effect.addSubview(host)
    let catcher = ClickCatcher(frame: effect.bounds)
    catcher.autoresizingMask = [.width, .height]
    effect.addSubview(catcher)

    let panel = NSPanel(contentRect: effect.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    catcher.onClick = { [weak self, weak panel] in
      if let panel { self?.close(panel) }
    }
    panel.contentView = effect
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .statusBar
    panel.isMovable = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    if let screen = NSScreen.main?.frame {
      panel.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2))
    }
    return panel
  }

  /// Stretchable rounded rect: corners kept, middle stretched to any size.
  private static func roundedMask(radius: CGFloat) -> NSImage {
    let side = radius * 2 + 1
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
  }
}

/// Takes the first click even though the panel never becomes key, so one click always closes it.
private final class ClickCatcher: NSView {
  var onClick: (() -> Void)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseDown(with event: NSEvent) {
    onClick?()
  }
}
