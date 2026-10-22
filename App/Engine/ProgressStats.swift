import Foundation

enum Milestone: Hashable, Codable, Sendable {
    case firstCalm
    case calmDuration(TimeInterval)
    case calmSessions(Int)
    case dayStreak(Int)

    static let durationThresholds: [TimeInterval] = [30, 60, 120, 300, 600, 900, 1800, 2700, 3600, 7200, 10800, 14400]
    static let sessionThresholds = [5, 10, 25, 50, 100]
    static let streakThresholds = [3, 7, 14, 30, 60]

    var title: String {
        switch self {
        case .firstCalm: String(localized: "First calm mission")
        case .calmDuration(let s): String(localized: "\(DurationText.short(s)) home alone, calmly")
        case .calmSessions(let n): String(localized: "\(n) calm missions")
        case .dayStreak(let n): String(localized: "\(n)-day training streak")
        }
    }

    var symbol: String {
        switch self {
        case .firstCalm: "sparkles"
        case .calmDuration: "house.fill"
        case .calmSessions: "checkmark.seal.fill"
        case .dayStreak: "flame.fill"
        }
    }
}

struct ProgressSnapshot: Equatable, Sendable {
    var longestCalm: TimeInterval
    var calmSessions: Int
    var dayStreak: Int
}

/// Derived progress numbers. Pure functions over sessions so they can be tested.
struct ProgressStats: Sendable {
    var calendar: Calendar = .current

    /// Consecutive training days. One rest day between sessions keeps the streak alive.
    func dayStreak(sessions: [AbsenceSession], today: Date) -> Int {
        let days = Set(sessions.filter(\.isFinished).map { calendar.startOfDay(for: $0.startedAt) }).sorted(by: >)
        guard let mostRecent = days.first else { return 0 }
        let todayStart = calendar.startOfDay(for: today)
        guard let gapToToday = calendar.dateComponents([.day], from: mostRecent, to: todayStart).day, gapToToday <= 2 else { return 0 }

        var streak = 1
        var previous = mostRecent
        for day in days.dropFirst() {
            guard let gap = calendar.dateComponents([.day], from: day, to: previous).day, gap <= 2 else { break }
            streak += gap
            previous = day
        }
        return streak
    }

    func longestCalm(sessions: [AbsenceSession]) -> TimeInterval {
        sessions.compactMap { session -> TimeInterval? in
            guard let outcome = session.reviewedOutcome else { return nil }
            switch outcome {
            case .calm(let d), .incomplete(let d): return d
            case .distress(let first, _): return session.kind == .baseline ? first : nil
            }
        }.max() ?? 0
    }

    func snapshot(sessions: [AbsenceSession], today: Date) -> ProgressSnapshot {
        ProgressSnapshot(
            longestCalm: longestCalm(sessions: sessions),
            calmSessions: sessions.filter(\.isCalm).count,
            dayStreak: dayStreak(sessions: sessions, today: today)
        )
    }

    /// Milestones newly reached between two snapshots.
    func newMilestones(before: ProgressSnapshot, after: ProgressSnapshot) -> [Milestone] {
        var result: [Milestone] = []
        if before.calmSessions == 0 && after.calmSessions > 0 { result.append(.firstCalm) }
        if let duration = Milestone.durationThresholds.last(where: { before.longestCalm < $0 && after.longestCalm >= $0 }) {
            result.append(.calmDuration(duration))
        }
        if let count = Milestone.sessionThresholds.last(where: { before.calmSessions < $0 && after.calmSessions >= $0 }) {
            result.append(.calmSessions(count))
        }
        if let streak = Milestone.streakThresholds.last(where: { before.dayStreak < $0 && after.dayStreak >= $0 }) {
            result.append(.dayStreak(streak))
        }
        return result
    }

    /// All milestones reached so far, for the progress screen.
    func reachedMilestones(_ snapshot: ProgressSnapshot) -> [Milestone] {
        var result: [Milestone] = []
        if snapshot.calmSessions > 0 { result.append(.firstCalm) }
        result += Milestone.durationThresholds.filter { snapshot.longestCalm >= $0 }.map(Milestone.calmDuration)
        result += Milestone.sessionThresholds.filter { snapshot.calmSessions >= $0 }.map(Milestone.calmSessions)
        result += Milestone.streakThresholds.filter { snapshot.dayStreak >= $0 }.map(Milestone.dayStreak)
        return result
    }

    /// Next duration milestone to aim for.
    func nextDurationGoal(after longest: TimeInterval) -> TimeInterval? {
        Milestone.durationThresholds.first { $0 > longest }
    }
}

/// What the free tier includes. Kept in one place and unit-tested.
enum FreeTier {
    static let monitoredMissions = 3
    static let dogs = 1

    static func canStartMission(kind: SessionKind, isPro: Bool, completedMissions: Int) -> Bool {
        isPro || kind == .baseline || completedMissions < monitoredMissions
    }

    static func remainingMissions(isPro: Bool, completedMissions: Int) -> Int? {
        isPro ? nil : max(0, monitoredMissions - completedMissions)
    }

    static func canAddDog(isPro: Bool, currentDogs: Int) -> Bool {
        isPro || currentDogs < dogs
    }
}
