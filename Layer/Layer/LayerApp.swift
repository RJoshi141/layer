import SwiftUI
import SwiftData

@main
struct LayerApp: App {
    @State private var profileStore = ProfileStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(profileStore)
        }
        .modelContainer(for: [Product.self, RoutineLog.self])
    }
}
