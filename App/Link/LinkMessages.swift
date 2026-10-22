import Foundation

/// What the owner's phone tells the camera when a mission starts.
struct LinkSessionStart: Codable, Hashable, Sendable {
    var sessionID: UUID
    var dogName: String
    var targetSeconds: TimeInterval
    var sensitivity: DetectionSensitivity
    var startedAt: Date
}

/// A distress sign as sent from the camera to the owner.
struct LinkEvent: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var sessionID: UUID
    var offset: TimeInterval
    var kind: DistressKind
    var confidence: Double
    var duration: TimeInterval
    /// About 30 s of sound levels leading up to the event.
    var levels: [Float]
    var snapshot: Data?
}

/// A heartbeat from the camera while it is armed or running.
struct LinkStatus: Codable, Hashable, Sendable {
    enum State: String, Codable, Sendable {
        case armed
        case running
        case stopped
    }

    var state: State
    var sessionID: UUID?
    var elapsed: TimeInterval
    var level: Float
    var batteryLevel: Float
    var isCharging: Bool
    var thermalWarning: Bool
    var deviceName: String
    var sentAt = Date.now
}

/// Messages on the nearby (MultipeerConnectivity) channel.
enum NearbyMessage: Codable, Sendable {
    case hello(linkID: String, role: DeviceRole, name: String)
    case start(LinkSessionStart)
    case stop(sessionID: UUID)
    case status(LinkStatus)
    case event(LinkEvent)
    case levels(sessionID: UUID, levels: [Float])
}

/// A short code that ties two devices together. Shown in the pairing QR.
struct PairingPayload: Codable, Hashable, Sendable {
    var version = 1
    var linkID: String
    var shareURL: URL?
    var ownerName: String

    static let scheme = "stay"

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "pair"
        var items = [URLQueryItem(name: "link", value: linkID), URLQueryItem(name: "name", value: ownerName)]
        if let shareURL { items.append(URLQueryItem(name: "share", value: shareURL.absoluteString)) }
        components.queryItems = items
        return components.url!
    }

    init(linkID: String, shareURL: URL?, ownerName: String) {
        self.linkID = linkID
        self.shareURL = shareURL
        self.ownerName = ownerName
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let link = items.first(where: { $0.name == "link" })?.value, Self.isValidLinkID(link) else { return nil }
        linkID = link
        ownerName = items.first(where: { $0.name == "name" })?.value ?? ""
        shareURL = items.first(where: { $0.name == "share" })?.value.flatMap(URL.init(string:))
    }

    /// Typed pairing codes, e.g. "K7Q2-9MXR".
    init?(code: String) {
        let cleaned = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard Self.isValidLinkID(cleaned) else { return nil }
        linkID = cleaned
        shareURL = nil
        ownerName = ""
    }

    static let alphabet = Array("23456789ABCDEFGHJKMNPQRSTUVWXYZ")

    static func makeLinkID() -> String {
        String((0..<8).map { _ in alphabet.randomElement()! })
    }

    static func isValidLinkID(_ id: String) -> Bool {
        id.count == 8 && id.allSatisfy { alphabet.contains($0) }
    }

    static func displayCode(_ linkID: String) -> String {
        guard linkID.count == 8 else { return linkID }
        return linkID.prefix(4) + "-" + linkID.suffix(4)
    }
}
