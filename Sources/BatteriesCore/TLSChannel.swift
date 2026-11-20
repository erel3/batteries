import Foundation
import Security

/// TLS over an already-open socket that has carried plaintext first (lockdown switches to TLS
/// after StartSession), with Finder's host certificate as the client identity.
///
/// ponytail: SecureTransport is deprecated since macOS 10.15 but is the only system TLS that
/// can take over a socket mid-stream. Upgrade path: Network.framework with an NWProtocolFramer
/// that carries the plaintext preamble beneath `NWProtocolTLS`.
final class TLSChannel {
  private let context: SSLContext
  private let stream: SocketStream
  private let connection: UnsafeMutablePointer<Int32>

  init(stream: SocketStream, certificatePEM: Data, keyPEM: Data) throws {
    self.stream = stream
    let identity = try Self.identity(certificatePEM: certificatePEM, keyPEM: keyPEM)
    guard let context = SSLCreateContext(nil, .clientSide, .streamType) else { throw DeviceLinkError.tls(errSSLInternal) }
    self.context = context
    connection = .allocate(capacity: 1)
    connection.initialize(to: stream.fd)

    try check(SSLSetIOFuncs(context, tlsRead, tlsWrite))
    try check(SSLSetConnection(context, connection))
    try check(SSLSetCertificate(context, [identity] as CFArray))
    // The phone's certificate is signed by the pair record's own root, not a public CA.
    // The usbmuxd tunnel is already bound to the device, so stop at server-auth and go on.
    try check(SSLSetSessionOption(context, .breakOnServerAuth, true))

    var status: OSStatus
    repeat {
      status = SSLHandshake(context)
    } while status == errSSLWouldBlock || status == errSSLPeerAuthCompleted
    try check(status)
  }

  deinit {
    connection.deinitialize(count: 1)
    connection.deallocate()
  }

  func write(_ data: Data) throws {
    try data.withUnsafeBytes { raw in
      var offset = 0
      while offset < raw.count {
        var written = 0
        let status = SSLWrite(context, raw.baseAddress! + offset, raw.count - offset, &written)
        guard status == noErr || status == errSSLWouldBlock else { throw DeviceLinkError.tls(status) }
        offset += written
      }
    }
  }

  func read(exactly count: Int) throws -> Data {
    var data = Data(count: count)
    try data.withUnsafeMutableBytes { raw in
      var offset = 0
      while offset < count {
        var got = 0
        let status = SSLRead(context, raw.baseAddress! + offset, count - offset, &got)
        if status == errSSLClosedGraceful || status == errSSLClosedNoNotify { throw DeviceLinkError.closed }
        guard status == noErr || status == errSSLWouldBlock else { throw DeviceLinkError.tls(status) }
        offset += got
      }
    }
    return data
  }

  func close() {
    SSLClose(context)
  }

  private func check(_ status: OSStatus) throws {
    guard status == noErr else { throw DeviceLinkError.tls(status) }
  }

  /// Builds the identity in memory: nothing goes to a keychain or to disk.
  static func identity(certificatePEM: Data, keyPEM: Data) throws -> SecIdentity {
    guard let certDER = PEM.decode(certificatePEM)?.der,
          let certificate = SecCertificateCreateWithData(nil, certDER as CFData),
          let (label, keyDER) = PEM.decode(keyPEM) else {
      throw DeviceLinkError.protocolError("pair record certificate or key is not PEM")
    }
    let rsa = label == "PRIVATE KEY" ? try PEM.pkcs1(fromPKCS8: keyDER) : keyDER
    let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateWithData(rsa as CFData, attributes as CFDictionary, &error) else {
      throw DeviceLinkError.protocolError("pair record key: \(error?.takeRetainedValue().localizedDescription ?? "unreadable")")
    }
    guard let identity = SecIdentityCreate(nil, certificate, key) else {
      throw DeviceLinkError.protocolError("pair record key does not match its certificate")
    }
    return identity
  }
}

private func tlsRead(_ connection: SSLConnectionRef, _ data: UnsafeMutableRawPointer, _ length: UnsafeMutablePointer<Int>) -> OSStatus {
  let fd = connection.assumingMemoryBound(to: Int32.self).pointee
  let wanted = length.pointee
  var total = 0
  while total < wanted {
    let got = Darwin.read(fd, data + total, wanted - total)
    if got > 0 { total += got; continue }
    length.pointee = total
    return got == 0 ? errSSLClosedNoNotify : errSSLClosedAbort
  }
  length.pointee = total
  return noErr
}

private func tlsWrite(_ connection: SSLConnectionRef, _ data: UnsafeRawPointer, _ length: UnsafeMutablePointer<Int>) -> OSStatus {
  let fd = connection.assumingMemoryBound(to: Int32.self).pointee
  let wanted = length.pointee
  var total = 0
  while total < wanted {
    let sent = Darwin.write(fd, data + total, wanted - total)
    if sent > 0 { total += sent; continue }
    length.pointee = total
    return errSSLClosedAbort
  }
  length.pointee = total
  return noErr
}

enum PEM {
  /// The first PEM block: its label ("CERTIFICATE", "RSA PRIVATE KEY", "PRIVATE KEY") and DER bytes.
  static func decode(_ pem: Data) -> (label: String, der: Data)? {
    guard let text = String(data: pem, encoding: .ascii) else { return nil }
    let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
    guard let begin = lines.firstIndex(where: { $0.hasPrefix("-----BEGIN ") }),
          let end = lines[begin...].firstIndex(where: { $0.hasPrefix("-----END ") }) else { return nil }
    let label = lines[begin].dropFirst("-----BEGIN ".count).dropLast("-----".count)
    guard let der = Data(base64Encoded: lines[(begin + 1)..<end].joined()) else { return nil }
    return (String(label), der)
  }

  /// PKCS#8 PrivateKeyInfo = SEQUENCE { INTEGER version, SEQUENCE algorithm, OCTET STRING key };
  /// the OCTET STRING holds the PKCS#1 RSAPrivateKey that SecKeyCreateWithData wants.
  static func pkcs1(fromPKCS8 der: Data) throws -> Data {
    var reader = DERReader(der)
    var info = try reader.child(tag: 0x30)
    _ = try info.child(tag: 0x02)
    _ = try info.child(tag: 0x30)
    return try info.child(tag: 0x04).bytes
  }
}

/// Just enough DER to walk PKCS#8: tag, definite length, contents.
struct DERReader {
  private(set) var bytes: Data
  init(_ bytes: Data) { self.bytes = Data(bytes) }

  mutating func child(tag: UInt8) throws -> DERReader {
    guard let first = bytes.first, first == tag, bytes.count >= 2 else { throw DeviceLinkError.protocolError("DER: expected tag \(tag)") }
    var index = bytes.startIndex + 1
    var length = Int(bytes[index])
    index += 1
    if length & 0x80 != 0 {
      let octets = length & 0x7f
      guard octets > 0, octets <= 4, bytes.endIndex - index >= octets else { throw DeviceLinkError.protocolError("DER: bad length") }
      length = bytes[index..<(index + octets)].reduce(0) { $0 << 8 | Int($1) }
      index += octets
    }
    guard bytes.endIndex - index >= length else { throw DeviceLinkError.protocolError("DER: truncated") }
    let contents = bytes[index..<(index + length)]
    bytes = Data(bytes[(index + length)...])
    return DERReader(Data(contents))
  }
}
