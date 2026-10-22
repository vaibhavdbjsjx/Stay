import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showBrief = false
    @State private var flowSessionID: UUID?
    @State private var showAddDog = false
    @State private var showPairing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let dog = model.selectedDog {
                    content(dog)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                } else {
                    EmptyStateView(symbol: "pawprint", title: String(localized: "Add your dog"), message: String(localized: "Create a profile to get a personalised plan."))
                    Button("Add a dog") { showAddDog = true }.buttonStyle(.stayPrimary).padding(24)
                }
            }
            .stayBackground()
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $flowSessionID) { id in
                MissionFlowView(sessionID: id)
            }
            .sheet(isPresented: $showBrief) {
                if let dog = model.selectedDog {
                    MissionBriefView(dog: dog) { session in
                        showBrief = false
                        flowSessionID = session.id
                    }
                }
            }
            .sheet(isPresented: $showAddDog) { AddDogView() }
            .sheet(isPresented: $showPairing) { OwnerPairingView() }
        }
    }

    @ViewBuilder
    private func content(_ dog: Dog) -> some View {
        let mission = model.todayMission(for: dog)
        VStack(alignment: .leading, spacing: 20) {
            header(dog)
            if let active = model.activeSession {
                ActiveSessionBanner(session: active) { flowSessionID = active.id }
            } else if let pending = model.sessionAwaitingReview(for: dog.id) {
                ReviewPromptCard(session: pending, dogName: dog.name) { flowSessionID = pending.id }
            }
            MissionHeroCard(dog: dog, mission: mission) { startTapped(dog: dog, mission: mission) }
            if case .absence = mission.kind, let drill = mission.cueDrill {
                CueDrillCard(dog: dog, drill: drill)
            }
            CoachTipCard(dog: dog)
            StatsStrip(dog: dog)
            CameraStatusCard { showPairing = true }
        }
    }

    private func header(_ dog: Dog) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))).eyebrowStyle()
                Text(greeting(dog)).font(StayFont.hero).foregroundStyle(StayPalette.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Menu {
                ForEach(model.dogs) { other in
                    Button {
                        model.selectDog(other.id)
                    } label: {
                        if other.id == dog.id { Label(other.name, systemImage: "checkmark") } else { Text(other.name) }
                    }
                }
                Divider()
                Button {
                    if model.canAddDog { showAddDog = true } else { model.presentedPaywall = true }
                } label: {
                    Label("Add a dog", systemImage: "plus")
                }
            } label: {
                DogAvatar(dog: dog, size: 52)
            }
            .accessibilityLabel(Text("Switch dog. Current: \(dog.name)"))
        }
        .padding(.top, 16)
    }

    private func greeting(_ dog: Dog) -> String {
        let hour = Calendar.current.component(.hour, from: .now)
        return switch hour {
        case 5..<12: String(localized: "Morning, \(dog.name)")
        case 12..<18: String(localized: "Hi, \(dog.name)")
        default: String(localized: "Evening, \(dog.name)")
        }
    }

    private func startTapped(dog: Dog, mission: DailyMission) {
        let kind: SessionKind = dog.plan.phase == .needsBaseline ? .baseline : .mission
        if model.canStart(kind) {
            showBrief = true
        } else {
            model.presentedPaywall = true
        }
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

// MARK: - Cards

private struct MissionHeroCard: View {
    @Environment(AppModel.self) private var model
    var dog: Dog
    var mission: DailyMission
    var start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(eyebrow).eyebrowStyle(StayPalette.cream.opacity(0.8))
                Spacer()
                if let remaining = model.remainingFreeMissions, dog.plan.phase == .training {
                    Pill(text: String(localized: "\(remaining) free left"), tint: StayPalette.cream, fill: .white.opacity(0.15))
                }
            }
            Text(MissionCopy.title(for: mission, dog: dog))
                .font(StayFont.display)
                .foregroundStyle(StayPalette.cream)
                .fixedSize(horizontal: false, vertical: true)
            Text(MissionCopy.subtitle(for: mission, dog: dog))
                .font(StayFont.callout)
                .foregroundStyle(StayPalette.cream.opacity(0.85))
            if !mission.warmups.isEmpty, !mission.completedToday {
                HStack(spacing: 8) {
                    Image(systemName: "flame").accessibilityHidden(true)
                    Text("Warm up: \(mission.warmups.map(DurationText.short).formatted(.list(type: .and)))")
                }
                .font(StayFont.captionEmphasis)
                .foregroundStyle(StayPalette.cream.opacity(0.9))
            }
            if mission.isRestDay {
                Label("Enjoy the day together", systemImage: "leaf.fill")
                    .font(StayFont.headline)
                    .foregroundStyle(StayPalette.cream)
            } else if mission.completedToday {
                HStack {
                    Label("Done for today", systemImage: "checkmark.seal.fill")
                        .font(StayFont.headline)
                        .foregroundStyle(StayPalette.cream)
                    Spacer()
                    Button("Another round", action: start)
                        .font(StayFont.captionEmphasis)
                        .foregroundStyle(StayPalette.cream)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.15), in: Capsule())
                }
            } else {
                Button(action: start) {
                    Label(dog.plan.phase == .needsBaseline ? String(localized: "Start baseline") : String(localized: "Start mission"), systemImage: "play.fill")
                }
                .buttonStyle(.stayPrimary(StayPalette.apricot))
                .disabled(model.activeSession != nil)
            }
        }
        .padding(22)
        .background(
            ZStack(alignment: .bottomTrailing) {
                StayPalette.heroGradient
                StayMark(houseColor: .white.opacity(0.08), dogColor: .white.opacity(0.07), faceColor: .clear)
                    .frame(width: 190, height: 190)
                    .offset(x: 40, y: 40)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: StayPalette.sageDeep.opacity(0.25), radius: 18, y: 10)
    }

    private var eyebrow: String {
        switch mission.kind {
        case .baseline: String(localized: "First step")
        case .absence: String(localized: "Today's mission")
        case .rest: String(localized: "Today")
        }
    }
}

