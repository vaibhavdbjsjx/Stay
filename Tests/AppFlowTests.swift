import XCTest
@testable import Stay

final class PairingPayloadTests: XCTestCase {
    func testURLRoundTrip() throws {
        let share = URL(string: "https://www.icloud.com/share/0abcDEF")!
        let payload = PairingPayload(linkID: "K7Q29MXR", shareURL: share, ownerName: "Vai's iPhone")
        let decoded = try XCTUnwrap(PairingPayload(url: payload.url))
        XCTAssertEqual(decoded.linkID, "K7Q29MXR")
        XCTAssertEqual(decoded.shareURL, share)
        XCTAssertEqual(decoded.ownerName, "Vai's iPhone")
    }

    func testTypedCodeIgnoresDashesAndCase() {
        XCTAssertEqual(PairingPayload(code: "k7q2-9mxr")?.linkID, "K7Q29MXR")
        XCTAssertNil(PairingPayload(code: "K7Q2"))
        // 0, 1, O and I are excluded to avoid typos.
        XCTAssertNil(PairingPayload(code: "K7Q2-9MX0"))
    }

    func testGeneratedLinkIDsAreValid() {
        for _ in 0..<50 {
            XCTAssertTrue(PairingPayload.isValidLinkID(PairingPayload.makeLinkID()))
        }
        XCTAssertEqual(PairingPayload.displayCode("K7Q29MXR"), "K7Q2-9MXR")
    }

    func testRejectsForeignURLs() {
        XCTAssertNil(PairingPayload(url: URL(string: "https://example.com/pair?link=K7Q29MXR")!))
        XCTAssertNil(PairingPayload(url: URL(string: "stay://pair?link=bad")!))
    }
}

final class DataStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDatabaseRoundTrip() {
        let store = DataStore(directory: directory)
        var db = StayDatabase()
        let dog = Dog(name: "Biscuit", breed: "Cocker Spaniel", ageYears: 3, ageMonths: 2, assessment: .unanswered, plan: .initial)
        db.dogs = [dog]
        db.sessions = [AbsenceSession(dogID: dog.id, kind: .baseline, plannedSeconds: 1800, startedAt: .now, monitoring: .nearby)]
        db.celebrated[dog.id] = [.firstCalm, .calmDuration(60)]
        db.preferences.role = .owner
        store.save(db)

        let loaded = store.load()
        XCTAssertEqual(loaded.dogs.first?.name, "Biscuit")
        XCTAssertEqual(loaded.sessions.count, 1)
        XCTAssertEqual(loaded.celebrated[dog.id], [.firstCalm, .calmDuration(60)])
        XCTAssertEqual(loaded.preferences.role, .owner)
    }

    func testMissingOrCorruptFileGivesEmptyDatabase() throws {
        let store = DataStore(directory: directory)
        XCTAssertTrue(store.load().dogs.isEmpty)
        try Data("not json".utf8).write(to: store.databaseURL)
        XCTAssertTrue(store.load().dogs.isEmpty)
    }
}

