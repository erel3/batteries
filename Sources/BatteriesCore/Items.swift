import Foundation

/// One ring in the widget or one row in the settings list, the way macOS's Batteries widget counts
/// them: AirPods buds show as one item while they are within `budsSpread` of each other, otherwise
/// as Left and Right; the case is always its own item.
public struct BatteryItem: Identifiable, Equatable, Sendable {
  public var deviceID: String
  public var name: String
  public var kind: DeviceKind
  /// `.main` is a whole device, or both buds shown together.
  public var role: PartRole
  public var percent: Int
  public var charging: Bool
  /// False for a last-known value: the device is away, or the app has not refreshed it lately.
  public var live: Bool

  public var id: String { "\(deviceID)/\(role.rawValue)" }

  public init(deviceID: String, name: String, kind: DeviceKind, role: PartRole, percent: Int, charging: Bool, live: Bool) {
    self.deviceID = deviceID
    self.name = name
    self.kind = kind
    self.role = role
    self.percent = percent
    self.charging = charging
    self.live = live
  }
}

extension Snapshot {
  /// Buds further apart than this show as two rings.
  public static let budsSpread = 10
  /// A value the app has not refreshed for this long shows greyed even if its source last saw it:
  /// the app may have quit. Three iPhone polls.
  public static let staleAfter: TimeInterval = 15 * 60
  /// The widget leaves out a device not seen for this long. Settings still lists it.
  public static let hideAfter: TimeInterval = 12 * 60 * 60
  /// The app saves every minute; silence this long means it is not running (quit, crashed, login
  /// item off), and the widget says so under the batteries.
  public static let appSilentAfter: TimeInterval = 30 * 60

  /// The widget's footer: nil while the app is running, how old the data is once it stops, and
  /// "Open Batteries" when it never ran.
  public func appNote(now: Date) -> String? {
    guard let updated else { return "Open Batteries" }
    guard now.timeIntervalSince(updated) > Self.appSilentAfter else { return nil }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return "Updated \(formatter.localizedString(for: updated, relativeTo: now))"
  }

  /// Buds charging in their case drop out of the widget from this level: only the case remains.
  public static let budsDoneAt = 80

  /// In the owner's order (settings sidebar). `splitBuds` keeps Left and Right apart always, for
  /// settings, where each bud has its own rule. `forWidget` drops devices not seen for `hideAfter`
  /// and buds charging in the case at `budsDoneAt` or more.
  public func items(now: Date, splitBuds: Bool = false, forWidget: Bool = false) -> [BatteryItem] {
    let shown = forWidget ? devices.filter { now.timeIntervalSince($0.seenAt) < Self.hideAfter } : devices
    return shown.flatMap { known in
      let live = known.live && now.timeIntervalSince(known.seenAt) < Self.staleAfter
      let items = Self.items(of: known.device, live: live, splitBuds: splitBuds)
      guard forWidget else { return items }
      return items.filter { !($0.role != .case && known.device.kind == .headphones && $0.charging && $0.percent >= Self.budsDoneAt) }
    }
  }

  static func items(of device: Device, live: Bool, splitBuds: Bool = false) -> [BatteryItem] {
    func item(_ role: PartRole, _ percent: Int, _ charging: Bool) -> BatteryItem {
      let name = role == .main ? device.name : "\(device.name) \(role.rawValue.capitalized)"
      return BatteryItem(deviceID: device.id, name: name, kind: device.kind, role: role, percent: percent, charging: charging, live: live)
    }
    var buds: [BatteryItem] = []
    if !splitBuds, let left = device.part(.left), let right = device.part(.right), abs(left.percent - right.percent) <= budsSpread {
      buds = [item(.main, min(left.percent, right.percent), left.charging || right.charging)]
    } else {
      buds = [device.part(.left), device.part(.right)].compactMap { $0 }.map { item($0.role, $0.percent, $0.charging) }
    }
    let main = device.part(.main).map { [item(.main, $0.percent, $0.charging)] } ?? []
    let caseItem = device.part(.case).map { [item(.case, $0.percent, $0.charging)] } ?? []
    return main + buds + caseItem
  }
}

/// Where the app and the widget share files. The widget is sandboxed, so the App Group container
/// is the only directory both can reach. Only the signed bundles touch it: macOS 15+ can prompt the owner
/// before an unsigned process (the CLI) reads another app's group container, so the CLI keeps its own cache.
public enum Store {
  public static let appGroup = "73R36N2A46.com.akim.batteries"

  public static var directory: URL {
    // Never nil on macOS: the path is built from the identifier, entitled or not.
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
      ?? URL(filePath: NSHomeDirectory()).appending(path: "Library/Group Containers/\(appGroup)")
  }

  public static var snapshotURL: URL { directory.appendingPathComponent("snapshot.json") }
}
