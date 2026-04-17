import SwiftUI

@main
struct BodyEnergyApp: App {
    @StateObject private var store = AppStore.preview

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    await store.refreshHealthData()
                }
        }
    }
}
