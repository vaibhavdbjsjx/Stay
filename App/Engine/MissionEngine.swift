import Foundation

// MARK: - Plan state

/// Everything the engine needs to remember about a dog's training plan.
/// Pure value type: the engine never mutates anything else.
struct PlanState: Codable, Hashable, Sendable {
    enum Phase: String, Codable, Sendable {
        case needsBaseline
        case training
    }

    var phase: Phase = .needsBaseline
    var baselineSeconds: TimeInterval?
    var targetSeconds: TimeInterval = 0
    var lastCalmSeconds: TimeInterval?
    var longestCalmSeconds: TimeInterval = 0
    var consecutiveCalm = 0
    var consecutiveDistress = 0
    var totalCalmSessions = 0
    var consecutiveTrainingDays = 0
    var lastTrainingDay: Date?
    var restSuggestedFor: Date?
    var cueStage = 0
    var cueCalmStreak = 0

    static let initial = PlanState()
}

// MARK: - Engine outputs

enum PlanChange: Equatable, Sendable {
    case baselineSet(baseline: TimeInterval, firstTarget: TimeInterval)
    case increased(from: TimeInterval, to: TimeInterval)
    case held(at: TimeInterval)
    case rolledBack(from: TimeInterval, to: TimeInterval)
}

struct PlanUpdate: Equatable, Sendable {
    var state: PlanState
    var change: PlanChange
    var suggestsRestTomorrow: Bool
}

enum RestReason: String, Equatable, Sendable {
    case scheduled
    case afterTrainingStreak
    case afterDistress
}

enum CueKind: String, CaseIterable, Codable, Sendable {
    case keys
    case shoes
    case jacket
    case bag
    case doorHandle
    case doorOpenClose
    case stepOutside

    var title: String {
        switch self {
        case .keys: String(localized: "Pick up your keys")
        case .shoes: String(localized: "Put on your shoes")
        case .jacket: String(localized: "Put on your jacket")
        case .bag: String(localized: "Pick up your bag")
        case .doorHandle: String(localized: "Touch the door handle")
        case .doorOpenClose: String(localized: "Open and close the door")
        case .stepOutside: String(localized: "Step outside for a second")
        }
    }

    var instruction: String {
        switch self {
        case .keys: String(localized: "Pick up your keys, jingle them, put them down and sit back down.")
        case .shoes: String(localized: "Put your shoes on, walk around the room, take them off again.")
        case .jacket: String(localized: "Put your jacket on, make a cup of tea, take it off.")
        case .bag: String(localized: "Lift your bag onto your shoulder, then put it back.")
        case .doorHandle: String(localized: "Walk to the front door, touch the handle, walk away.")
        case .doorOpenClose: String(localized: "Open the front door, close it again, come back inside.")
        case .stepOutside: String(localized: "Step out, close the door, and come straight back in.")
        }
    }

    var symbol: String {
        switch self {
        case .keys: "key.fill"
        case .shoes: "shoe.fill"
        case .jacket: "tshirt.fill"
        case .bag: "bag.fill"
        case .doorHandle: "door.left.hand.closed"
        case .doorOpenClose: "door.left.hand.open"
        case .stepOutside: "figure.walk.departure"
        }
    }
}

enum CueReaction: String, Codable, Sendable, CaseIterable {
    case calm
    case noticed
    case worried

    var title: String {
        switch self {
        case .calm: String(localized: "Didn't care")
        case .noticed: String(localized: "Noticed")
        case .worried: String(localized: "Got worried")
        }
    }
}

struct CueDrill: Equatable, Sendable {
    /// `nil` once every cue is mastered: then the drill mixes all cues.
    var cue: CueKind?
    var reps: Int
    var calmRepsSoFar: Int
    var calmRepsNeeded: Int
}

struct DailyMission: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case baseline(capSeconds: TimeInterval)
        case absence(targetSeconds: TimeInterval)
        case rest(RestReason)
    }

    var kind: Kind
    var warmups: [TimeInterval]
    var cueDrill: CueDrill?
    var completedToday: Bool

    var targetSeconds: TimeInterval? {
        switch kind {
        case .baseline(let cap): cap
        case .absence(let target): target
        case .rest: nil
        }
    }

    var isRestDay: Bool {
        if case .rest = kind { return true }
        return false
    }
}

// MARK: - Configuration

