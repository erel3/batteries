import Foundation

/// Which reader a device's values came from. Each reader is merged on its own schedule, so a
/// phone read never marks the keyboard as away and the other way round.
public enum Source: String, Codable, Sendable {
  case powerSources, iphone
}

/// The last value ever seen for a device, and whether the latest read of its source still saw it.
/// A device that is away keeps its last values with `live == false`: the UI greys it and shows
/// its age, and alerts ignore it.
public struct Known: Codable, Equatable, Sendable, Identifiable {
  public var device: Device
  public var source: Source
  public var seenAt: Date
  public var live: Bool

  public var id: String { device.id }
}

public struct Snapshot: Codable, Equatable, Sendable {
  public var devices: [Known] = []

  public init(devices: [Known] = []) {
    self.devices = devices
  }

  /// Replaces what `source` reported last time with `readings`. Devices of that source missing
  /// from `readings` stay, marked away. Order is first-seen order, so rows never jump around.
  public mutating func merge(_ readings: [Device], from source: Source, at now: Date) {
    let seen = Set(readings.map(\.id))
    for index in devices.indices where devices[index].source == source && !seen.contains(devices[index].id) {
      devices[index].live = false
    }
    for reading in readings {
      let known = Known(device: reading, source: source, seenAt: now, live: true)
      if let index = devices.firstIndex(where: { $0.id == reading.id }) {
        devices[index] = known
      } else if reading.kind == .mac {
        devices.insert(known, at: 0)  // a new Mac starts first; after that the owner's order holds
      } else {
        devices.append(known)
      }
    }
  }

  public static func load(from url: URL) -> Snapshot {
    guard let data = try? Data(contentsOf: url) else { return Snapshot() }
    return (try? decoder.decode(Snapshot.self, from: data)) ?? Snapshot()
  }

  public func save(to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Self.encoder.encode(self).write(to: url, options: .atomic)
  }

  public static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
