import Foundation

/// App-wide constants the owner sets before shipping.
enum AppConfig {
    /// Used by Settings → Contact support and the website.
    static let supportEmail = "support.stay11@gmail.com"

    /// The in-app "Contact support" row only appears once a real address is set.
    static var hasSupportEmail: Bool { !supportEmail.hasSuffix("@example.com") && supportEmail.contains("@") }

    /// Where the static website in /website is deployed (Netlify).
    static let websiteURL = URL(string: "https://stay-dog-coach.netlify.app/")!
    static let privacyURL = websiteURL.appendingPathComponent("privacy.html")
    static let termsURL = websiteURL.appendingPathComponent("terms.html")
    static let supportURL = websiteURL.appendingPathComponent("support.html")
    /// Apple's standard licensed application end user licence agreement.
    static let appleEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
