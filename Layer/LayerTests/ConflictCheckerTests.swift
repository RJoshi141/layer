import Testing
@testable import Layer

@MainActor
struct ConflictCheckerTests {
    let rules = [
        ConflictRule(id: "retinoid-exfoliant", tagsA: ["retinoid"], tagsB: ["exfoliant"], severity: .caution, advice: ""),
        ConflictRule(id: "niacinamide-vitc", tagsA: ["niacinamide"], tagsB: ["vitamin-c"], severity: .fine, advice: ""),
    ]

    func item(_ name: String, _ tags: Set<String>, category: ProductCategory = .serum) -> RoutineItem {
        RoutineItem(id: name, name: name, category: category, tags: tags)
    }

    @Test func flagsPairsInEitherOrder() {
        let bha = item("BHA", ["bha", "exfoliant"])
        let retinol = item("Retinol", ["retinoid"])
        #expect(ConflictChecker.pairFindings([bha, retinol], rules: rules).map(\.severity) == [.caution])
        #expect(ConflictChecker.pairFindings([retinol, bha], rules: rules).map(\.severity) == [.caution])
    }

    @Test func ignoresComboInsideOneFormula() {
        // Retinol + AHA in one bottle was formulated together, not our call to flag
        let combo = item("Night Peel", ["retinoid", "exfoliant"])
        #expect(ConflictChecker.pairFindings([combo], rules: rules).isEmpty)
    }

    @Test func surfacesMythBusters() {
        let findings = ConflictChecker.pairFindings([item("B3", ["niacinamide"]), item("C", ["vitamin-c"])], rules: rules)
        #expect(findings.map(\.severity) == [.fine])
    }

    @Test func morningNeedsSunscreen() {
        let am = ConflictChecker.routineFindings([item("Serum", ["niacinamide"])], period: .am)
        #expect(am.contains { $0.id == "no-spf" })

        let withSPF = ConflictChecker.routineFindings([item("SPF", ["spf-mineral"], category: .sunscreen)], period: .am)
        #expect(!withSPF.contains { $0.id == "no-spf" })
    }

    @Test func retinoidInMorningIsFlagged() {
        let am = ConflictChecker.routineFindings([item("Retinol", ["retinoid"])], period: .am)
        #expect(am.contains { $0.id.hasPrefix("retinoid-am") })
        let pm = ConflictChecker.routineFindings([item("Retinol", ["retinoid"])], period: .pm)
        #expect(pm.isEmpty)
    }

    @Test func cautionSortsBeforeFine() {
        let items = [item("B3", ["niacinamide"]), item("C", ["vitamin-c"]), item("BHA", ["exfoliant"]), item("Retinol", ["retinoid"])]
        let findings = ConflictChecker.check(items, period: .pm, rules: rules)
        #expect(findings.first?.severity == .caution)
        #expect(findings.last?.severity == .fine)
    }

    @Test func bundledRulesUseRealTags() {
        // Catches typos in conflict_rules.json: every tag a rule mentions must exist on some ingredient
        let db = IngredientDatabase.shared
        let known = Set(db.ingredients.flatMap(\.tags))
        for rule in db.rules {
            #expect(Set(rule.tagsA + rule.tagsB).isSubset(of: known), "\(rule.id)")
        }
    }
}
