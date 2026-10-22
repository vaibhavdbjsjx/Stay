import Foundation

enum DeviceRole: String, Codable, CaseIterable, Identifiable, Sendable {
    /// The owner's own phone: plans, missions, alerts and progress.
    case owner
    /// A spare iPhone or iPad that watches the dog.
    case camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner: String(localized: "My phone")
        case .camera: String(localized: "Dog camera")
        }
    }
}

/// How this device is linked to its partner device.
struct DeviceLink: Codable, Hashable, Sendable {
    enum Database: String, Codable, Sendable {
        /// Both devices use the same iCloud account.
        case privateDB
        /// The camera joined the owner's zone through a CloudKit share.
        case sharedDB
        /// No iCloud: nearby (Wi-Fi) only.
        case nearbyOnly
    }

    var linkID: String
    var database: Database
    var zoneName: String
    var zoneOwnerName: String?
    var shareURL: URL?
    var partnerName: String?
    var pairedAt = Date.now
}

struct AppPreferences: Codable, Hashable, Sendable {
    var role: DeviceRole?
    var hasCompletedOnboarding = false
    var selectedDogID: UUID?
    var remindersEnabled = true
    var reminderHour = 9
    var reminderMinute = 0
    var link: DeviceLink?
    /// Camera mode: sensitivity used when no dog setting arrives from the owner.
    var cameraSensitivity: DetectionSensitivity = .balanced
    var cameraDisplayName: String?
}

struct CueLogEntry: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var dogID: UUID
    var date = Date.now
    var cue: CueKind?
    var reaction: CueReaction
}

/// Everything Stay stores on the device, in one Codable document.
struct StayDatabase: Codable, Sendable {
    var schemaVersion = 1
    var dogs: [Dog] = []
    var sessions: [AbsenceSession] = []
    var journal: [JournalEntry] = []
    var cueLog: [CueLogEntry] = []
    var celebrated: [UUID: [Milestone]] = [:]
    var preferences = AppPreferences()
}
