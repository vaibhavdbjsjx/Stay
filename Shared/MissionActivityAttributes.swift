import ActivityKit
import Foundation

/// Live Activity / Dynamic Island payload for a running mission.
struct MissionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Status: String, Codable, Hashable, Sendable {
            case calm
            case alert
            case timeToReturn
            case ended
        }

        var status: Status
        var eventCount: Int
        var lastEventLabel: String?
        var endedAt: Date?
    }

    var sessionID: UUID
    var dogName: String
    var startedAt: Date
    var targetSeconds: TimeInterval

    var targetEnd: Date { startedAt.addingTimeInterval(targetSeconds) }
}
