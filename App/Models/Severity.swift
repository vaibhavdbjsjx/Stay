import Foundation

enum SeverityLevel: String, Codable, CaseIterable, Sendable {
    case mild
    case moderate
    case severe

    var title: String {
        switch self {
        case .mild: String(localized: "Mild")
        case .moderate: String(localized: "Moderate")
        case .severe: String(localized: "Significant")
        }
    }

    var summary: String {
        switch self {
        case .mild:
            String(localized: "Small, steady steps should work well. Expect to make progress quickly.")
        case .moderate:
            String(localized: "We'll keep sessions short and build up gently. Consistency beats speed.")
        case .severe:
            String(localized: "We'll take very small steps. Please also talk to your vet — they can rule out pain and discuss support that works alongside training.")
        }
    }
}

struct SeverityAssessment: Codable, Hashable, Sendable {
    /// Question id → chosen option index.
    var answers: [String: Int]
    var score: Int
    var level: SeverityLevel
    var recommendsVet: Bool

    static let unanswered = SeverityAssessment(answers: [:], score: 0, level: .moderate, recommendsVet: false)
}

struct SeverityQuestion: Identifiable, Sendable {
    struct Option: Sendable {
        let title: String
        let score: Int
        let flagsVet: Bool
    }

    let id: String
    let prompt: String
    let options: [Option]
}

/// A short questionnaire modelled on the intake forms used by separation
/// anxiety trainers. It sizes the first steps; it is not a diagnosis.
enum SeverityQuestionnaire {
    static func questions(dogName: String) -> [SeverityQuestion] {
        [
            SeverityQuestion(id: "tolerance", prompt: String(localized: "How long can \(dogName) stay alone before getting upset?"), options: [
                .init(title: String(localized: "Less than a minute"), score: 3, flagsVet: false),
                .init(title: String(localized: "A few minutes"), score: 2, flagsVet: false),
                .init(title: String(localized: "15 to 30 minutes"), score: 1, flagsVet: false),
                .init(title: String(localized: "Longer, but not long enough"), score: 0, flagsVet: false),
            ]),
            SeverityQuestion(id: "vocal", prompt: String(localized: "Does \(dogName) bark, howl or whine when alone?"), options: [
                .init(title: String(localized: "Never"), score: 0, flagsVet: false),
                .init(title: String(localized: "Sometimes"), score: 1, flagsVet: false),
                .init(title: String(localized: "Most times"), score: 2, flagsVet: false),
                .init(title: String(localized: "Every time"), score: 3, flagsVet: false),
            ]),
            SeverityQuestion(id: "destructive", prompt: String(localized: "Any chewing or scratching at doors and windows?"), options: [
                .init(title: String(localized: "No"), score: 0, flagsVet: false),
                .init(title: String(localized: "Occasionally"), score: 1, flagsVet: false),
                .init(title: String(localized: "Often"), score: 2, flagsVet: false),
                .init(title: String(localized: "Yes, and they've hurt their paws or teeth"), score: 3, flagsVet: true),
            ]),
            SeverityQuestion(id: "toileting", prompt: String(localized: "Accidents indoors only when left alone?"), options: [
                .init(title: String(localized: "No"), score: 0, flagsVet: false),
                .init(title: String(localized: "Sometimes"), score: 1, flagsVet: false),
                .init(title: String(localized: "Usually"), score: 2, flagsVet: false),
            ]),
            SeverityQuestion(id: "predeparture", prompt: String(localized: "Does \(dogName) get worried as you get ready to leave?"), options: [
                .init(title: String(localized: "No"), score: 0, flagsVet: false),
                .init(title: String(localized: "A little — they follow me around"), score: 1, flagsVet: false),
                .init(title: String(localized: "Yes — panting, pacing or trembling"), score: 2, flagsVet: false),
            ]),
            SeverityQuestion(id: "eating", prompt: String(localized: "Will \(dogName) eat a treat or chew while you're gone?"), options: [
                .init(title: String(localized: "Yes"), score: 0, flagsVet: false),
                .init(title: String(localized: "Not usually"), score: 1, flagsVet: false),
            ]),
            SeverityQuestion(id: "escape", prompt: String(localized: "Has \(dogName) ever tried to escape a crate, room or house?"), options: [
                .init(title: String(localized: "No"), score: 0, flagsVet: false),
                .init(title: String(localized: "Yes"), score: 2, flagsVet: false),
                .init(title: String(localized: "Yes, and got injured"), score: 3, flagsVet: true),
            ]),
        ]
    }

    static func assess(answers: [String: Int], dogName: String = "") -> SeverityAssessment {
        let questions = questions(dogName: dogName)
        var score = 0
        var vet = false
        for question in questions {
            guard let index = answers[question.id], question.options.indices.contains(index) else { continue }
            let option = question.options[index]
            score += option.score
            vet = vet || option.flagsVet
        }
        let level: SeverityLevel = switch score {
        case ..<6: .mild
        case 6..<11: .moderate
        default: .severe
        }
        return SeverityAssessment(answers: answers, score: score, level: level, recommendsVet: vet || level == .severe)
    }
}
