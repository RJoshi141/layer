import Testing
@testable import Layer

@MainActor
struct CheckInHeuristicsTests {
    let cleanser = ShelfEntry(id: "c", name: "Gentle Foaming Cleanser", brand: "CeraVe", category: .cleanser, activeNames: [])
    let retinol = ShelfEntry(id: "r", name: "Retinol 0.5% in Squalane", brand: "The Ordinary", category: .serum, activeNames: ["Retinol"])
    let bha = ShelfEntry(id: "b", name: "2% BHA Liquid Exfoliant", brand: "Paula's Choice", category: .treatment, activeNames: ["Salicylic Acid", "BHA"])

    var shelf: [ShelfEntry] { [cleanser, retinol, bha] }

    @Test func findsProductsByActiveAndCategory() {
        let ids = CheckInHeuristics.products(in: "Used the cleanser and the retinol tonight", shelf: shelf)
        #expect(ids == ["c", "r"])
    }

    @Test func respectsSkips() {
        let ids = CheckInHeuristics.products(in: "Did the retinol but skipped the BHA", shelf: shelf)
        #expect(ids == ["r"])
    }

    @Test func vagueCategoryNeedsOneMatch() {
        let twoSerums = shelf + [ShelfEntry(id: "v", name: "C Firma", brand: "Drunk Elephant", category: .serum, activeNames: [])]
        // "my serum" could be either one, so we don't guess
        #expect(CheckInHeuristics.products(in: "just my serum", shelf: twoSerums).isEmpty)
    }

    @Test func readsSkinFeelWithNegation() {
        #expect(CheckInHeuristics.skinFeel(in: "Skin feels tight. Not oily at all") == ["tight"])
    }

    @Test func pairsReactionsWithArea() {
        #expect(CheckInHeuristics.reactions(in: "Small breakout on my chin, some redness on the cheek") == ["breakout: chin", "redness: cheeks"])
        #expect(CheckInHeuristics.reactions(in: "No breakouts today").isEmpty)
    }

    @Test func detectsPeriod() {
        #expect(CheckInHeuristics.period(in: "This morning I used sunscreen") == .am)
        #expect(CheckInHeuristics.period(in: "Did my routine before bed") == .pm)
        #expect(CheckInHeuristics.period(in: "Used the retinol") == nil)
    }
}
