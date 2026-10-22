import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.openURL) private var openURL
    @State private var showPairing = false
    @State private var showAddDog = false
    @State private var showManageSubscriptions = false
    @State private var exportURL: URL?
    @State private var confirmDeleteAll = false
    @State private var confirmRoleSwitch = false
    @State private var restoreMessage: String?
    @State private var restoring = false

    var body: some View {
        NavigationStack {
            Form {
                subscriptionSection
                dogsSection
                cameraSection
                remindersSection
                dataSection
                LegalLinksSection()
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .stayBackground()
            .navigationTitle("Settings")
            .sheet(isPresented: $showPairing) { OwnerPairingView() }
            .sheet(isPresented: $showAddDog) { AddDogView() }
            .manageSubscriptionsSheet(isPresented: $showManageSubscriptions)
            .alert("Restore purchases", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage ?? "")
            }
            .confirmationDialog("Delete all data?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) { model.deleteAllData() }
            } message: {
                Text("This removes every dog, session, photo and journal entry from this device. Your subscription isn't affected. This can't be undone.")
            }
            .confirmationDialog("Use this device as the dog camera?", isPresented: $confirmRoleSwitch, titleVisibility: .visible) {
                Button("Switch to Camera mode") { model.setRole(.camera) }
            } message: {
                Text("Your dogs and history stay on this device. You can switch back at any time.")
            }
        }
    }

    // MARK: Sections

    private var subscriptionSection: some View {
        Section {
            if purchases.isPro {
                HStack(spacing: 14) {
                    IconBadge(symbol: "crown.fill", tint: StayPalette.apricot, fill: StayPalette.apricotSoft)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(purchases.activePlanName ?? String(localized: "Stay Pro")).font(StayFont.headline)
                        if let renewal = purchases.renewalDate {
                            Text(purchases.willAutoRenew ? String(localized: "Renews \(renewal.formatted(date: .abbreviated, time: .omitted))") : String(localized: "Ends \(renewal.formatted(date: .abbreviated, time: .omitted))"))
                                .font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                        } else {
                            Text("Thank you for supporting Stay").font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                        }
                    }
                }
                if purchases.activeProductID != PurchaseManager.ProductID.lifetime {
                    Button("Manage subscription") { showManageSubscriptions = true }
                }
            } else {
                Button {
                    model.presentedPaywall = true
                } label: {
                    HStack(spacing: 14) {
                        IconBadge(symbol: "crown.fill", tint: .white, fill: StayPalette.apricot)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Try Stay Pro").font(StayFont.headline).foregroundStyle(StayPalette.ink)
                            Text("Unlimited missions, away-from-home alerts, reports").font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                        }
                    }
                }
            }
            Button {
                restoring = true
                Task {
                    do {
                        try await purchases.restore()
                        restoreMessage = purchases.isPro ? String(localized: "Your purchase has been restored.") : String(localized: "No previous purchases were found for this Apple Account.")
                        model.connectLinks()
                    } catch {
                        restoreMessage = String(localized: "Couldn't reach the App Store. Please try again.")
                    }
                    restoring = false
                }
            } label: {
                HStack {
                    Text("Restore purchases")
                    if restoring { Spacer(); ProgressView() }
                }
            }
            .disabled(restoring)
        } header: {
            Text("Subscription")
        }
    }

    private var dogsSection: some View {
        Section("Dogs") {
            ForEach(model.dogs) { dog in
                NavigationLink {
                    DogSettingsView(dog: dog)
                } label: {
                    HStack(spacing: 12) {
                        DogAvatar(dog: dog, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dog.name).font(StayFont.bodyEmphasis)
                            Text([dog.breed, dog.ageDescription].filter { !$0.isEmpty }.joined(separator: " · ")).font(StayFont.caption).foregroundStyle(StayPalette.inkSecondary)
                        }
                        Spacer()
                        if dog.id == model.selectedDog?.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(StayPalette.sage).accessibilityLabel(Text("Selected"))
                        }
                    }
                }
            }
            Button {
                if model.canAddDog { showAddDog = true } else { model.presentedPaywall = true }
            } label: {
                Label(model.canAddDog ? String(localized: "Add a dog") : String(localized: "Add a dog (Pro)"), systemImage: "plus.circle")
            }
        }
    }

    private var cameraSection: some View {
        Section {
            Button {
                showPairing = true
            } label: {
                HStack {
                    Label("Dog camera", systemImage: "video.fill")
                    Spacer()
                    Text(model.isPaired ? String(localized: "Paired") : String(localized: "Set up")).foregroundStyle(StayPalette.inkSecondary)
                }
            }
            Button("Use this device as the dog camera") { confirmRoleSwitch = true }
        } header: {
            Text("Camera")
        } footer: {
            Text("Remote alerts and the near-live view away from home use your iCloud and need Stay Pro. Live view on the same Wi-Fi is free.")
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("Daily mission reminder", isOn: Binding(
                get: { model.preferences.remindersEnabled },
                set: { enabled in
                    model.updatePreferences { $0.remindersEnabled = enabled }
                    Task {
                        if enabled { await NotificationScheduler.requestAuthorization() }
                        await model.rescheduleReminders()
                    }
                }
            ))
            if model.preferences.remindersEnabled {
                DatePicker("Time", selection: Binding(
                    get: {
                        Calendar.current.date(from: DateComponents(hour: model.preferences.reminderHour, minute: model.preferences.reminderMinute)) ?? .now
                    },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        model.updatePreferences {
                            $0.reminderHour = parts.hour ?? 9
                            $0.reminderMinute = parts.minute ?? 0
                        }
                        Task { await model.rescheduleReminders() }
                    }
                ), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Rest days get a gentle note instead of a mission.")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                exportURL = try? model.exportData()
            } label: {
                Label("Export my data", systemImage: "square.and.arrow.up")
            }
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Share export file (JSON)", systemImage: "doc.text")
                }
            }
            Button(role: .destructive) {
                confirmDeleteAll = true
            } label: {
                Label("Delete all data", systemImage: "trash")
            }
        } header: {
            Text("Your data")
        } footer: {
            Text("Stay keeps your data on this device. Camera pairing uses your own iCloud. There's no account and nothing is sold or shared.")
        }
    }

    private var aboutSection: some View {
        Section {
            Button {
                let subject = "Stay support".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "mailto:\(AppConfig.supportEmail)?subject=\(subject)") { openURL(url) }
            } label: {
                Label("Contact support", systemImage: "envelope")
            }
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
        } footer: {
            Text("Stay offers training support based on graduated-absence methods. It isn't a medical device and doesn't diagnose or treat any condition. For severe anxiety, injuries or sudden changes, please see your vet.")
                .padding(.top, 8)
        }
    }
}

struct LegalLinksSection: View {
    var body: some View {
        Section("Legal") {
            Link(destination: AppConfig.privacyURL) { Label("Privacy policy", systemImage: "hand.raised") }
            Link(destination: AppConfig.termsURL) { Label("Terms of use", systemImage: "doc.plaintext") }
            Link(destination: AppConfig.supportURL) { Label("Help & support", systemImage: "questionmark.circle") }
        }
    }
}
