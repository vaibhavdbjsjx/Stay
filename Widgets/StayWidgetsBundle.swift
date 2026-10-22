import SwiftUI
import WidgetKit

@main
struct StayWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "x", provider: P()) { _ in Text("x") }
    }
}
struct P: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) { completion(SimpleEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) { completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never)) }
}
struct SimpleEntry: TimelineEntry { let date: Date }
