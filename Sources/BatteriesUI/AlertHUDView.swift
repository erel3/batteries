import BatteriesCore
import SwiftUI

/// The centre-of-screen alert: a big ring, red for "plug it in", green for "unplug it".
/// One that waits for a click says so.
public struct AlertHUDView: View {
  let item: BatteryItem
  let kind: AlertKind
  let untilClicked: Bool

  public init(item: BatteryItem, kind: AlertKind, untilClicked: Bool = false) {
    self.item = item
    self.kind = kind
    self.untilClicked = untilClicked
  }

  public var body: some View {
    VStack(spacing: 10) {
      BatteryRing(item: item, tint: kind == .low ? .red : .green).frame(width: 110, height: 110)
      Text("\(item.percent)%").font(.title.weight(.semibold)).monospacedDigit()
      Text(item.name).font(.headline).lineLimit(1)
      Text(kind == .low ? "Low Battery" : "Charged").font(.subheadline).foregroundStyle(.secondary)
      if untilClicked {
        Text("Click to close").font(.caption).foregroundStyle(.tertiary)
      }
    }
    .padding(24)
    .frame(width: 220, height: untilClicked ? 280 : 260)
  }
}
