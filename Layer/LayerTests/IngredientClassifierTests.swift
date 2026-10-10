import Foundation
import Testing
@testable import Layer

@MainActor
struct IngredientClassifierTests {
    func role(_ name: String) -> IngredientReference.Role? {
        IngredientClassifier.classify(name)?.role
    }

    @Test func plantOilsVsEssentialOils() {
        #expect(role("Simmondsia Chinensis (Jojoba) Seed Oil") == .barrier)
        #expect(role("Citrus Grandis (Grapefruit) Peel Oil") == .caution)
        #expect(role("Lavandula Hybrida Flower Oil") == .caution)
    }

    @Test func namingConventions() {
        #expect(role("Camellia Japonica Leaf Extract") == .botanical)
        #expect(role("PEG-75 Stearate") == .base)
        #expect(role("Cyclohexasiloxane") == .barrier)
        #expect(role("Myristyl Alcohol") == .base)
        #expect(role("Palmitoyl Hexapeptide-12") == .active)
        #expect(role("Ethylhexyl Palmitate") == .barrier)
        #expect(role("Sodium Cocoyl Glutamate") == .cleanser)
        #expect(role("Lactobacillus Ferment") == .hydrator)
    }

    @Test func unknownStillGetsAdded() {
        // Doesn't match any rule, but it's a real-looking name, so it's kept as "other"
        let ref = IngredientClassifier.classify("Tremella Fuciformis Polysaccharide")
        #expect(ref?.role == .other)
        #expect(ref?.isLearned == true)
    }

    @Test func rejectsOCRJunk() {
        #expect(IngredientClassifier.classify("1 2") == nil)
        #expect(IngredientClassifier.classify("Store in a cool dry place away from direct sunlight and keep out of reach") == nil)
    }

    @Test func learnedIngredientsAreRememberedAcrossLaunches() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "learned-\(UUID()).json")
        let first = IngredientDatabase(ingredients: [], rules: [], learnedURL: url)
        let tremella = try #require(IngredientClassifier.classify("Tremella Fuciformis Polysaccharide"))
        #expect(first.match("Tremella Fuciformis Polysaccharide") == nil)

        first.learn([tremella])

        // A fresh database reading the same file is like the next app launch
        let data = try Data(contentsOf: url)
        let saved = try JSONDecoder().decode([IngredientReference].self, from: data)
        let second = IngredientDatabase(ingredients: [], rules: [], learned: saved, learnedURL: url)
        #expect(second.match("Tremella Fuciformis Polysaccharide")?.key == tremella.key)
        #expect(second.reference(for: tremella.key) != nil)
    }
}
