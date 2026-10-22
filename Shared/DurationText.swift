import Foundation

/// Human-friendly duration strings used across the app, widget and Live Activity.
enum DurationText {
    /// "45 s", "3 min 20 s", "12 min", "1 h 5 min".
    static func short(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return minutes > 0
                ? String(localized: "\(hours) h \(minutes) min")
                : String(localized: "\(hours) h")
        }
        if minutes > 0 {
            return secs > 0
                ? String(localized: "\(minutes) min \(secs) s")
                : String(localized: "\(minutes) min")
        }
        return String(localized: "\(secs) s")
    }

    /// "3:20", "12:05", "1:05:00".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Fully spelled out for VoiceOver, e.g. "3 minutes, 20 seconds".
    static func spoken(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        return formatter.string(from: max(0, seconds.rounded())) ?? short(seconds)
    }
}