private struct ActiveSessionBanner: View {
    var session: AbsenceSession
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                IconBadge(symbol: "timer", tint: .white, fill: StayPalette.apricot)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mission in progress").font(StayFont.headline).foregroundStyle(StayPalette.ink)
                    Text(session.startedAt, style: .timer).font(StayFont.callout.monospacedDigit()).foregroundStyle(StayPalette.inkSecondary)
                }
                Spacer()
                Text("Open").font(StayFont.captionEmphasis).foregroundStyle(StayPalette.apricot)
            }
            .stayCard(padding: 16, fill: StayPalette.apricotSoft)
        }
        .buttonStyle(.plain)
    }
}

private struct ReviewPromptCard: View {
    var session: AbsenceSession
    var dogName: String
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                IconBadge(symbol: "checklist", tint: StayPalette.sage, fill: StayPalette.sageSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review \(dogName)'s session").font(StayFont.headline).foregroundStyle(StayPalette.ink)
                    Text(session.events.isEmpty ? String(localized: "No signs detected. Confirm to update the plan.") : String(localized: "\(session.events.count) moments to check"))
                        .font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(StayPalette.inkTertiary)
            }
            .stayCard(padding: 16)
        }
        .buttonStyle(.plain)
    }
}

private struct CueDrillCard: View {
    @Environment(AppModel.self) private var model
    var dog: Dog
    var drill: CueDrill

