import BatteriesCore
import SwiftUI
import WidgetKit

/// The widget body for each size, after macOS's own Batteries widget:
/// small, one device: a large ring and its percent; small, several: a 2×2 grid of rings;
/// medium: up to four rings in a row with the percent under each;
/// large: six rows of glyph, name, percent and battery bar.
/// Values that are not current are dimmed. Takes the family explicitly so tests can render it.
public struct BatteriesWidgetView: View {
  let items: [BatteryItem]
  let family: WidgetFamily

  public init(items: [BatteryItem], family: WidgetFamily) {
    self.items = items
    self.family = family
  }

  public var body: some View {
    if items.isEmpty {
      Text("No batteries").font(.callout).foregroundStyle(.secondary)
    } else {
      switch family {
      case .systemSmall where items.count == 1: single(items[0])
      case .systemSmall: grid(Self.fit(items, slots: 4))
      case .systemMedium: row(Self.fit(items, slots: 4))
      default: list(Self.fit(items, slots: 6))
      }
    }
  }

  /// More batteries than slots: current ones win over greyed ones, and within each, buds and
  /// devices win over AirPods cases. Shown in the owner's order.
  static func fit(_ items: [BatteryItem], slots: Int) -> [BatteryItem] {
    guard items.count > slots else { return items }
    func rank(_ item: BatteryItem) -> Int { (item.live ? 0 : 2) + (item.role == .case ? 1 : 0) }
    let byRank = items.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
    let kept = Set(byRank.prefix(slots).map(\.element.id))
    return items.filter { kept.contains($0.id) }
  }

  private func single(_ item: BatteryItem) -> some View {
    VStack(spacing: 8) {
      BatteryRing(item: item).padding(.horizontal, 12)
      percent(item).font(.title2.weight(.semibold))
    }
    .opacity(item.live ? 1 : 0.5)
  }

  private func grid(_ items: [BatteryItem]) -> some View {
    Grid(horizontalSpacing: 14, verticalSpacing: 14) {
      ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
        GridRow {
          ForEach(items[start..<min(start + 2, items.count)]) { item in
            BatteryRing(item: item).opacity(item.live ? 1 : 0.5)
          }
        }
      }
    }
  }

  private func row(_ items: [BatteryItem]) -> some View {
    HStack(spacing: 16) {
      ForEach(items) { item in
        VStack(spacing: 8) {
          BatteryRing(item: item)
          percent(item).font(.callout.weight(.semibold))
        }
        .opacity(item.live ? 1 : 0.5)
      }
    }
  }

  /// As macOS's own large Batteries widget: six fixed rows of glyph, name, percent and a battery
  /// bar, hairlines between them from the name on, empty rows kept so the grid never shifts.
  private func list(_ items: [BatteryItem]) -> some View {
    let rows = 6
    return VStack(spacing: 0) {
      ForEach(0..<rows, id: \.self) { index in
        Group {
          if index < items.count { listRow(items[index]) } else { Color.clear }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
          // From the name to the widget's right edge, past the content margin, as Apple draws it.
          if index < rows - 1 { Rectangle().fill(.primary.opacity(0.2)).frame(height: 1).padding(.leading, 34).padding(.trailing, -24) }
        }
      }
    }
  }

  private func listRow(_ item: BatteryItem) -> some View {
    HStack(spacing: 10) {
      Image(systemName: item.symbol).font(.system(size: 14)).frame(width: 24)
      Text(item.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
      Spacer(minLength: 4)
      percent(item).font(.system(size: 10, weight: .medium))
      BatteryBar(item: item).frame(width: 24, height: 11)
    }
    .opacity(item.live ? 1 : 0.5)
  }

  private func percent(_ item: BatteryItem) -> some View {
    Text("\(item.percent)%").monospacedDigit().foregroundStyle(item.live ? .primary : .secondary)
  }
}

/// The horizontal battery of macOS's own large widget: green with a bolt while charging, red at
/// 20% and below, yellow for the Mac in Low Power Mode, otherwise the text colour.
struct BatteryBar: View {
  let item: BatteryItem

  private var fill: Color {
    if item.charging { return .green }
    if item.percent <= 20 { return .red }
    if item.kind == .mac && ProcessInfo.processInfo.isLowPowerModeEnabled { return .yellow }
    return .primary
  }

  var body: some View {
    HStack(spacing: 1) {
      ZStack {
        RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.4), lineWidth: 1)
        GeometryReader { geometry in
          RoundedRectangle(cornerRadius: 1.5)
            .fill(fill)
            .frame(width: max(2, geometry.size.width * CGFloat(item.percent) / 100))
            .widgetAccentable()
        }
        .padding(2)
        if item.charging {
          Image(systemName: "bolt.fill")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 0.5)
        }
      }
      RoundedRectangle(cornerRadius: 1).fill(.primary.opacity(0.4)).frame(width: 1.5, height: 4)
    }
  }
}
