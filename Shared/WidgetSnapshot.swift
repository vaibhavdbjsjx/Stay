import Foundation

/// A small summary the app writes to the App Group so the widget can render
/// without touching the main database.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    var dogName: String
    var streakDays: Int
    var todayTitle: String
    var todayDetail: String
    var isRestDay: Bool
    var isDoneToday: Bool
    var longestCalmSeconds: TimeInterval
    var recentDurations: [TimeInterval]
    var updatedAt: Date

    static let placeholder = WidgetSnapshot(
        dogName: "Your dog",
        streakDays: 4,
        todayTitle: String(localized: "Leave for 3 min 20 s"),
        todayDetail: String(localized: "Then 5 calm key pick-ups"),
        isRestDay: false,
        isDoneToday: false,
        longestCalmSeconds: 185,
        recentDurations: [60, 70, 80, 75, 95, 110, 125],
        updatedAt: .now
    )

    static let empty = WidgetSnapshot(
        dogName: "",
        streakDays: 0,
        todayTitle: String(localized: "Set up Stay"),
        todayDetail: String(localized: "Open the app to create your dog's plan"),
        isRestDay: false,
        isDoneToday: false,
        longestCalmSeconds: 0,
        recentDurations: [],
        updatedAt: .now
    )

    private static var fileURL: URL {
        SharedConfig.sharedContainerURL.appendingPathComponent("widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
