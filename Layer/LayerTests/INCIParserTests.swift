import Testing
@testable import Layer

@MainActor
struct INCIParserTests {
    @Test func splitsOnCommasButKeepsChemicalNames() {
        let lines = [
            "Ingredients: Water (Aqua), Glycerin, 1,2-Hexanediol,",
            "Niacinamide, PEG-40 Hydrogenated Castor Oil.",
        ]
        #expect(INCIParser.parse(lines: lines) == [
            "Water (Aqua)", "Glycerin", "1,2-Hexanediol", "Niacinamide", "PEG-40 Hydrogenated Castor Oil",
        ])
    }

    @Test func rejoinsWordsBrokenAcrossLines() {
        let lines = ["INGREDIENTS: Aqua, Sodium Hyal-", "uronate, Panthenol"]
        #expect(INCIParser.parse(lines: lines) == ["Aqua", "Sodium Hyaluronate", "Panthenol"])
    }

    @Test func stopsWhereTheListEnds() {
        let lines = ["Ingredients: Water, Glycerin, Squalane. Made in Korea", "Directions: apply to clean skin"]
        #expect(INCIParser.parse(lines: lines) == ["Water", "Glycerin", "Squalane"])
    }

    @Test func ignoresCommasInsideParentheses() {
        let lines = ["Ingredients: Butyrospermum Parkii (Shea, Karite) Butter, Glycerin"]
        #expect(INCIParser.parse(lines: lines) == ["Butyrospermum Parkii (Shea, Karite) Butter", "Glycerin"])
    }

    @Test func readsBothListsOnUSSunscreens() {
        let lines = [
            "Active ingredients: Zinc Oxide 20% Purpose: Sunscreen",
            "Inactive ingredients: Water, Squalane, Tocopherol",
        ]
        #expect(INCIParser.parse(lines: lines) == ["Zinc Oxide 20%", "Water", "Squalane", "Tocopherol"])
    }

    @Test func stitchesOverlappingPhotos() {
        // Photo 1 cuts off mid-word, photo 2 overlaps and has the full name
        let left = ["Water", "Glycerin", "Sodium Hyal"]
        let right = ["Sodium Hyaluronate", "Panthenol", "Squalane"]
        #expect(INCIParser.merge([left, right]) == ["Water", "Glycerin", "Sodium Hyaluronate", "Panthenol", "Squalane"])
    }

    @Test func keepsRealIngredientsThatShareAPrefix() {
        // Not at a photo edge, so it's a real ingredient, not a cut-off fragment
        let one = ["Water", "Sodium Hyaluronate", "Glycerin"]
        let two = ["Sodium Hyaluronate Crosspolymer", "Panthenol"]
        #expect(INCIParser.merge([one, two]).contains("Sodium Hyaluronate"))
    }
}

@MainActor
struct IngredientMatchingTests {
    let db = IngredientDatabase(
        ingredients: [
            IngredientReference(key: "water", name: "Water", aliases: ["Aqua"], role: .base, tags: [], summary: ""),
            IngredientReference(key: "niacinamide", name: "Niacinamide", aliases: ["Vitamin B3"], role: .active, tags: ["niacinamide"], summary: ""),
            IngredientReference(key: "zinc-oxide", name: "Zinc Oxide", aliases: [], role: .sunscreen, tags: ["spf-mineral"], summary: ""),
        ],
        rules: []
    )

    @Test func matchesAliases() {
        #expect(db.match("Vitamin B3")?.key == "niacinamide")
    }

    @Test func matchesParentheticalNames() {
        #expect(db.match("Water (Aqua)")?.key == "water")
        #expect(db.match("Water/Aqua/Eau")?.key == "water")
    }

    @Test func ignoresStrengthMarkers() {
        #expect(db.match("Zinc Oxide 20%")?.key == "zinc-oxide")
    }

    @Test func toleratesOCRTypos() {
        #expect(db.match("Niacinamlde")?.key == "niacinamide")
    }

    @Test func returnsNilForUnknowns() {
        #expect(db.match("Polysorbate 20") == nil)
    }

    @Test func bundledDatabaseLoads() {
        #expect(IngredientDatabase.shared.ingredients.count > 50)
        #expect(IngredientDatabase.shared.match("Parfum")?.key == "fragrance")
    }
}
