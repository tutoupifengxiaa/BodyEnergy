import SwiftUI

@main
struct BodyEnergyWatchApp: App {
    @StateObject private var viewModel = WatchEnergyViewModel()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(viewModel)
        }
    }
}
