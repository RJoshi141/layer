import Foundation
import FoundationModels

// Guided generation: the on-device model has to fill this exact shape, no JSON parsing on our side
@Generable
nonisolated struct ProductDraft {
    @Guide(description: "Product name as printed, without the brand. Empty string if not visible.")
    var name: String

    @Guide(description: "Brand name. Empty string if not visible.")
    var brand: String

    @Guide(description: "What kind of product this is.", .anyOf([
        "cleanser", "toner", "serum", "treatment", "moisturizer", "sunscreen", "eyeCream", "mask", "oil", "other",
    ]))
    var category: String

    @Guide(description: "Months the product lasts after opening, from the open-jar symbol like '12M'. 0 if not printed.")
    var monthsAfterOpening: Int

    @Guide(description: "Actives with a percentage printed on the package, like '2% Salicylic Acid'. Empty if none.")
    var statedActives: [String]
}

nonisolated struct LabelExtractor {
    static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    private static let instructions = """
        You read OCR text from skincare packaging and fill in product details. \
        The text can contain OCR mistakes and can mix the front and back of the package. \
        Only use information that is in the text. Never guess a brand or product name that isn't there.
        """

    func extract(from rawText: String) async throws -> ProductDraft {
        let session = LanguageModelSession(instructions: Self.instructions)
        // ~4K token context on device, so keep the prompt tight
        let prompt = "Packaging text:\n\(rawText.prefix(2500))"
        return try await session.respond(to: prompt, generating: ProductDraft.self).content
    }
}

nonisolated extension LabelFields {
    // Model wins on fuzzy stuff (name, brand, category). Regex wins on the PAO icon when it found one.
    mutating func fill(from draft: ProductDraft) {
        if !draft.name.isEmpty { name = draft.name }
        if !draft.brand.isEmpty { brand = draft.brand }
        if let c = ProductCategory(rawValue: draft.category), c != .other { category = c }
        if paoMonths == nil, (1...60).contains(draft.monthsAfterOpening) { paoMonths = draft.monthsAfterOpening }
        for active in draft.statedActives
        where !statedActives.contains(where: { $0.caseInsensitiveCompare(active) == .orderedSame }) {
            statedActives.append(active)
        }
    }
}
