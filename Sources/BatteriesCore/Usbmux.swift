import Darwin
import Foundation

public enum DeviceLinkError: Error, Equatable, Sendable {
  case socket(String)
  case closed
  case protocolError(String)
  case tls(OSStatus)
}

/// A blocking Unix-socket stream with exact reads, shared by usbmuxd and lockdown.
final class SocketStream {
  let fd: Int32

  init(unixPath: String) throws {
    fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw DeviceLinkError.socket("socket: \(String(cString: strerror(errno)))") }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    guard unixPath.utf8.count < capacity else { close(fd); throw DeviceLinkError.socket("path too long") }
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
      raw.copyBytes(from: unixPath.utf8)
      raw[unixPath.utf8.count] = 0
    }
    let result = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard result == 0 else {
      let reason = String(cString: strerror(errno))
      close(fd)
      throw DeviceLinkError.socket("connect \(unixPath): \(reason)")
    }
    // A phone that drops off Wi-Fi mid-request must not hang the caller forever.
    var timeout = timeval(tv_sec: 10, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
  }

  deinit { close(fd) }

  /// For a stream that waits on purpose, like usbmuxd's Listen: no read timeout.
  func waitIndefinitely() {
    var none = timeval(tv_sec: 0, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
  }

  func write(_ data: Data) throws {
    try data.withUnsafeBytes { raw in
      var offset = 0
      while offset < raw.count {
        let sent = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
        guard sent > 0 else { throw DeviceLinkError.closed }
        offset += sent
      }
    }
  }

  func read(exactly count: Int) throws -> Data {
    var data = Data(count: count)
    try data.withUnsafeMutableBytes { raw in
      var offset = 0
      while offset < count {
        let got = Darwin.read(fd, raw.baseAddress! + offset, count - offset)
        guard got > 0 else { throw DeviceLinkError.closed }
        offset += got
      }
    }
    return data
  }
}

/// Apple's usbmuxd: lists iPhones reachable by cable or Wi-Fi, hands out the pair record
/// Finder created when the phone was trusted, and tunnels a TCP port on the phone.
public enum Usbmux {
  public static let socketPath = "/var/run/usbmuxd"
  private static let label = "batteries"

  public struct PhoneLink: Equatable, Sendable {
    public var deviceID: Int
    public var udid: String
    public var connection: String
  }

  /// usbmuxd's framing: little-endian length, version 1, message 8 (plist), tag; then an XML plist.
  static func frame(_ message: [String: Any], tag: UInt32 = 1) throws -> Data {
    var body = message
    body["ClientVersionString"] = label
    body["ProgName"] = label
    let plist = try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
    var header = Data()
    for value in [UInt32(16 + plist.count), 1, 8, tag] {
      withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
    }
    return header + plist
  }

  static func request(_ message: [String: Any], on stream: SocketStream) throws -> [String: Any] {
    try stream.write(frame(message))
    return try readMessage(on: stream)
  }

  static func readMessage(on stream: SocketStream) throws -> [String: Any] {
    let header = try stream.read(exactly: 16)
    let length = header.prefix(4).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    guard length >= 16, length < 1 << 20 else { throw DeviceLinkError.protocolError("usbmuxd frame length \(length)") }
    let body = try stream.read(exactly: Int(length) - 16)
    guard let reply = try PropertyListSerialization.propertyList(from: body, format: nil) as? [String: Any] else {
      throw DeviceLinkError.protocolError("usbmuxd reply is not a dictionary")
    }
    return reply
  }

  /// Blocks for as long as usbmuxd runs, calling `onChange` each time an iPhone connects or
  /// disconnects, by cable or Wi-Fi, and once at the start for each phone already there.
  /// Returns only by throwing, when usbmuxd closes the connection.
  public static func listen(_ onChange: @Sendable () -> Void) throws -> Never {
    let stream = try SocketStream(unixPath: socketPath)
    // Without the protocol version usbmuxd answers Result 0 and then never sends an event
    // (measured on macOS 27.2.1); libusbmuxd sends 3.
    let reply = try request(["MessageType": "Listen", "kLibUSBMuxVersion": 3], on: stream)
    guard reply["Number"] as? Int == 0 else {
      throw DeviceLinkError.protocolError("usbmuxd Listen refused: \(reply["Number"] ?? "?")")
    }
    stream.waitIndefinitely()
    while true {
      if isConnectionChange(try readMessage(on: stream)) { onChange() }
    }
  }

  /// Pure: usbmuxd also sends Paired and other events; only these two change what can be read.
  static func isConnectionChange(_ message: [String: Any]) -> Bool {
    ["Attached", "Detached"].contains(message["MessageType"] as? String ?? "")
  }

  public static func phones() throws -> [PhoneLink] {
    let reply = try request(["MessageType": "ListDevices"], on: SocketStream(unixPath: socketPath))
    let list = reply["DeviceList"] as? [[String: Any]] ?? []
    return list.compactMap { entry in
      guard let id = entry["DeviceID"] as? Int,
            let props = entry["Properties"] as? [String: Any],
            let udid = props["SerialNumber"] as? String else { return nil }
      return PhoneLink(deviceID: id, udid: udid, connection: props["ConnectionType"] as? String ?? "?")
    }
  }

  static func pairRecord(udid: String) throws -> PairRecord {
    let reply = try request(["MessageType": "ReadPairRecord", "PairRecordID": udid], on: SocketStream(unixPath: socketPath))
    guard let data = reply["PairRecordData"] as? Data else {
      throw DeviceLinkError.protocolError("no pair record for this phone (trust it in Finder once)")
    }
    return try PairRecord(plist: data)
  }

  /// Returns a stream that is now a raw tunnel to `port` on the phone.
  static func connect(deviceID: Int, port: UInt16) throws -> SocketStream {
    let stream = try SocketStream(unixPath: socketPath)
    let reply = try request(["MessageType": "Connect", "DeviceID": deviceID, "PortNumber": Int(port.bigEndian)], on: stream)
    guard reply["Number"] as? Int == 0 else {
      throw DeviceLinkError.protocolError("usbmuxd Connect refused: \(reply["Number"] ?? "?")")
    }
    return stream
  }
}

/// The part of Finder's pair record lockdown needs. Held in memory only, never written out.
struct PairRecord {
  let hostID: String
  let systemBUID: String
  let hostCertificate: Data
  let hostPrivateKey: Data

  init(plist: Data) throws {
    guard let dict = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
          let hostID = dict["HostID"] as? String,
          let buid = dict["SystemBUID"] as? String,
          let cert = dict["HostCertificate"] as? Data,
          let key = dict["HostPrivateKey"] as? Data else {
      throw DeviceLinkError.protocolError("pair record is missing a field")
    }
    self.hostID = hostID
    self.systemBUID = buid
    self.hostCertificate = cert
    self.hostPrivateKey = key
  }
}