struct EngineConfig: Sendable {
    /// Shortest mission we will ever suggest (stepping out of the door).
    var minimumSeconds: TimeInterval = 5
    /// The baseline test ends here even if the dog stays calm.
    var baselineCapSeconds: TimeInterval = 30 * 60
    /// Never add more than this in one step, however long absences get.
    var maxStepSeconds: TimeInterval = 10 * 60
    /// Rest after this many training days in a row.
    var trainingDaysBeforeRest = 5
    /// After distress, go back to this share of the last duration the dog handled.
    var rollbackFactor = 0.8
    /// Extra rollback applied on the second distress in a row.
    var repeatedDistressFactor = 0.8
    /// Calm cue ratings in a row before moving to the next cue.
    var cueCalmRepsToAdvance = 3

    static let standard = EngineConfig()

    /// Start below the baseline so the very first mission is an easy win.
    func startFactor(for severity: SeverityLevel) -> Double {
        switch severity {
        case .mild: 0.7
        case .moderate: 0.6
        case .severe: 0.5
        }
    }

    /// Growth after a calm session: 10–20 %, gentler for more anxious dogs.
    func increaseStep(for severity: SeverityLevel) -> Double {
        switch severity {
        case .mild: 0.20
        case .moderate: 0.15
        case .severe: 0.10
        }
    }

    func cueReps(for severity: SeverityLevel) -> Int {
        severity == .severe ? 3 : 5
    }
}

// MARK: - Engine

/// The graduated-absence protocol: baseline, small calm steps up, roll back
/// after confirmed distress, regular rest days and pre-departure cue work.
/// Deterministic and side-effect free so every rule is unit-tested.
struct MissionEngine: Sendable {
    var config: EngineConfig = .standard
    var calendar: Calendar = .current

    // MARK: Baseline

    func completeBaseline(_ state: PlanState, outcome: SessionOutcome, severity: SeverityLevel, on day: Date) -> PlanUpdate {
        let baseline: TimeInterval = switch outcome {
        case .calm(let duration): min(duration, config.baselineCapSeconds)
        case .incomplete(let duration): min(duration, config.baselineCapSeconds)
        case .distress(let firstSign, _): firstSign
        }
        let clampedBaseline = max(config.minimumSeconds, baseline)
        let first = max(config.minimumSeconds, Self.roundDown(clampedBaseline * config.startFactor(for: severity)))

        var next = state
        next.phase = .training
        next.baselineSeconds = clampedBaseline
        next.targetSeconds = first
        if case .distress = outcome {
            next.consecutiveDistress = 1
        } else {
            next.longestCalmSeconds = max(next.longestCalmSeconds, clampedBaseline)
            next.lastCalmSeconds = clampedBaseline
        }
        registerTrainingDay(&next, on: day)
        return PlanUpdate(state: next, change: .baselineSet(baseline: clampedBaseline, firstTarget: first), suggestsRestTomorrow: false)
    }

    // MARK: Missions

    /// Move the plan based on a reviewed session. Only confirmed data moves the plan.
    func apply(_ outcome: SessionOutcome, to state: PlanState, severity: SeverityLevel, on day: Date) -> PlanUpdate {
        guard state.phase == .training else {
            return completeBaseline(state, outcome: outcome, severity: severity, on: day)
        }

        var next = state
        let current = state.targetSeconds
        let change: PlanChange
        var restTomorrow = false

        switch outcome {
        case .calm(let duration):
            next.consecutiveCalm += 1
            next.consecutiveDistress = 0
            next.totalCalmSessions += 1
            next.lastCalmSeconds = duration
            next.longestCalmSeconds = max(next.longestCalmSeconds, duration)
            let increased = increase(current, severity: severity)
            next.targetSeconds = increased
            change = .increased(from: current, to: increased)

        case .distress(let firstSign, _):
            next.consecutiveCalm = 0
            next.consecutiveDistress += 1
            // The dog's threshold today is roughly when the first sign appeared.
            let threshold = max(config.minimumSeconds, firstSign)
            let anchor = [threshold, current, state.lastCalmSeconds ?? threshold].min() ?? threshold
            var factor = config.rollbackFactor
            if next.consecutiveDistress >= 2 {
                factor *= config.repeatedDistressFactor
                restTomorrow = true
                next.restSuggestedFor = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))
            }
            let rolled = max(config.minimumSeconds, Self.roundDown(anchor * factor))
            next.targetSeconds = min(rolled, current)
            change = .rolledBack(from: current, to: next.targetSeconds)

