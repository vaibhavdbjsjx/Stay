import Charts
import SwiftUI

/// Full-screen flow for one session: running → review → result.
struct MissionFlowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var sessionID: UUID
    @State private var result: ReviewResult?

    var body: some View {
        Group {
            if let result {
                MissionResultView(result: result) { dismiss() }
            } else if let session = model.session(sessionID) {
                if !session.isFinished {
                    MissionRunningView(session: session) { dismiss() }
                } else {
                    SessionReviewView(session: session) { result = $0 }
                }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.session(sessionID)?.isFinished)
        .animation(.easeInOut(duration: 0.35), value: result)
    }
}

// MARK: - Running

struct MissionRunningView: View {
    @Environment(AppModel.self) private var model
    var session: AbsenceSession
    var minimize: () -> Void
    @State private var confirmEnd = false

    private var dog: Dog? { model.dogs.first { $0.id == session.dogID } }

    var body: some View {
        TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(session.startedAt)
            let isBaseline = session.kind == .baseline
            let reached = !isBaseline && elapsed >= session.plannedSeconds
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        Button(action: minimize) {
                            Image(systemName: "chevron.down")
                                .font(.headline)
                                .frame(width: 40, height: 40)
                                .background(StayPalette.surface, in: Circle())
                        }
                        .accessibilityLabel(Text("Minimise"))
                        Spacer()
                        VStack(spacing: 2) {
                            Text(isBaseline ? String(localized: "Baseline") : String(localized: "Mission")).eyebrowStyle()
                            Text(dog?.name ?? "").font(StayFont.headline)
                        }
                        Spacer()
                        DogAvatar(dog: dog, size: 40)
                    }

                    ZStack {
                        ProgressRing(
                            progress: isBaseline ? (elapsed.truncatingRemainder(dividingBy: 60) / 60) : elapsed / max(1, session.plannedSeconds),
                            lineWidth: 16,
                            tint: session.events.isEmpty ? (reached ? StayPalette.calm : StayPalette.sage) : StayPalette.apricot
                        )
                        VStack(spacing: 6) {
                            Text(DurationText.clock(elapsed))
                                .font(StayFont.timer)
                                .foregroundStyle(StayPalette.ink)
                                .contentTransition(.numericText())
                                .accessibilityLabel(Text("Elapsed \(DurationText.spoken(elapsed))"))
                            if isBaseline {
                                Text("Come back at the first sign of stress").font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                            } else {
                                Text(reached ? String(localized: "Time to head back") : String(localized: "of \(DurationText.short(session.plannedSeconds))"))
                                    .font(StayFont.captionEmphasis)
                                    .foregroundStyle(reached ? StayPalette.calm : StayPalette.inkSecondary)
                            }
                        }
                        .multilineTextAlignment(.center)
                        .padding(30)
                    }
                    .frame(width: 260, height: 260)
                    .onChange(of: reached) { _, nowReached in if nowReached { Haptics.success() } }

