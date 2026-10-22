import Charts
import PDFKit
import SwiftUI

/// A PDF summary of the plan and sessions to send to a trainer or vet.
@MainActor
enum TrainerReport {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter, points
    static let rowsPerPage = 24

    static func make(dog: Dog, model: AppModel) -> URL? {
        let sessions = model.sessions(for: dog.id).filter(\.isFinished)
        let reviewed = sessions.filter(\.isReviewed)
        let snapshot = model.stats.snapshot(sessions: reviewed, today: .now)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Stay report - \(dog.name).pdf")
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, [
            kCGPDFContextTitle as String: "Stay report – \(dog.name)",
            kCGPDFContextCreator as String: "Stay",
        ] as CFDictionary) else { return nil }

        let chunks = stride(from: 0, to: max(sessions.count, 1), by: rowsPerPage).map { Array(sessions.dropFirst($0).prefix(rowsPerPage)) }
        let totalPages = 1 + (sessions.isEmpty ? 0 : chunks.count)
        var pages: [AnyView] = [AnyView(SummaryPage(dog: dog, photo: model.photo(for: dog), snapshot: snapshot, reviewed: reviewed, journal: model.journal(for: dog.id), total: totalPages))]
        if !sessions.isEmpty {
            for (index, chunk) in chunks.enumerated() {
                pages.append(AnyView(SessionsPage(dogName: dog.name, sessions: chunk, page: index + 2, total: totalPages)))
            }
        }
        for page in pages {
            let renderer = ImageRenderer(content: page.frame(width: pageSize.width, height: pageSize.height).environment(\.colorScheme, .light))
            context.beginPDFPage(nil)
            renderer.render { _, draw in draw(context) }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }
}

private struct PageFrame<Content: View>: View {
    var page: Int
    var total: Int
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                StayMark(faceColor: .white).frame(width: 22, height: 22)
                    .background(Color(hex: 0x3F6B5E), in: RoundedRectangle(cornerRadius: 5))
                Text("Stay · Separation training report").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(Date.now.formatted(date: .long, time: .omitted)).font(.system(size: 10))
            }
            .foregroundStyle(Color(hex: 0x2A2420))
            .padding(.bottom, 12)
            Rectangle().fill(Color(hex: 0xE5DDD2)).frame(height: 1)
            content.padding(.top, 18)
            Spacer(minLength: 0)
            Rectangle().fill(Color(hex: 0xE5DDD2)).frame(height: 1)
            HStack {
                Text("Training support only. Not a medical diagnosis or treatment. Detected signs are reviewed by the owner.")
                Spacer()
                Text("Page \(page) of \(total)")
            }
            .font(.system(size: 8))
            .foregroundStyle(Color(hex: 0x6E645B))
            .padding(.top, 8)
        }
        .padding(40)
        .background(Color.white)
    }
}

private struct SummaryPage: View {
    var dog: Dog
    var photo: UIImage?
    var snapshot: ProgressSnapshot
    var reviewed: [AbsenceSession]
    var journal: [JournalEntry]
    var total: Int

    private let ink = Color(hex: 0x2A2420)
    private let muted = Color(hex: 0x6E645B)

