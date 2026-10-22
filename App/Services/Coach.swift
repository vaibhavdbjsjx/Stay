import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct CoachTip: Equatable, Sendable {
    var title: String
    var body: String
    var symbol: String
    var isAIGenerated = false
}

struct WeeklyInsight: Equatable, Sendable {
    var headline: String
    var paragraphs: [String]
    var isAIGenerated = false
}

/// The facts the coach reasons about. Built from local data only.
struct CoachContext: Sendable {
    var dogName: String
    var breed: String
    var severity: SeverityLevel
    var recommendsVet: Bool
    var phase: PlanState.Phase
    var targetSeconds: TimeInterval
    var longestCalmSeconds: TimeInterval
    var consecutiveCalm: Int
    var consecutiveDistress: Int
    var dayStreak: Int
    var mission: DailyMission
    var lastWeek: [AbsenceSession]
    var previousWeek: [AbsenceSession]
    var cue: CueKind?
    var recentMoods: [JournalMood]
    var dayOfYear: Int

    var lastWeekCalm: Int { lastWeek.filter(\.isCalm).count }
    var lastWeekDistress: Int { lastWeek.filter { if case .distress? = $0.reviewedOutcome { true } else { false } }.count }
    var lastWeekLongest: TimeInterval { lastWeek.filter(\.isCalm).map(\.actualSeconds).max() ?? 0 }
    var previousWeekLongest: TimeInterval { previousWeek.filter(\.isCalm).map(\.actualSeconds).max() ?? 0 }
    var commonSign: DistressKind? {
        let kinds = lastWeek.flatMap(\.confirmedEvents).map(\.kind)
        return Dictionary(grouping: kinds, by: { $0 }).max { $0.value.count < $1.value.count }?.key
    }
}

/// Deterministic coaching used everywhere Apple Intelligence isn't available,
/// and as the safety net if the on-device model fails.
struct RulesCoach: Sendable {
    func dailyTip(_ c: CoachContext) -> CoachTip {
        let name = c.dogName
        switch c.mission.kind {
        case .baseline:
            return CoachTip(
                title: String(localized: "Today we just watch"),
                body: String(localized: "The baseline isn't a test \(name) can fail. Leave as you normally would and come back at the first sign of stress. That moment is where training starts."),
                symbol: "eye"
            )
        case .rest(let reason):
            switch reason {
            case .afterDistress:
                return CoachTip(
                    title: String(localized: "A calm day off"),
                    body: String(localized: "Two tough sessions in a row means \(name) needs a break from being alone. Try not to leave at all today — a sniffy walk or a puzzle feeder helps reset."),
                    symbol: "leaf"
                )
            case .afterTrainingStreak, .scheduled:
                return CoachTip(
                    title: String(localized: "Rest days are training too"),
                    body: String(localized: "Skipping absences today keeps stress low and makes tomorrow's mission easier. Play, train a fun trick or go somewhere new together."),
                    symbol: "sun.max"
                )
            }
        case .absence(let target):
            if c.consecutiveDistress > 0 {
                return CoachTip(
                    title: String(localized: "Smaller is faster"),
                    body: String(localized: "We've stepped back to \(DurationText.short(target)). Short wins rebuild \(name)'s confidence more quickly than pushing through. Keep departures boring and quiet."),
                    symbol: "arrow.uturn.backward"
                )
            }
            if c.consecutiveCalm >= 3 {
                return CoachTip(
                    title: String(localized: "\(c.consecutiveCalm) calm sessions in a row"),
                    body: String(localized: "\(name) is building real tolerance. Vary your routine a little today — leave from a different door or at a different time — so the calm holds in any situation."),
                    symbol: "sparkles"
                )
            }
            if let cue = c.cue {
                return CoachTip(
                    title: String(localized: "Make cues boring"),
                    body: String(localized: "Practise “\(cue.title.lowercased())” a few times while you're staying home. When the cue stops predicting a departure, it stops causing worry."),
                    symbol: cue.symbol
                )
            }
            let tips = [
                CoachTip(title: String(localized: "Keep comings and goings low-key"),
                         body: String(localized: "Skip the big goodbye and the excited hello. A calm return teaches \(name) that you leaving and coming back is no big deal."),
                         symbol: "door.left.hand.closed"),
                CoachTip(title: String(localized: "Avoid other absences"),
                         body: String(localized: "Progress is fastest when \(name) is never left alone for longer than the current mission. A sitter, daycare or a friend can cover the gaps."),
                         symbol: "person.2"),
                CoachTip(title: String(localized: "Exercise first, not right before"),
                         body: String(localized: "A walk an hour before the mission helps \(name) settle. Straight after a walk can leave them too wired to relax."),
                         symbol: "figure.walk"),
                CoachTip(title: String(localized: "Watch the body, not just the noise"),
                         body: String(localized: "Pacing, panting, lip licking and staring at the door are early signs. Mark them on review so the plan stays honest."),
                         symbol: "eye"),
            ]
            return tips[c.dayOfYear % tips.count]
        }
    }

