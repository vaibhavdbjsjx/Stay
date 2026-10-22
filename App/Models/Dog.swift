import Foundation

enum DetectionSensitivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case relaxed
    case balanced
    case watchful

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relaxed: String(localized: "Relaxed")
        case .balanced: String(localized: "Balanced")
        case .watchful: String(localized: "Watchful")
        }
    }

    var detail: String {
        switch self {
        case .relaxed: String(localized: "Only sustained barking, howling or pacing. Fewer alerts.")
        case .balanced: String(localized: "Recommended. Ignores a single woof, catches real distress.")
        case .watchful: String(localized: "Flags early, quiet signs like whining. More alerts to review.")
        }
    }
}

struct Dog: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var breed: String
    var ageYears: Int
    var ageMonths: Int
    var photoFilename: String?
    var assessment: SeverityAssessment
    var plan: PlanState
    var sensitivity: DetectionSensitivity = .balanced
    /// Calendar weekdays (1 = Sunday … 7 = Saturday) kept free of absences.
    var restWeekdays: Set<Int> = []
    var createdAt = Date.now

    var severity: SeverityLevel { assessment.level }

    var ageDescription: String {
        switch (ageYears, ageMonths) {
        case (0, let m): String(localized: "\(m) months old")
        case (let y, 0): String(localized: "\(y) years old")
        case (let y, let m): String(localized: "\(y) y \(m) m old")
        }
    }

    var initials: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}
