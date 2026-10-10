import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Query private var products: [Product]

    var body: some View {
        TabView {
            Tab("Shelf", systemImage: "square.stack.3d.up") { ShelfView() }
            Tab("Routine", systemImage: "list.number") { RoutineView() }
        }
        // First launch: no profile yet, so ask the skin questions before anything else
        .fullScreenCover(isPresented: .constant(profileStore.profile == nil)) {
            OnboardingView(initial: nil) { profileStore.save($0) }
        }
        // Keep the home screen widget in sync with whatever changed: routines, new products, expiry
        .onChange(of: WidgetSnapshot.make(from: products), initial: true) { _, snapshot in
            WidgetSync.save(snapshot)
        }
    }
}

#Preview {
    ContentView()
        .environment(ProfileStore())
        .modelContainer(for: [Product.self, RoutineLog.self], inMemory: true)
}
