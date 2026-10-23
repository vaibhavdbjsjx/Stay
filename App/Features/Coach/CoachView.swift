import SwiftUI

struct CoachView: View {
    @Environment(AppModel.self) private var model
    @State private var insight: WeeklyInsight?
    @State private var tip: CoachTip?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let dog = model.selectedDog {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if let tip { TodayTipCard(tip: tip).reveal(0) }
                        weeklyCard(dog).reveal(1)
                        if dog.assessment.recommendsVet {
                            VetCard(dogName: dog.name)
                        }
                        SectionHeader(title: String(localized: "The method"))
                        ForEach(CoachLibrary.articles) { article in
                            NavigationLink {
                                ArticleView(article: article)
                            } label: {
                                ArticleRow(article: article)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(20)
                    .task(id: dog.plan) { await load(dog) }
                }
            }
            .stayBackground()
            .navigationTitle("Coach")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.coach.isAIAvailable ? "apple.intelligence" : "sparkles")
                .foregroundStyle(StayPalette.apricot)
            Text(model.coach.isAIAvailable
                 ? String(localized: "Personalised on this iPhone with Apple Intelligence. Nothing leaves your device.")
                 : String(localized: "Personalised from your dog's sessions, on this device."))
                .font(StayFont.caption)
                .foregroundStyle(StayPalette.inkSecondary)
        }
    }

    @ViewBuilder
    private func weeklyCard(_ dog: Dog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week").eyebrowStyle(StayPalette.apricot)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            if let insight {
                Text(insight.headline).font(StayFont.title).foregroundStyle(StayPalette.ink)
                ZStack {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(insight.paragraphs, id: \.self) { paragraph in
                            Text(paragraph).font(StayFont.body).foregroundStyle(StayPalette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .blur(radius: model.purchases.isPro ? 0 : 6)
                    .accessibilityHidden(!model.purchases.isPro)
                    if !model.purchases.isPro {
                        Button {
                            model.presentedPaywall = true
                        } label: {
                            Label("Unlock weekly insights", systemImage: "lock.fill")
                        }
                        .buttonStyle(.stayPrimary(StayPalette.apricot))
                        .padding(.horizontal, 20)
                    }
                }
            } else {
                Text("Gathering this week's sessions…").font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
            }
        }
        .stayCard()
    }

    private func load(_ dog: Dog) async {
        let context = model.coachContext(for: dog)
        tip = model.coach.quickTip(context)
        loading = true
        tip = await model.coach.dailyTip(context)
        insight = await model.coach.weeklyInsight(context)
        loading = false
    }
}

private struct TodayTipCard: View {
    var tip: CoachTip

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's tip").eyebrowStyle(StayPalette.cream.opacity(0.8))
                Spacer()
                Image(systemName: tip.symbol).foregroundStyle(StayPalette.cream)
            }
            Text(tip.title).font(StayFont.title).foregroundStyle(StayPalette.cream)
            Text(tip.body).font(StayFont.body).foregroundStyle(StayPalette.cream.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .background(StayPalette.heroGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct VetCard: View {
    var dogName: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(symbol: "cross.case.fill", tint: StayPalette.alert, fill: StayPalette.alert.opacity(0.12))
            VStack(alignment: .leading, spacing: 4) {
                Text("Keep your vet in the loop").font(StayFont.headline)
                Text("\(dogName)'s intake answers suggest significant distress. Training works best alongside your vet, who can rule out pain and discuss other support. Share the trainer report from Progress.")
                    .font(StayFont.callout).foregroundStyle(StayPalette.inkSecondary)
            }
        }
        .stayCard()
    }
}

struct CoachArticle: Identifiable, Hashable {
    var id: String
    var symbol: String
    var title: String
    var summary: String
    var sections: [String]
}

enum CoachLibrary {
    static let articles: [CoachArticle] = [
        CoachArticle(
            id: "threshold", symbol: "gauge.with.dots.needle.33percent",
            title: String(localized: "Stay under threshold"),
            summary: String(localized: "Why short, calm absences beat long, stressful ones."),
            sections: [
                String(localized: "A dog learns to be calm alone by being alone and calm, again and again. Every time a session goes past the point where your dog starts to worry, that worry is practised too."),
                String(localized: "That's why Stay starts below your baseline, grows each mission by only 10–20%, and steps back after confirmed stress. The aim is lots of easy wins."),
                String(localized: "If you're unsure whether something was stress, it's fine to mark it as stress. A slightly slower plan is better than a setback."),
            ]
        ),
        CoachArticle(
            id: "suspend", symbol: "calendar.badge.exclamationmark",
            title: String(localized: "Avoid longer absences"),
            summary: String(localized: "Gaps in cover undo progress faster than anything."),
            sections: [
                String(localized: "While you train, try not to leave your dog alone for longer than the current mission. One long absence can erase weeks of calm practice."),
                String(localized: "Friends, family, a dog sitter, daycare or taking your dog with you all count. Plan your week around it where you can."),
            ]
        ),
        CoachArticle(
            id: "cues", symbol: "key.fill",
            title: String(localized: "Make departure cues boring"),
            summary: String(localized: "Keys, shoes and the door shouldn't predict anything."),
            sections: [
                String(localized: "Many dogs start to worry long before the door closes — when the shoes go on or the keys jingle. Practising those cues without leaving takes away their meaning."),
                String(localized: "Do each cue a few times a day, then carry on as normal. When your dog barely looks up, Stay moves to the next one."),
            ]
        ),
        CoachArticle(
            id: "signs", symbol: "eye.fill",
            title: String(localized: "Reading stress"),
            summary: String(localized: "Quiet signs matter as much as barking."),
            sections: [
                String(localized: "Barking, howling and whining are easy to spot. Pacing, panting, drooling, lip licking, yawning, scratching at the door and not touching food are signs too."),
                String(localized: "Stay listens and watches for vocal signs and pacing. You know your dog best: confirm or dismiss each moment on review, and add anything the camera missed."),
            ]
        ),
        CoachArticle(
            id: "rest", symbol: "leaf.fill",
            title: String(localized: "Rest days"),
            summary: String(localized: "Progress needs time to settle."),
            sections: [
                String(localized: "Stay adds a rest day after five training days in a row and after two tough sessions. You can also choose regular rest days in your dog's settings."),
                String(localized: "On rest days, skip absences. Walks, sniff games and quiet time together are perfect."),
            ]
        ),
        CoachArticle(
            id: "vet", symbol: "cross.case.fill",
            title: String(localized: "When to see a vet"),
            summary: String(localized: "Training support works best with professional care."),
            sections: [
                String(localized: "If your dog hurts themselves trying to escape, stops eating, or panics even with you nearby, please talk to your vet. Pain and other health issues can make anxiety worse."),
                String(localized: "A certified separation anxiety trainer can also help. The trainer report in Progress gives them your full history in one PDF."),
                String(localized: "Stay is training support. It doesn't diagnose or treat any condition."),
            ]
        ),
    ]
}

private struct ArticleRow: View {
    var article: CoachArticle

    var body: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: article.symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(article.title).font(StayFont.bodyEmphasis).foregroundStyle(StayPalette.ink)
                Text(article.summary).font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(StayPalette.inkTertiary)
        }
        .stayCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct ArticleView: View {
    var article: CoachArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                IconBadge(symbol: article.symbol, size: 60)
                Text(article.title).font(StayFont.display)
                ForEach(article.sections, id: \.self) { section in
                    Text(section).font(StayFont.body).foregroundStyle(StayPalette.ink).lineSpacing(3)
                }
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .stayBackground()
        .navigationBarTitleDisplayMode(.inline)
    }
}
