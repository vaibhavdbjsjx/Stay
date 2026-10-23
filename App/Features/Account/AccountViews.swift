import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift
import SwiftUI

/// Sign in with Apple and Google, shown with equal prominence.
struct SignInOptions: View {
    @Environment(AccountService.self) private var account
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                account.configure(request)
            } onCompletion: { result in
                account.completeApple(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if AccountService.isGoogleConfigured {
                Button {
                    Task { await account.signInWithGoogle() }
                } label: {
                    HStack(spacing: 10) {
                        GoogleSignInButtonIcon()
                        Text("Continue with Google")
                            .font(.system(size: 19, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(Color(hex: 0x1F1F1F))
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0x747775), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(account.isWorking)
                .accessibilityLabel(Text("Continue with Google"))
            }

            if account.isWorking {
                ProgressView().padding(.top, 4)
            }
            if let error = account.lastError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(StayFont.caption)
                    .foregroundStyle(StayPalette.alert)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: account.lastError)
    }
}

/// The multicolour "G" mark from Google's own package, sized for our button.
private struct GoogleSignInButtonIcon: View {
    var body: some View {
        GoogleSignInButton(scheme: .light, style: .icon, state: .normal) {}
            .allowsHitTesting(false)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }
}

/// Settings section: profile, sign out and account deletion.
struct AccountSection: View {
    @Environment(AccountService.self) private var account
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        Section {
            if let user = account.account {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(StayPalette.sunriseGradient)
                        Text(String(user.displayName.prefix(1)).uppercased())
                            .font(.system(.headline, design: .serif))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 42, height: 42)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName).font(StayFont.bodyEmphasis)
                        Text(user.email ?? String(localized: "Signed in with \(user.provider.title)"))
                            .font(StayFont.caption)
                            .foregroundStyle(StayPalette.inkSecondary)
                    }
                }
                Button("Sign out") { account.signOut() }
                Button("Delete account", role: .destructive) { confirmDelete = true }
                    .disabled(deleting)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sign in to put your name on trainer reports and share cards, and to label your phone when pairing a camera. Optional — everything works without an account.")
                        .font(StayFont.caption)
                        .foregroundStyle(StayPalette.inkSecondary)
                    SignInOptions()
                }
                .padding(.vertical, 6)
            }
        } header: {
            Text("Account")
        }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                deleting = true
                Task {
                    await account.deleteAccount()
                    deleting = false
                }
            }
        } message: {
            Text("This signs you out and removes your account from Stay. Your dogs and training history stay on this device unless you also choose Delete all data. To fully disconnect Sign in with Apple, go to Settings › Apple Account › Sign in with Apple › Stay.")
        }
    }
}

/// Optional onboarding step offered after permissions.
struct AccountOnboardingStep: View {
    @Environment(AccountService.self) private var account
    var finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            ZStack {
                Circle().fill(StayPalette.sageSoft).frame(width: 110, height: 110)
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 46, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(StayPalette.sage)
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            Text("Add your name").font(StayFont.display).foregroundStyle(StayPalette.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Sign in so your name appears on trainer reports and share cards. It's optional: Stay keeps your data on this device either way, and there's no password to remember.")
                .font(StayFont.body)
                .foregroundStyle(StayPalette.inkSecondary)
            Spacer()
            if account.isSignedIn {
                Label("Signed in as \(account.account?.displayName ?? "")", systemImage: "checkmark.circle.fill")
                    .font(StayFont.headline)
                    .foregroundStyle(StayPalette.calm)
                    .frame(maxWidth: .infinity)
                Button("Continue", action: finish).buttonStyle(.stayPrimary)
            } else {
                SignInOptions()
                Button("Continue without an account", action: finish)
                    .font(StayFont.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .stayBackground()
        .navigationBarTitleDisplayMode(.inline)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: account.isSignedIn)
    }
}
