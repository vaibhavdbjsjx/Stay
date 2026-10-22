import XCTest
@testable import Stay

final class ProgressAndPolicyTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: n, to: calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 18))!)!
    }

    private func session(day n: Int, planned: TimeInterval = 60, actual: TimeInterval = 60, distressAt: TimeInterval? = nil, reviewed: Bool = true) -> AbsenceSession {
        var s = AbsenceSession(dogID: UUID(), kind: .mission, plannedSeconds: planned, startedAt: day(n), endedAt: day(n).addingTimeInterval(actual), monitoring: .nearby)
        if let distressAt {
            s.events = [DistressEvent(offset: distressAt, kind: .bark, confidence: 0.9, duration: 5, review: .confirmed)]
        }
        s.isReviewed = reviewed
        return s
    }

    private var stats: ProgressStats { ProgressStats(calendar: calendar) }

    func testStreakCountsConsecutiveDays() {
        let sessions = [session(day: 0), session(day: 1), session(day: 2)]
        XCTAssertEqual(stats.dayStreak(sessions: sessions, today: day(2)), 3)
    }

    func testOneRestDayKeepsStreak() {
        let sessions = [session(day: 0), session(day: 1), session(day: 3)]
        XCTAssertEqual(stats.dayStreak(sessions: sessions, today: day(3)), 4)
    }

    func testTwoMissedDaysBreakStreak() {
        let sessions = [session(day: 0), session(day: 3)]
        XCTAssertEqual(stats.dayStreak(sessions: sessions, today: day(3)), 1)
        XCTAssertEqual(stats.dayStreak(sessions: sessions, today: day(6)), 0)
    }

    func testLongestCalmIgnoresDistressAndUnreviewed() {
        let sessions = [
            session(day: 0, planned: 100, actual: 100),
            session(day: 1, planned: 300, actual: 300, distressAt: 200),
            session(day: 2, planned: 500, actual: 500, reviewed: false),
        ]
        XCTAssertEqual(stats.longestCalm(sessions: sessions), 100)
    }

    func testMilestonesFireOnceWhenCrossed() {
        let before = ProgressSnapshot(longestCalm: 50, calmSessions: 4, dayStreak: 6)
        let after = ProgressSnapshot(longestCalm: 65, calmSessions: 5, dayStreak: 7)
        XCTAssertEqual(stats.newMilestones(before: before, after: after), [.calmDuration(60), .calmSessions(5), .dayStreak(7)])
        XCTAssertEqual(stats.newMilestones(before: after, after: after), [])
    }

    func testFirstCalmMilestone() {
        let before = ProgressSnapshot(longestCalm: 0, calmSessions: 0, dayStreak: 0)
        let after = ProgressSnapshot(longestCalm: 20, calmSessions: 1, dayStreak: 1)
        XCTAssertEqual(stats.newMilestones(before: before, after: after), [.firstCalm])
    }

    func testFreeTier() {
        XCTAssertTrue(FreeTier.canStartMission(kind: .baseline, isPro: false, completedMissions: 10))
        XCTAssertTrue(FreeTier.canStartMission(kind: .mission, isPro: false, completedMissions: 2))
        XCTAssertFalse(FreeTier.canStartMission(kind: .mission, isPro: false, completedMissions: 3))
        XCTAssertTrue(FreeTier.canStartMission(kind: .mission, isPro: true, completedMissions: 300))
        XCTAssertEqual(FreeTier.remainingMissions(isPro: false, completedMissions: 1), 2)
        XCTAssertNil(FreeTier.remainingMissions(isPro: true, completedMissions: 1))
        XCTAssertFalse(FreeTier.canAddDog(isPro: false, currentDogs: 1))
        XCTAssertTrue(FreeTier.canAddDog(isPro: true, currentDogs: 4))
    }

    func testSeverityQuestionnaire() {
        let calm = SeverityQuestionnaire.assess(answers: ["tolerance": 3, "vocal": 1])
        XCTAssertEqual(calm.level, .mild)
        XCTAssertFalse(calm.recommendsVet)

        let injured = SeverityQuestionnaire.assess(answers: ["tolerance": 3, "destructive": 3])
        XCTAssertTrue(injured.recommendsVet, "Self-injury always suggests a vet")

        let severe = SeverityQuestionnaire.assess(answers: ["tolerance": 0, "vocal": 3, "destructive": 2, "toileting": 2, "predeparture": 2, "escape": 1])
        XCTAssertEqual(severe.level, .severe)
        XCTAssertTrue(severe.recommendsVet)
    }

    func testDurationText() {
        XCTAssertEqual(DurationText.short(45), "45 s")
        XCTAssertEqual(DurationText.short(200), "3 min 20 s")
        XCTAssertEqual(DurationText.short(720), "12 min")
        XCTAssertEqual(DurationText.short(3900), "1 h 5 min")
        XCTAssertEqual(DurationText.clock(200), "3:20")
        XCTAssertEqual(DurationText.clock(3725), "1:02:05")
    }
}
