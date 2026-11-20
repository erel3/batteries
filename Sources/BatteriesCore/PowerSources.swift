import Foundation
import IOKit.ps

/// The Mac's own battery and every Bluetooth accessory macOS tracks (AirPods with each bud
/// and the case, BLE keyboards and mice): the list `pmset -g accps` prints.
public enum PowerSources {
  /// Private, exported by IOKit: the public `IOPSCopyPowerSourcesInfo` returns the internal
  /// battery only. Type 4 is the accessory list (measured on macOS 27.2.1: 0 = everything,
  /// 1 = internal, 4 = accessories only).
  @_silgen_name("IOPSCopyPowerSourcesByType")
  private static func copyByType(_ type: Int32) -> Unmanaged<CFTypeRef>?

  private static let accessories: Int32 = 4

  public static func read() -> [Device] {
    var descriptions: [[String: Any]] = []
    let internalInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    descriptions += describe(internalInfo)
    if let accessoryInfo = copyByType(accessories)?.takeRetainedValue() {
      descriptions += describe(accessoryInfo)
    }
    return parse(descriptions)
  }

  private static func describe(_ info: CFTypeRef) -> [[String: Any]] {
    let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
    return list.compactMap {
      IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
    }
  }

  /// Pure: power source descriptions in, devices out. AirPods arrive as two sources sharing
  /// a "Group Identifier" (buds "Combined" with "Combined Parts" left/right, and the "Case"),
  /// and are folded into one device.
  public static func parse(_ descriptions: [[String: Any]]) -> [Device] {
    var devices: [Device] = []
    var groups: [String: Int] = [:]

    for desc in descriptions {
      guard let name = desc["Name"] as? String else { continue }
      if desc["Type"] as? String == "InternalBattery" {
        guard let percent = percent(desc) else { continue }
        // Named like macOS's own widget names it: the computer name from Sharing settings.
        devices.append(Device(id: "mac", name: Host.current().localizedName ?? "Mac", kind: .mac, parts: [
          Part(role: .main, percent: percent, charging: desc["Is Charging"] as? Bool ?? false)
        ]))
        continue
      }

      let parts = accessoryParts(desc)
      guard !parts.isEmpty else { continue }

      if let group = desc["Group Identifier"] as? String {
        let deviceName = (desc["Part Identifier"] as? String == "Case") ? stripCase(name) : name
        if let index = groups[group] {
          devices[index].parts += parts
          if desc["Part Identifier"] as? String != "Case" { devices[index].name = deviceName }
        } else {
          groups[group] = devices.count
          devices.append(Device(id: group, name: deviceName, kind: .headphones, parts: parts))
        }
        continue
      }

      let id = desc["Accessory Identifier"] as? String ?? name
      devices.append(Device(id: id, name: name, kind: kind(name: name, desc), parts: parts))
    }

    for index in devices.indices {
      devices[index].parts.sort { order($0.role) < order($1.role) }
    }
    return devices
  }

  private static func accessoryParts(_ desc: [String: Any]) -> [Part] {
    if let combined = desc["Combined Parts"] as? [[String: Any]] {
      return combined.compactMap { part in
        guard let role = role(part["Part Identifier"] as? String), let value = percent(part) else { return nil }
        return Part(role: role, percent: value, charging: part["Is Charging"] as? Bool ?? false)
      }
    }
    guard let value = percent(desc) else { return [] }
    let role = role(desc["Part Identifier"] as? String) ?? .main
    return [Part(role: role, percent: value, charging: desc["Is Charging"] as? Bool ?? false)]
  }

  private static func percent(_ desc: [String: Any]) -> Int? {
    guard let current = desc["Current Capacity"] as? Int else { return nil }
    let max = desc["Max Capacity"] as? Int ?? 100
    guard max > 0 else { return nil }
    return Int((Double(current) * 100 / Double(max)).rounded())
  }

  private static func role(_ identifier: String?) -> PartRole? {
    switch identifier {
    case "Left": .left
    case "Right": .right
    case "Case": .case
    case "Combined", "Single", nil: .main
    default: nil
    }
  }

  private static func order(_ role: PartRole) -> Int {
    PartRole.allCases.firstIndex(of: role) ?? 0
  }

  private static func stripCase(_ name: String) -> String {
    name.hasSuffix(" Case") ? String(name.dropLast(5)) : name
  }

  /// Keychron firmware swaps "Accessory Category" (the K8 HE keyboard reports Mouse and the
  /// M3 mouse reports Keyboard, measured 2026-11-20), so the name is asked first.
  private static func kind(name: String, _ desc: [String: Any]) -> DeviceKind {
    let lower = name.lowercased()
    if lower.contains("mouse") || lower.contains("trackpad") || lower.range(of: #"\bm\d"#, options: .regularExpression) != nil {
      return .mouse
    }
    if lower.contains("keyboard") || lower.range(of: #"\bk\d"#, options: .regularExpression) != nil {
      return .keyboard
    }
    if lower.contains("dualsense") || lower.contains("controller") { return .gamepad }
    switch desc["Accessory Category"] as? String {
    case "Mouse", "Trackpad": return .mouse
    case "Keyboard": return .keyboard
    case "Headset", "Headphones", "Audio Battery Case": return .headphones
    case "Game Controller", "Gamepad": return .gamepad
    default: return .other
    }
  }
}
