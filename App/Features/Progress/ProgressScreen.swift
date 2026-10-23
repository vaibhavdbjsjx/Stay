import Charts
import SwiftUI

struct ProgressScreen: View {
    @Environment(AppModel.self) private var model
    @State private var showShare = false
    @State private var showReport = false
    @State private var editingEntry: JournalEntry?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let dog = model.selectedDog {
                    content(dog).padding(20)
                }
            }
            .stayBackground()
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showShare = true } label: { Label("Share progress", systemImage: "square.and.arrow.up") }
                        Button { showReport = true } label: { Label("Trainer report (PDF)", systemImage: "doc.richtext") }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text("Share"))
                }
            }
            .sheet(isPresented: $showShare) {
                if let dog = model.selectedDog { ShareStudioView(dog: dog, highlight: nil) }
            }
            .sheet(isPresented: $showReport) {
                if let dog = model.selectedDog { TrainerReportView(dog: dog) }
            }
            .sheet(item: $editingEntry) { entry in
                JournalEditor(entry: entry)
            }
        }
    }

    @ViewBuilder
    private func content(_ dog: Dog) -> some View {
        let reviewed = model.sessions(for: dog.id).filter(\.isReviewed)
        let snapshot = model.stats.snapshot(sessions: reviewed, today: .now)
        VStack(alignment: .leading, spacing: 22) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                MetricTile(value: snapshot.longestCalm > 0 ? DurationText.short(snapshot.longestCalm) : "—", label: String(localized: "Longest calm"), symbol: "house.fill")
                MetricTile(value: "\(snapshot.dayStreak)", label: String(localized: "Day streak"), symbol: "flame.fill", tint: StayPalette.apricot)
                MetricTile(value: "\(snapshot.calmSessions)", label: String(localized: "Calm sessions"), symbol: "checkmark.seal.fill", tint: StayPalette.calm)
                MetricTile(value: dog.plan.phase == .training ? DurationText.short(dog.plan.targetSeconds) : "—", label: String(localized: "Next mission"), symbol: "target", tint: StayPalette.amber)
            }
            .reveal(0)

            if reviewed.isEmpty {
                EmptyStateView(symbol: "chart.line.uptrend.xyaxis", title: String(localized: "Your chart starts here"), message: String(localized: "Complete and review the baseline to see \(dog.name)'s progress."))
                    .stayCard()
            } else {
                TrendChart(sessions: reviewed).stayCard().reveal(1)
                if let goal = model.stats.nextDurationGoal(after: snapshot.longestCalm) {
                    NextGoalCard(longest: snapshot.longestCalm, goal: goal)
                }
            }

            MilestoneShelf(reached: model.milestones(for: dog.id)).reveal(2)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: String(localized: "Sessions"), trailing: reviewed.isEmpty ? nil : String(localized: "\(reviewed.count) total"))
                let all = model.sessions(for: dog.id).filter(\.isFinished)
                if all.isEmpty {
                    Text("Finished sessions will appear here.").font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
                }
                ForEach(all.prefix(30)) { session in
                    NavigationLink {
                        SessionDetailView(sessionID: session.id)
                    } label: {
                        SessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: String(localized: "Journal"))
                    Button {
                        editingEntry = JournalEntry(dogID: dog.id, mood: .okay, text: "")
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill").font(StayFont.bodyEmphasis)
                    }
                }
                let entries = model.journal(for: dog.id)
                if entries.isEmpty {
                    Text("Jot down how days go — sleep, walks, visitors. Patterns are easier to spot later.")
                        .font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
                }
                ForEach(entries.prefix(20)) { entry in
                    Button { editingEntry = entry } label: { JournalRow(entry: entry) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct TrendChart: View {
    var sessions: [AbsenceSession]
    @State private var selected: Date?
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Point: Identifiable {
        var id: UUID
        var date: Date
        var seconds: Double
        var calm: Bool
    }

    var body: some View {
        let points = sessions.sorted { $0.startedAt < $1.startedAt }.suffix(40).map {
            Point(id: $0.id, date: $0.startedAt, seconds: ($0.isCalm ? $0.actualSeconds : ($0.firstConfirmedDistress ?? $0.actualSeconds)), calm: $0.isCalm)
        }
        VStack(alignment: .leading, spacing: 12) {
            Text("Time alone").font(StayFont.headline)
            Text("Calm sessions in green, sessions with stress in orange").font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Seconds", grown ? point.seconds : 0))
                        .foregroundStyle(StayPalette.sage.opacity(0.4))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date), y: .value("Seconds", grown ? point.seconds : 0))
                        .foregroundStyle(point.calm ? StayPalette.calm : StayPalette.apricot)
                        .symbolSize(60)
                }
                if let selected, let nearest = points.min(by: { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }) {
                    RuleMark(x: .value("Selected", nearest.date))
                        .foregroundStyle(StayPalette.inkTertiary)
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(spacing: 2) {
                                Text(DurationText.short(nearest.seconds)).font(StayFont.captionEmphasis)
                                Text(nearest.date.formatted(.dateTime.month().day())).font(.caption2)
                            }
                            .padding(6)
                            .background(StayPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 8))
                        }
                }
            }
            .chartXSelection(value: $selected)
            .chartYScale(domain: 0...max(10, (points.map(\.seconds).max() ?? 10) * 1.15))
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(StayPalette.hairline)
                    AxisValueLabel { if let seconds = value.as(Double.self) { Text(DurationText.short(seconds)) } }
                }
            }
            .frame(height: 200)
            .accessibilityLabel(Text("Chart of time alone across \(points.count) sessions"))
            .onAppear {
                if reduceMotion { grown = true } else {
                    withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.15)) { grown = true }
                }
            }
        }
    }
}

