import BatteriesCore
import Foundation

// `batteries [--json] [--no-phone]`: reads every source once, merges into the last-known cache,
// and prints each device. Away devices keep their last value, marked with its age.

let arguments = Set(CommandLine.arguments.dropFirst())
let unknown = arguments.subtracting(["--json", "--no-phone"])
guard unknown.isEmpty else {
  FileHandle.standardError.write(Data("usage: batteries [--json] [--no-phone]\n".utf8))
  exit(64)
}

let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
  .appendingPathComponent("Batteries/snapshot.json")
let now = Date()
var snapshot = Snapshot.load(from: cache)
snapshot.merge(PowerSources.read(), from: .powerSources, at: now)
if !arguments.contains("--no-phone") {
  snapshot.merge(IPhoneBattery.read(), from: .iphone, at: now)
}
do {
  try snapshot.save(to: cache)
} catch {
  FileHandle.standardError.write(Data("batteries: cannot save \(cache.path): \(error)\n".utf8))
}

if arguments.contains("--json") {
  print(String(bytes: try Snapshot.encoder.encode(snapshot), encoding: .utf8) ?? "")
  exit(0)
}

func age(_ date: Date) -> String {
  let seconds = Int(now.timeIntervalSince(date))
  switch seconds {
  case ..<60: return "just now"
  case ..<3600: return "\(seconds / 60) min ago"
  case ..<86_400: return "\(seconds / 3600) h ago"
  default: return "\(seconds / 86_400) d ago"
  }
}

for known in snapshot.devices {
  let parts = known.device.parts.map { part in
    let label = part.role == .main ? "" : "\(part.role.rawValue) "
    return "\(label)\(part.percent)%\(part.charging ? " charging" : "")"
  }.joined(separator: ", ")
  let state = known.live ? "" : "  (away, \(age(known.seenAt)))"
  print("\(known.device.name) [\(known.device.kind.rawValue)]: \(parts)\(state)")
}
