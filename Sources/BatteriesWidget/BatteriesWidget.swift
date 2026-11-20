import BatteriesCore
import BatteriesUI
import SwiftUI
import WidgetKit

// The widget never reads a battery itself: the sandbox would not let it. It only draws the snapshot
// the app writes to the App Group container, and the app asks WidgetCenter to reload when it changes.

struct Entry: TimelineEntry {
  let date: Date
  let items: [BatteryItem]
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> Entry {
    Entry(date: .now, items: [
      BatteryItem(deviceID: "mac", name: "MacBook Pro", kind: .mac, role: .main, percent: 80, charging: false, live: true),
      BatteryItem(deviceID: "pods", name: "AirPods Pro", kind: .headphones, role: .main, percent: 64, charging: false, live: true),
      BatteryItem(deviceID: "pods", name: "AirPods Pro Case", kind: .headphones, role: .case, percent: 95, charging: true, live: true),
      BatteryItem(deviceID: "kb", name: "Keyboard", kind: .keyboard, role: .main, percent: 18, charging: false, live: true)
    ])
  }

  func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : current())
  }

  /// Re-read every 15 min even without a push from the app, so values the app stopped refreshing
  /// (it quit) turn grey on time.
  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    let entry = current()
    completion(Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(Snapshot.staleAfter))))
  }

  private func current() -> Entry {
    let now = Date.now
    return Entry(date: now, items: Snapshot.load(from: Store.snapshotURL).items(now: now, forWidget: true))
  }
}

struct EntryView: View {
  @Environment(\.widgetFamily) private var family
  let entry: Entry

  var body: some View {
    BatteriesWidgetView(items: entry.items, family: family)
      // The system's default widget background, as Stocks has. macOS 27's own Batteries widget is
      // Liquid Glass, which other apps' widgets cannot get: materials and translucent colours come
      // out the same grey (measured 2026-11-21).
      .containerBackground(for: .widget) { Color.clear }
  }
}

@main
struct BatteryWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "com.akim.batteries.widget", provider: Provider()) { entry in
      EntryView(entry: entry)
    }
    .configurationDisplayName("Batteries")
    .description("Battery of the Mac and its accessories, and the iPhone.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
