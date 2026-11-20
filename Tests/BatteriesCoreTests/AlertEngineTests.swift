import XCTest
@testable import BatteriesCore

final class AlertEngineTests: XCTestCase {
  let settings = AlertSettings(rules: ["kb": [.main: AlertRule(low: 20, high: 80), .left: AlertRule(low: 20, high: 80)]])

  func reading(_ percent: Int, charging: Bool, role: PartRole = .main) -> Device {
    Device(id: "kb", name: "Keyboard", kind: .keyboard, parts: [Part(role: role, percent: percent, charging: charging)])
  }

  func kinds(_ engine: inout AlertEngine, _ steps: [(Int, Bool)]) -> [AlertKind?] {
    steps.map { engine.evaluate(reading($0.0, charging: $0.1), settings: settings).first?.kind }
  }

  func testLowFiresOnceThenRearmsAfterHysteresis() {
    var engine = AlertEngine()
    let fired = kinds(&engine, [(25, false), (20, false), (19, false), (21, false), (24, false), (25, false), (20, false)])
    XCTAssertEqual(fired, [nil, .low, nil, nil, nil, nil, .low])
  }

  func testPluggingInRearmsLow() {
    var engine = AlertEngine()
    XCTAssertEqual(kinds(&engine, [(15, false), (15, true), (15, false)]), [.low, nil, .low])
  }

  func testHighOnlyWhileCharging() {
    var engine = AlertEngine()
    XCTAssertEqual(kinds(&engine, [(85, false), (79, true), (80, true), (90, true), (90, false), (90, true)]),
                   [nil, nil, .high, nil, nil, .high])
  }

  func testPerPartRuleAndSwitchedOffSide() {
    var engine = AlertEngine()
    let custom = AlertSettings(rules: ["kb": [.case: AlertRule(low: 50, style: .circleUntilClicked)]])
    let alerts = engine.evaluate(reading(45, charging: false, role: .case), settings: custom)
    XCTAssertEqual(alerts.map(\.kind), [.low])
    XCTAssertEqual(alerts.map(\.style), [.circleUntilClicked], "the alert carries its battery's style")
    XCTAssertEqual(engine.evaluate(reading(100, charging: true, role: .case), settings: custom), [])
  }

  func testBatteryWithoutRuleNeverAlerts() {
    var engine = AlertEngine()
    XCTAssertEqual(engine.evaluate(reading(1, charging: false, role: .right), settings: settings), [])
    XCTAssertEqual(engine.evaluate(reading(100, charging: true, role: .case), settings: settings), [])
  }

  func testSetRuleDropsEmptyRules() {
    var settings = AlertSettings()
    settings.setRule(AlertRule(low: 10), device: "kb", role: .main)
    XCTAssertEqual(settings.rule(device: "kb", role: .main).low, 10)
    settings.setRule(.off, device: "kb", role: .main)
    XCTAssertEqual(settings, AlertSettings())
  }
}
