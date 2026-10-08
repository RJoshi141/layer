import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Shelf", systemImage: "square.stack.3d.up") { ShelfView() }
            Tab("Routine", systemImage: "list.number") { RoutineView() }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Product.self, RoutineLog.self], inMemory: true)
}
