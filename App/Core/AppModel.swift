import CloudKit
import Foundation
import SwiftUI
import UIKit
import WidgetKit

/// What came out of reviewing a session, for the result screen.
struct ReviewResult: Equatable {
    var sessionID: UUID
    var outcome: SessionOutcome
    var change: PlanChange
    var suggestsRest: Bool
    var milestones: [Milestone]
}

/// Root state for the app. Owns the database, links and services.
@MainActor
@Observable
final class AppModel {
    private(set) var db: StayDatabase
    let store: DataStore
    let purchases = PurchaseManager()
    let account = AccountService()
    let coach = CoachService()
    let nearby = NearbyLink()
    let cloud = CloudRelay()
    let liveActivity = LiveActivityController()
    @ObservationIgnored private(set) lazy var camera = CameraController(model: self)

    var engine = MissionEngine()
    var stats = ProgressStats()

    // Live mission state (owner side)
    private(set) var cameraStatus: LinkStatus?
    private(set) var cloudSnapshot: UIImage?
    private(set) var cloudSnapshotAt: Date?
    private(set) var latestAlert: DistressEvent?
    var presentedPaywall = false
    var pendingPairing: PairingPayload?

    private var cloudToken: CKServerChangeToken?
    private var pollTask: Task<Void, Never>?
    private var photoCache: [String: UIImage] = [:]
    private var saveTask: Task<Void, Never>?

    init(store: DataStore = DataStore()) {
        self.store = store
        self.db = store.load()
        nearby.onMessage = { [weak self] message in self?.handleNearby(message) }
    }

    /// Called once the UI is up.
    func launch() async {
        await purchases.load()
        await account.verifyOnLaunch()
        liveActivity.endStaleActivities(keeping: activeSession?.id)
        connectLinks()
        refreshWidget()
        await rescheduleReminders()
        if activeSession != nil { startPolling() }
    }

    // MARK: Persistence

