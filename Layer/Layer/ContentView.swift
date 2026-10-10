import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Query private var products: [Product]
    @State private var tab: AppTab = .shelf

    var body: some View {
        // Both tabs stay alive (scroll position, open screens), only the visible one gets touches.
        // Pages swap instantly, like a native tab bar. Only the pill animates.
        ZStack {
            ShelfView().tabPage(isActive: tab == .shelf)
            RoutineView().tabPage(isActive: tab == .routine)
        }
        .safeAreaInset(edge: .bottom) {
            TabPills(selection: $tab)
        }
        // First launch: no profile yet, so ask the skin questions before anything else
        .fullScreenCover(isPresented: .constant(profileStore.profile == nil)) {
            OnboardingView(initial: nil) { profileStore.save($0) }
        }
        // Keep the home screen widget in sync with whatever changed: routines, new products, expiry
        .onChange(of: WidgetSnapshot.make(from: products), initial: true) { _, snapshot in
            WidgetSync.save(snapshot)
        }
        // Any photo on white (older saves, or a store photo Vision missed earlier) gets lifted to clear.
        // Reruns whenever a photo changes. Transparent ones are skipped, so it settles fast.
        .task(id: products.map { $0.imageData?.count ?? 0 }) {
            await BackgroundCleanup.run(products)
        }
    }
}

enum AppTab: CaseIterable {
    case shelf, routine

    var title: String { self == .shelf ? "Shelf" : "Routine" }
    var icon: String { self == .shelf ? "shelf" : "layers" }
}

// Custom tab bar: one espresso pill that glides between tabs
private struct TabPills: View {
    @Binding var selection: AppTab
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isOn = selection == tab
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 8) {
                        LayerIcon(name: tab.icon, size: tab == .shelf ? 32 : 20)   // shelf glyph is wide and short, so it needs more room to read the same size
                        Text(tab.title).font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(isOn ? Theme.onPrimary : Theme.ink)
                    .padding(.horizontal, 22)
                    .frame(height: 48)
                    .background {
                        if isOn {
                            Capsule()
                                .fill(Theme.primary)
                                .matchedGeometryEffect(id: "selected", in: pill)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(6)
        .background(Theme.card, in: .capsule)
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .padding(.bottom, 6)
        .animation(.snappy(duration: 0.16), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private extension View {
    func tabPage(isActive: Bool) -> some View {
        self
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }
}

#Preview {
    ContentView()
        .environment(ProfileStore())
        .modelContainer(for: [Product.self, RoutineLog.self], inMemory: true)
}