                    statusBanner(reached: reached)
                    LiveViewPanel(session: session)
                    if !session.events.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Detected so far").font(StayFont.headline)
                            ForEach(session.events) { event in
                                HStack(spacing: 12) {
                                    Image(systemName: event.kind.symbol).foregroundStyle(StayPalette.apricot).frame(width: 24)
                                    Text(event.kind.title).font(StayFont.bodyEmphasis)
                                    Spacer()
                                    Text("at \(DurationText.clock(event.offset))").font(StayFont.caption.monospacedDigit()).foregroundStyle(StayPalette.inkSecondary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .stayCard()
                    }
                    Button {
                        Haptics.warning()
                        model.addManualEvent(to: session.id, offset: elapsed, kind: .other)
                    } label: {
                        Label("I noticed a sign of stress", systemImage: "hand.raised.fill")
                    }
                    .buttonStyle(.staySecondary)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        model.endSession(session.id, reason: .returnedEarly)
                    } label: {
                        Label(reached || isBaseline ? String(localized: "I'm back") : String(localized: "I'm back early"), systemImage: "house.fill")
                    }
                    .buttonStyle(.stayPrimary(reached ? StayPalette.calm : StayPalette.sage))
                    Button(role: .destructive) {
                        confirmEnd = true
                    } label: {
                        Text("End because of stress").font(StayFont.callout.weight(.semibold))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(StayPalette.canvas.opacity(0.96))
            }
            .confirmationDialog("End the mission because of stress?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End now", role: .destructive) {
                    if session.events.isEmpty {
                        model.addManualEvent(to: session.id, offset: elapsed, kind: .other)
                    }
                    model.endSession(session.id, reason: .distress)
                }
            } message: {
                Text("The camera will stop too. Head back calmly — you'll review what happened next.")
            }
        }
        .stayBackground()
    }

    @ViewBuilder
    private func statusBanner(reached: Bool) -> some View {
        if let alert = model.latestAlert, session.events.contains(where: { $0.id == alert.id }) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(alert.kind.title) detected").font(StayFont.headline).foregroundStyle(.white)
                    Text("Check the live view. If it continues, head back calmly.").font(StayFont.caption).foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Button {
                    model.dismissLatestAlert()
                } label: {
                    Image(systemName: "xmark").foregroundStyle(.white)
                }
                .accessibilityLabel(Text("Dismiss alert"))
            }
            .padding(16)
            .background(StayPalette.alert, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if session.monitoring != .selfObserved {
            HStack(spacing: 10) {
                Circle().fill(StayPalette.calm).frame(width: 10, height: 10)
                Text(session.events.isEmpty ? String(localized: "All calm so far") : String(localized: "Settled again")).font(StayFont.bodyEmphasis)
                Spacer()
                if let status = model.cameraStatus, status.state == .armed, status.sessionID == nil, Date.now.timeIntervalSince(session.startedAt) > 20 {
                    Text("Camera isn't monitoring").font(StayFont.caption).foregroundStyle(StayPalette.alert)
                }
            }
            .stayCard(padding: 14, fill: StayPalette.calm.opacity(0.1))
        }
    }
}

/// Live frames over Wi-Fi, or iCloud snapshots refreshed every few seconds.
struct LiveViewPanel: View {
    @Environment(AppModel.self) private var model
    var session: AbsenceSession

    var body: some View {
        let nearbyFrame = model.nearby.latestFrame
        let cloudFrame = model.cloudSnapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live view").font(StayFont.headline)
                Spacer()
                if nearbyFrame != nil {
                    Pill(text: String(localized: "Live"), symbol: "dot.radiowaves.left.and.right", tint: StayPalette.calm, fill: StayPalette.calm.opacity(0.14))
                } else if let at = model.cloudSnapshotAt, cloudFrame != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Pill(text: String(localized: "\(max(0, Int(context.date.timeIntervalSince(at))))s ago"), symbol: "icloud", tint: StayPalette.inkSecondary, fill: StayPalette.surfaceRaised)
                    }
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black.opacity(0.85))
                if let image = nearbyFrame ?? cloudFrame {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(Text("Camera view of your dog"))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: session.monitoring == .selfObserved ? "eye" : "video.slash")
                            .font(.title)
                        Text(session.monitoring == .selfObserved
                             ? String(localized: "No camera for this mission. Use “I noticed a sign of stress” if you hear or see anything.")
                             : String(localized: "Waiting for the first picture from the dog camera…"))
                            .font(StayFont.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .foregroundStyle(.white.opacity(0.75))
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            if let status = model.cameraStatus, session.monitoring != .selfObserved {
                HStack(spacing: 12) {
                    Label(status.batteryLevel >= 0 ? "\(Int(status.batteryLevel * 100))%" : "—", systemImage: status.isCharging ? "battery.100.bolt" : "battery.50")
                    if status.thermalWarning { Label("Camera is warm", systemImage: "thermometer.high").foregroundStyle(StayPalette.alert) }
                    Spacer()
                    LevelSparkline(levels: [status.level]).frame(width: 40, height: 18)
                }
                .font(StayFont.caption)
                .foregroundStyle(StayPalette.inkSecondary)
            }
        }
        .stayCard()
    }
}

