import XCTest
@testable import BatteriesCore

final class ItemsTests: XCTestCase {
  let now = Date(timeIntervalSince1970: 1_000_000)

  func airPods(left: Int, right: Int, case casePercent: Int?) -> Device {
    var parts = [Part(role: .left, percent: left, charging: false), Part(role: .right, percent: right, charging: true)]
    if let casePercent { parts.append(Part(role: .case, percent: casePercent, charging: false)) }
    return Device(id: "pods", name: "AirPods Pro", kind: .headphones, parts: parts)
  }

  func testBudsCloseTogetherShowAsOneRingAtTheLowerValue() {
    let items = Snapshot.items(of: airPods(left: 80, right: 72, case: 99), live: true)
    XCTAssertEqual(items.map(\.role), [.main, .case])
    XCTAssertEqual(items[0].percent, 72)
    XCTAssertTrue(items[0].charging, "either bud charging marks the pair charging")
    XCTAssertEqual(items[1].name, "AirPods Pro Case")
  }

  func testBudsFarApartShowSeparately() {
    let items = Snapshot.items(of: airPods(left: 80, right: 40, case: nil), live: true)
    XCTAssertEqual(items.map(\.role), [.left, .right])
    XCTAssertEqual(items.map(\.name), ["AirPods Pro Left", "AirPods Pro Right"])
  }

  func testMacFirstAndStaleValuesGreyed() {
    var snapshot = Snapshot()
    snapshot.merge([Device(id: "kb", name: "K8", kind: .keyboard, parts: [Part(role: .main, percent: 60, charging: false)])],
                   from: .powerSources, at: now)
    snapshot.merge([Device(id: "mac", name: "Mac", kind: .mac, parts: [Part(role: .main, percent: 90, charging: false)])],
                   from: .iphone, at: now.addingTimeInterval(-Snapshot.staleAfter))
    let items = snapshot.items(now: now)
    XCTAssertEqual(items.map(\.deviceID), ["mac", "kb"])
    XCTAssertEqual(items.map(\.live), [false, true], "a live value the app has not refreshed for 15 min is no longer current")
  }

  func testWidgetHidesDevicesNotSeenFor12Hours() {
    var snapshot = Snapshot()
    snapshot.merge([Device(id: "kb", name: "K8", kind: .keyboard, parts: [Part(role: .main, percent: 60, charging: false)])],
                   from: .powerSources, at: now.addingTimeInterval(-Snapshot.hideAfter))
    snapshot.merge([Device(id: "phone", name: "iPhone", kind: .phone, parts: [Part(role: .main, percent: 50, charging: false)])],
                   from: .iphone, at: now.addingTimeInterval(-Snapshot.hideAfter + 60))
    XCTAssertEqual(snapshot.items(now: now, forWidget: true).map(\.deviceID), ["phone"])
    XCTAssertEqual(snapshot.items(now: now).map(\.deviceID), ["kb", "phone"], "settings keeps every device")
  }

  func testOwnersOrderHoldsAndANewMacStartsFirst() {
    var snapshot = Snapshot()
    let kb = Device(id: "kb", name: "K8", kind: .keyboard, parts: [Part(role: .main, percent: 60, charging: false)])
    let mouse = Device(id: "mouse", name: "M3", kind: .mouse, parts: [Part(role: .main, percent: 70, charging: false)])
    let mac = Device(id: "mac", name: "Mac", kind: .mac, parts: [Part(role: .main, percent: 90, charging: false)])
    snapshot.merge([kb, mouse], from: .powerSources, at: now)
    snapshot.merge([kb, mouse, mac], from: .powerSources, at: now)
    XCTAssertEqual(snapshot.items(now: now).map(\.deviceID), ["mac", "kb", "mouse"])
    snapshot.devices.swapAt(0, 2)  // the owner drags the Mac last
    snapshot.merge([kb, mouse, mac], from: .powerSources, at: now)
    XCTAssertEqual(snapshot.items(now: now).map(\.deviceID), ["mouse", "kb", "mac"], "a new reading keeps the owner's order")
  }

  func testWidgetDropsBudsChargedInTheCase() {
    func pods(_ left: Int, _ right: Int, charging: Bool) -> Snapshot {
      var snapshot = Snapshot()
      snapshot.merge([Device(id: "pods", name: "AirPods Pro", kind: .headphones, parts: [
        Part(role: .left, percent: left, charging: charging), Part(role: .right, percent: right, charging: charging),
        Part(role: .case, percent: 88, charging: false)
      ])], from: .powerSources, at: now)
      return snapshot
    }
    XCTAssertEqual(pods(79, 85, charging: true).items(now: now, forWidget: true).map(\.role), [.main, .case], "79 and 85 are one row at 79")
    XCTAssertEqual(pods(80, 85, charging: true).items(now: now, forWidget: true).map(\.role), [.case])
    XCTAssertEqual(pods(60, 85, charging: true).items(now: now, forWidget: true).map(\.role), [.left, .case], "the charged right bud drops alone")
    XCTAssertEqual(pods(90, 95, charging: false).items(now: now, forWidget: true).map(\.role), [.main, .case], "out of the case they always show")
    XCTAssertEqual(pods(80, 85, charging: true).items(now: now, splitBuds: true).map(\.role), [.left, .right, .case], "settings keeps them")
  }

  func testWidgetNoteSaysWhenTheAppStopped() {
    var snapshot = Snapshot()
    XCTAssertEqual(snapshot.appNote(now: now), "Open Batteries", "never ran")
    snapshot.updated = now.addingTimeInterval(-Snapshot.appSilentAfter)
    XCTAssertNil(snapshot.appNote(now: now), "running: saves every minute")
    snapshot.updated = now.addingTimeInterval(-2 * 60 * 60)
    XCTAssertEqual(snapshot.appNote(now: now)?.hasPrefix("Updated "), true)
    XCTAssertEqual(snapshot.appNote(now: now)?.contains("2"), true)
  }

  func testSnapshotFromBeforeTheHeartbeatStillLoads() throws {
    let old = Data(#"{"devices":[]}"#.utf8)
    XCTAssertNil(try Snapshot.decoder.decode(Snapshot.self, from: old).updated)
  }

  func testSplitBudsForSettings() {
    let items = Snapshot.items(of: airPods(left: 80, right: 78, case: 99), live: true, splitBuds: true)
    XCTAssertEqual(items.map(\.role), [.left, .right, .case])
  }

  func testRulesEncodeAsAJSONObjectAndFirstBuildLevelsStillLoad() throws {
    let settings = AlertSettings(rules: ["pods": [.case: AlertRule(low: 30, style: .circle)]])
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let json = try XCTUnwrap(String(bytes: encoder.encode(settings), encoding: .utf8))
    XCTAssertTrue(json.contains(#""case":{"low":30,"style":"circle"}"#), json)
    XCTAssertEqual(try JSONDecoder().decode(AlertSettings.self, from: Data(json.utf8)), settings)

    let firstBuild = #"{"defaults":{"low":20,"high":80},"overrides":{"kb":{"main":{"low":10,"high":100}}}}"#
    XCTAssertEqual(try JSONDecoder().decode(AlertSettings.self, from: Data(firstBuild.utf8)),
                   AlertSettings(rules: ["kb": [.main: AlertRule(low: 10, high: 100)]]))
  }
}
