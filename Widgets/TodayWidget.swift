import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: .now, snapshot: context.isPreview ? .placeholder : (WidgetSnapshot.load() ?? .placeholder)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry(date: .now, snapshot: WidgetSnapshot.load() ?? .empty)
        // The app reloads timelines whenever the plan changes; refresh after midnight too.
        let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400)).addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(tomorrow)))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StayToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(hex: 0x4A7A6B), Color(hex: 0x24443B)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Today's mission")
        .description("Your dog's mission for today and training streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TodayEntry

    private let cream = Color(hex: 0xFBF3E6)
    private let apricot = Color(hex: 0xF2A477)

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemMedium: medium
        default: small
        }
    }

    private var s: WidgetSnapshot { entry.snapshot }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StayMark(faceColor: Color(hex: 0x24443B)).frame(width: 26, height: 26)
                Spacer()
                streakBadge
            }
            Spacer(minLength: 0)
            Text(s.dogName.isEmpty ? String(localized: "Stay") : s.dogName)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(cream.opacity(0.7))
            Text(s.todayTitle)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(cream)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if s.isDoneToday || s.isRestDay {
                Image(systemName: s.isDoneToday ? "checkmark.seal.fill" : "leaf.fill").foregroundStyle(apricot)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    StayMark(faceColor: Color(hex: 0x24443B)).frame(width: 24, height: 24)
                    Text(s.dogName.isEmpty ? String(localized: "Stay") : s.dogName)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(cream.opacity(0.7))
                }
                Spacer(minLength: 0)
                Text(s.todayTitle).font(.system(.title3, design: .serif).weight(.semibold)).foregroundStyle(cream).lineLimit(2)
                Text(s.todayDetail).font(.system(.caption, design: .rounded)).foregroundStyle(cream.opacity(0.8)).lineLimit(2)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                streakBadge
                Spacer(minLength: 0)
                if !s.recentDurations.isEmpty {
                    let peak = max(s.recentDurations.max() ?? 1, 1)
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array(s.recentDurations.enumerated()), id: \.offset) { index, value in
                            Capsule()
                                .fill(index == s.recentDurations.count - 1 ? apricot : cream.opacity(0.5))
                                .frame(width: 7, height: max(6, CGFloat(value / peak) * 46))
                        }
                    }
                    .frame(height: 48, alignment: .bottom)
                }
                if s.longestCalmSeconds > 0 {
                    Text("Best \(DurationText.short(s.longestCalmSeconds))").font(.system(.caption2, design: .rounded).weight(.semibold)).foregroundStyle(cream.opacity(0.8))
                }
            }
        }
    }

    private var streakBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
            Text("\(s.streakDays)")
        }
        .font(.system(.caption, design: .rounded).weight(.bold))
        .foregroundStyle(Color(hex: 0x24443B))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(apricot, in: Capsule())
        .accessibilityLabel(Text("\(s.streakDays) day streak"))
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill").font(.caption)
                Text("\(s.streakDays)").font(.system(.title3, design: .rounded).weight(.bold))
            }
        }
        .widgetAccentable()
        .accessibilityLabel(Text("\(s.streakDays) day streak"))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(s.dogName.isEmpty ? String(localized: "Stay") : s.dogName, systemImage: "pawprint.fill")
                .font(.caption.weight(.semibold))
                .widgetAccentable()
            Text(s.todayTitle).font(.headline).lineLimit(1)
            Text(s.todayDetail).font(.caption).lineLimit(1)
        }
    }

    private var inline: some View {
        Label(s.todayTitle, systemImage: "pawprint.fill")
    }
}

#Preview(as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
}
