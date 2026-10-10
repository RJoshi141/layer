import Foundation
import WidgetKit

// What the widget shows. The widget extension can't open the app's SwiftData store directly,
// so the app writes this small snapshot into the shared App Group whenever the routine changes.
// LayerWidget has a matching copy of this struct (same JSON shape).
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    nonisolated struct Step: Codable, Equatable, Sendable {
        let name: String
        let symbol: String
        let icon: String          // line icon name, the widget has its own copy of the icon set
        let isExpired: Bool
    }

    var morning: [Step]
    var night: [Step]
    var morningHeadsUp: String?
    var nightHeadsUp: String?
}

nonisolated enum WidgetSync {
    static let appGroup = "group.com.ritikajoshi.layer"
    static let key = "routineSnapshot"

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        // Skip the reload if nothing changed, widget refreshes are budgeted by the system
        if defaults.data(forKey: key) == data { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WidgetSnapshot {
    static func make(from products: [Product]) -> WidgetSnapshot {
        let rules = IngredientDatabase.shared.rules

        func steps(_ period: RoutinePeriod) -> [Product] {
            products.filter { $0.isIn(period) }.sorted { $0.category.layerRank < $1.category.layerRank }
        }
        // The most important warning, so the widget can nudge you before you start
        func headsUp(_ period: RoutinePeriod) -> String? {
            ConflictChecker.check(steps(period).map(\.routineItem), period: period, rules: rules)
                .first { $0.severity != .fine }?.title
        }

        return WidgetSnapshot(
            morning: steps(.am).map { Step(name: $0.name, symbol: $0.category.symbol, icon: $0.category.iconName, isExpired: $0.isExpired) },
            night: steps(.pm).map { Step(name: $0.name, symbol: $0.category.symbol, icon: $0.category.iconName, isExpired: $0.isExpired) },
            morningHeadsUp: headsUp(.am),
            nightHeadsUp: headsUp(.pm)
        )
    }
}