private struct NextGoalCard: View {
    var longest: TimeInterval
    var goal: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Next milestone").eyebrowStyle()
                Spacer()
                Text(DurationText.short(goal)).font(StayFont.captionEmphasis).foregroundStyle(StayPalette.apricot)
            }
            ProgressView(value: min(1, longest / goal)).tint(StayPalette.apricot)
            Text("\(DurationText.short(max(0, goal - longest))) to go").font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
        }
        .stayCard()
        .accessibilityElement(children: .combine)
    }
}

private struct MilestoneShelf: View {
    var reached: [Milestone]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: String(localized: "Milestones"), trailing: String(localized: "\(reached.count) earned"))
            if reached.isEmpty {
                Text("Your first calm mission earns the first badge.").font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(reached.reversed(), id: \.self) { milestone in
                            VStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(StayPalette.sunriseGradient).frame(width: 58, height: 58)
                                    Image(systemName: milestone.symbol).font(.title3.weight(.semibold)).foregroundStyle(.white)
                                }
                                Text(milestone.title)
                                    .font(StayFont.captionEmphasis)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .frame(width: 100)
                            }
                            .padding(14)
                            .background(StayPalette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }
}

struct SessionRow: View {
    var session: AbsenceSession

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: symbol, tint: tint, fill: tint.opacity(0.14), size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(StayFont.bodyEmphasis).foregroundStyle(StayPalette.ink)
                Text(session.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))
                    .font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
            }
            Spacer()
            Text(DurationText.short(session.actualSeconds)).font(StayFont.bodyEmphasis.monospacedDigit()).foregroundStyle(StayPalette.ink)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(StayPalette.inkTertiary)
        }
        .stayCard(padding: 14)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if !session.isReviewed { return String(localized: "Waiting for review") }
        switch session.reviewedOutcome {
        case .calm: return session.kind == .baseline ? String(localized: "Baseline · calm") : String(localized: "Calm")
        case .distress: return session.kind == .baseline ? String(localized: "Baseline") : String(localized: "Stress noticed")
        case .incomplete: return String(localized: "Came back early")
        case nil: return String(localized: "Session")
        }
    }

    private var symbol: String {
        if !session.isReviewed { return "hourglass" }
        switch session.reviewedOutcome {
        case .calm: return "checkmark"
        case .distress: return "waveform.path.ecg"
        default: return "arrow.uturn.backward"
        }
    }

    private var tint: Color {
        if !session.isReviewed { return StayPalette.amber }
        return session.isCalm ? StayPalette.calm : StayPalette.apricot
    }
}

struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var sessionID: UUID
    @State private var reviewing = false
    @State private var confirmDelete = false

    var body: some View {
        if let session = model.session(sessionID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        MetricTile(value: DurationText.short(session.actualSeconds), label: String(localized: "Alone"), symbol: "clock.fill")
                        MetricTile(value: session.kind == .baseline ? String(localized: "Baseline") : DurationText.short(session.plannedSeconds), label: String(localized: "Planned"), symbol: "target", tint: StayPalette.apricot)
                    }
                    if !session.levelTimeline.isEmpty {
                        SessionTimelineChart(session: session).stayCard()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Timeline").font(StayFont.headline)
                        TimelineLine(symbol: "figure.walk.departure", title: String(localized: "Left"), time: session.startedAt, tint: StayPalette.sage)
                        ForEach(session.events) { event in
                            TimelineLine(symbol: event.kind.symbol, title: "\(event.kind.title) · \(event.review == .confirmed ? String(localized: "confirmed") : event.review == .dismissed ? String(localized: "dismissed") : String(localized: "to review"))", time: session.startedAt.addingTimeInterval(event.offset), tint: event.review == .dismissed ? StayPalette.inkTertiary : StayPalette.apricot)
                        }
                        if let end = session.endedAt {
                            TimelineLine(symbol: "house.fill", title: String(localized: "Back home"), time: end, tint: StayPalette.calm)
                        }
                    }
                    .stayCard()
                    let images = session.events.compactMap(\.snapshotFilename).compactMap(model.image(named:))
                    if !images.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(images.indices, id: \.self) { index in
                                    Image(uiImage: images[index]).resizable().scaledToFill()
                                        .frame(width: 160, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                        .accessibilityLabel(Text("Snapshot \(index + 1)"))
                                }
                            }
                        }
                    }
                    if !session.note.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes").font(StayFont.headline)
                            Text(session.note).font(StayFont.body)
                        }
                        .stayCard()
                    }
                    if !session.isReviewed {
                        Button("Review now") { reviewing = true }.buttonStyle(.stayPrimary)
                    }
                }
                .padding(20)
            }
            .stayBackground()
            .navigationTitle(session.startedAt.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel(Text("Delete session"))
                }
            }
            .fullScreenCover(isPresented: $reviewing) { MissionFlowView(sessionID: session.id) }
            .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    dismiss()
                    model.deleteSession(sessionID)
                }
            } message: {
                Text("Your plan won't change, but this session will be removed from charts and reports.")
            }
        }
    }
}

private struct TimelineLine: View {
    var symbol: String
    var title: String
    var time: Date
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 24)
            Text(title).font(StayFont.callout)
            Spacer()
            Text(time.formatted(date: .omitted, time: .standard)).font(StayFont.caption.monospacedDigit()).foregroundStyle(StayPalette.inkSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct JournalRow: View {
    var entry: JournalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(symbol: entry.mood.symbol, tint: StayPalette.amber, fill: StayPalette.amber.opacity(0.14), size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.mood.title).font(StayFont.bodyEmphasis)
                    Spacer()
                    Text(entry.date.formatted(.dateTime.day().month())).font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                }
                if !entry.text.isEmpty {
                    Text(entry.text).font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary).lineLimit(3).multilineTextAlignment(.leading)
                }
            }
        }
        .stayCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

struct JournalEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var entry: JournalEntry

    var body: some View {
        NavigationStack {
            Form {
                Picker("How was today?", selection: $entry.mood) {
                    ForEach(JournalMood.allCases) { mood in
                        Label(mood.title, systemImage: mood.symbol).tag(mood)
                    }
                }
                .pickerStyle(.inline)
                DatePicker("Date", selection: $entry.date, in: ...Date.now, displayedComponents: .date)
                Section("Notes") {
                    TextField("Walks, sleep, visitors, anything new…", text: $entry.text, axis: .vertical)
                        .lineLimit(4...10)
                }
                if model.journal(for: entry.dogID).contains(where: { $0.id == entry.id }) {
                    Section {
                        Button("Delete entry", role: .destructive) {
                            model.deleteJournal(entry.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveJournal(entry)
                        dismiss()
                    }
                }
            }
        }
    }
}
