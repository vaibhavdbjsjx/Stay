import Foundation
import UserNotifications

/// Local notifications: daily mission reminders and the "time to head back" nudge.
/// Remote distress alerts come from CloudKit subscriptions instead.
@MainActor
enum NotificationScheduler {
    private static let reminderPrefix = "stay.reminder."
    private static let returnID = "stay.return"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    struct ReminderDay: Sendable {
        var date: Date
        var title: String
        var body: String
    }

    /// Replaces the next week of reminders with day-specific text.
    static func scheduleReminders(_ days: [ReminderDay], hour: Int, minute: Int) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(reminderPrefix) })
        let calendar = Calendar.current
        for day in days {
            var components = calendar.dateComponents([.year, .month, .day], from: day.date)
            components.hour = hour
            components.minute = minute
            guard let fireDate = calendar.date(from: components), fireDate > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = day.title
            content.body = day.body
            content.sound = .default
            content.threadIdentifier = "reminders"
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let id = reminderPrefix + ISO8601DateFormatter().string(from: fireDate)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    static func cancelReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(reminderPrefix) })
    }

    static func scheduleReturn(after seconds: TimeInterval, dogName: String) async {
        guard seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time to head back")
        content.body = String(localized: "\(dogName)'s mission is complete. Come back calmly and keep the greeting low-key.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: returnID, content: content, trigger: trigger))
    }

    static func cancelReturn() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [returnID])
    }

    /// Shown when an alert arrives over Wi-Fi while Stay is in the foreground.
    static func notifyDistress(dogName: String, kind: DistressKind) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "\(dogName) may be stressed")
        content.body = String(localized: "\(kind.title) detected. Open Stay to check the live view.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
