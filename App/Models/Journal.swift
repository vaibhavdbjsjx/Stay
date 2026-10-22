import Foundation

enum JournalMood: String, Codable, CaseIterable, Identifiable, Sendable {
    case great
    case okay
    case rough

    var id: String { rawValue }

    var title: String {
        switch self {
        case .great: String(localized: "Great day")
        case .okay: String(localized: "Okay")
        case .rough: String(localized: "Rough day")
        }
    }

    var symbol: String {
        switch self {
        case .great: "sun.max.fill"
        case .okay: "cloud.sun.fill"
        case .rough: "cloud.rain.fill"
        }
    }
}

struct JournalEntry: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var dogID: UUID
    var date = Date.now
    var mood: JournalMood
    var text: String
}
