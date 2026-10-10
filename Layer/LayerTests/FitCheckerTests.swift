import Testing
@testable import Layer

@MainActor
struct FitCheckerTests {
    func ref(_ key: String, _ tags: [String], role: IngredientReference.Role = .active) -> IngredientReference {
        IngredientReference(key: key, name: key.capitalized, aliases: [], role: role, tags: tags, summary: "")
    }

    @Test func flagsGoodForConcern() {
        let profile = SkinProfile(concerns: [.breakouts])
        let findings = FitChecker(profile: profile).findings(forLabel: [ref("salicylic acid", ["bha", "exfoliant"])])
        #expect(findings.contains { $0.id == "good-breakouts" })
    }

    @Test func drynessNeedsMoreThanGlycerin() {
        let profile = SkinProfile(concerns: [.dryness])
        let glycerinOnly = [ref("glycerin", ["humectant"], role: .hydrator)]
        #expect(FitChecker(profile: profile).findings(forLabel: glycerinOnly).isEmpty)

        let rich = glycerinOnly + [ref("ceramide np", ["ceramide"], role: .barrier)]
        #expect(FitChecker(profile: profile).findings(forLabel: rich).contains { $0.id == "good-dryness" })
    }

    @Test func fragranceOnlyMattersIfSensitiveOrAvoided() {
        let label = [ref("parfum", ["fragrance"], role: .caution)]
        #expect(FitChecker(profile: SkinProfile()).findings(forLabel: label).isEmpty)
        #expect(!FitChecker(profile: SkinProfile(sensitivity: .often)).findings(forLabel: label).isEmpty)
        #expect(!FitChecker(profile: SkinProfile(avoid: [.fragrance])).findings(forLabel: label).isEmpty)
    }

    @Test func alcoholPositionMatters() {
        let profile = SkinProfile(skinType: .dry)
        let alcohol = ref("alcohol denat", ["drying-alcohol"], role: .caution)
        let filler: [IngredientReference?] = Array(repeating: nil, count: 20)
        #expect(FitChecker(profile: profile).findings(forLabel: [nil, alcohol]).contains { $0.id == "fit-alcohol" })
        #expect(!FitChecker(profile: profile).findings(forLabel: filler + [alcohol]).contains { $0.id == "fit-alcohol" })
    }

    @Test func beginnersGetStartSlow() {
        let label = [ref("retinol", ["retinoid"])]
        #expect(FitChecker(profile: SkinProfile(experience: .new)).findings(forLabel: label).contains { $0.id == "fit-start-slow" })
        #expect(!FitChecker(profile: SkinProfile(experience: .experienced)).findings(forLabel: label).contains { $0.id == "fit-start-slow" })
    }

    @Test func cautionsComeFirst() {
        let profile = SkinProfile(concerns: [.fineLines], experience: .new)
        let findings = FitChecker(profile: profile).findings(forLabel: [ref("retinol", ["retinoid"])])
        #expect(findings.first?.severity == .caution)
    }
}

@MainActor
struct CategoryHeuristicTests {
    @Test func sunWarningOnRetinolIsNotASunscreen() {
        let front = "retinol complex lotion sunburn alert: use a sunscreen spf 30 or higher"
        #expect(HeuristicExtractor.category(in: front) == .moisturizer)
    }

    @Test func realSPFClaimIsASunscreen() {
        #expect(HeuristicExtractor.category(in: "daily defense lotion spf 50 broad spectrum") == .sunscreen)
    }
}

@MainActor
struct CategoryFromLabelTests {
    @Test func serumWithDirectionsMentioningOtherProducts() {
        // "after cleansing" and "before moisturizer" are directions, not the product type
        let text = "niacinamide 10% serum. apply a few drops after cleansing, before moisturizer."
        #expect(HeuristicExtractor.category(in: text) == .serum)
    }

    @Test func moisturizerThatMentionsSerum() {
        let text = "barrier repair cream. use after your serum for best results."
        #expect(HeuristicExtractor.category(in: text) == .moisturizer)
    }

    @Test func tubSoldByWeightWithNoTypeWord() {
        #expect(HeuristicExtractor.category(in: "deep hydration 50 g 1.7 oz") == .moisturizer)
    }

    @Test func typeWordOnTheSecondPhotoStillCounts() {
        // Photo 1: ingredient panel. Photo 2: front of the bottle.
        let back = ["Ingredients: Water, Glycerin, Niacinamide, Zinc PCA"]
        let front = ["The Ordinary", "Niacinamide 10% + Zinc 1%", "Serum"]
        #expect(HeuristicExtractor.extract(perImage: [back, front]).category == .serum)
    }
}