    func weeklyInsight(_ c: CoachContext) -> WeeklyInsight {
        let name = c.dogName
        var paragraphs: [String] = []
        let total = c.lastWeek.count
        guard total > 0 else {
            return WeeklyInsight(
                headline: String(localized: "A fresh week for \(name)"),
                paragraphs: [
                    String(localized: "There were no missions in the last seven days. Short, frequent sessions work best — even one 30-second mission keeps momentum."),
                    String(localized: "Start with today's mission and Stay will adapt from there."),
                ]
            )
        }
        let headline: String
        if c.lastWeekLongest > c.previousWeekLongest, c.previousWeekLongest > 0 {
            headline = String(localized: "\(name)'s best week yet")
            paragraphs.append(String(localized: "Longest calm absence went from \(DurationText.short(c.previousWeekLongest)) to \(DurationText.short(c.lastWeekLongest)). That's real progress."))
        } else if c.lastWeekDistress > c.lastWeekCalm {
            headline = String(localized: "A harder week — and that's normal")
            paragraphs.append(String(localized: "\(c.lastWeekDistress) of \(total) sessions showed stress. Stay has eased the plan back so \(name) can find their feet again."))
        } else {
            headline = String(localized: "Steady progress for \(name)")
            paragraphs.append(String(localized: "\(c.lastWeekCalm) of \(total) sessions were calm this week, with a longest calm absence of \(DurationText.short(c.lastWeekLongest))."))
        }
        if let sign = c.commonSign {
            paragraphs.append(String(localized: "The most common sign was \(sign.title.lowercased()). Notice what happens just before it — a sound outside, a time of day — and keep the next missions a little shorter around that trigger."))
        }
        if c.dayStreak >= 3 {
            paragraphs.append(String(localized: "You've trained \(c.dayStreak) days in a row. Remember to keep a rest day or two each week."))
        }
        if c.recommendsVet {
            paragraphs.append(String(localized: "Because \(name)'s anxiety looked significant at the start, it's worth checking in with your vet about how training is going."))
        }
        return WeeklyInsight(headline: headline, paragraphs: paragraphs)
    }
}

/// Personalised coaching. Uses Apple's on-device Foundation Models on iOS 26+
/// when Apple Intelligence is available, otherwise the rules coach. Nothing
/// leaves the device and no third-party service is used.
@MainActor
@Observable
final class CoachService {
    private let rules = RulesCoach()
    private var tipCache: [String: CoachTip] = [:]
    private var insightCache: [String: WeeklyInsight] = [:]

    var isAIAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    func quickTip(_ context: CoachContext) -> CoachTip {
        tipCache[cacheKey(context)] ?? rules.dailyTip(context)
    }

    func dailyTip(_ context: CoachContext) async -> CoachTip {
        let key = cacheKey(context)
        if let cached = tipCache[key] { return cached }
        let fallback = rules.dailyTip(context)
        var tip = fallback
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let prompt = """
            Write today's coaching tip for the owner. Facts:
            \(Self.facts(context))
            Today's suggested focus (rewrite it in your own words and personalise it): \(fallback.title) — \(fallback.body)
            Reply with a short title (max 6 words) on the first line, then 2 sentences of advice.
            """
            if let text = await Self.generate(prompt) {
                let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
                if lines.count >= 2 {
                    tip = CoachTip(
                        title: lines[0].trimmingCharacters(in: CharacterSet(charactersIn: "*#\" ")),
                        body: lines.dropFirst().joined(separator: " "),
                        symbol: fallback.symbol,
                        isAIGenerated: true
                    )
                }
            }
        }
        #endif
        tipCache[key] = tip
        return tip
    }

    func weeklyInsight(_ context: CoachContext) async -> WeeklyInsight {
        let key = cacheKey(context)
        if let cached = insightCache[key] { return cached }
        let fallback = rules.weeklyInsight(context)
        var insight = fallback
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable, !context.lastWeek.isEmpty {
            let prompt = """
            Write a weekly progress insight for the owner. Facts:
            \(Self.facts(context))
            Key observations: \(fallback.paragraphs.joined(separator: " "))
            Reply with a warm headline (max 7 words) on the first line, then 2 or 3 short paragraphs separated by blank lines.
            """
            if let text = await Self.generate(prompt) {
                let blocks = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if blocks.count >= 2 {
                    insight = WeeklyInsight(
                        headline: blocks[0].trimmingCharacters(in: CharacterSet(charactersIn: "*#\" ")),
                        paragraphs: Array(blocks.dropFirst().prefix(4)),
                        isAIGenerated: true
                    )
                }
            }
        }
        #endif
        insightCache[key] = insight
        return insight
    }

    func invalidate() {
        tipCache.removeAll()
        insightCache.removeAll()
    }

    private func cacheKey(_ c: CoachContext) -> String {
        "\(c.dogName)-\(c.dayOfYear)-\(c.targetSeconds)-\(c.consecutiveCalm)-\(c.consecutiveDistress)-\(c.lastWeek.count)"
    }

    private static func facts(_ c: CoachContext) -> String {
        var lines = [
            "Dog: \(c.dogName)\(c.breed.isEmpty ? "" : ", \(c.breed)")",
            "Separation anxiety level from intake questionnaire: \(c.severity.rawValue)",
            "Current mission length: \(DurationText.short(c.targetSeconds))",
            "Longest calm absence so far: \(DurationText.short(c.longestCalmSeconds))",
            "Calm sessions in a row: \(c.consecutiveCalm)",
            "Sessions with stress in a row: \(c.consecutiveDistress)",
            "Training days in a row: \(c.dayStreak)",
            "Last 7 days: \(c.lastWeek.count) sessions, \(c.lastWeekCalm) calm, \(c.lastWeekDistress) with stress",
        ]
        if let sign = c.commonSign { lines.append("Most common stress sign: \(sign.rawValue)") }
        if let cue = c.cue { lines.append("Departure cue being practised: \(cue.title)") }
        return lines.joined(separator: "\n")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func generate(_ prompt: String) async -> String? {
        let session = LanguageModelSession(instructions: """
        You are a kind, practical coach in a dog separation anxiety training app. \
        You support graduated-absence training as used by certified separation anxiety trainers. \
        Keep advice short, specific and encouraging. Never promise a cure and never diagnose. \
        Never suggest medication or doses; for severe cases, suggest talking to a vet. \
        Never suggest punishment, crates for confinement, or leaving the dog longer than the planned mission.
        """)
        do {
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }
    #endif
}
