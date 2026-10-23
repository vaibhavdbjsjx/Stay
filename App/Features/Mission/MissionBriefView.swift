import SwiftUI

/// The "before you go" sheet: warm-ups, checklist and how to monitor.
struct MissionBriefView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var dog: Dog
    var onStart: (AbsenceSession) -> Void

    @State private var useCamera = true
    @State private var completedWarmups: Set<Int> = []
    @State private var runningWarmup: Int?
    @State private var customTarget: TimeInterval?

    private var mission: DailyMission { model.todayMission(for: dog) }
    private var isBaseline: Bool { dog.plan.phase == .needsBaseline }
    private var target: TimeInterval {
        if isBaseline { return model.engine.config.baselineCapSeconds }
        return customTarget ?? (mission.targetSeconds ?? dog.plan.targetSeconds)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isBaseline ? String(localized: "Baseline") : String(localized: "Mission")).eyebrowStyle(StayPalette.apricot)
                        Text(isBaseline ? String(localized: "Up to \(DurationText.short(target))") : DurationText.short(target))
                            .font(StayFont.hero)
                            .foregroundStyle(StayPalette.ink)
                        Text(isBaseline
                             ? String(localized: "Leave the way you normally would. Watch the live view and come back at the first sign of stress — that moment sets the starting point.")
                             : String(localized: "Come back when the timer ends, or sooner if \(dog.name) shows stress. Coming back early is always okay."))
                            .font(StayFont.callout)
                            .foregroundStyle(StayPalette.inkSecondary)
                    }

                    if mission.isRestDay && !isBaseline {
                        Label("Today is a rest day. Training anyway is fine if you must leave, but keep it short.", systemImage: "leaf")
                            .font(StayFont.callout)
                            .stayCard(padding: 14, fill: StayPalette.sageSoft)
                    }

                    if !mission.warmups.isEmpty && !isBaseline {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Warm-up departures").font(StayFont.headline)
                            Text("Quick exits first help \(dog.name) relax into the main mission.")
                                .font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                            ForEach(Array(mission.warmups.enumerated()), id: \.offset) { index, seconds in
                                WarmupRow(index: index, seconds: seconds, done: completedWarmups.contains(index), running: runningWarmup == index) {
                                    runningWarmup = index
                                } finished: {
                                    completedWarmups.insert(index)
                                    runningWarmup = nil
                                    Haptics.success()
                                }
                            }
                        }
                        .stayCard()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Before you go").font(StayFont.headline)
                        ChecklistLine(text: String(localized: "A walk or play an hour ago, not right now"))
                        ChecklistLine(text: String(localized: "Water, a comfy spot and something to chew"))
                        ChecklistLine(text: String(localized: "No big goodbye — just go"))
                        ChecklistLine(text: String(localized: "No other absences today longer than this one"))
                    }
                    .stayCard()

                    monitoringCard
                }
                .padding(20)
            }
            .stayBackground()
            .safeAreaInset(edge: .bottom) {
                Button {
                    let source: MonitoringSource = useCamera ? (model.cameraReachability ?? .selfObserved) : .selfObserved
                    let session = model.startSession(dog: dog, kind: isBaseline ? .baseline : .mission, plannedSeconds: target, monitoring: source)
                    onStart(session)
                } label: {
                    Label(isBaseline ? String(localized: "Start baseline") : String(localized: "I'm leaving now"), systemImage: "figure.walk.departure")
                }
                .buttonStyle(.stayPrimary(StayPalette.apricot))
                .accessibilityIdentifier("brief.start")
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !isBaseline {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Use today's plan") { customTarget = nil }
                            Button("Make it shorter (−20%)") {
                                customTarget = max(model.engine.config.minimumSeconds, MissionEngine.roundDown((mission.targetSeconds ?? 30) * 0.8))
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel(Text("Adjust length"))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var monitoringCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monitoring").font(StayFont.headline)
            switch model.cameraReachability {
            case .nearby:
                StatusLine(symbol: "wifi", title: String(localized: "Dog camera connected"), detail: String(localized: "Live view over Wi-Fi, alerts through iCloud when you're out of range"), isOn: true)
            case .cloud:
                StatusLine(symbol: "icloud.fill", title: String(localized: "Dog camera reachable"), detail: String(localized: "Snapshots every few seconds and instant alerts"), isOn: true)
            default:
                StatusLine(symbol: "video.slash", title: String(localized: "No camera connected"), detail: model.isPaired ? String(localized: "Open Stay on the camera device and tap Arm") : String(localized: "You can still run the mission and note any signs yourself"), isOn: false)
            }
            if model.cameraReachability != nil {
                Toggle("Monitor with the dog camera", isOn: $useCamera)
                    .font(StayFont.callout)
            }
        }
        .stayCard()
    }
}

private struct ChecklistLine: View {
    var text: String
    @State private var checked = false

    var body: some View {
        Button {
            Haptics.select()
            checked.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checked ? StayPalette.sage : StayPalette.inkTertiary)
                    .font(.title3)
                Text(text).font(StayFont.callout).foregroundStyle(StayPalette.ink).multilineTextAlignment(.leading)
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

private struct WarmupRow: View {
    var index: Int
    var seconds: TimeInterval
    var done: Bool
    var running: Bool
    var start: () -> Void
    var finished: () -> Void
    @State private var startedAt: Date?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(index + 1).circle")
                .font(.title3)
                .foregroundStyle(done ? StayPalette.sage : StayPalette.inkSecondary)
            Text("Step out for \(DurationText.short(seconds))").font(StayFont.callout)
            Spacer()
            if running, let startedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    let remaining = max(0, seconds - context.date.timeIntervalSince(startedAt))
                    Text(DurationText.clock(remaining))
                        .font(StayFont.bodyEmphasis.monospacedDigit())
                        .foregroundStyle(StayPalette.apricot)
                        .onChange(of: remaining <= 0) { _, isDone in if isDone { finished() } }
                }
            } else if !done {
                Button("Start") {
                    startedAt = .now
                    start()
                }
                .font(StayFont.captionEmphasis)
                .buttonStyle(.bordered)
            }
        }
    }
}
