import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if !model.preferences.hasCompletedOnboarding {
                OnboardingFlow()
                    .transition(.opacity)
            } else if model.role == .camera {
                CameraModeView()
                    .transition(.opacity)
            } else {
                OwnerTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.preferences.hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.35), value: model.role)
        .sheet(isPresented: $model.presentedPaywall) {
            PaywallView()
        }
        .sheet(item: $model.pendingPairing) { payload in
            JoinPairingView(payload: payload)
        }
    }
}

extension PairingPayload: Identifiable {
    var id: String { linkID }
}

struct OwnerTabView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .today

    enum Tab: Hashable {
        case today, progress, coach, settings
    }

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "house.fill") }
                .tag(Tab.today)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)
            CoachView()
                .tabItem { Label("Coach", systemImage: "sparkles") }
                .tag(Tab.coach)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
    }
}
