import SwiftUI
import WatchKit
import WidgetKit

@MainActor
final class BodyEnergyWatchDelegate: NSObject, WKApplicationDelegate {
    let manager: WatchConnectivityManager
    let viewModel: WatchEnergyViewModel

    override init() {
        let manager = WatchConnectivityManager()
        self.manager = manager
        self.viewModel = WatchEnergyViewModel(manager: manager)
        super.init()
    }

    func applicationDidFinishLaunching() {
        manager.activate(requestLatest: false)
        if manager.activities.active?.kind == .workout {
            Task { await manager.activities.workoutController.recoverActiveSession() }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func handleActiveWorkoutRecovery() {
        Task { await manager.activities.workoutController.recoverActiveSession() }
    }
}

@main
struct BodyEnergyWatchApp: App {
    @WKApplicationDelegateAdaptor(BodyEnergyWatchDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(appDelegate.viewModel)
        }
        .backgroundTask(.watchConnectivity) {
            await appDelegate.manager.receiveBackgroundUpdates()
        }
    }
}
