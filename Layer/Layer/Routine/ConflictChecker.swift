import Foundation

// Plain value snapshot of a product, so the checker is pure and testable without SwiftData
nonisolated struct RoutineItem: Identifiable, Sendable {
    let id: String
    let name: String
    let category: ProductCategory
    let tags: Set<String>
    var isExpired = false
}

nonisolated struct Finding: Identifiable, Sendable {
    let id: String
    let severity: ConflictRule.Severity
    let title: String
    let advice: String
}

// Deterministic on purpose. Safety calls come from rules; an LLM only gets to explain them later.
nonisolated enum ConflictChecker {
    static func check(_ items: [RoutineItem], period: RoutinePeriod, rules: [ConflictRule]) -> [Finding] {
        let findings = pairFindings(items, rules: rules) + routineFindings(items, period: period)
        // Most serious first: avoid → caution → fine
        let rank: [ConflictRule.Severity: Int] = [.avoid: 0, .caution: 1, .fine: 2]
        return findings.sorted { rank[$0.severity]! < rank[$1.severity]! }
    }

    // Pairs across different products. Retinol + AHA inside one formula was designed that way, so we skip it.
    static func pairFindings(_ items: [RoutineItem], rules: [ConflictRule]) -> [Finding] {
        var out: [Finding] = []
        for i in items.indices {
            for j in items.indices where j > i {
                let a = items[i], b = items[j]
                for rule in rules where matches(rule, a, b) {
                    out.append(Finding(
                        id: "\(rule.id)|\(a.id)|\(b.id)",
                        severity: rule.severity,
                        title: "\(a.name) + \(b.name)",
                        advice: rule.advice
                    ))
                }
            }
        }
        return out
    }

    // One product vs the rest of the shelf. Only real clashes, no myth-busting "fine" notes.
    static func clashes(of item: RoutineItem, with others: [RoutineItem], rules: [ConflictRule]) -> [Finding] {
        others.flatMap { other in
            rules
                .filter { $0.severity != .fine && matches($0, item, other) }
                .map { Finding(id: "\($0.id)|\(other.id)", severity: $0.severity, title: other.name, advice: $0.advice) }
        }
    }

    static func matches(_ rule: ConflictRule, _ a: RoutineItem, _ b: RoutineItem) -> Bool {
        let tagsA = Set(rule.tagsA), tagsB = Set(rule.tagsB)
        return (!a.tags.isDisjoint(with: tagsA) && !b.tags.isDisjoint(with: tagsB))
            || (!a.tags.isDisjoint(with: tagsB) && !b.tags.isDisjoint(with: tagsA))
    }

    // Checks that depend on the routine as a whole, not a pair
    static func routineFindings(_ items: [RoutineItem], period: RoutinePeriod) -> [Finding] {
        var out: [Finding] = []
        let sensitizing: Set<String> = ["retinoid", "exfoliant"]

        if period == .am {
            for item in items where item.tags.contains("retinoid") {
                out.append(Finding(
                    id: "retinoid-am|\(item.id)",
                    severity: .caution,
                    title: "\(item.name) in the morning",
                    advice: "Most retinoids break down in sunlight. They work best at night."
                ))
            }
            let hasSPF = items.contains { $0.category == .sunscreen || $0.tags.contains("spf-mineral") || $0.tags.contains("spf-chemical") }
            if !hasSPF {
                out.append(Finding(
                    id: "no-spf",
                    severity: .caution,
                    title: "No sunscreen",
                    advice: "Add an SPF as the last step, especially if you use acids or retinoids at any point."
                ))
            }
        }

        if period == .pm, let spf = items.first(where: { $0.category == .sunscreen }) {
            out.append(Finding(
                id: "spf-pm|\(spf.id)",
                severity: .fine,
                title: "\(spf.name) at night",
                advice: "Sunscreen isn't needed at night. You can save it for the morning."
            ))
        }

        let strong = items.filter { !$0.tags.isDisjoint(with: sensitizing) }
        if strong.count >= 3 {
            out.append(Finding(
                id: "too-many-actives",
                severity: .caution,
                title: "\(strong.count) strong actives",
                advice: "That's a lot for one routine. Spreading them across nights is easier on your barrier."
            ))
        }

        for item in items where item.isExpired {
            out.append(Finding(
                id: "expired|\(item.id)",
                severity: .caution,
                title: "\(item.name) is past its date",
                advice: "Actives like vitamin C and retinol lose strength after opening. Time to replace it."
            ))
        }
        return out
    }
}
