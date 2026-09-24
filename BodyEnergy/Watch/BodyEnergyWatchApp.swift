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
        WidgetCenter.shared.reloadAllTimelines()
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
