import Foundation

/// User-facing words for missions and plan changes, shared by the app,
/// reminders and the widget so they always agree.
enum MissionCopy {
    static func title(for mission: DailyMission, dog: Dog) -> String {
        switch mission.kind {
        case .baseline: String(localized: "Baseline: see how \(dog.name) does")
        case .absence(let target): String(localized: "Leave for \(DurationText.short(target))")
        case .rest: String(localized: "Rest day")
        }
    }

    static func subtitle(for mission: DailyMission, dog: Dog) -> String {
        switch mission.kind {
        case .baseline:
            String(localized: "Head out as usual. Come back at the first sign of stress, or after 30 minutes.")
        case .absence:
            if let drill = mission.cueDrill, let cue = drill.cue {
                String(localized: "Then practise “\(cue.title.lowercased())” \(drill.reps) times while staying home.")
            } else {
                String(localized: "Keep the goodbye and the hello calm and quiet.")
            }
        case .rest(let reason):
            switch reason {
            case .scheduled: String(localized: "A planned day off from absences. Enjoy time together.")
            case .afterTrainingStreak: String(localized: "Five training days in a row. A day off locks in the progress.")
            case .afterDistress: String(localized: "After a tough couple of sessions, \(dog.name) needs a break from being alone.")
            }
        }
    }

    static func widgetLines(mission: DailyMission, dog: Dog) -> (title: String, detail: String) {
        if mission.completedToday {
            return (String(localized: "Done for today"), String(localized: "Review the session and rest up"))
        }
        switch mission.kind {
        case .baseline: return (String(localized: "Baseline test"), String(localized: "See how long \(dog.name) is calm"))
        case .absence(let target):
            let detail = mission.cueDrill?.cue.map { String(localized: "Then: \($0.title.lowercased())") } ?? String(localized: "Calm goodbye, calm hello")
            return (String(localized: "Leave for \(DurationText.short(target))"), detail)
        case .rest: return (String(localized: "Rest day"), String(localized: "No absences today"))
        }
    }

    static func reminder(mission: DailyMission, dog: Dog) -> (title: String, body: String) {
        switch mission.kind {
        case .baseline:
            (String(localized: "Ready for \(dog.name)'s baseline?"), String(localized: "A short first session shows where to start."))
        case .absence(let target):
            (String(localized: "Today's mission for \(dog.name)"), String(localized: "Leave for \(DurationText.short(target)). Small steps, calm wins."))
        case .rest:
            (String(localized: "Rest day for \(dog.name)"), String(localized: "No absences today. A walk or a sniff game is perfect."))
        }
    }

    static func changeHeadline(_ change: PlanChange, dogName: String) -> String {
        switch change {
        case .baselineSet: String(localized: "Baseline set")
        case .increased: String(localized: "\(dogName) stayed calm")
        case .held: String(localized: "Same step next time")
        case .rolledBack: String(localized: "We'll take a smaller step")
        }
    }

    static func changeDetail(_ change: PlanChange, dogName: String) -> String {
        switch change {
        case .baselineSet(let baseline, let first):
            String(localized: "\(dogName) coped for about \(DurationText.short(baseline)). The first mission starts a little below that, at \(DurationText.short(first)), so it's an easy win.")
        case .increased(let from, let to):
            String(localized: "Next mission goes from \(DurationText.short(from)) to \(DurationText.short(to)). Steady, small steps are how calm grows.")
        case .held(let at):
            String(localized: "You came back early with no signs of stress. We'll repeat \(DurationText.short(at)) next time.")
        case .rolledBack(let from, let to):
            String(localized: "Next mission drops from \(DurationText.short(from)) to \(DurationText.short(to)). Going back a step after stress is part of the method, not a setback.")
        }
    }
}
