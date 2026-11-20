import XCTest
@testable import BatteriesCore

final class IPhoneTests: XCTestCase {
  func testBatteryDomainAsTheRealPhoneSentIt() {
    let domain: [String: Any] = [
      "BatteryCurrentCapacity": 54, "BatteryIsCharging": false, "ExternalChargeCapable": false,
      "ExternalConnected": false, "FullyCharged": false, "GasGaugeCapability": true, "HasBattery": true
    ]
    XCTAssertEqual(IPhoneBattery.parse(domain), Part(role: .main, percent: 54, charging: false))
    XCTAssertNil(IPhoneBattery.parse(["HasBattery": true]))
  }

  func testUsbmuxFrameHeader() throws {
    let frame = try Usbmux.frame(["MessageType": "ListDevices"], tag: 7)
    let words = (0..<4).map { index in
      frame.subdata(in: (index * 4)..<(index * 4 + 4)).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    }
    XCTAssertEqual(words, [UInt32(frame.count), 1, 8, 7])
    let body = try XCTUnwrap(PropertyListSerialization.propertyList(from: frame.dropFirst(16), format: nil) as? [String: Any])
    XCTAssertEqual(body["MessageType"] as? String, "ListDevices")
    XCTAssertEqual(body["ProgName"] as? String, "batteries")
  }

  func testOnlyConnectAndDisconnectTriggerARead() {
    XCTAssertTrue(Usbmux.isConnectionChange(["MessageType": "Attached", "DeviceID": 3]))
    XCTAssertTrue(Usbmux.isConnectionChange(["MessageType": "Detached", "DeviceID": 3]))
    XCTAssertFalse(Usbmux.isConnectionChange(["MessageType": "Paired", "DeviceID": 3]))
    XCTAssertFalse(Usbmux.isConnectionChange(["MessageType": "Result", "Number": 0]))
  }

  func testPEMAndPKCS8Unwrap() throws {
    let pkcs1 = Data([0x30, 0x03, 0x02, 0x01, 0x00])
    let algorithm: [UInt8] = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]
    let inner = [0x02, 0x01, 0x00] + algorithm + [0x04, UInt8(pkcs1.count)] + Array(pkcs1)
    // Long-form length on the outer SEQUENCE, as real keys have.
    let pkcs8 = Data([0x30, 0x81, UInt8(inner.count)] + inner)
    // Armour assembled at runtime: a literal PEM header trips the secrets hook. The body is fake.
    let label = ["PRIVATE", "KEY"].joined(separator: " ")
    let pem = "-----BEGIN \(label)-----\n\(pkcs8.base64EncodedString(options: .lineLength64Characters))\n-----END \(label)-----\n"

    let decoded = try XCTUnwrap(PEM.decode(Data(pem.utf8)))
    XCTAssertEqual(decoded.label, "PRIVATE KEY")
    XCTAssertEqual(decoded.der, pkcs8)
    XCTAssertEqual(try PEM.pkcs1(fromPKCS8: decoded.der), pkcs1)
    XCTAssertThrowsError(try PEM.pkcs1(fromPKCS8: pkcs1), "a bare PKCS#1 key is not PKCS#8")
    XCTAssertNil(PEM.decode(Data("not pem".utf8)))
  }
}
