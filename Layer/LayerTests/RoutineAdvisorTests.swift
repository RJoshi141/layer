import Testing
@testable import Layer

@MainActor
struct RoutineAdvisorTests {
    let rules = [
        ConflictRule(id: "retinoid-exfoliant", tagsA: ["retinoid"], tagsB: ["exfoliant"], severity: .caution, advice: "Alternate them."),
    ]

    func product(
        _ name: String,
        _ category: ProductCategory,
        tags: Set<String> = [],
        am: Bool = false,
        pm: Bool = false,
        expired: Bool = false,
        cautions: [String] = [],
        helps: [SkinConcern] = []
    ) -> AdvisorProduct {
        AdvisorProduct(id: name, name: name, category: category, tags: tags, activeNames: [], isExpired: expired,
                       inAM: am, inPM: pm, cautions: cautions, helps: helps)
    }

    func advise(_ products: [AdvisorProduct], profile: SkinProfile? = nil, _ period: RoutinePeriod) -> [Suggestion] {
        RoutineAdvisor(products: products, profile: profile, rules: rules).suggestions(for: period)
    }

    @Test func retinoidInMorningGetsMovedToNight() {
        let s = advise([product("Retinol", .serum, tags: ["retinoid"], am: true)], .am)
        #expect(s.contains { $0.action == .move(productID: "Retinol", from: .am, to: .pm) })
    }

    @Test func clashMovesTheAcidToItsNaturalHome() {
        // Vitamin C belongs in the morning, so in a night clash it's the one that moves
        let rules = [ConflictRule(id: "vitc-exfoliant", tagsA: ["vitamin-c"], tagsB: ["exfoliant"], severity: .caution, advice: "")]
        let products = [
            product("BHA", .treatment, tags: ["exfoliant", "bha"], pm: true),
            product("Vit C", .serum, tags: ["vitamin-c"], pm: true),
        ]
        let s = RoutineAdvisor(products: products, profile: nil, rules: rules).suggestions(for: .pm)
        #expect(s.contains { $0.action == .move(productID: "Vit C", from: .pm, to: .am) })
    }

    @Test func expiredProductIsSwappedForShelfAlternative() {
        let products = [
            product("Old Cream", .moisturizer, pm: true, expired: true),
            product("New Cream", .moisturizer),
        ]
        let s = advise(products, .pm)
        #expect(s.contains { $0.action == .swap(remove: "Old Cream", add: "New Cream", period: .pm) })
    }

    @Test func morningWithoutSPFSuggestsTheOneOnTheShelf() {
        let products = [
            product("Cleanser", .cleanser, am: true),
            product("SPF 50", .sunscreen),
        ]
        let s = advise(products, .am)
        #expect(s.contains { $0.action == .add(productID: "SPF 50", to: .am) })
    }

    @Test func uncoveredConcernNamesIngredientsNotBrands() {
        let profile = SkinProfile(concerns: [.darkSpots])
        let s = advise([product("Cream", .moisturizer, pm: true)], profile: profile, .pm)
        let gap = s.first { $0.id == "concern-darkSpots" }
        #expect(gap?.detail.contains("vitamin C") == true)
        #expect(gap?.action == nil)
    }

    @Test func fixesComeBeforeTips() {
        let products = [
            product("Retinol", .serum, tags: ["retinoid"], am: true),
            product("Cream", .moisturizer, am: true, cautions: ["Contains fragrance"]),
        ]
        let s = advise(products, .am)
        #expect(s.first?.kind == .fix)
    }
}
