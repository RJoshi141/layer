import SwiftUI
import UIKit
import SwiftData

@main
struct LayerApp: App {
    @State private var profileStore = ProfileStore()

    init() {
        FontRegistry.registerBundledFonts()

        // Display serif for navigation titles, to match the editorial look
        let serif = { (size: CGFloat, weight: UIFont.Weight) -> UIFont in
            if let custom = UIFont(name: Theme.displayFontName, size: size) { return custom }
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            return UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size)
        }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(Theme.page)
        appearance.largeTitleTextAttributes = [.font: serif(34, .regular), .foregroundColor: UIColor(Theme.ink)]
        appearance.titleTextAttributes = [.font: serif(17, .medium), .foregroundColor: UIColor(Theme.ink)]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        // No system blue anywhere: back buttons, toolbar icons and tab bar use espresso
        UINavigationBar.appearance().tintColor = UIColor(Theme.ink)
        UITabBar.appearance().tintColor = UIColor(Theme.ink)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(profileStore)
                .tint(Theme.ink)
        }
        .modelContainer(for: [Product.self, RoutineLog.self])
    }
}
