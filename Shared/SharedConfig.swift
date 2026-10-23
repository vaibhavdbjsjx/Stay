import Foundation

/// Identifiers shared by the app and the widget extension.
/// Values come from Info.plist, which takes them from Config/Shared.xcconfig.
enum SharedConfig {
    static var appGroupID: String {
        Bundle.main.object(forInfoDictionaryKey: "StayAppGroup") as? String ?? "group.com.vaibhavsg.stay"
    }

    /// The App Group container when available, otherwise Application Support
    /// (e.g. unsigned builds), so the app keeps working either way.
    static var sharedContainerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}
