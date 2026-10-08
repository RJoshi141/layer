import SwiftUI
import SwiftData

@main
struct LayerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Product.self, RoutineLog.self])
    }
}
