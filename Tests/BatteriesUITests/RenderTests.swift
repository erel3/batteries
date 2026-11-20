import AppKit
import BatteriesCore
@testable import BatteriesUI
import SwiftUI
import WidgetKit
import XCTest

/// Renders every widget size and the centre alert off screen. Fails if a view cannot render or a
/// glyph name does not exist. `BATTERIES_RENDER_DIR=/some/dir swift test` also writes PNGs to look at.
@MainActor
final class RenderTests: XCTestCase {
  static let items = [
    BatteryItem(deviceID: "mac", name: "MacBook Pro", kind: .mac, role: .main, percent: 80, charging: false, live: true),
    BatteryItem(deviceID: "pods", name: "AirPods Pro", kind: .headphones, role: .main, percent: 77, charging: true, live: true),
    BatteryItem(deviceID: "pods", name: "AirPods Pro Case", kind: .headphones, role: .case, percent: 99, charging: false, live: true),
    BatteryItem(deviceID: "kb", name: "Keychron K8 HE", kind: .keyboard, role: .main, percent: 18, charging: false, live: true),
    BatteryItem(deviceID: "mouse", name: "Keychron M3 mini 4K", kind: .mouse, role: .main, percent: 44, charging: false, live: true),
    BatteryItem(deviceID: "phone", name: "iPhone", kind: .phone, role: .main, percent: 54, charging: false, live: false)
  ]

  func testEverySymbolExists() {
    let roles: [PartRole] = [.main, .left, .right, .case]
    let kinds: [DeviceKind] = [.mac, .phone, .headphones, .keyboard, .mouse, .gamepad, .other]
    for kind in kinds {
      for name in ["AirPods Pro", "AirPods", "AirPods Max", "WF-1000XM4"] {
        for role in roles {
          let item = BatteryItem(deviceID: "x", name: name, kind: kind, role: role, percent: 50, charging: false, live: true)
          XCTAssertNotNil(NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil), "\(item.symbol) for \(name) \(role)")
        }
      }
    }
  }

  func testCurrentBatteriesWinSlotsInTheOwnersOrder() {
    // items[5] (iPhone) is greyed: with 5 slots it loses to the five current ones.
    let mixed = [Self.items[5]] + Self.items.prefix(5)
    XCTAssertEqual(BatteriesWidgetView.fit(mixed, slots: 5).map(\.deviceID), Self.items.prefix(5).map(\.deviceID))
    XCTAssertEqual(BatteriesWidgetView.fit(mixed, slots: 6).map(\.deviceID), mixed.map(\.deviceID), "room for all: order untouched")
    XCTAssertEqual(BatteriesWidgetView.fit([Self.items[5], Self.items[0]], slots: 2).map(\.deviceID), ["phone", "mac"])
    // mac, pods, pods case, kb: one slot short, the case goes first.
    XCTAssertEqual(BatteriesWidgetView.fit(Array(Self.items.prefix(4)), slots: 3).map(\.role), [.main, .main, .main])
    XCTAssertEqual(BatteriesWidgetView.fit(Array(Self.items.prefix(4)), slots: 3).map(\.deviceID), ["mac", "pods", "kb"])
  }

  func testWidgetSizesAndAlertRender() throws {
    struct Case {
      let name: String
      let family: WidgetFamily
      let size: CGSize
      let items: [BatteryItem]
    }
    let cases = [
      Case(name: "small-one", family: .systemSmall, size: CGSize(width: 170, height: 170), items: [Self.items[0]]),
      Case(name: "small", family: .systemSmall, size: CGSize(width: 170, height: 170), items: Self.items),
      Case(name: "medium", family: .systemMedium, size: CGSize(width: 364, height: 170), items: Self.items),
      Case(name: "large", family: .systemLarge, size: CGSize(width: 364, height: 382), items: Self.items)
    ]
    for test in cases {
      let view = BatteriesWidgetView(items: test.items, family: test.family)
        .padding(16)
        .frame(width: test.size.width, height: test.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
      try render(view, name: test.name)
    }
    try render(AlertHUDView(item: Self.items[3], kind: .low).background(Color(nsColor: .windowBackgroundColor)), name: "hud-low")
  }

  private func render(_ view: some View, name: String) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try XCTUnwrap(renderer.cgImage, name)
    XCTAssertGreaterThan(image.width, 100, name)
    guard let dir = ProcessInfo.processInfo.environment["BATTERIES_RENDER_DIR"] else { return }
    let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    try png.write(to: URL(filePath: dir).appending(path: "\(name).png"))
  }
}