    var body: some View {
        PageFrame(page: 1, total: total) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill().frame(width: 70, height: 70).clipShape(Circle())
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dog.name).font(.system(size: 26, weight: .semibold, design: .serif))
                        Text([dog.breed, dog.ageDescription].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(muted)
                        Text("Starting level: \(dog.severity.title) (intake score \(dog.assessment.score))").font(.system(size: 12)).foregroundStyle(muted)
                    }
                }
                .foregroundStyle(ink)
                HStack(spacing: 10) {
                    stat(String(localized: "Baseline"), dog.plan.baselineSeconds.map(DurationText.short) ?? "—")
                    stat(String(localized: "Current mission"), dog.plan.phase == .training ? DurationText.short(dog.plan.targetSeconds) : "—")
                    stat(String(localized: "Longest calm"), snapshot.longestCalm > 0 ? DurationText.short(snapshot.longestCalm) : "—")
                    stat(String(localized: "Calm sessions"), "\(snapshot.calmSessions) of \(reviewed.count)")
                }
                if reviewed.count >= 2 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Time alone per session (minutes)").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                        Chart(reviewed.sorted { $0.startedAt < $1.startedAt }) { session in
                            BarMark(x: .value("Date", session.startedAt, unit: .day), y: .value("Minutes", session.actualSeconds / 60))
                                .foregroundStyle(session.isCalm ? Color(hex: 0x4E8F69) : Color(hex: 0xE07F52))
                        }
                        .frame(height: 170)
                        Text("Green: calm. Orange: owner-confirmed signs of stress.").font(.system(size: 9)).foregroundStyle(muted)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Intake questionnaire").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                    ForEach(SeverityQuestionnaire.questions(dogName: dog.name), id: \.id) { question in
                        if let answer = dog.assessment.answers[question.id], question.options.indices.contains(answer) {
                            HStack(alignment: .top) {
                                Text(question.prompt).frame(maxWidth: .infinity, alignment: .leading)
                                Text(question.options[answer].title).fontWeight(.semibold).frame(width: 190, alignment: .leading)
                            }
                            .font(.system(size: 9.5))
                            .foregroundStyle(ink)
                        }
                    }
                }
                let signs = Dictionary(grouping: reviewed.flatMap(\.confirmedEvents), by: \.kind)
                if !signs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confirmed signs of stress").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                        Text(signs.sorted { $0.value.count > $1.value.count }.map { "\($0.key.title): \($0.value.count)" }.joined(separator: " · "))
                            .font(.system(size: 10)).foregroundStyle(ink)
                    }
                }
                if let note = journal.first(where: { !$0.text.isEmpty }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latest journal note (\(note.date.formatted(date: .abbreviated, time: .omitted)))").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                        Text(note.text).font(.system(size: 10)).foregroundStyle(ink).lineLimit(4)
                    }
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .semibold)).textCase(.uppercase).foregroundStyle(muted)
            Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(ink)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xF4ECE1), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SessionsPage: View {
    var dogName: String
    var sessions: [AbsenceSession]
    var page: Int
    var total: Int

    var body: some View {
        PageFrame(page: page, total: total) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(dogName) – sessions").font(.system(size: 16, weight: .semibold, design: .serif)).padding(.bottom, 10)
                row(["Date", "Type", "Planned", "Alone", "Outcome", "Confirmed signs"], header: true)
                ForEach(sessions) { session in
                    row([
                        session.startedAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()),
                        session.kind == .baseline ? String(localized: "Baseline") : String(localized: "Mission"),
                        session.kind == .baseline ? "—" : DurationText.short(session.plannedSeconds),
                        DurationText.short(session.actualSeconds),
                        outcome(session),
                        session.confirmedEvents.isEmpty ? "—" : session.confirmedEvents.map { "\($0.kind.title) @\(DurationText.clock($0.offset))" }.joined(separator: ", "),
                    ], header: false)
                }
            }
            .foregroundStyle(Color(hex: 0x2A2420))
        }
    }

    private func outcome(_ session: AbsenceSession) -> String {
        guard session.isReviewed else { return String(localized: "Not reviewed") }
        switch session.reviewedOutcome {
        case .calm: return String(localized: "Calm")
        case .distress(let first, _): return String(localized: "Stress from \(DurationText.clock(first))")
        case .incomplete: return String(localized: "Back early, calm")
        case nil: return "—"
        }
    }

    private func row(_ values: [String], header: Bool) -> some View {
        let widths: [CGFloat] = [96, 52, 56, 56, 92, 180]
        return HStack(alignment: .top, spacing: 0) {
            ForEach(values.indices, id: \.self) { index in
                Text(values[index])
                    .font(.system(size: header ? 8.5 : 9, weight: header ? .bold : .regular))
                    .frame(width: widths[index], alignment: .leading)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Rectangle().fill(Color(hex: 0xEFE8DE)).frame(height: 0.5) }
    }
}

struct TrainerReportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var dog: Dog
    @State private var url: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let url {
                    PDFPreview(url: url)
                } else {
                    ProgressView("Preparing report…")
                }
            }
            .stayBackground()
            .navigationTitle("Trainer report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if let url {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .task {
                if !model.purchases.isPro {
                    dismiss()
                    model.presentedPaywall = true
                    return
                }
                url = TrainerReport.make(dog: dog, model: model)
            }
        }
    }
}

private struct PDFPreview: UIViewRepresentable {
    var url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