        case .incomplete(let duration):
            // Owner came back early with no signs of stress: repeat the same step.
            next.longestCalmSeconds = max(next.longestCalmSeconds, duration)
            change = .held(at: current)
        }

        registerTrainingDay(&next, on: day)
        return PlanUpdate(state: next, change: change, suggestsRestTomorrow: restTomorrow)
    }

    /// A calm step up of 10–20 %, rounded down to a friendly number and
    /// capped so long absences grow by at most `maxStepSeconds`.
    func increase(_ seconds: TimeInterval, severity: SeverityLevel) -> TimeInterval {
        let step = min(seconds * config.increaseStep(for: severity), config.maxStepSeconds)
        let raw = seconds + step
        var rounded = Self.roundDown(raw)
        if rounded <= seconds {
            // Very short missions: always move forward by the smallest friendly unit.
            rounded = seconds + Self.granularity(for: seconds)
        }
        return rounded
    }

    // MARK: Cue drills

    func applyCueReaction(_ reaction: CueReaction, to state: PlanState) -> PlanState {
        var next = state
        guard next.cueStage < CueKind.allCases.count else { return next }
        switch reaction {
        case .calm:
            next.cueCalmStreak += 1
            if next.cueCalmStreak >= config.cueCalmRepsToAdvance {
                next.cueStage += 1
                next.cueCalmStreak = 0
            }
        case .noticed:
            break
        case .worried:
            next.cueCalmStreak = 0
        }
        return next
    }

    func cueDrill(for state: PlanState, severity: SeverityLevel) -> CueDrill {
        let cues = CueKind.allCases
        let cue = state.cueStage < cues.count ? cues[state.cueStage] : nil
        return CueDrill(cue: cue, reps: config.cueReps(for: severity), calmRepsSoFar: state.cueCalmStreak, calmRepsNeeded: config.cueCalmRepsToAdvance)
    }

    // MARK: Today

    func dailyMission(for state: PlanState, severity: SeverityLevel, restWeekdays: Set<Int>, today: Date, completedSessionsToday: Int) -> DailyMission {
        let day = calendar.startOfDay(for: today)

        if state.phase == .needsBaseline {
            return DailyMission(kind: .baseline(capSeconds: config.baselineCapSeconds), warmups: [], cueDrill: nil, completedToday: completedSessionsToday > 0)
        }

        if let rest = restReason(for: state, restWeekdays: restWeekdays, day: day), completedSessionsToday == 0 {
            return DailyMission(kind: .rest(rest), warmups: [], cueDrill: nil, completedToday: false)
        }

        let target = state.targetSeconds
        return DailyMission(
            kind: .absence(targetSeconds: target),
            warmups: warmups(for: target),
            cueDrill: cueDrill(for: state, severity: severity),
            completedToday: completedSessionsToday > 0
        )
    }

    func restReason(for state: PlanState, restWeekdays: Set<Int>, day: Date) -> RestReason? {
        if let suggested = state.restSuggestedFor, calendar.isDate(suggested, inSameDayAs: day) {
            return .afterDistress
        }
        if restWeekdays.contains(calendar.component(.weekday, from: day)) {
            return .scheduled
        }
        if state.consecutiveTrainingDays >= config.trainingDaysBeforeRest,
           let last = state.lastTrainingDay,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
           calendar.isDate(last, inSameDayAs: yesterday) {
            return .afterTrainingStreak
        }
        return nil
    }

    /// Short practice departures before the main mission.
    func warmups(for target: TimeInterval) -> [TimeInterval] {
        guard target >= 20 else { return [] }
        if target < 60 { return [config.minimumSeconds] }
        return [Self.roundDown(target * 0.15), Self.roundDown(target * 0.35)].map { max(config.minimumSeconds, $0) }
    }

    // MARK: Helpers

    private func registerTrainingDay(_ state: inout PlanState, on day: Date) {
        let today = calendar.startOfDay(for: day)
        if let last = state.lastTrainingDay {
            if calendar.isDate(last, inSameDayAs: today) {
                // Same day: streak unchanged.
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate(last, inSameDayAs: yesterday) {
                state.consecutiveTrainingDays += 1
            } else {
                state.consecutiveTrainingDays = 1
            }
        } else {
            state.consecutiveTrainingDays = 1
        }
        state.lastTrainingDay = today
    }

    /// Friendlier numbers the longer the absence: 1 s, 5 s, 10 s, 30 s, 1 min.
    static func granularity(for seconds: TimeInterval) -> TimeInterval {
        switch seconds {
        case ..<60: 1
        case ..<300: 5
        case ..<1200: 10
        case ..<3600: 30
        default: 60
        }
    }

    static func roundDown(_ seconds: TimeInterval) -> TimeInterval {
        let g = granularity(for: seconds)
        return (seconds / g).rounded(.down) * g
    }
}
