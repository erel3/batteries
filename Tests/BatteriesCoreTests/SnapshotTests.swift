import XCTest
@testable import BatteriesCore

final class SnapshotTests: XCTestCase {
  let keyboard = Device(id: "kb", name: "Keyboard", kind: .keyboard, parts: [Part(role: .main, percent: 60, charging: false)])
  let phone = Device(id: "iphone-1", name: "iPhone", kind: .phone, parts: [Part(role: .main, percent: 54, charging: false)])
  let t0 = Date(timeIntervalSince1970: 1_000)
  let t1 = Date(timeIntervalSince1970: 2_000)

  func testAwayDeviceKeepsLastValueAndAge() {
    var snapshot = Snapshot()
    snapshot.merge([keyboard], from: .powerSources, at: t0)
    snapshot.merge([], from: .powerSources, at: t1)
    XCTAssertEqual(snapshot.devices.count, 1)
    XCTAssertFalse(snapshot.devices[0].live)
    XCTAssertEqual(snapshot.devices[0].seenAt, t0)
    XCTAssertEqual(snapshot.devices[0].device.parts[0].percent, 60)
  }

  func testOneSourceNeverMarksAnothersDevicesAway() {
    var snapshot = Snapshot()
    snapshot.merge([keyboard], from: .powerSources, at: t0)
    snapshot.merge([phone], from: .iphone, at: t0)
    snapshot.merge([], from: .iphone, at: t1)
    XCTAssertEqual(snapshot.devices.map(\.live), [true, false])
  }

  func testComingBackUpdatesInPlaceKeepingOrder() {
    var snapshot = Snapshot()
    snapshot.merge([keyboard], from: .powerSources, at: t0)
    snapshot.merge([phone], from: .iphone, at: t0)
    var lower = keyboard
    lower.parts[0].percent = 40
    snapshot.merge([lower], from: .powerSources, at: t1)
    XCTAssertEqual(snapshot.devices.map(\.id), ["kb", "iphone-1"])
    XCTAssertEqual(snapshot.devices[0].device.parts[0].percent, 40)
    XCTAssertEqual(snapshot.devices[0].seenAt, t1)
  }

  func testRoundTripsThroughDisk() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("batteries-\(UUID().uuidString)/snapshot.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    var snapshot = Snapshot()
    snapshot.merge([keyboard, phone], from: .powerSources, at: t0)
    try snapshot.save(to: url)
    XCTAssertEqual(Snapshot.load(from: url), snapshot)
    XCTAssertEqual(Snapshot.load(from: url.appendingPathExtension("missing")), Snapshot())
  }
}
