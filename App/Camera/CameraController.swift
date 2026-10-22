import AVFoundation
import Foundation
import UIKit

/// Camera mode: arms the detection pipeline, follows the owner's start/stop
/// commands and relays events, heartbeats and frames.
@MainActor
@Observable
final class CameraController {
    enum State: Equatable {
        case idle
        case starting
        case armed
        case running(LinkSessionStart)
    }

    private(set) var state: State = .idle
    private(set) var level: Float = 0
    private(set) var levelHistory: [Float] = []
    private(set) var sessionEvents: [LinkEvent] = []
    private(set) var issues: [DetectionPipeline.SetupIssue] = []
    private(set) var batteryLevel: Float = -1
    private(set) var isCharging = false
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    private(set) var lastSessionSummary: (dogName: String, duration: TimeInterval, events: Int)?

    let pipeline = DetectionPipeline()
    private unowned let model: AppModel
    private var loops: [Task<Void, Never>] = []
    private var latestSnapshot: Data?
    private var handledStarts: Set<UUID> = []
    private var handledStops: Set<UUID> = []
    private var lastHistoryAt = Date.distantPast
    private var orientationObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var currentStart: LinkSessionStart? {
        if case .running(let start) = state { return start }
        return nil
    }

    var sensitivity: DetectionSensitivity {
        currentStart?.sensitivity ?? model.preferences.cameraSensitivity
    }

    var hasThermalWarning: Bool { thermalState == .serious || thermalState == .critical }

    // MARK: Arm / disarm

