import SwiftUI

/// Numbers that drive the share cards and the progress video.
struct ShareStory {
    var dogName: String
    var photo: UIImage?
    var firstSeconds: TimeInterval
    var bestSeconds: TimeInterval
    var dayCount: Int
    var calmSessions: Int
    var streak: Int
    var recent: [TimeInterval]
    var firstImage: UIImage?
    var latestImage: UIImage?
    var highlight: Milestone?

    @MainActor
    static func make(dog: Dog, model: AppModel, highlight: Milestone?) -> ShareStory {
        let reviewed = model.sessions(for: dog.id).filter(\.isReviewed).sorted { $0.startedAt < $1.startedAt }
        let first = reviewed.first
        let firstSeconds: TimeInterval = dog.plan.baselineSeconds
            ?? first.map { $0.firstConfirmedDistress ?? $0.actualSeconds } ?? 0
        let best = model.stats.longestCalm(sessions: reviewed)
        let days = first.map { (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: $0.startedAt), to: Calendar.current.startOfDay(for: .now)).day ?? 0) + 1 } ?? 1
        let firstImage = first?.snapshotFilenames.first.flatMap(model.image(named:))
        let latestCalm = reviewed.last(where: \.isCalm)
        let latestImage = latestCalm?.snapshotFilenames.last.flatMap(model.image(named:))
        return ShareStory(
            dogName: dog.name,
            photo: model.photo(for: dog),
            firstSeconds: firstSeconds,
            bestSeconds: max(best, firstSeconds),
            dayCount: max(1, days),
            calmSessions: reviewed.filter(\.isCalm).count,
            streak: model.stats.dayStreak(sessions: reviewed, today: .now),
            recent: reviewed.suffix(10).map { $0.isCalm ? $0.actualSeconds : ($0.firstConfirmedDistress ?? $0.actualSeconds) },
            firstImage: firstImage,
            latestImage: latestImage,
            highlight: highlight
        )
    }

    var improvementText: String? {
        guard firstSeconds > 0, bestSeconds > firstSeconds else { return nil }
        let factor = bestSeconds / firstSeconds
        if factor >= 2 { return String(localized: "\(Int(factor.rounded(.down)))× longer") }
        return String(localized: "+\(Int(((factor - 1) * 100).rounded()))%")
    }
}

enum ShareCardStyle: String, CaseIterable, Identifiable {
    case beforeAfter
    case milestone
    case trend

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beforeAfter: String(localized: "Day 1 vs today")
        case .milestone: String(localized: "Milestone")
        case .trend: String(localized: "Progress")
        }
    }
}

/// A 4:5 card designed at 360×450 points and rendered at 3× (1080×1350).
struct ShareCardView: View {
    var story: ShareStory
    var style: ShareCardStyle

    static let size = CGSize(width: 360, height: 450)

    var body: some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: 0) {
                switch style {
                case .beforeAfter: beforeAfter
                case .milestone: milestone
                case .trend: trend
                }
                Spacer(minLength: 0)
                brand
            }
            .padding(26)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .light)
    }

    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x4F8070), Color(hex: 0x24443B)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xF6B48A, opacity: 0.35), .clear], center: .center, startRadius: 0, endRadius: 200))
                .frame(width: 420, height: 420)
                .offset(x: 120, y: -150)
            StayMark(houseColor: .white.opacity(0.06), dogColor: .white.opacity(0.05), faceColor: .clear)
                .frame(width: 300, height: 300)
                .offset(x: 110, y: 120)
        }
    }

    private var brand: some View {
        HStack(spacing: 8) {
            StayMark(faceColor: Color(hex: 0x24443B)).frame(width: 26, height: 26)
            Text("Stay").font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(Color(hex: 0xFBF3E6))
            Text("· Dog Separation Coach").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Color(hex: 0xFBF3E6).opacity(0.7))
            Spacer()
        }
    }

    private var avatar: some View {
        Group {
            if let photo = story.photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                ZStack {
                    StayPalette.sunriseGradient
                    Image(systemName: "pawprint.fill").font(.system(size: 26)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color(hex: 0xFBF3E6), lineWidth: 3))
    }

    private var cream: Color { Color(hex: 0xFBF3E6) }
    private var apricot: Color { Color(hex: 0xF2A477) }

    private var beforeAfter: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(story.dogName).font(.system(size: 26, weight: .semibold, design: .serif)).foregroundStyle(cream)
                    Text("Learning to love alone time").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(cream.opacity(0.75))
                }
            }
            HStack(spacing: 12) {
                comparison(label: String(localized: "Day 1"), seconds: story.firstSeconds, image: story.firstImage, highlight: false)
                comparison(label: String(localized: "Day \(story.dayCount)"), seconds: story.bestSeconds, image: story.latestImage, highlight: true)
            }
            if let improvement = story.improvementText {
                Text(improvement)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x24443B))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(apricot, in: Capsule())
            }
        }
    }

    private func comparison(label: String, seconds: TimeInterval, image: UIImage?, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.white.opacity(highlight ? 0.16 : 0.08)
                    Image(systemName: highlight ? "house.fill" : "door.left.hand.open")
                        .font(.system(size: 28)).foregroundStyle(cream.opacity(0.7))
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(label).font(.system(size: 12, weight: .bold, design: .rounded)).textCase(.uppercase).foregroundStyle(cream.opacity(0.7))
            Text(seconds > 0 ? DurationText.short(seconds) : "—")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(highlight ? apricot : cream)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("home alone, calm").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(cream.opacity(0.6))
        }
    }

    private var milestone: some View {
        VStack(alignment: .leading, spacing: 18) {
            avatar
            Text("Milestone unlocked").font(.system(size: 13, weight: .bold, design: .rounded)).textCase(.uppercase).tracking(1.2).foregroundStyle(apricot)
            Text(story.highlight?.title ?? String(localized: "\(DurationText.short(story.bestSeconds)) home alone, calmly"))
                .font(.system(size: 36, weight: .semibold, design: .serif))
                .foregroundStyle(cream)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(story.dogName) has done \(story.calmSessions) calm missions so far. Small steps, every day.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(cream.opacity(0.8))
            HStack(spacing: 10) {
                badge(symbol: "flame.fill", text: String(localized: "\(story.streak)-day streak"))
                badge(symbol: "house.fill", text: DurationText.short(story.bestSeconds))
            }
        }
    }

    private func badge(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(cream)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.white.opacity(0.14), in: Capsule())
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(story.dogName)'s progress").font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(cream)
                    Text("Last \(story.recent.count) sessions").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(cream.opacity(0.7))
                }
            }
            let maxValue = max(story.recent.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(Array(story.recent.enumerated()), id: \.offset) { index, value in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(index == story.recent.count - 1 ? apricot : cream.opacity(0.55))
                        .frame(height: max(10, CGFloat(value / maxValue) * 170))
                }
            }
            .frame(height: 180, alignment: .bottom)
            HStack(alignment: .firstTextBaseline) {
                Text(DurationText.short(story.bestSeconds)).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(cream)
                Text("longest calm absence").font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(cream.opacity(0.7))
            }
        }
    }
}

@MainActor
enum ShareCardRenderer {
    static func render(_ story: ShareStory, style: ShareCardStyle) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(story: story, style: style))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
