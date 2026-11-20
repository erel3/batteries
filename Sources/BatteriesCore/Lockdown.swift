import Foundation
import Security

/// The phone's lockdown service (port 62078): asks it for its battery and nothing else.
public enum IPhoneBattery {
  static let lockdownPort: UInt16 = 62078
  static let batteryDomain = "com.apple.mobile.battery"

  /// Reads every iPhone usbmuxd can reach. A phone that fails is skipped, not fatal:
  /// the caller keeps its last known value.
  public static func read() -> [Device] {
    guard let phones = try? Usbmux.phones() else { return [] }
    return phones.compactMap { try? read($0) }
  }

  public static func read(_ phone: Usbmux.PhoneLink) throws -> Device {
    let record = try Usbmux.pairRecord(udid: phone.udid)
    let session = try LockdownSession(phone: phone, record: record)
    defer { session.stop() }
    let name = (try? session.getValue(domain: nil, key: "DeviceName")) as? String ?? "iPhone"
    guard let battery = try session.getValue(domain: batteryDomain, key: nil) as? [String: Any] else {
      throw DeviceLinkError.protocolError("battery domain is not a dictionary")
    }
    guard let part = parse(battery) else { throw DeviceLinkError.protocolError("no BatteryCurrentCapacity") }
    return Device(id: "iphone-\(phone.udid)", name: name, kind: .phone, parts: [part])
  }

  /// Pure: lockdown's `com.apple.mobile.battery` domain in, the phone's one part out.
  public static func parse(_ battery: [String: Any]) -> Part? {
    guard let percent = battery["BatteryCurrentCapacity"] as? Int else { return nil }
    return Part(role: .main, percent: percent, charging: battery["BatteryIsCharging"] as? Bool ?? false)
  }
}

/// One lockdown session: plaintext QueryType + StartSession, then TLS with Finder's host
/// identity, `GetValue`, `StopSession`.
final class LockdownSession {
  private let stream: SocketStream
  private var tls: TLSChannel?
  private var sessionID: String?

  init(phone: Usbmux.PhoneLink, record: PairRecord) throws {
    stream = try Usbmux.connect(deviceID: phone.deviceID, port: IPhoneBattery.lockdownPort)
    let type = try exchange(["Request": "QueryType"])
    guard type["Type"] as? String == "com.apple.mobile.lockdown" else {
      throw DeviceLinkError.protocolError("port 62078 is not lockdown")
    }
    let start = try exchange(["Request": "StartSession", "HostID": record.hostID, "SystemBUID": record.systemBUID])
    if let error = start["Error"] as? String { throw DeviceLinkError.protocolError("StartSession: \(error)") }
    sessionID = start["SessionID"] as? String
    if start["EnableSessionSSL"] as? Bool == true {
      tls = try TLSChannel(stream: stream, certificatePEM: record.hostCertificate, keyPEM: record.hostPrivateKey)
    }
  }

  func getValue(domain: String?, key: String?) throws -> Any? {
    var request: [String: Any] = ["Request": "GetValue"]
    if let domain { request["Domain"] = domain }
    if let key { request["Key"] = key }
    let reply = try exchange(request)
    if let error = reply["Error"] as? String { throw DeviceLinkError.protocolError("GetValue: \(error)") }
    return reply["Value"]
  }

  func stop() {
    guard let sessionID else { return }
    _ = try? exchange(["Request": "StopSession", "SessionID": sessionID])
    self.sessionID = nil
    tls?.close()
  }

  /// Lockdown's framing: big-endian length, then an XML plist.
  private func exchange(_ message: [String: Any]) throws -> [String: Any] {
    var body = message
    body["Label"] = "batteries"
    let plist = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
    var header = Data()
    withUnsafeBytes(of: UInt32(plist.count).bigEndian) { header.append(contentsOf: $0) }
    try send(header + plist)
    let length = try receive(4).withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
    guard length < 1 << 20 else { throw DeviceLinkError.protocolError("lockdown frame length \(length)") }
    let reply = try receive(Int(length))
    guard let dict = try PropertyListSerialization.propertyList(from: reply, format: nil) as? [String: Any] else {
      throw DeviceLinkError.protocolError("lockdown reply is not a dictionary")
    }
    return dict
  }

  private func send(_ data: Data) throws {
    if let tls { try tls.write(data) } else { try stream.write(data) }
  }

  private func receive(_ count: Int) throws -> Data {
    if let tls { return try tls.read(exactly: count) }
    return try stream.read(exactly: count)
  }
}
