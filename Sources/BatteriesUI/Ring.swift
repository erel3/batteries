import BatteriesCore
import SwiftUI

extension BatteryItem {
  /// SF Symbol for the ring's centre, as macOS's own Batteries widget draws each device.
  public var symbol: String {
    switch kind {
    case .mac: return "laptopcomputer"
    case .phone: return "iphone"
    case .keyboard: return "keyboard"
    case .mouse: return "magicmouse"
    case .gamepad: return "gamecontroller"
    case .other: return "battery.100percent"
    case .headphones: return headphonesSymbol
    }
  }

  private var headphonesSymbol: String {
    guard name.localizedCaseInsensitiveContains("airpods") else {
      return [.main: "headphones", .case: "earbuds.case"][role] ?? "earbuds"
    }
    if name.localizedCaseInsensitiveContains("max") { return "airpodsmax" }
    let pro = name.localizedCaseInsensitiveContains("pro")
    switch role {
    case .main: return pro ? "airpodspro" : "airpods"
    case .left: return pro ? "airpodpro.left" : "airpod.left"
    case .right: return pro ? "airpodpro.right" : "airpod.right"
    case .case: return pro ? "airpodspro.chargingcase.wireless.fill" : "airpods.chargingcase.fill"
    }
  }

  /// Same rule as the system widget: red at 20% and below, green otherwise, grey when not current.
  public var tint: Color {
    guard live else { return .gray }
    return percent <= 20 ? .red : .green
  }
}

/// The circular gauge: a track, the charge arc from 12 o'clock clockwise, the device glyph inside
/// and a bolt cut into the top of the ring while charging. Scales with its frame.
public struct BatteryRing: View {
  let item: BatteryItem
  let tint: Color

  public init(item: BatteryItem, tint: Color? = nil) {
    self.item = item
    self.tint = tint ?? item.tint
  }

  public var body: some View {
    GeometryReader { geometry in
      let side = min(geometry.size.width, geometry.size.height)
      let line = side * 0.09
      ZStack {
        Circle().stroke(.primary.opacity(0.15), lineWidth: line)
        Circle()
          .trim(from: 0, to: CGFloat(max(item.percent, 2)) / 100)
          .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .widgetAccentable()
        Image(systemName: item.symbol)
          .font(.system(size: side * 0.36, weight: .medium))
          .foregroundStyle(item.live ? .primary : .secondary)
        if item.charging {
          Image(systemName: "bolt.fill")
            .font(.system(size: side * 0.2, weight: .bold))
            .foregroundStyle(tint)
            .padding(side * 0.03)
            .background(Circle().fill(.background))
            .offset(y: -side / 2)
        }
      }
      .padding(line / 2)
      .frame(width: side, height: side)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(item.name) \(item.percent)%\(item.charging ? ", charging" : "")")
  }
}
