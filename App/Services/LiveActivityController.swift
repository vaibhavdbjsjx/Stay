import ActivityKit
import Foundation

/// Runs the mission timer on the Lock Screen and in the Dynamic Island.
@MainActor
final class LiveActivityController {
    private var activity: Activity<MissionActivityAttributes>?

    func start(session: AbsenceSession, dogName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end(status: .ended, eventCount: 0)
        let attributes = MissionActivityAttributes(sessionID: session.id, dogName: dogName, startedAt: session.startedAt, targetSeconds: session.plannedSeconds)
        let state = MissionActivityAttributes.ContentState(status: .calm, eventCount: 0, lastEventLabel: nil, endedAt: nil)
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: session.startedAt.addingTimeInterval(max(session.plannedSeconds, 60) + 3600))
        )
    }

    func update(status: MissionActivityAttributes.ContentState.Status, eventCount: Int, lastEventLabel: String?) {
        guard let activity else { return }
        let state = MissionActivityAttributes.ContentState(status: status, eventCount: eventCount, lastEventLabel: lastEventLabel, endedAt: nil)
        let box = UncheckedBox(value: activity)
        Task { await box.value.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end(status: MissionActivityAttributes.ContentState.Status, eventCount: Int) {
        guard let ending = activity else { return }
        activity = nil
        let finalState = MissionActivityAttributes.ContentState(status: status, eventCount: eventCount, lastEventLabel: nil, endedAt: .now)
        let box = UncheckedBox(value: ending)
        Task {
            await box.value.end(ActivityContent(state: finalState, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(60)))
        }
    }

    /// Ends activities left over from a previous launch (e.g. after a crash).
    func endStaleActivities(keeping sessionID: UUID?) {
        Task {
            for stale in Activity<MissionActivityAttributes>.activities where stale.attributes.sessionID != sessionID {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
