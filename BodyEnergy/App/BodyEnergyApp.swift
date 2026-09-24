import SwiftUI
import UIKit

@MainActor
final class BodyEnergyAppDelegate: NSObject, UIApplicationDelegate {
    let store: AppStore
    private var requestedAuthorization = false

    override init() {
        store = AppStore()
        super.init()
    }

    init(store: AppStore) {
        self.store = store
        super.init()
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        store.startAutomaticUpdates { UIApplication.shared.isProtectedDataAvailable }
        return true
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        Task { await store.refreshHealthData(requestAuthorization: false) }
    }

    func refreshOnActivation() async {
        if !requestedAuthorization {
            requestedAuthorization = true
            await store.refreshHealthData()
        } else {
            await store.refreshHealthData(requestAuthorization: false)
        }
    }
}

@main
struct BodyEnergyApp: App {
    @UIApplicationDelegateAdaptor(BodyEnergyAppDelegate.self) private var appDelegate
    private var store: AppStore { appDelegate.store }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await appDelegate.refreshOnActivation()
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(60)) } catch { return }
                        await store.refreshIfNeeded()
                    }
                }
        }
    }
}
