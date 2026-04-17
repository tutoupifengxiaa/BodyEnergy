import SwiftUI

@main
struct BodyEnergyApp: App {
    @StateObject private var store = AppStore.preview
    private let screenBounds = UIScreen.main.bounds

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color.white
                    .ignoresSafeArea()

                ContentView()
                    .frame(width: screenBounds.width, height: screenBounds.height)
            }
            .frame(width: screenBounds.width, height: screenBounds.height)
            .environmentObject(store)
            .task {
                await store.refreshHealthData()
            }
        }
    }
}