    func arm() async {
        guard state == .idle else { return }
        state = .starting
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateDeviceState()

        let callbacks = DetectionPipeline.Callbacks(
            onLevel: { [weak self] level in Task { @MainActor in self?.receive(level: level) } },
            onSign: { [weak self] sign, snapshot, levels in Task { @MainActor in self?.receive(sign: sign, snapshot: snapshot, levels: levels) } },
            onLiveFrame: { [weak self] frame in Task { @MainActor in self?.model.nearby.sendFrame(frame) } },
            onSnapshot: { [weak self] snapshot in Task { @MainActor in self?.latestSnapshot = snapshot } }
        )
        pipeline.configure(callbacks: callbacks, sensitivity: model.preferences.cameraSensitivity)
        pipeline.setLiveFramesEnabled(true)
        issues = await pipeline.start()
        applyOrientation()
        orientationObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyOrientation() }
        }
        state = .armed
        model.connectLinks()
        startLoops()
        sendStatus()
    }

    func disarm() {
        if let start = currentStart { finishSession(start.sessionID, notifyOwner: true) }
        loops.forEach { $0.cancel() }
        loops.removeAll()
        if state != .idle { pipeline.stop() }
        if let orientationObserver { NotificationCenter.default.removeObserver(orientationObserver) }
        orientationObserver = nil
        state = .idle
        level = 0
        UIApplication.shared.isIdleTimerDisabled = false
        sendStatus(state: .stopped)
    }

    func updateSensitivity(_ sensitivity: DetectionSensitivity) {
        model.updatePreferences { $0.cameraSensitivity = sensitivity }
        if currentStart == nil { pipeline.setSensitivity(sensitivity) }
    }

    // MARK: Commands

    func handleStart(_ start: LinkSessionStart) {
        guard !handledStarts.contains(start.sessionID) else { return }
        // Ignore stale commands, e.g. a start left in iCloud from hours ago.
        let expectedEnd = start.startedAt.addingTimeInterval(max(start.targetSeconds, 60) * 2 + 1800)
        guard expectedEnd > .now, !handledStops.contains(start.sessionID) else { return }
        guard state != .idle, state != .starting else { return }
        handledStarts.insert(start.sessionID)
        if let current = currentStart, current.sessionID != start.sessionID {
            finishSession(current.sessionID, notifyOwner: false)
        }
        sessionEvents = []
        pipeline.setSensitivity(start.sensitivity)
        pipeline.beginSession(at: start.startedAt)
        state = .running(start)
        Haptics.tap()
        sendStatus()
    }

    func handleStop(sessionID: UUID) {
        handledStops.insert(sessionID)
        guard currentStart?.sessionID == sessionID else { return }
        finishSession(sessionID, notifyOwner: false)
    }

    /// The camera user ends the session on this device.
    func stopFromCamera() {
        guard let start = currentStart else { return }
        finishSession(start.sessionID, notifyOwner: true)
    }

    private func finishSession(_ sessionID: UUID, notifyOwner: Bool) {
        guard let start = currentStart, start.sessionID == sessionID else { return }
        let levels = pipeline.endSession()
        model.nearby.send(.levels(sessionID: sessionID, levels: levels))
        lastSessionSummary = (start.dogName, Date.now.timeIntervalSince(start.startedAt), sessionEvents.count)
        handledStops.insert(sessionID)
        state = .armed
        pipeline.setSensitivity(model.preferences.cameraSensitivity)
        sendStatus()
    }

    // MARK: Pipeline output

    private func receive(level: Float) {
        // Smooth for display.
        self.level = self.level * 0.6 + level * 0.4
        if Date.now.timeIntervalSince(lastHistoryAt) >= 0.5 {
            lastHistoryAt = .now
            levelHistory.append(self.level)
            if levelHistory.count > 120 { levelHistory.removeFirst(levelHistory.count - 120) }
        }
    }

    private func receive(sign: DetectedSign, snapshot: Data?, levels: [Float]) {
        guard let start = currentStart else { return }
        let event = LinkEvent(
            id: UUID(), sessionID: start.sessionID, offset: sign.offset, kind: sign.kind,
            confidence: sign.confidence, duration: sign.duration, levels: levels, snapshot: snapshot
        )
        sessionEvents.append(event)
        model.nearby.send(.event(event))
        if let link = model.preferences.link {
            Task { await model.cloud.postEvent(event, dogName: start.dogName, link: link) }
        }
    }

    // MARK: Loops

    private func startLoops() {
        loops.forEach { $0.cancel() }
        // Owner commands over iCloud.
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollControl()
                try? await Task.sleep(for: .seconds(3))
            }
        })
        // Heartbeat, device state and safety stop.
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self?.updateDeviceState()
                self?.enforceSafetyLimit()
                self?.sendStatus()
            }
        })
        // Near-live view snapshots over iCloud.
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await self?.postSnapshot()
            }
        })
    }

    private func pollControl() async {
        guard let link = model.preferences.link, let control = await model.cloud.fetchControl(link: link) else { return }
        switch control.command {
        case .start:
            if let start = control.start { handleStart(start) }
        case .stop:
            if let id = control.sessionID { handleStop(sessionID: id) }
        }
    }

    private func postSnapshot() async {
        guard isRunning, let link = model.preferences.link, let snapshot = latestSnapshot else { return }
        await model.cloud.postSnapshot(snapshot, sessionID: currentStart?.sessionID, link: link)
    }

    private func enforceSafetyLimit() {
        // Never keep listening far beyond the plan if the owner forgot to end it.
        guard let start = currentStart else { return }
        let limit = max(start.targetSeconds, 60) * 2 + 1800
        if Date.now.timeIntervalSince(start.startedAt) > limit {
            finishSession(start.sessionID, notifyOwner: true)
        }
    }

    private func updateDeviceState() {
        let device = UIDevice.current
        batteryLevel = device.batteryLevel
        isCharging = device.batteryState == .charging || device.batteryState == .full
        thermalState = ProcessInfo.processInfo.thermalState
    }

    private func sendStatus(state override: LinkStatus.State? = nil) {
        let linkState: LinkStatus.State = override ?? (isRunning ? .running : (state == .idle ? .stopped : .armed))
        let status = LinkStatus(
            state: linkState,
            sessionID: currentStart?.sessionID,
            elapsed: currentStart.map { Date.now.timeIntervalSince($0.startedAt) } ?? 0,
            level: level,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            thermalWarning: hasThermalWarning,
            deviceName: UIDevice.current.name
        )
        model.nearby.send(.status(status))
        if let link = model.preferences.link {
            Task { await model.cloud.postStatus(status, link: link) }
        }
    }

    private func applyOrientation() {
        let angle: CGFloat = switch UIDevice.current.orientation {
        case .landscapeLeft: 0
        case .landscapeRight: 180
        case .portraitUpsideDown: 270
        default: 90
        }
        pipeline.setRotation(angle)
    }
}
