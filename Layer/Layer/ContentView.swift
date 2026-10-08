import SwiftUI
import SwiftData

// Just the shelf for now. Routine and Ask tabs come with the voice + assistant milestones.
struct ContentView: View {
    var body: some View {
        ShelfView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Product.self, RoutineLog.self], inMemory: true)
}
