import Foundation
import MultipeerConnectivity
import UIKit

/// Wraps a non-Sendable value so it can cross to the main actor. Only used
/// for framework objects that are documented as thread-safe (MCPeerID).
struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
}

/// Direct device-to-device link on the same Wi-Fi using MultipeerConnectivity.
/// Gives a real live view and instant alerts without any server.
@MainActor
@Observable
final class NearbyLink: NSObject {
    static let serviceType = "stay-link"

    enum ConnectionState: Equatable {
        case idle
        case searching
        case connected(peerName: String)
    }

    private(set) var state: ConnectionState = .idle
    private(set) var latestFrame: UIImage?
    private(set) var latestFrameAt: Date?

    var onMessage: ((NearbyMessage) -> Void)?

    private var role: DeviceRole = .owner
    private var linkID: String?
    private let peerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    override init() {
        peerID = MCPeerID(displayName: String(UIDevice.current.name.prefix(60)))
        super.init()
    }

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    /// Starts advertising (camera) or browsing (owner) for the partner with the same link ID.
    func start(linkID: String, role: DeviceRole) {
        if self.linkID == linkID, self.role == role, session != nil { return }
        stop()
        self.linkID = linkID
        self.role = role
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        switch role {
        case .camera:
            let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: ["link": linkID], serviceType: Self.serviceType)
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
        case .owner:
            let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
            browser.delegate = self
            browser.startBrowsingForPeers()
            self.browser = browser
        }
        state = .searching
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        state = .idle
        latestFrame = nil
    }

    func send(_ message: NearbyMessage) {
        guard let session, !session.connectedPeers.isEmpty,
              let json = try? JSONEncoder().encode(message) else { return }
        var data = Data([0])
        data.append(json)
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    func sendFrame(_ jpeg: Data) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        var data = Data([1])
        data.append(jpeg)
        try? session.send(data, toPeers: session.connectedPeers, with: .unreliable)
    }

    // MARK: Main-actor handlers

    fileprivate func handle(data: Data) {
        guard let kind = data.first else { return }
        let body = data.dropFirst()
        if kind == 1 {
            if let image = UIImage(data: Data(body)) {
                latestFrame = image
                latestFrameAt = .now
            }
        } else if let message = try? JSONDecoder().decode(NearbyMessage.self, from: Data(body)) {
            // A device that doesn't know our link code is not our partner.
            if case .hello(let id, _, _) = message, id != linkID {
                session?.disconnect()
                return
            }
            onMessage?(message)
        }
    }

    fileprivate func peerChanged(name: String, state newState: MCSessionState) {
        switch newState {
        case .connected:
            state = .connected(peerName: name)
            if let linkID {
                send(.hello(linkID: linkID, role: role, name: UIDevice.current.name))
            }
        case .notConnected:
            if session?.connectedPeers.isEmpty ?? true {
                state = session == nil ? .idle : .searching
                latestFrame = nil
            }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    fileprivate func invite(_ peer: UncheckedBox<MCPeerID>, info: [String: String]?) {
        guard let browser, let session, info?["link"] == linkID else { return }
        browser.invitePeer(peer.value, to: session, withContext: nil, timeout: 20)
    }

    fileprivate func answerInvitation(context: Data?, handler: UncheckedBox<(Bool, MCSession?) -> Void>) {
        handler.value(session != nil, session)
    }
}

extension NearbyLink: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let name = peerID.displayName
        Task { @MainActor in self.peerChanged(name: name, state: state) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in self.handle(data: data) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension NearbyLink: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let box = UncheckedBox(value: peerID)
        Task { @MainActor in self.invite(box, info: info) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

extension NearbyLink: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let box = UncheckedBox(value: invitationHandler)
        Task { @MainActor in self.answerInvitation(context: context, handler: box) }
    }
}