@MainActor
final class AppModelFlowTests: XCTestCase {
    private func makeModel() -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return AppModel(store: DataStore(directory: directory))
    }

    private func finish(_ model: AppModel, _ sessionID: UUID, after seconds: TimeInterval) {
        // Simulate time passing by moving the start back.
        model.backdate(sessionID: sessionID, by: seconds)
        model.endSession(sessionID, reason: .returnedEarly)
    }

    func testBaselineThenCalmMissionGrowsPlan() throws {
        let model = makeModel()
        let dog = model.addDog(name: "Biscuit", breed: "", years: 2, months: 0, photo: nil, answers: ["tolerance": 1])
        let baseline = model.startSession(dog: dog, kind: .baseline, plannedSeconds: 1800, monitoring: .selfObserved)
        model.backdate(sessionID: baseline.id, by: 300)
        model.addManualEvent(to: baseline.id, offset: 200, kind: .bark)
        model.endSession(baseline.id, reason: .distress)

        let first = try XCTUnwrap(model.finishReview(sessionID: baseline.id))
        guard case .baselineSet(let measured, let target) = first.change else { return XCTFail("expected baseline") }
        XCTAssertEqual(measured, 200)
        XCTAssertLessThan(target, 200)

        let trained = try XCTUnwrap(model.dogs.first)
        let mission = model.startSession(dog: trained, kind: .mission, plannedSeconds: trained.plan.targetSeconds, monitoring: .selfObserved)
        finish(model, mission.id, after: trained.plan.targetSeconds + 2)
        let second = try XCTUnwrap(model.finishReview(sessionID: mission.id))
        guard case .increased(let from, let to) = second.change else { return XCTFail("expected increase, got \(second.change)") }
        XCTAssertEqual(from, target)
        XCTAssertGreaterThan(to, from)
        XCTAssertTrue(second.milestones.contains(.firstCalm))
    }

    func testDismissedDetectionsDoNotRollBack() throws {
        let model = makeModel()
        var dog = model.addDog(name: "Pip", breed: "", years: 1, months: 0, photo: nil, answers: [:])
        dog.plan.phase = .training
        dog.plan.targetSeconds = 120
        model.updateDog(dog)
        let session = model.startSession(dog: dog, kind: .mission, plannedSeconds: 120, monitoring: .nearby)
        model.ingest(LinkEvent(id: UUID(), sessionID: session.id, offset: 40, kind: .bark, confidence: 0.8, duration: 4, levels: [], snapshot: nil))
        // Duplicate delivery (Wi-Fi and iCloud) is ignored.
        let duplicate = try XCTUnwrap(model.session(session.id)?.events.first)
        model.ingest(LinkEvent(id: duplicate.id, sessionID: session.id, offset: 40, kind: .bark, confidence: 0.8, duration: 4, levels: [], snapshot: nil))
        XCTAssertEqual(model.session(session.id)?.events.count, 1)

        finish(model, session.id, after: 125)
        // Owner leaves the event unchecked: it is treated as dismissed.
        let result = try XCTUnwrap(model.finishReview(sessionID: session.id))
        guard case .increased = result.change else { return XCTFail("expected increase, got \(result.change)") }
    }

    func testFreeTierStopsAfterThreeMissions() {
        let model = makeModel()
        let dog = model.addDog(name: "Rex", breed: "", years: 4, months: 0, photo: nil, answers: [:])
        for _ in 0..<FreeTier.monitoredMissions {
            XCTAssertTrue(model.canStart(.mission))
            let session = model.startSession(dog: dog, kind: .mission, plannedSeconds: 30, monitoring: .selfObserved)
            model.endSession(session.id, reason: .returnedEarly)
        }
        XCTAssertFalse(model.canStart(.mission))
        XCTAssertTrue(model.canStart(.baseline))
        XCTAssertEqual(model.remainingFreeMissions, 0)
    }

    func testDeleteAllDataClearsEverything() {
        let model = makeModel()
        let dog = model.addDog(name: "Rex", breed: "", years: 4, months: 0, photo: nil, answers: [:])
        model.saveJournal(JournalEntry(dogID: dog.id, mood: .great, text: "Slept all afternoon"))
        model.deleteAllData()
        XCTAssertTrue(model.dogs.isEmpty)
        XCTAssertTrue(model.db.journal.isEmpty)
        XCTAssertFalse(model.preferences.hasCompletedOnboarding)
    }
}

final class RulesCoachTests: XCTestCase {
    private func context(kind: DailyMission.Kind, calm: Int = 0, distress: Int = 0) -> CoachContext {
        CoachContext(
            dogName: "Biscuit", breed: "", severity: .moderate, recommendsVet: false, phase: .training,
            targetSeconds: 120, longestCalmSeconds: 100, consecutiveCalm: calm, consecutiveDistress: distress,
            dayStreak: 2, mission: DailyMission(kind: kind, warmups: [], cueDrill: nil, completedToday: false),
            lastWeek: [], previousWeek: [], cue: nil, recentMoods: [], dayOfYear: 10
        )
    }

    func testTipsFollowThePlanState() {
        let coach = RulesCoach()
        XCTAssertEqual(coach.dailyTip(context(kind: .rest(.afterDistress))).symbol, "leaf")
        XCTAssertEqual(coach.dailyTip(context(kind: .absence(targetSeconds: 120), distress: 1)).symbol, "arrow.uturn.backward")
        XCTAssertEqual(coach.dailyTip(context(kind: .absence(targetSeconds: 120), calm: 4)).symbol, "sparkles")
        XCTAssertTrue(coach.dailyTip(context(kind: .baseline(capSeconds: 1800))).body.contains("Biscuit"))
    }

    func testWeeklyInsightWithNoSessions() {
        let insight = RulesCoach().weeklyInsight(context(kind: .absence(targetSeconds: 120)))
        XCTAssertFalse(insight.paragraphs.isEmpty)
    }

    func testCopyNeverPromisesACure() {
        let dog = Dog(name: "Biscuit", breed: "", ageYears: 1, ageMonths: 0, assessment: .unanswered, plan: .initial)
        let changes: [PlanChange] = [.baselineSet(baseline: 60, firstTarget: 36), .increased(from: 60, to: 69), .held(at: 60), .rolledBack(from: 60, to: 40)]
        for change in changes {
            let text = (MissionCopy.changeHeadline(change, dogName: dog.name) + MissionCopy.changeDetail(change, dogName: dog.name)).lowercased()
            XCTAssertFalse(text.contains("cure"))
            XCTAssertFalse(text.contains("diagnos"))
        }
    }
}
