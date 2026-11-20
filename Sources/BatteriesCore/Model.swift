import Foundation

/// What a device is, so a widget can pick a glyph and the settings can group rows.
public enum DeviceKind: String, Codable, Sendable {
  case mac, phone, headphones, keyboard, mouse, gamepad, other
}

/// One battery inside a device: the whole device (`main`), or one AirPods bud or its case.
public enum PartRole: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable {
  case main, left, right, `case`
}

public struct Part: Codable, Equatable, Sendable {
  public var role: PartRole
  public var percent: Int
  public var charging: Bool

  public init(role: PartRole, percent: Int, charging: Bool) {
    self.role = role
    self.percent = percent
    self.charging = charging
  }
}

/// One reading of one device from one source, at the moment it was taken.
public struct Device: Codable, Equatable, Sendable, Identifiable {
  /// Stable across launches: the accessory identifier macOS assigns, the AirPods group, "mac", or "iphone-<udid>".
  public var id: String
  public var name: String
  public var kind: DeviceKind
  public var parts: [Part]

  public init(id: String, name: String, kind: DeviceKind, parts: [Part]) {
    self.id = id
    self.name = name
    self.kind = kind
    self.parts = parts
  }

  public func part(_ role: PartRole) -> Part? {
    parts.first { $0.role == role }
  }
}
