import AuthenticationServices
import Foundation
import GoogleSignIn
import Security
import UIKit

/// The signed-in person. Stay keeps no server account: this identity lives in
/// the Keychain on this device and personalises reports, pairing and sharing.
struct UserAccount: Codable, Equatable, Sendable {
    enum Provider: String, Codable, Sendable {
        case apple
        case google

        var title: String {
            switch self {
            case .apple: String(localized: "Apple")
            case .google: String(localized: "Google")
            }
        }
    }

    var provider: Provider
    var userID: String
    var name: String
    var email: String?
    var signedInAt = Date.now

    var displayName: String {
        if !name.isEmpty { return name }
        if let email, let local = email.split(separator: "@").first { return String(local) }
        return String(localized: "Signed in")
    }
}

/// Sign in with Apple and Google. Both are optional: every feature works
/// without an account.
@MainActor
@Observable
final class AccountService {
    enum AccountError: LocalizedError {
        case offline
        case failed
        case notConfigured

        var errorDescription: String? {
            switch self {
            case .offline: String(localized: "You seem to be offline. Connect to the internet and try again.")
            case .failed: String(localized: "Sign-in didn't complete. Please try again.")
            case .notConfigured: String(localized: "Google sign-in isn't available in this version.")
            }
        }
    }

    private(set) var account: UserAccount?
    private(set) var isWorking = false
    var lastError: String?

    private var revokeObserver: NSObjectProtocol?

    init() {
        account = Keychain.load()
        revokeObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleAppleRevocation() }
        }
    }

    var isSignedIn: Bool { account != nil }

    /// Google needs an OAuth client ID in Config/Shared.xcconfig. Without one the button is hidden.
    static var isGoogleConfigured: Bool {
        let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String ?? ""
        return id.hasSuffix(".apps.googleusercontent.com")
    }

    // MARK: Launch

    /// Confirms the stored identity is still valid with its provider.
    func verifyOnLaunch() async {
        guard let account else { return }
        switch account.provider {
        case .apple:
            let state = await withCheckedContinuation { (continuation: CheckedContinuation<ASAuthorizationAppleIDProvider.CredentialState, Never>) in
                ASAuthorizationAppleIDProvider().getCredentialState(forUserID: account.userID) { state, _ in
                    continuation.resume(returning: state)
                }
            }
            if state == .revoked || state == .notFound { signOutLocally() }
        case .google:
            guard Self.isGoogleConfigured else { return }
            // A failed restore offline isn't a sign-out; only a missing previous sign-in is.
            if !GIDSignIn.sharedInstance.hasPreviousSignIn() { signOutLocally() }
            _ = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
        }
    }

    func handle(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: Apple

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        lastError = nil
    }

    func completeApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                lastError = AccountError.failed.localizedDescription
                return
            }
            // Apple shares the name and email only on the first sign-in; keep what we had.
            let previous = account?.userID == credential.user ? account : nil
            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) } ?? ""
            let updated = UserAccount(
                provider: .apple,
                userID: credential.user,
                name: name.isEmpty ? (previous?.name ?? "") : name,
                email: credential.email ?? previous?.email
            )
            store(updated)
            Haptics.success()
        case .failure(let error):
            let code = (error as? ASAuthorizationError)?.code
            if code == .canceled { return }
            lastError = Self.isOffline(error) ? AccountError.offline.localizedDescription : AccountError.failed.localizedDescription
        }
    }

    // MARK: Google

    func signInWithGoogle() async {
        guard Self.isGoogleConfigured else {
            lastError = AccountError.notConfigured.localizedDescription
            return
        }
        guard let presenter = Self.topViewController() else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            let user = result.user
            store(UserAccount(
                provider: .google,
                userID: user.userID ?? user.profile?.email ?? UUID().uuidString,
                name: user.profile?.name ?? "",
                email: user.profile?.email
            ))
            Haptics.success()
        } catch {
            if (error as NSError).code == GIDSignInError.canceled.rawValue { return }
            lastError = Self.isOffline(error) ? AccountError.offline.localizedDescription : AccountError.failed.localizedDescription
        }
    }

    // MARK: Sign out / delete

    func signOut() {
        if account?.provider == .google, Self.isGoogleConfigured {
            GIDSignIn.sharedInstance.signOut()
        }
        signOutLocally()
    }

    /// Removes the account from Stay. For Google this also revokes Stay's access
    /// token; Apple users can additionally stop using their Apple Account with
    /// Stay in Settings › Apple Account › Sign in with Apple.
    func deleteAccount() async {
        if account?.provider == .google, Self.isGoogleConfigured {
            try? await GIDSignIn.sharedInstance.disconnect()
        }
        signOutLocally()
    }

    // MARK: Helpers

    private func handleAppleRevocation() {
        if account?.provider == .apple { signOutLocally() }
    }

    private func signOutLocally() {
        account = nil
        Keychain.delete()
    }

    private func store(_ account: UserAccount) {
        self.account = account
        Keychain.save(account)
    }

    private static func isOffline(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
            || (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.domain == NSURLErrorDomain
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    /// Minimal Keychain storage for the account record.
    private enum Keychain {
        private static var query: [String: Any] { [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "stay.account",
            kSecAttrAccount as String: "current",
        ] }

        static func save(_ account: UserAccount) {
            guard let data = try? JSONEncoder().encode(account) else { return }
            SecItemDelete(query as CFDictionary)
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }

        static func load() -> UserAccount? {
            var request = query
            request[kSecReturnData as String] = true
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
            return try? JSONDecoder().decode(UserAccount.self, from: data)
        }

        static func delete() {
            SecItemDelete(query as CFDictionary)
        }
    }
}
