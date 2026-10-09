import Foundation
import FoundationModels

// What the parser knows about a shelf product. Plain values so it's testable.
nonisolated struct ShelfEntry: Sendable {
    let id: String
    let name: String
    let brand: String
    let category: ProductCategory
    let activeNames: [String]   // "retinol", "salicylic acid", "bha"... so "used the retinol" finds the right bottle
}

nonisolated struct CheckInResult: Sendable {
    var period: RoutinePeriod
    var productIDs: [String]
    var skinFeel: [String]
    var reactions: [String]
    var usedModel: Bool
}

// "Used the cleanser and the retinol, skin feels tight, small breakout on my chin"
//   → products: [cleanser, retinol serum], feel: [tight], reactions: [breakout: chin]
nonisolated enum CheckInParser {
    static func parse(_ transcript: String, shelf: [ShelfEntry], now: Date = .now) async -> CheckInResult {
        var result = CheckInResult(
            period: CheckInHeuristics.period(in: transcript) ?? (Calendar.current.component(.hour, from: now) < 15 ? .am : .pm),
            productIDs: CheckInHeuristics.products(in: transcript, shelf: shelf),
            skinFeel: CheckInHeuristics.skinFeel(in: transcript),
            reactions: CheckInHeuristics.reactions(in: transcript),
            usedModel: false
        )

        guard LabelExtractor.isAvailable, !shelf.isEmpty,
              let draft = try? await extract(transcript, shelf: shelf) else { return result }

        // Model picks only count if they map to a real shelf product. No invented products.
        let picked = draft.productsUsed.compactMap { said in
            shelf.first { IngredientDatabase.normalize($0.name) == IngredientDatabase.normalize(said) }?.id
        }
        result.productIDs = unique(result.productIDs + picked)
        result.skinFeel = unique(result.skinFeel + draft.skinFeel.map { $0.lowercased() })
        result.reactions = unique(result.reactions + draft.reactions.map { $0.lowercased() })
        if CheckInHeuristics.period(in: transcript) == nil, let p = RoutinePeriod(rawValue: draft.period) {
            result.period = p
        }
        result.usedModel = true
        return result
    }

    private static func extract(_ transcript: String, shelf: [ShelfEntry]) async throws -> CheckInDraft {
        let shelfList = shelf.map { entry in
            let actives = entry.activeNames.isEmpty ? "" : ", contains \(entry.activeNames.joined(separator: ", "))"
            return "- \(entry.name) (\(entry.brand.isEmpty ? "" : entry.brand + ", ")\(entry.category.label.lowercased())\(actives))"
        }.joined(separator: "\n")

        let session = LanguageModelSession(instructions: """
            You turn a short spoken skincare check-in into structured data. \
            Products must be copied exactly from the shelf list. Never add products that aren't on it.
            """)
        let prompt = "Shelf:\n\(shelfList)\n\nCheck-in:\n\(transcript)"
        return try await session.respond(to: prompt, generating: CheckInDraft.self).content
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}

@Generable
nonisolated struct CheckInDraft {
    @Guide(description: "Exact names from the shelf list of products the person used. Leave out anything they say they skipped.")
    var productsUsed: [String]

    @Guide(description: "One or two word tags for how their skin feels, like 'tight', 'oily', 'calm'. Empty if not mentioned.")
    var skinFeel: [String]

    @Guide(description: "Skin reactions written as 'type: area', like 'breakout: chin' or 'redness: cheeks'. Empty if none.")
    var reactions: [String]

    @Guide(description: "Which routine this is about.", .anyOf(["am", "pm", "unknown"]))
    var period: String
}

// Keyword rules. Always run, and the whole parser when Apple Intelligence is off.
nonisolated enum CheckInHeuristics {
    static let feelWords = [
        "tight", "dry", "oily", "greasy", "calm", "glowy", "smooth", "plump", "soft", "balanced",
        "irritated", "itchy", "flaky", "stinging", "burning", "sensitive", "dull", "bumpy",
    ]
    static let reactionWords: [(said: String, label: String)] = [
        ("breakout", "breakout"), ("breakouts", "breakout"), ("breaking out", "breakout"), ("broke out", "breakout"), ("pimple", "breakout"),
        ("zit", "breakout"), ("whitehead", "breakout"), ("redness", "redness"), ("rash", "rash"),
        ("irritation", "irritation"), ("peeling", "peeling"), ("bumps", "bumps"), ("purging", "purging"),
    ]
    static let areas = ["chin", "forehead", "cheeks", "cheek", "nose", "jawline", "jaw", "t zone", "temples", "neck", "mouth", "eyes"]
    static let negations = ["skipped", "skip", "didn t", "did not", "didnt", "no", "without", "not", "forgot"]

    static func period(in transcript: String) -> RoutinePeriod? {
        let t = norm(transcript)
        if ["this morning", "morning", "am routine", "a m"].contains(where: { has(t, $0) }) { return .am }
        if ["tonight", "night", "evening", "pm routine", "before bed", "p m"].contains(where: { has(t, $0) }) { return .pm }
        return nil
    }

    static func products(in transcript: String, shelf: [ShelfEntry]) -> [String] {
        let clauses = self.clauses(transcript)
        var used: [String] = []
        var skipped = Set<String>()

        for entry in shelf {
            // Specific mentions: name, brand, or an active it contains
            let specific = ([entry.name, entry.brand] + entry.activeNames).map(norm).filter { $0.count >= 3 }
            // "my sunscreen" only counts if there's exactly one sunscreen on the shelf
            let categoryOnly = shelf.filter { $0.category == entry.category }.count == 1
                ? categoryWords(entry.category) : []

            for clause in clauses where (specific + categoryOnly).contains(where: { has(clause, $0) }) {
                if isNegated(clause) { skipped.insert(entry.id) } else { used.append(entry.id) }
            }
        }
        var seen = Set<String>()
        return used.filter { !skipped.contains($0) && seen.insert($0).inserted }
    }

    static func skinFeel(in transcript: String) -> [String] {
        let clauses = self.clauses(transcript)
        return feelWords.filter { word in
            clauses.contains { has($0, word) && !has($0, "not \(word)") }
        }
    }

    static func reactions(in transcript: String) -> [String] {
        var out: [String] = []
        for clause in clauses(transcript) where !isNegated(clause) {
            guard let reaction = reactionWords.first(where: { has(clause, $0.said) }) else { continue }
            let area = areas.first { has(clause, $0) }
            let label = area.map { "\(reaction.label): \($0 == "cheek" ? "cheeks" : $0)" } ?? reaction.label
            if !out.contains(label) { out.append(label) }
        }
        return out
    }

    // MARK: - Helpers

    static func categoryWords(_ category: ProductCategory) -> [String] {
        switch category {
        case .sunscreen: ["sunscreen", "spf", "sunblock"]
        case .moisturizer: ["moisturizer", "moisturiser", "cream"]
        case .eyeCream: ["eye cream"]
        case .oil: ["face oil", "oil"]
        case .other: []
        default: [category.label.lowercased()]
        }
    }

    // Split on punctuation and "but", so "used the BHA but skipped retinol" keeps the negation local
    static func clauses(_ transcript: String) -> [String] {
        transcript
            .components(separatedBy: CharacterSet(charactersIn: ".,;!?\n"))
            .flatMap { $0.components(separatedBy: " but ") }
            .map(norm)
            .filter { !$0.isEmpty }
    }

    static func isNegated(_ clause: String) -> Bool {
        negations.contains { has(clause, $0) }
    }

    static func norm(_ s: String) -> String { IngredientDatabase.normalize(s) }

    // Whole-word match on normalized text
    static func has(_ text: String, _ phrase: String) -> Bool {
        (" " + text + " ").contains(" " + phrase + " ")
    }
}