// MARK: - Review

struct SessionReviewView: View {
    @Environment(AppModel.self) private var model
    var session: AbsenceSession
    var onFinish: (ReviewResult) -> Void
    @State private var note = ""
    @State private var addingSign = false

    private var dog: Dog? { model.dogs.first { $0.id == session.dogID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Review").eyebrowStyle(StayPalette.apricot)
                        Text("How did \(dog?.name ?? String(localized: "your dog")) do?").font(StayFont.display)
                        Text("Confirm what really was stress and dismiss false alarms, like a doorbell or a happy bark. Only confirmed signs change the plan.")
                            .font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
                    }
                    HStack(spacing: 12) {
                        MetricTile(value: DurationText.short(session.actualSeconds), label: String(localized: "Alone"), symbol: "clock.fill")
                        MetricTile(value: session.kind == .baseline ? "—" : DurationText.short(session.plannedSeconds), label: String(localized: "Planned"), symbol: "target", tint: StayPalette.apricot)
                    }
                    if !session.levelTimeline.isEmpty {
                        SessionTimelineChart(session: session).stayCard()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text(session.events.isEmpty ? String(localized: "No signs detected") : String(localized: "Detected moments")).font(StayFont.headline)
                        if session.events.isEmpty {
                            Text(session.monitoring == .selfObserved
                                 ? String(localized: "If you noticed anything — barking, pacing, whining — add it below so the plan stays honest.")
                                 : String(localized: "The camera didn't pick up any barking, howling, whining or pacing."))
                                .font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
                        }
                        ForEach(session.events) { event in
                            EventReviewRow(event: event, image: event.snapshotFilename.flatMap(model.image(named:))) { review in
                                Haptics.select()
                                model.setReview(review, eventID: event.id, sessionID: session.id)
                            }
                        }
                        Button {
                            addingSign = true
                        } label: {
                            Label("Add a sign I noticed", systemImage: "plus.circle.fill")
                                .font(StayFont.bodyEmphasis)
                        }
                    }
                    .stayCard()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes").font(StayFont.headline)
                        TextField("Anything unusual? A delivery, a storm…", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .font(StayFont.body)
                    }
                    .stayCard()
                }
                .padding(20)
            }
            .stayBackground()
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.setNote(note, sessionID: session.id)
                    if let result = model.finishReview(sessionID: session.id) {
                        Haptics.success()
                        onFinish(result)
                    }
                } label: {
                    Text(session.pendingEvents.isEmpty ? String(localized: "Save review") : String(localized: "Save — dismiss \(session.pendingEvents.count) unchecked"))
                }
                .buttonStyle(.stayPrimary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .sheet(isPresented: $addingSign) {
                AddSignSheet(maxOffset: session.actualSeconds) { offset, kind in
                    model.addManualEvent(to: session.id, offset: offset, kind: kind)
                }
                .presentationDetents([.medium])
            }
            .onAppear { note = session.note }
        }
    }
}

