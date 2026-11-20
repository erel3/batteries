import Foundation

/// How an alert shows: a system notification, or a ring in the centre of the screen that hides
/// after a few seconds or stays until clicked.
public enum AlertStyle: String, Codable, Sendable, CaseIterable {
  case notification, circle, circleUntilClicked
}

/// One battery's alert rule. `nil` switches that side off.
/// LOW fires while discharging at or below `low` (plug it in);
/// HIGH fires while charging at or above `high` (unplug it).
public struct AlertRule: Codable, Equatable, Sendable {
  public var low: Int?
  public var high: Int?
  public var style: AlertStyle

  public init(low: Int? = nil, high: Int? = nil, style: AlertStyle = .notification) {
    self.low = low
    self.high = high
    self.style = style
  }

  /// Rules saved before `style` existed decode as notifications.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    low = try container.decodeIfPresent(Int.self, forKey: .low)
    high = try container.decodeIfPresent(Int.self, forKey: .high)
    style = try container.decodeIfPresent(AlertStyle.self, forKey: .style) ?? .notification
  }

  public static let off = AlertRule()
  /// Where a side starts when the owner switches it on.
  public static let startLow = 20
  public static let startHigh = 80
}

/// The owner's rules per device and per part (an AirPods case drains differently from the buds).
/// A battery without a rule never alerts: alerts are turned on one battery at a time.
public struct AlertSettings: Codable, Equatable, Sendable {
  public var rules: [String: [PartRole: AlertRule]]

  // "overrides" is the key the first build saved per-device levels under; keeping it keeps them.
  private enum CodingKeys: String, CodingKey {
    case rules = "overrides"
  }

  public init(rules: [String: [PartRole: AlertRule]] = [:]) {
    self.rules = rules
  }

  public func rule(device: String, role: PartRole) -> AlertRule {
    rules[device]?[role] ?? .off
  }

  /// Stores a rule; an all-default rule is removed instead, so the saved settings stay small.
  public mutating func setRule(_ rule: AlertRule, device: String, role: PartRole) {
    rules[device, default: [:]][role] = rule == .off ? nil : rule
    if rules[device]?.isEmpty == true { rules[device] = nil }
  }
}

public enum AlertKind: String, Codable, Sendable {
  case low, high
}

public struct Alert: Equatable, Sendable {
  public var deviceID: String
  public var deviceName: String
  public var role: PartRole
  public var kind: AlertKind
  public var percent: Int
  public var style: AlertStyle
}

/// Fires each alert once per crossing. After firing, a side re-arms only once the battery is
/// `hysteresis` points back on the safe side or the charger state flips, so a value hovering
/// at 20/21% does not repeat the alert every read.
public struct AlertEngine: Codable, Equatable, Sendable {
  public var hysteresis = 5
  private var fired: Set<String> = []

  public init(hysteresis: Int = 5) {
    self.hysteresis = hysteresis
  }

  /// Only live readings belong here: a greyed last-known value never alerts.
  public mutating func evaluate(_ device: Device, settings: AlertSettings) -> [Alert] {
    var alerts: [Alert] = []
    for part in device.parts {
      let rule = settings.rule(device: device.id, role: part.role)
      if let low = rule.low {
        let key = "\(device.id)/\(part.role.rawValue)/low"
        if fired.contains(key) {
          if part.charging || part.percent >= low + hysteresis { fired.remove(key) }
        } else if !part.charging && part.percent <= low {
          fired.insert(key)
          alerts.append(Alert(deviceID: device.id, deviceName: device.name, role: part.role, kind: .low, percent: part.percent, style: rule.style))
        }
      }
      if let high = rule.high {
        let key = "\(device.id)/\(part.role.rawValue)/high"
        if fired.contains(key) {
          if !part.charging || part.percent <= high - hysteresis { fired.remove(key) }
        } else if part.charging && part.percent >= high {
          fired.insert(key)
          alerts.append(Alert(deviceID: device.id, deviceName: device.name, role: part.role, kind: .high, percent: part.percent, style: rule.style))
        }
      }
    }
    return alerts
  }
}
