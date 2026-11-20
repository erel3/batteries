import XCTest
@testable import BatteriesCore

/// Fixtures are the real descriptions macOS 27.2.1 returned on 2026-11-20 (trimmed to the keys we read).
final class PowerSourcesTests: XCTestCase {
  let mac: [String: Any] = [
    "Name": "InternalBattery-0", "Type": "InternalBattery",
    "Current Capacity": 80, "Max Capacity": 100, "Is Charging": false
  ]
  let keyboard: [String: Any] = [
    "Name": "Keychron K8 HE", "Type": "Accessory Source", "Accessory Category": "Mouse",
    "Accessory Identifier": "9C2FCF8D-663A-991A-8753-9B31F37027CB", "Current Capacity": 61, "Max Capacity": 100
  ]
  let mouse: [String: Any] = [
    "Name": "Keychron M3 mini 4K", "Type": "Accessory Source", "Accessory Category": "Keyboard",
    "Accessory Identifier": "4BCC3A44-76AC-14E7-F241-15ECB5C14B97", "Current Capacity": 44, "Max Capacity": 100
  ]
  let airpodsCase: [String: Any] = [
    "Name": "Andrey’s AirPods Pro Case", "Type": "Accessory Source", "Part Identifier": "Case",
    "Group Identifier": "60B81998", "Accessory Identifier": "78D67172",
    "Current Capacity": 99, "Max Capacity": 100, "Is Charging": false
  ]
  let airpodsBuds: [String: Any] = [
    "Name": "Andrey’s AirPods Pro", "Type": "Accessory Source", "Part Identifier": "Combined",
    "Group Identifier": "60B81998", "Accessory Identifier": "0238E61D",
    "Current Capacity": 80, "Max Capacity": 100, "Is Charging": true,
    "Combined Parts": [
      ["Part Identifier": "Left", "Current Capacity": 80, "Max Capacity": 100, "Is Charging": true],
      ["Part Identifier": "Right", "Current Capacity": 75, "Max Capacity": 100, "Is Charging": false]
    ]
  ]

  func testMacKeyboardMouse() {
    let devices = PowerSources.parse([mac, keyboard, mouse])
    XCTAssertEqual(devices.map(\.id), ["mac", "9C2FCF8D-663A-991A-8753-9B31F37027CB", "4BCC3A44-76AC-14E7-F241-15ECB5C14B97"])
    XCTAssertEqual(devices[0].parts, [Part(role: .main, percent: 80, charging: false)])
    XCTAssertEqual(devices[1].kind, .keyboard, "Keychron's swapped category must not win over the name")
    XCTAssertEqual(devices[2].kind, .mouse)
  }

  func testAirPodsFoldIntoOneDeviceWhicheverArrivesFirst() {
    for order in [[airpodsCase, airpodsBuds], [airpodsBuds, airpodsCase]] {
      let devices = PowerSources.parse(order)
      XCTAssertEqual(devices.count, 1)
      XCTAssertEqual(devices[0].id, "60B81998")
      XCTAssertEqual(devices[0].name, "Andrey’s AirPods Pro")
      XCTAssertEqual(devices[0].kind, .headphones)
      XCTAssertEqual(devices[0].parts, [
        Part(role: .left, percent: 80, charging: true),
        Part(role: .right, percent: 75, charging: false),
        Part(role: .case, percent: 99, charging: false)
      ])
    }
  }

  func testCapacityIsScaledAndBrokenEntriesAreSkipped() {
    let scaled: [String: Any] = ["Name": "Pad", "Current Capacity": 1, "Max Capacity": 4, "Accessory Identifier": "x"]
    let noCapacity: [String: Any] = ["Name": "Ghost", "Accessory Identifier": "y"]
    let noName: [String: Any] = ["Current Capacity": 10]
    let devices = PowerSources.parse([scaled, noCapacity, noName])
    XCTAssertEqual(devices.map(\.name), ["Pad"])
    XCTAssertEqual(devices[0].parts[0].percent, 25)
  }
}
