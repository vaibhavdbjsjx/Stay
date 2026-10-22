import Foundation

/// App-wide constants the owner sets before shipping.
enum AppConfig {
    /// Replace with your support address. Used by Settings → Contact support.
    static let supportEmail = "support@example.com"

    /// Where the static website in /website is deployed (e.g. GitHub Pages).
    static let websiteURL = URL(string: "https://stayapp.github.io")!
    static let privacyURL = websiteURL.appendingPathComponent("privacy.html")
    static let termsURL = websiteURL.appendingPathComponent("terms.html")
    static let supportURL = websiteURL.appendingPathComponent("support.html")
    /// Apple's standard licensed application end user licence agreement.
    static let appleEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