    var body: some View {
        let today = model.cueRepsToday(for: dog.id).count
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(symbol: drill.cue?.symbol ?? "shuffle", tint: StayPalette.apricot, fill: StayPalette.apricotSoft)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Departure cue practice").eyebrowStyle()
                    Text(drill.cue?.title ?? String(localized: "Mix all your cues")).font(StayFont.headline).foregroundStyle(StayPalette.ink)
                    Text(drill.cue?.instruction ?? String(localized: "Do your departure routine in a random order, then stay home."))
                        .font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(0..<drill.reps, id: \.self) { index in
                    Capsule().fill(index < today ? StayPalette.apricot : StayPalette.apricotSoft).frame(height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("\(min(today, drill.reps)) of \(drill.reps) reps done today"))
            Text("How did \(dog.name) react?").font(StayFont.captionEmphasis).foregroundStyle(StayPalette.inkSecondary)
            HStack(spacing: 8) {
                ForEach(CueReaction.allCases, id: \.self) { reaction in
                    Button {
                        reaction == .worried ? Haptics.warning() : Haptics.tap()
                        model.logCue(reaction, dog: dog)
                    } label: {
                        Text(reaction.title)
                            .font(StayFont.captionEmphasis)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(reaction == .worried ? StayPalette.alert : StayPalette.sage)
                            .background(reaction == .worried ? StayPalette.alert.opacity(0.1) : StayPalette.sageSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if drill.cue != nil {
                Text("\(drill.calmRepsSoFar) of \(drill.calmRepsNeeded) calm reps in a row to unlock the next cue")
                    .font(StayFont.caption).foregroundStyle(StayPalette.inkTertiary)
            }
        }
        .stayCard()
    }
}

private struct CoachTipCard: View {
    @Environment(AppModel.self) private var model
    var dog: Dog
    @State private var tip: CoachTip?

    var body: some View {
        let shown = tip ?? model.coach.quickTip(model.coachContext(for: dog))
        HStack(alignment: .top, spacing: 14) {
            IconBadge(symbol: shown.symbol)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Coach").eyebrowStyle()
                    if shown.isAIGenerated {
                        Image(systemName: "apple.intelligence")
                            .font(.caption2)
                            .foregroundStyle(StayPalette.inkTertiary)
                            .accessibilityLabel(Text("Written on device by Apple Intelligence"))
                    }
                }
                Text(shown.title).font(StayFont.headline).foregroundStyle(StayPalette.ink)
                Text(shown.body).font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .stayCard()
        .task(id: dog.plan) {
            tip = await model.coach.dailyTip(model.coachContext(for: dog))
        }
    }
}

private struct StatsStrip: View {
    @Environment(AppModel.self) private var model
    var dog: Dog

    var body: some View {
        let reviewed = model.sessions(for: dog.id).filter(\.isReviewed)
        let longest = model.stats.longestCalm(sessions: reviewed)
        let streak = model.stats.dayStreak(sessions: reviewed, today: .now)
        HStack(spacing: 12) {
            MetricTile(value: longest > 0 ? DurationText.short(longest) : "—", label: String(localized: "Longest calm"), symbol: "house.fill")
            MetricTile(value: "\(streak)", label: streak == 1 ? String(localized: "Day streak") : String(localized: "Days streak"), symbol: "flame.fill", tint: StayPalette.apricot)
        }
    }
}

private struct CameraStatusCard: View {
    @Environment(AppModel.self) private var model
    var openPairing: () -> Void

    var body: some View {
        Button(action: openPairing) {
            HStack(spacing: 14) {
                IconBadge(symbol: "video.fill", tint: tint, fill: tint.opacity(0.14), size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dog camera").font(StayFont.bodyEmphasis).foregroundStyle(StayPalette.ink)
                    Text(detail).font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(StayPalette.inkTertiary)
            }
            .stayCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var tint: Color {
        model.cameraReachability != nil ? StayPalette.calm : StayPalette.inkTertiary
    }

    private var detail: String {
        switch model.cameraReachability {
        case .nearby: String(localized: "Connected on Wi-Fi · live view ready")
        case .cloud: String(localized: "Reachable through iCloud")
        default: model.isPaired ? String(localized: "Paired · open Stay on the camera and tap Arm") : String(localized: "Not paired yet · tap to set up")
        }
    }
}
