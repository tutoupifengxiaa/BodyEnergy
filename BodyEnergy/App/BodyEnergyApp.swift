import SwiftUI

@main
struct BodyEnergyApp: App {
    @StateObject private var store = AppStore.preview

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ContentView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environmentObject(store)
            .task {
                await store.refreshHealthData()
            }
        }
    }
}
