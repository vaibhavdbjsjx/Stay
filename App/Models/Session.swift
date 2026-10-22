import Foundation

enum SessionKind: String, Codable, Sendable {
    case baseline
    case mission
}

enum MonitoringSource: String, Codable, Sendable {
    case nearby        // MultipeerConnectivity, same Wi-Fi
    case cloud         // CloudKit relay
    case selfObserved  // no camera; owner reports what happened
}

enum DistressKind: String, Codable, CaseIterable, Sendable {
    case bark
    case howl
    case whimper
    case growl
    case pacing
    case other

    var title: String {
        switch self {
        case .bark: String(localized: "Barking")
        case .howl: String(localized: "Howling")
        case .whimper: String(localized: "Whining")
        case .growl: String(localized: "Growling")
        case .pacing: String(localized: "Pacing")
        case .other: String(localized: "Other sign")
        }
    }

    var symbol: String {
        switch self {
        case .bark: "speaker.wave.3.fill"
        case .howl: "waveform"
        case .whimper: "waveform.path"
        case .growl: "speaker.wave.2.fill"
        case .pacing: "figure.walk.motion"
        case .other: "exclamationmark.bubble.fill"
        }
    }
}

enum EventReview: String, Codable, Sendable {
    case pending
    case confirmed
    case dismissed
}

struct DistressEvent: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    /// Seconds since the session started.
    var offset: TimeInterval
    var kind: DistressKind
    var confidence: Double
    var duration: TimeInterval
    var snapshotFilename: String?
    var review: EventReview = .pending
    var isManual = false
}

enum SessionEndReason: String, Codable, Sendable {
    case completed       // owner came back at or after the target
    case returnedEarly   // owner came back before the target
    case distress        // owner came back because of an alert
    case cameraStopped   // the camera device stopped (battery, heat, user)
}

struct AbsenceSession: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var dogID: UUID
    var kind: SessionKind
    var plannedSeconds: TimeInterval
    var startedAt: Date
    var endedAt: Date?
    var monitoring: MonitoringSource
    var events: [DistressEvent] = []
    /// Normalised sound level (0…1), one sample every `levelInterval` seconds.
    var levelTimeline: [Float] = []
    var levelInterval: TimeInterval = 5
    var snapshotFilenames: [String] = []
    var isReviewed = false
    var endReason: SessionEndReason?
    var note = ""

    var isFinished: Bool { endedAt != nil }

    var actualSeconds: TimeInterval {
        guard let endedAt else { return Date.now.timeIntervalSince(startedAt) }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    var confirmedEvents: [DistressEvent] { events.filter { $0.review == .confirmed } }
    var pendingEvents: [DistressEvent] { events.filter { $0.review == .pending } }
    var firstConfirmedDistress: TimeInterval? { confirmedEvents.map(\.offset).min() }

    /// The outcome the mission engine consumes. `nil` until the owner reviews.
    var reviewedOutcome: SessionOutcome? {
        guard isReviewed, isFinished else { return nil }
        if let first = firstConfirmedDistress {
            return .distress(firstSignAt: first, duration: actualSeconds)
        }
        if actualSeconds >= plannedSeconds * SessionOutcome.completionRatio {
            return .calm(duration: actualSeconds)
        }
        return .incomplete(duration: actualSeconds)
    }

    var isCalm: Bool {
        if case .calm = reviewedOutcome { return true }
        return false
    }
}

/// What actually happened, as confirmed by the owner.
enum SessionOutcome: Equatable, Sendable {
    case calm(duration: TimeInterval)
    case distress(firstSignAt: TimeInterval, duration: TimeInterval)
    case incomplete(duration: TimeInterval)

    /// A session counts as complete when the dog was alone for at least this share of the plan.
    static let completionRatio = 0.9
}
