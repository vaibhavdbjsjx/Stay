import XCTest
@testable import Stay

final class MissionEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private var engine: MissionEngine { MissionEngine(config: .standard, calendar: calendar) }

    private func day(_ n: Int) -> Date {
        // 2026-01-05 is a Monday.
        calendar.date(byAdding: .day, value: n, to: calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9))!)!
    }

    private func trainingState(target: TimeInterval, lastCalm: TimeInterval? = nil) -> PlanState {
        var state = PlanState.initial
        state.phase = .training
        state.baselineSeconds = target
        state.targetSeconds = target
        state.lastCalmSeconds = lastCalm
        return state
    }

    // MARK: Baseline

    func testFreshPlanAsksForBaseline() {
        let mission = engine.dailyMission(for: .initial, severity: .moderate, restWeekdays: [], today: day(0), completedSessionsToday: 0)
        XCTAssertEqual(mission.kind, .baseline(capSeconds: 30 * 60))
        XCTAssertNil(mission.cueDrill)
        XCTAssertFalse(mission.completedToday)
    }

    func testBaselineWithDistressStartsBelowFirstSign() {
        let update = engine.completeBaseline(.initial, outcome: .distress(firstSignAt: 200, duration: 230), severity: .moderate, on: day(0))
        XCTAssertEqual(update.state.phase, .training)
        XCTAssertEqual(update.state.baselineSeconds, 200)
        // 60 % of 200 s = 120 s.
        XCTAssertEqual(update.state.targetSeconds, 120)
        XCTAssertEqual(update.change, .baselineSet(baseline: 200, firstTarget: 120))
        XCTAssertEqual(update.state.longestCalmSeconds, 0, "A distressed baseline is not a calm absence")
    }

    func testBaselineStartFactorDependsOnSeverity() {
        let mild = engine.completeBaseline(.initial, outcome: .distress(firstSignAt: 100, duration: 100), severity: .mild, on: day(0))
        let severe = engine.completeBaseline(.initial, outcome: .distress(firstSignAt: 100, duration: 100), severity: .severe, on: day(0))
        XCTAssertEqual(mild.state.targetSeconds, 70)
        XCTAssertEqual(severe.state.targetSeconds, 50)
    }

    func testCalmBaselineIsCappedAndCountsAsLongestCalm() {
        let update = engine.completeBaseline(.initial, outcome: .calm(duration: 45 * 60), severity: .mild, on: day(0))
        XCTAssertEqual(update.state.baselineSeconds, 30 * 60)
        XCTAssertEqual(update.state.longestCalmSeconds, 30 * 60)
        XCTAssertEqual(update.state.targetSeconds, 1260) // 70 % of 30 min = 21 min
    }

    func testTinyBaselineNeverGoesBelowMinimum() {
        let update = engine.completeBaseline(.initial, outcome: .distress(firstSignAt: 2, duration: 10), severity: .severe, on: day(0))
        XCTAssertEqual(update.state.baselineSeconds, 5)
        XCTAssertEqual(update.state.targetSeconds, 5)
    }

    func testApplyingOutcomeBeforeBaselineCompletesBaseline() {
        let update = engine.apply(.calm(duration: 300), to: .initial, severity: .moderate, on: day(0))
        XCTAssertEqual(update.state.phase, .training)
        XCTAssertEqual(update.state.baselineSeconds, 300)
    }

    // MARK: Increases

    func testCalmSessionIncreasesWithinTenToTwentyPercent() {
        for severity in SeverityLevel.allCases {
            for target in stride(from: 30.0, through: 3000.0, by: 37.0) {
                let next = engine.increase(target, severity: severity)
                XCTAssertGreaterThan(next, target, "\(severity) \(target)")
                XCTAssertLessThanOrEqual(next / target, 1.2 + 1e-9, "\(severity) \(target) → \(next)")
            }
        }
    }

    func testIncreaseSizeMatchesSeverity() {
        XCTAssertEqual(engine.increase(100, severity: .mild), 120)
        XCTAssertEqual(engine.increase(100, severity: .moderate), 115)
        XCTAssertEqual(engine.increase(100, severity: .severe), 110)
    }

    func testIncreaseIsRoundedToFriendlyNumbers() {
        // 200 s × 1.15 = 230 s (5 s granularity under 5 min).
        XCTAssertEqual(engine.increase(200, severity: .moderate), 230)
        // 700 s × 1.15 = 805 → 800 (10 s granularity).
        XCTAssertEqual(engine.increase(700, severity: .moderate), 800)
        // 1500 s × 1.15 = 1725 → 1710 (30 s granularity).
        XCTAssertEqual(engine.increase(1500, severity: .moderate), 1710)
    }

    func testLongAbsencesGrowByAtMostTenMinutes() {
        let next = engine.increase(2 * 3600, severity: .mild)
        XCTAssertEqual(next, 2 * 3600 + 600)
    }

    func testVeryShortMissionsAlwaysMoveForward() {
        XCTAssertEqual(engine.increase(5, severity: .severe), 6)
        XCTAssertEqual(engine.increase(9, severity: .severe), 10)
    }

    func testCalmOutcomeUpdatesStreaksAndLongest() {
        let state = trainingState(target: 120)
        let update = engine.apply(.calm(duration: 125), to: state, severity: .moderate, on: day(1))
        XCTAssertEqual(update.change, .increased(from: 120, to: 135))
        XCTAssertEqual(update.state.consecutiveCalm, 1)
        XCTAssertEqual(update.state.totalCalmSessions, 1)
        XCTAssertEqual(update.state.longestCalmSeconds, 125)
        XCTAssertEqual(update.state.lastCalmSeconds, 125)
        XCTAssertFalse(update.suggestsRestTomorrow)
    }

    // MARK: Rollback

    func testDistressRollsBackBelowFirstSign() {
        let state = trainingState(target: 300, lastCalm: 260)
        let update = engine.apply(.distress(firstSignAt: 180, duration: 200), to: state, severity: .moderate, on: day(1))
        // Anchor = min(180, 300, 260) = 180 → 80 % = 144 → rounded down to 140.
        XCTAssertEqual(update.change, .rolledBack(from: 300, to: 140))
        XCTAssertEqual(update.state.consecutiveCalm, 0)
        XCTAssertEqual(update.state.consecutiveDistress, 1)
        XCTAssertFalse(update.suggestsRestTomorrow)
    }

    func testDistressAfterTargetStillRollsBackBelowTarget() {
        let state = trainingState(target: 120, lastCalm: 100)
        let update = engine.apply(.distress(firstSignAt: 150, duration: 160), to: state, severity: .mild, on: day(1))
        XCTAssertEqual(update.state.targetSeconds, 80) // min(150,120,100)=100 × 0.8
    }

    func testRepeatedDistressRollsBackFurtherAndSuggestsRest() {
        var state = trainingState(target: 300, lastCalm: 300)
        state = engine.apply(.distress(firstSignAt: 200, duration: 210), to: state, severity: .moderate, on: day(1)).state
        let second = engine.apply(.distress(firstSignAt: 100, duration: 110), to: state, severity: .moderate, on: day(2))
        // Anchor 100 × 0.8 × 0.8 = 64 → 60 (5 s granularity).
        XCTAssertEqual(second.state.targetSeconds, 60)
        XCTAssertTrue(second.suggestsRestTomorrow)
        XCTAssertEqual(second.state.restSuggestedFor, calendar.startOfDay(for: day(3)))

        let tomorrow = engine.dailyMission(for: second.state, severity: .moderate, restWeekdays: [], today: day(3), completedSessionsToday: 0)
        XCTAssertEqual(tomorrow.kind, .rest(.afterDistress))
    }

    func testRollbackNeverGoesBelowMinimum() {
        let state = trainingState(target: 6)
        let update = engine.apply(.distress(firstSignAt: 1, duration: 4), to: state, severity: .severe, on: day(1))
        XCTAssertEqual(update.state.targetSeconds, 5)
    }

    func testCalmAfterDistressResetsDistressCount() {
        var state = trainingState(target: 100)
        state = engine.apply(.distress(firstSignAt: 60, duration: 70), to: state, severity: .moderate, on: day(1)).state
        state = engine.apply(.calm(duration: 50), to: state, severity: .moderate, on: day(2)).state
        XCTAssertEqual(state.consecutiveDistress, 0)
        XCTAssertEqual(state.consecutiveCalm, 1)
    }

    // MARK: Incomplete

    func testIncompleteSessionHoldsTarget() {
        let state = trainingState(target: 240)
        let update = engine.apply(.incomplete(duration: 90), to: state, severity: .moderate, on: day(1))
        XCTAssertEqual(update.change, .held(at: 240))
        XCTAssertEqual(update.state.targetSeconds, 240)
        XCTAssertEqual(update.state.consecutiveCalm, 0)
        XCTAssertEqual(update.state.longestCalmSeconds, 90)
    }

    // MARK: Only confirmed data moves the plan

    func testUnreviewedSessionHasNoOutcome() {
        var session = AbsenceSession(dogID: UUID(), kind: .mission, plannedSeconds: 60, startedAt: day(0), endedAt: day(0).addingTimeInterval(60), monitoring: .nearby)
        session.events = [DistressEvent(offset: 20, kind: .bark, confidence: 0.9, duration: 4)]
        XCTAssertNil(session.reviewedOutcome)
        session.isReviewed = true
        // Pending (unconfirmed) events do not count as distress.
        XCTAssertEqual(session.reviewedOutcome, .calm(duration: 60))
    }

    func testDismissedEventsAreIgnoredAndConfirmedCount() {
        var session = AbsenceSession(dogID: UUID(), kind: .mission, plannedSeconds: 60, startedAt: day(0), endedAt: day(0).addingTimeInterval(60), monitoring: .cloud)
        session.events = [
            DistressEvent(offset: 10, kind: .bark, confidence: 0.9, duration: 3, review: .dismissed),
            DistressEvent(offset: 40, kind: .howl, confidence: 0.8, duration: 6, review: .confirmed),
        ]
        session.isReviewed = true
        XCTAssertEqual(session.reviewedOutcome, .distress(firstSignAt: 40, duration: 60))
    }

    func testShortCalmSessionIsIncomplete() {
        var session = AbsenceSession(dogID: UUID(), kind: .mission, plannedSeconds: 100, startedAt: day(0), endedAt: day(0).addingTimeInterval(80), monitoring: .nearby)
        session.isReviewed = true
        XCTAssertEqual(session.reviewedOutcome, .incomplete(duration: 80))
        session.endedAt = day(0).addingTimeInterval(95)
        XCTAssertEqual(session.reviewedOutcome, .calm(duration: 95))
    }

    // MARK: Rest days

    func testRestAfterFiveTrainingDaysInARow() {
        var state = trainingState(target: 60)
        for n in 0..<5 {
            state = engine.apply(.calm(duration: state.targetSeconds), to: state, severity: .mild, on: day(n)).state
        }
        XCTAssertEqual(state.consecutiveTrainingDays, 5)
        let mission = engine.dailyMission(for: state, severity: .mild, restWeekdays: [], today: day(5), completedSessionsToday: 0)
        XCTAssertEqual(mission.kind, .rest(.afterTrainingStreak))
    }

    func testStreakResetsAfterABreak() {
        var state = trainingState(target: 60)
        state = engine.apply(.calm(duration: 60), to: state, severity: .mild, on: day(0)).state
        state = engine.apply(.calm(duration: 70), to: state, severity: .mild, on: day(1)).state
        state = engine.apply(.calm(duration: 80), to: state, severity: .mild, on: day(4)).state
        XCTAssertEqual(state.consecutiveTrainingDays, 1)
    }

    func testMultipleSessionsSameDayCountOnce() {
        var state = trainingState(target: 60)
        state = engine.apply(.calm(duration: 60), to: state, severity: .mild, on: day(0)).state
        state = engine.apply(.calm(duration: 70), to: state, severity: .mild, on: day(0).addingTimeInterval(3600)).state
        XCTAssertEqual(state.consecutiveTrainingDays, 1)
    }

    func testScheduledRestWeekday() {
        let state = trainingState(target: 60)
        let weekday = calendar.component(.weekday, from: day(2))
        let mission = engine.dailyMission(for: state, severity: .mild, restWeekdays: [weekday], today: day(2), completedSessionsToday: 0)
        XCTAssertEqual(mission.kind, .rest(.scheduled))
        let otherDay = engine.dailyMission(for: state, severity: .mild, restWeekdays: [weekday], today: day(3), completedSessionsToday: 0)
        XCTAssertEqual(otherDay.kind, .absence(targetSeconds: 60))
    }

    func testTrainingAnywayOnRestDayShowsTheMission() {
        let state = trainingState(target: 60)
        let weekday = calendar.component(.weekday, from: day(2))
        let mission = engine.dailyMission(for: state, severity: .mild, restWeekdays: [weekday], today: day(2), completedSessionsToday: 1)
        XCTAssertEqual(mission.kind, .absence(targetSeconds: 60))
        XCTAssertTrue(mission.completedToday)
    }

    // MARK: Warm-ups

    func testWarmups() {
        XCTAssertEqual(engine.warmups(for: 10), [])
        XCTAssertEqual(engine.warmups(for: 40), [5])
        XCTAssertEqual(engine.warmups(for: 200), [30, 70])
        XCTAssertEqual(engine.warmups(for: 1200), [180, 420])
    }

    func testDailyMissionIncludesWarmupsAndCueDrill() {
        let mission = engine.dailyMission(for: trainingState(target: 200), severity: .moderate, restWeekdays: [], today: day(0), completedSessionsToday: 0)
        XCTAssertEqual(mission.kind, .absence(targetSeconds: 200))
        XCTAssertEqual(mission.warmups, [30, 70])
        XCTAssertEqual(mission.cueDrill?.cue, .keys)
        XCTAssertEqual(mission.cueDrill?.reps, 5)
    }

    // MARK: Cues

    func testCueAdvancesAfterThreeCalmRatings() {
        var state = trainingState(target: 60)
        state = engine.applyCueReaction(.calm, to: state)
        state = engine.applyCueReaction(.calm, to: state)
        XCTAssertEqual(state.cueStage, 0)
        state = engine.applyCueReaction(.calm, to: state)
        XCTAssertEqual(state.cueStage, 1)
        XCTAssertEqual(state.cueCalmStreak, 0)
        XCTAssertEqual(engine.cueDrill(for: state, severity: .mild).cue, .shoes)
    }

    func testWorriedCueResetsProgressAndNoticedHolds() {
        var state = trainingState(target: 60)
        state = engine.applyCueReaction(.calm, to: state)
        state = engine.applyCueReaction(.noticed, to: state)
        XCTAssertEqual(state.cueCalmStreak, 1)
        state = engine.applyCueReaction(.worried, to: state)
        XCTAssertEqual(state.cueCalmStreak, 0)
        XCTAssertEqual(state.cueStage, 0)
    }

    func testAllCuesMasteredBecomesMixedDrill() {
        var state = trainingState(target: 60)
        state.cueStage = CueKind.allCases.count
        XCTAssertNil(engine.cueDrill(for: state, severity: .severe).cue)
        XCTAssertEqual(engine.cueDrill(for: state, severity: .severe).reps, 3)
        XCTAssertEqual(engine.applyCueReaction(.calm, to: state), state)
    }

    // MARK: A realistic run

    func testFourWeekSimulationProgressesAndRecovers() {
        var state = PlanState.initial
        state = engine.completeBaseline(state, outcome: .distress(firstSignAt: 90, duration: 100), severity: .moderate, on: day(0)).state
        XCTAssertEqual(state.targetSeconds, 54)

        var dayIndex = 1
        var calmRun = 0
        while dayIndex < 28 {
            let mission = engine.dailyMission(for: state, severity: .moderate, restWeekdays: [], today: day(dayIndex), completedSessionsToday: 0)
            if case .absence(let target) = mission.kind {
                calmRun += 1
                // Simulate one bad day in week two.
                let outcome: SessionOutcome = dayIndex == 10 ? .distress(firstSignAt: target * 0.7, duration: target) : .calm(duration: target)
                state = engine.apply(outcome, to: state, severity: .moderate, on: day(dayIndex)).state
            }
            dayIndex += 1
        }
        XCTAssertGreaterThan(state.targetSeconds, 120, "Steady practice should more than double the starting step")
        XCTAssertGreaterThan(state.longestCalmSeconds, 100)
        XCTAssertLessThan(calmRun, 27, "Rest days must have been scheduled")
    }

    // MARK: Rounding

    func testGranularity() {
        XCTAssertEqual(MissionEngine.roundDown(47.9), 47)
        XCTAssertEqual(MissionEngine.roundDown(203), 200)
        XCTAssertEqual(MissionEngine.roundDown(619), 610)
        XCTAssertEqual(MissionEngine.roundDown(1799), 1770)
        XCTAssertEqual(MissionEngine.roundDown(3725), 3720)
    }
}
