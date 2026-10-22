import SwiftUI
import UIKit
import UserNotifications

@main
struct StayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.purchases)
                .tint(StayPalette.sage)
                .task {
                    appDelegate.model = model
                    await model.launch()
                }
                .onOpenURL { url in
                    if let payload = PairingPayload(url: url) {
                        model.pendingPairing = payload
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        model.connectLinks()
                        Task { await model.pollCloudOnce() }
                    case .background:
                        model.saveNow()
                    default:
                        break
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor var model: AppModel?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Needed for CloudKit subscription pushes. No user prompt; alerts still need notification permission.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await model?.handleRemoteNotification()
        return .newData
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        Task { @MainActor in
            await self.model?.handleRemoteNotification()
            completionHandler()
        }
    }
}