    private func mutate(_ change: (inout StayDatabase) -> Void) {
        change(&db)
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let store = store
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let snapshot = self?.db else { return }
            await Task.detached { store.save(snapshot) }.value
        }
    }

    func saveNow() {
        saveTask?.cancel()
        store.save(db)
    }

    // MARK: Preferences

    var preferences: AppPreferences { db.preferences }
    var role: DeviceRole? { db.preferences.role }

    func updatePreferences(_ change: (inout AppPreferences) -> Void) {
        mutate { change(&$0.preferences) }
    }

    func setRole(_ role: DeviceRole) {
        if self.role != role {
            if role != .camera { camera.disarm() }
            nearby.stop()
        }
        updatePreferences { $0.role = role }
        connectLinks()
    }

    func completeOnboarding() {
        updatePreferences { $0.hasCompletedOnboarding = true }
        saveNow()
        connectLinks()
        refreshWidget()
        Task { await rescheduleReminders() }
    }

    // MARK: Dogs

    var dogs: [Dog] { db.dogs }

    var selectedDog: Dog? {
        if let id = db.preferences.selectedDogID, let dog = db.dogs.first(where: { $0.id == id }) { return dog }
        return db.dogs.first
    }

    func selectDog(_ id: UUID) {
        updatePreferences { $0.selectedDogID = id }
        refreshWidget()
        Task { await rescheduleReminders() }
    }

    var canAddDog: Bool { FreeTier.canAddDog(isPro: purchases.isPro, currentDogs: dogs.count) }

    @discardableResult
    func addDog(name: String, breed: String, years: Int, months: Int, photo: UIImage?, answers: [String: Int]) -> Dog {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var dog = Dog(
            name: trimmed,
            breed: breed.trimmingCharacters(in: .whitespacesAndNewlines),
            ageYears: years,
            ageMonths: months,
            assessment: SeverityQuestionnaire.assess(answers: answers, dogName: trimmed),
            plan: .initial
        )
        if let photo { dog.photoFilename = store.saveImage(photo, maxSide: 1200) }
        mutate {
            $0.dogs.append(dog)
            $0.preferences.selectedDogID = dog.id
        }
        refreshWidget()
        return dog
    }

    func updateDog(_ dog: Dog) {
        mutate { db in
            guard let index = db.dogs.firstIndex(where: { $0.id == dog.id }) else { return }
            db.dogs[index] = dog
        }
        refreshWidget()
        Task { await rescheduleReminders() }
    }

    func setPhoto(_ image: UIImage, for dogID: UUID) {
        guard var dog = dogs.first(where: { $0.id == dogID }) else { return }
        if let old = dog.photoFilename {
            store.deleteMedia(old)
            photoCache[old] = nil
        }
        dog.photoFilename = store.saveImage(image, maxSide: 1200)
        updateDog(dog)
    }

    func deleteDog(_ id: UUID) {
        let media = db.sessions.filter { $0.dogID == id }.flatMap { $0.snapshotFilenames + $0.events.compactMap(\.snapshotFilename) }
            + [db.dogs.first { $0.id == id }?.photoFilename].compactMap { $0 }
        media.forEach(store.deleteMedia)
        mutate { db in
            db.dogs.removeAll { $0.id == id }
            db.sessions.removeAll { $0.dogID == id }
            db.journal.removeAll { $0.dogID == id }
            db.cueLog.removeAll { $0.dogID == id }
            db.celebrated[id] = nil
            if db.preferences.selectedDogID == id { db.preferences.selectedDogID = db.dogs.first?.id }
        }
        refreshWidget()
    }

    func photo(for dog: Dog) -> UIImage? {
        guard let name = dog.photoFilename else { return nil }
        if let cached = photoCache[name] { return cached }
        let image = store.image(named: name)
        photoCache[name] = image
        return image
    }

    func image(named filename: String) -> UIImage? {
        if let cached = photoCache[filename] { return cached }
        let image = store.image(named: filename)
        photoCache[filename] = image
        return image
    }

    // MARK: Sessions

    func sessions(for dogID: UUID) -> [AbsenceSession] {
        db.sessions.filter { $0.dogID == dogID }.sorted { $0.startedAt > $1.startedAt }
    }

    func session(_ id: UUID) -> AbsenceSession? {
        db.sessions.first { $0.id == id }
    }

    var activeSession: AbsenceSession? {
        db.sessions.first { !$0.isFinished }
    }

    /// The most recent finished session that still needs the owner's review.
    func sessionAwaitingReview(for dogID: UUID) -> AbsenceSession? {
        sessions(for: dogID).first { $0.isFinished && !$0.isReviewed }
    }

    var completedMonitoredMissions: Int {
        db.sessions.filter { $0.kind == .mission && $0.isFinished }.count
    }

    func canStart(_ kind: SessionKind) -> Bool {
        FreeTier.canStartMission(kind: kind, isPro: purchases.isPro, completedMissions: completedMonitoredMissions)
    }

    var remainingFreeMissions: Int? {
        FreeTier.remainingMissions(isPro: purchases.isPro, completedMissions: completedMonitoredMissions)
    }

    func todayMission(for dog: Dog, on date: Date = .now) -> DailyMission {
        let calendar = engine.calendar
        let reviewedToday = sessions(for: dog.id).filter { $0.isReviewed && calendar.isDate($0.startedAt, inSameDayAs: date) }.count
        return engine.dailyMission(for: dog.plan, severity: dog.severity, restWeekdays: dog.restWeekdays, today: date, completedSessionsToday: reviewedToday)
    }

    /// Whether the camera can be reached right now, and how.
    var cameraReachability: MonitoringSource? {
        if nearby.isConnected { return .nearby }
        if purchases.isPro, let link = db.preferences.link, link.database != .nearbyOnly,
           let status = cameraStatus, status.state != .stopped, Date.now.timeIntervalSince(status.sentAt) < 90 {
            return .cloud
        }
        return nil
    }

    var isPaired: Bool { db.preferences.link != nil }

    @discardableResult
    func startSession(dog: Dog, kind: SessionKind, plannedSeconds: TimeInterval, monitoring: MonitoringSource) -> AbsenceSession {
        if let active = activeSession { endSession(active.id, reason: .returnedEarly) }
        let session = AbsenceSession(dogID: dog.id, kind: kind, plannedSeconds: plannedSeconds, startedAt: .now, monitoring: monitoring)
        mutate { $0.sessions.append(session) }
        latestAlert = nil
        if monitoring != .selfObserved {
            let start = LinkSessionStart(sessionID: session.id, dogName: dog.name, targetSeconds: plannedSeconds, sensitivity: dog.sensitivity, startedAt: session.startedAt)
            nearby.send(.start(start))
            if let link = db.preferences.link {
                Task { await cloud.sendStart(start, link: link) }
            }
            startPolling()
        }
        liveActivity.start(session: session, dogName: dog.name)
        Task { await NotificationScheduler.scheduleReturn(after: plannedSeconds, dogName: dog.name) }
        Haptics.success()
        return session
    }

    func endSession(_ id: UUID, reason: SessionEndReason) {
        guard let session = session(id), !session.isFinished else { return }
        // Keep the last camera picture: it powers the Day 1 vs Day N share card and video.
        let lastFrame = session.monitoring == .selfObserved ? nil : (nearby.latestFrame ?? cloudSnapshot)
        let frameName = lastFrame.flatMap { store.saveImage($0, maxSide: 900) }
        mutate { db in
            guard let index = db.sessions.firstIndex(where: { $0.id == id }) else { return }
            if let frameName { db.sessions[index].snapshotFilenames.append(frameName) }
            db.sessions[index].endedAt = .now
            if reason == .returnedEarly, db.sessions[index].actualSeconds >= db.sessions[index].plannedSeconds * SessionOutcome.completionRatio {
                db.sessions[index].endReason = .completed
            } else {
                db.sessions[index].endReason = reason
            }
        }
        nearby.send(.stop(sessionID: id))
        if let link = db.preferences.link {
            Task { await cloud.sendStop(sessionID: id, link: link) }
        }
        NotificationScheduler.cancelReturn()
        liveActivity.end(status: session.events.isEmpty ? .ended : .alert, eventCount: session.events.count)
        // Keep polling briefly so late events from the camera still arrive.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            if self?.activeSession == nil { self?.pollTask?.cancel() }
        }
        saveNow()
    }

    /// Moves a running session's start earlier. Used by tests to simulate time passing.
    func backdate(sessionID: UUID, by seconds: TimeInterval) {
        mutate { db in
            guard let index = db.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
            db.sessions[index].startedAt.addTimeInterval(-seconds)
        }
    }

    func addManualEvent(to sessionID: UUID, offset: TimeInterval, kind: DistressKind) {
        mutate { db in
            guard let index = db.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
            let event = DistressEvent(offset: offset, kind: kind, confidence: 1, duration: 5, review: .confirmed, isManual: true)
            db.sessions[index].events.append(event)
            db.sessions[index].events.sort { $0.offset < $1.offset }
        }
    }

    func setReview(_ review: EventReview, eventID: UUID, sessionID: UUID) {
        mutate { db in
            guard let s = db.sessions.firstIndex(where: { $0.id == sessionID }),
                  let e = db.sessions[s].events.firstIndex(where: { $0.id == eventID }) else { return }
            db.sessions[s].events[e].review = review
        }
    }

    func setNote(_ note: String, sessionID: UUID) {
        mutate { db in
            guard let s = db.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
            db.sessions[s].note = note
        }
    }

    /// Locks in the owner's review and moves the plan. Only confirmed events count.
    func finishReview(sessionID: UUID) -> ReviewResult? {
        guard var session = session(sessionID), session.isFinished,
              let dogIndex = db.dogs.firstIndex(where: { $0.id == session.dogID }) else { return nil }
        // Anything left unreviewed is treated as dismissed: the plan only moves on confirmed data.
        for index in session.events.indices where session.events[index].review == .pending {
            session.events[index].review = .dismissed
        }
        session.isReviewed = true
        guard let outcome = session.reviewedOutcome else { return nil }

        let dog = db.dogs[dogIndex]
        let before = stats.snapshot(sessions: sessions(for: dog.id), today: .now)
        let update = engine.apply(outcome, to: dog.plan, severity: dog.severity, on: session.startedAt)

        mutate { db in
            if let s = db.sessions.firstIndex(where: { $0.id == sessionID }) { db.sessions[s] = session }
            db.dogs[dogIndex].plan = update.state
        }

        let after = stats.snapshot(sessions: sessions(for: dog.id), today: .now)
        let already = Set(db.celebrated[dog.id] ?? [])
        let fresh = stats.newMilestones(before: before, after: after).filter { !already.contains($0) }
        if !fresh.isEmpty {
            mutate { $0.celebrated[dog.id, default: []].append(contentsOf: fresh) }
        }
        coach.invalidate()
        refreshWidget()
        Task { await rescheduleReminders() }
        saveNow()
        return ReviewResult(sessionID: sessionID, outcome: outcome, change: update.change, suggestsRest: update.suggestsRestTomorrow, milestones: fresh)
    }

    func deleteSession(_ id: UUID) {
        guard let session = session(id) else { return }
        (session.snapshotFilenames + session.events.compactMap(\.snapshotFilename)).forEach(store.deleteMedia)
        mutate { $0.sessions.removeAll { $0.id == id } }
        refreshWidget()
    }

    // MARK: Cues and journal

    func logCue(_ reaction: CueReaction, dog: Dog) {
        let drill = engine.cueDrill(for: dog.plan, severity: dog.severity)
        var updated = dog
        updated.plan = engine.applyCueReaction(reaction, to: dog.plan)
        mutate { db in
            db.cueLog.append(CueLogEntry(dogID: dog.id, cue: drill.cue, reaction: reaction))
            if let index = db.dogs.firstIndex(where: { $0.id == dog.id }) { db.dogs[index] = updated }
        }
    }

    func cueRepsToday(for dogID: UUID) -> [CueLogEntry] {
        db.cueLog.filter { $0.dogID == dogID && Calendar.current.isDateInToday($0.date) }
    }

    func journal(for dogID: UUID) -> [JournalEntry] {
        db.journal.filter { $0.dogID == dogID }.sorted { $0.date > $1.date }
    }

    func saveJournal(_ entry: JournalEntry) {
        mutate { db in
            if let index = db.journal.firstIndex(where: { $0.id == entry.id }) {
                db.journal[index] = entry
            } else {
                db.journal.append(entry)
            }
        }
    }

    func deleteJournal(_ id: UUID) {
        mutate { $0.journal.removeAll { $0.id == id } }
    }

    func milestones(for dogID: UUID) -> [Milestone] {
        stats.reachedMilestones(stats.snapshot(sessions: sessions(for: dogID), today: .now))
    }

    // MARK: Coach

    func coachContext(for dog: Dog) -> CoachContext {
        let calendar = Calendar.current
        let all = sessions(for: dog.id).filter(\.isReviewed)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: .now) ?? .now
        let mission = todayMission(for: dog)
        return CoachContext(
            dogName: dog.name,
            breed: dog.breed,
            severity: dog.severity,
            recommendsVet: dog.assessment.recommendsVet,
            phase: dog.plan.phase,
            targetSeconds: dog.plan.targetSeconds,
            longestCalmSeconds: stats.longestCalm(sessions: all),
            consecutiveCalm: dog.plan.consecutiveCalm,
            consecutiveDistress: dog.plan.consecutiveDistress,
            dayStreak: stats.dayStreak(sessions: all, today: .now),
            mission: mission,
            lastWeek: all.filter { $0.startedAt >= weekAgo },
            previousWeek: all.filter { $0.startedAt >= twoWeeksAgo && $0.startedAt < weekAgo },
            cue: mission.cueDrill?.cue,
            recentMoods: journal(for: dog.id).prefix(5).map(\.mood),
            dayOfYear: calendar.ordinality(of: .day, in: .year, for: .now) ?? 0
        )
    }

    // MARK: Links (owner side)

    func connectLinks() {
        guard let role, let link = db.preferences.link else {
            nearby.stop()
            return
        }
        nearby.start(linkID: link.linkID, role: role)
        if role == .owner, link.database == .privateDB, purchases.isPro {
            let zoneID = CKRecordZone.ID(zoneName: link.zoneName, ownerName: CKCurrentUserDefaultName)
            Task { await cloud.installOwnerSubscription(zoneID: zoneID) }
            Task { await pollCloudOnce() }
        }
    }

    /// Owner: create a pairing code (and CloudKit share when iCloud is available).
    func preparePairing() async -> (payload: PairingPayload, cloudError: String?) {
        let linkID = db.preferences.link?.linkID ?? PairingPayload.makeLinkID()
        let name = account.account?.displayName ?? UIDevice.current.name
        if let existing = db.preferences.link, existing.database == .privateDB, existing.shareURL != nil {
            return (PairingPayload(linkID: linkID, shareURL: existing.shareURL, ownerName: name), nil)
        }
        do {
            let link = try await cloud.prepareOwnerLink(linkID: linkID)
            updatePreferences { $0.link = link }
            connectLinks()
            return (PairingPayload(linkID: linkID, shareURL: link.shareURL, ownerName: name), nil)
        } catch {
            let link = DeviceLink(linkID: linkID, database: .nearbyOnly, zoneName: CloudRelay.zonePrefix + linkID)
            updatePreferences { $0.link = link }
            connectLinks()
            return (PairingPayload(linkID: linkID, shareURL: nil, ownerName: name), error.localizedDescription)
        }
    }

    /// Camera: join the owner's link from a scanned or typed code.
    func joinPairing(_ payload: PairingPayload) async throws {
        let link = try await cloud.joinLink(payload)
        updatePreferences { $0.link = link }
        connectLinks()
    }

    func unpair() {
        if role == .owner, let link = db.preferences.link {
            Task { await cloud.deleteLink(link) }
        }
        nearby.stop()
        camera.disarm()
        updatePreferences { $0.link = nil }
        cameraStatus = nil
        cloudSnapshot = nil
    }

    private func handleNearby(_ message: NearbyMessage) {
        switch message {
        case .hello(_, let peerRole, _):
            // A camera that reconnects mid-mission picks the session back up.
            if role == .owner, peerRole == .camera, let active = activeSession, active.monitoring != .selfObserved,
               let dog = dogs.first(where: { $0.id == active.dogID }) {
                nearby.send(.start(LinkSessionStart(sessionID: active.id, dogName: dog.name, targetSeconds: active.plannedSeconds, sensitivity: dog.sensitivity, startedAt: active.startedAt)))
            }
        case .status(let status):
            if role == .owner { receiveStatus(status) }
        case .event(let event):
            if role == .owner { ingest(event) }
        case .levels(let sessionID, let levels):
            if role == .owner {
                mutate { db in
                    guard let index = db.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
                    db.sessions[index].levelTimeline = levels
                }
            }
        case .start(let start):
            if role == .camera { camera.handleStart(start) }
        case .stop(let sessionID):
            if role == .camera { camera.handleStop(sessionID: sessionID) }
        }
    }

    private func receiveStatus(_ status: LinkStatus) {
        cameraStatus = status
        guard let active = activeSession, status.sessionID == active.id, active.monitoring == .cloud, !nearby.isConnected else { return }
        // Over iCloud we build a coarse level timeline from heartbeats.
        mutate { db in
            guard let index = db.sessions.firstIndex(where: { $0.id == active.id }) else { return }
            db.sessions[index].levelTimeline.append(status.level)
            db.sessions[index].levelInterval = 10
        }
    }

    /// Adds a camera event to the matching session (deduplicated by ID).
    func ingest(_ event: LinkEvent) {
        guard let session = session(event.sessionID), !session.events.contains(where: { $0.id == event.id }),
              let dog = dogs.first(where: { $0.id == session.dogID }) else { return }
        var snapshotName: String?
        if let data = event.snapshot { snapshotName = store.saveJPEG(data) }
        let distress = DistressEvent(id: event.id, offset: event.offset, kind: event.kind, confidence: event.confidence, duration: event.duration, snapshotFilename: snapshotName)
        mutate { db in
            guard let index = db.sessions.firstIndex(where: { $0.id == event.sessionID }) else { return }
            db.sessions[index].events.append(distress)
            db.sessions[index].events.sort { $0.offset < $1.offset }
            if let snapshotName, db.sessions[index].snapshotFilenames.count < 12 {
                db.sessions[index].snapshotFilenames.append(snapshotName)
            }
            if db.sessions[index].levelTimeline.isEmpty, !event.levels.isEmpty {
                db.sessions[index].levelTimeline = event.levels
                db.sessions[index].levelInterval = 1
            }
        }
        guard !session.isFinished else { return }
        latestAlert = distress
        Haptics.warning()
        let count = (self.session(session.id)?.events.count) ?? 1
        liveActivity.update(status: .alert, eventCount: count, lastEventLabel: event.kind.title)
        if UIApplication.shared.applicationState != .active {
            Task { await NotificationScheduler.notifyDistress(dogName: dog.name, kind: event.kind) }
        }
    }

    func dismissLatestAlert() { latestAlert = nil }

    // MARK: Cloud polling (owner)

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollCloudOnce()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func pollCloudOnce() async {
        guard role == .owner, purchases.isPro, let link = db.preferences.link, link.database != .nearbyOnly else { return }
        let poll = await cloud.pollOwner(link: link, since: cloudToken)
        cloudToken = poll.token
        if let status = poll.status, status.sentAt > (cameraStatus?.sentAt ?? .distantPast) {
            receiveStatus(status)
        }
        if let snapshot = poll.snapshot, snapshot.takenAt > (cloudSnapshotAt ?? .distantPast) {
            cloudSnapshot = snapshot.image
            cloudSnapshotAt = snapshot.takenAt
        }
        for event in poll.events { ingest(event) }
    }

    /// From a CloudKit push.
    func handleRemoteNotification() async {
        await pollCloudOnce()
    }

    // MARK: Widget and reminders

    func refreshWidget() {
        guard let dog = selectedDog else {
            WidgetSnapshot.empty.save()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let mission = todayMission(for: dog)
        let reviewed = sessions(for: dog.id).filter(\.isReviewed)
        let text = MissionCopy.widgetLines(mission: mission, dog: dog)
        let recent = reviewed.filter(\.isCalm).prefix(7).reversed().map(\.actualSeconds)
        WidgetSnapshot(
            dogName: dog.name,
            streakDays: stats.dayStreak(sessions: reviewed, today: .now),
            todayTitle: text.title,
            todayDetail: text.detail,
            isRestDay: mission.isRestDay,
            isDoneToday: mission.completedToday,
            longestCalmSeconds: stats.longestCalm(sessions: reviewed),
            recentDurations: Array(recent),
            updatedAt: .now
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func rescheduleReminders() async {
        guard role == .owner, db.preferences.remindersEnabled, let dog = selectedDog else {
            await NotificationScheduler.cancelReminders()
            return
        }
        let calendar = Calendar.current
        var days: [NotificationScheduler.ReminderDay] = []
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: .now) else { continue }
            if offset == 0, todayMission(for: dog).completedToday { continue }
            let mission = engine.dailyMission(for: dog.plan, severity: dog.severity, restWeekdays: dog.restWeekdays, today: date, completedSessionsToday: 0)
            let copy = MissionCopy.reminder(mission: mission, dog: dog)
            days.append(.init(date: date, title: copy.title, body: copy.body))
        }
        await NotificationScheduler.scheduleReminders(days, hour: db.preferences.reminderHour, minute: db.preferences.reminderMinute)
    }

    // MARK: Data management

    func exportData() throws -> URL {
        let data = try DataStore.encoder.encode(db)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Stay-export-\(Date.now.formatted(.iso8601.year().month().day())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func deleteAllData() {
        if let active = activeSession { endSession(active.id, reason: .returnedEarly) }
        stopPolling()
        nearby.stop()
        camera.disarm()
        store.deleteEverything()
        photoCache.removeAll()
        db = StayDatabase()
        saveNow()
        coach.invalidate()
        refreshWidget()
        Task { await NotificationScheduler.cancelReminders() }
    }
}