private struct EventReviewRow: View {
    var event: DistressEvent
    var image: UIImage?
    var setReview: (EventReview) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        StayPalette.apricotSoft
                        Image(systemName: event.kind.symbol).foregroundStyle(StayPalette.apricot)
                    }
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.kind.title).font(StayFont.bodyEmphasis)
                Text(event.isManual ? String(localized: "Added by you at \(DurationText.clock(event.offset))") : String(localized: "At \(DurationText.clock(event.offset)) · \(Int(event.confidence * 100))% sure"))
                    .font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 6) {
                ReviewToggle(symbol: "checkmark", label: String(localized: "Stress"), selected: event.review == .confirmed, tint: StayPalette.alert) { setReview(.confirmed) }
                ReviewToggle(symbol: "xmark", label: String(localized: "Not stress"), selected: event.review == .dismissed, tint: StayPalette.inkSecondary) { setReview(.dismissed) }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ReviewToggle: View {
    var symbol: String
    var label: String
    var selected: Bool
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(.callout, weight: .bold))
                Text(label).font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .frame(width: 58, height: 48)
            .foregroundStyle(selected ? .white : tint)
            .background(selected ? tint : tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct AddSignSheet: View {
    @Environment(\.dismiss) private var dismiss
    var maxOffset: TimeInterval
    var add: (TimeInterval, DistressKind) -> Void
    @State private var kind: DistressKind = .bark
    @State private var offset: TimeInterval = 0

    var body: some View {
        NavigationStack {
            Form {
                Picker("What did you notice?", selection: $kind) {
                    ForEach(DistressKind.allCases, id: \.self) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                Section("When, roughly?") {
                    Slider(value: $offset, in: 0...max(1, maxOffset), step: 1)
                    Text("\(DurationText.clock(offset)) into the session").font(StayFont.callout.monospacedDigit())
                }
            }
            .navigationTitle("Add a sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        add(offset, kind)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Sound level over the session with event markers.
struct SessionTimelineChart: View {
    var session: AbsenceSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sound level").font(StayFont.headline)
            Chart {
                ForEach(Array(session.levelTimeline.enumerated()), id: \.offset) { index, level in
                    AreaMark(x: .value("Time", Double(index) * session.levelInterval), y: .value("Level", level))
                        .foregroundStyle(LinearGradient(colors: [StayPalette.sage.opacity(0.5), StayPalette.sage.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Time", Double(index) * session.levelInterval), y: .value("Level", level))
                        .foregroundStyle(StayPalette.sage)
                        .interpolationMethod(.catmullRom)
                }
                ForEach(session.events) { event in
                    RuleMark(x: .value("Event", event.offset))
                        .foregroundStyle(event.review == .dismissed ? StayPalette.inkTertiary : StayPalette.apricot)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }
            .chartYScale(domain: 0...1)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(StayPalette.hairline)
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) { Text(DurationText.clock(seconds)) }
                    }
                }
            }
            .frame(height: 120)
            .accessibilityLabel(Text("Sound level chart with \(session.events.count) detected moments"))
        }
    }
}

// MARK: - Result

struct MissionResultView: View {
    @Environment(AppModel.self) private var model
    var result: ReviewResult
    var done: () -> Void
    @State private var appeared = false
    @State private var showShare = false

    private var session: AbsenceSession? { model.session(result.sessionID) }
    private var dog: Dog? { session.flatMap { s in model.dogs.first { $0.id == s.dogID } } }

    var body: some View {
        let name = dog?.name ?? String(localized: "Your dog")
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    if !result.milestones.isEmpty { ConfettiView().frame(height: 220) }
                    ZStack {
                        Circle().fill(tint.opacity(0.14)).frame(width: 150, height: 150)
                        Circle().fill(tint.opacity(0.22)).frame(width: 110, height: 110)
                        Image(systemName: symbol)
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .scaleEffect(appeared ? 1 : 0.6)
                    .accessibilityHidden(true)
                }
                .padding(.top, 30)
                VStack(spacing: 10) {
                    Text(MissionCopy.changeHeadline(result.change, dogName: name)).font(StayFont.display).multilineTextAlignment(.center)
                    Text(MissionCopy.changeDetail(result.change, dogName: name)).font(StayFont.body).foregroundStyle(StayPalette.inkSecondary).multilineTextAlignment(.center)
                }
                PlanChangeGraphic(change: result.change)
                if result.suggestsRest {
                    Label("Tomorrow is a rest day. No absences — just a nice, easy day.", systemImage: "leaf.fill")
                        .font(StayFont.callout)
                        .stayCard(padding: 14, fill: StayPalette.sageSoft)
                }
                if !result.milestones.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("New milestone").eyebrowStyle(StayPalette.apricot)
                        ForEach(result.milestones, id: \.self) { milestone in
                            HStack(spacing: 12) {
                                IconBadge(symbol: milestone.symbol, tint: StayPalette.apricot, fill: StayPalette.apricotSoft)
                                Text(milestone.title).font(StayFont.headline)
                            }
                        }
                    }
                    .stayCard()
                }
                if dog?.assessment.recommendsVet == true, case .rolledBack = result.change {
                    Text("If sessions are often hard, your vet can help alongside training.")
                        .font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary).multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
        .stayBackground()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if !result.milestones.isEmpty || isCalm {
                    Button {
                        showShare = true
                    } label: {
                        Label("Share \(name)'s progress", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.stayPrimary(StayPalette.apricot))
                }
                Button("Done", action: done).buttonStyle(.staySecondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showShare) {
            if let dog { ShareStudioView(dog: dog, highlight: result.milestones.first) }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { appeared = true }
            if !result.milestones.isEmpty { Haptics.success() }
        }
    }

    private var isCalm: Bool {
        if case .calm = result.outcome { return true }
        return false
    }

    private var tint: Color {
        switch result.change {
        case .rolledBack: StayPalette.apricot
        default: StayPalette.calm
        }
    }

    private var symbol: String {
        switch result.change {
        case .baselineSet: "flag.checkered"
        case .increased: "arrow.up.right"
        case .held: "equal"
        case .rolledBack: "arrow.uturn.backward"
        }
    }
}

private struct PlanChangeGraphic: View {
    var change: PlanChange

    var body: some View {
        let values: (TimeInterval, TimeInterval)? = switch change {
        case .baselineSet(let b, let f): (b, f)
        case .increased(let from, let to): (from, to)
        case .rolledBack(let from, let to): (from, to)
        case .held: nil
        }
        if let (from, to) = values {
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(isBaseline ? String(localized: "Baseline") : String(localized: "This time")).font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                    Text(DurationText.short(from)).font(StayFont.metric)
                }
                Image(systemName: "arrow.right").foregroundStyle(StayPalette.inkTertiary)
                VStack(spacing: 4) {
                    Text("Next mission").font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                    Text(DurationText.short(to)).font(StayFont.metric).foregroundStyle(StayPalette.sage)
                }
            }
            .frame(maxWidth: .infinity)
            .stayCard()
            .accessibilityElement(children: .combine)
        }
    }

    private var isBaseline: Bool {
        if case .baselineSet = change { return true }
        return false
    }
}

/// Lightweight celebratory confetti drawn with Canvas.
struct ConfettiView: View {
    @State private var start = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let pieces: [(x: Double, speed: Double, spin: Double, hue: Int, size: Double)] = (0..<70).map { _ in
        (Double.random(in: 0...1), Double.random(in: 0.5...1.2), Double.random(in: -3...3), Int.random(in: 0..<4), Double.random(in: 5...10))
    }

    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            TimelineView(.animation) { context in
                Canvas { ctx, size in
                    let t = context.date.timeIntervalSince(start)
                    let colors: [Color] = [StayPalette.apricot, StayPalette.sage, Color(hex: 0xF0BC5E), Color(hex: 0xF6B48A)]
                    for piece in pieces {
                        let y = -20 + t * 160 * piece.speed
                        guard y < size.height + 20 else { continue }
                        let x = piece.x * size.width + sin(t * 2 + piece.spin) * 18
                        let transform = CGAffineTransform(translationX: x, y: y).rotated(by: t * piece.spin)
                        let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)
                        let path = Path(roundedRect: rect, cornerRadius: 1).applying(transform)
                        ctx.fill(path, with: .color(colors[piece.hue].opacity(max(0, 1 - t / 3))))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
