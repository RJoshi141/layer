import Foundation

// Product fields we want off a label, wherever they came from
nonisolated struct LabelFields: Sendable {
    var name = ""
    var brand = ""
    var category: ProductCategory = .other
    var paoMonths: Int?
    var statedActives: [String] = []   // "2% Salicylic Acid"
}

// Regex rules. Always runs, and is the full fallback when Apple Intelligence isn't available.
nonisolated enum HeuristicExtractor {
    static func extract(from lines: [String]) -> LabelFields {
        extract(perImage: [lines])
    }

    static func extract(perImage: [[String]]) -> LabelFields {
        let lines = perImage.flatMap { $0 }
        let text = lines.joined(separator: " ")
        // Ingredient names ("Jojoba Seed Oil", "Shea Butter Cream") would mislead the type check,
        // so read everything else on every photo: front, claims, directions
        let outside = perImage
            .map { INCIParser.textOutsideIngredients($0.joined(separator: " ")) }
            .joined(separator: " ")

        var fields = LabelFields()
        fields.paoMonths = paoMonths(in: text)
        fields.statedActives = statedActives(in: text)
        fields.category = category(in: outside.lowercased())
        fields.name = lines.first(where: looksLikeName) ?? ""
        return fields
    }

    // The open-jar icon OCRs as "12M" or "12 M"
    static func paoMonths(in text: String) -> Int? {
        guard let r = text.range(of: #"\b\d{1,2}\s?M\b"#, options: .regularExpression),
              let n = Int(text[r].filter(\.isNumber)),
              (1...60).contains(n) else { return nil }
        return n
    }

    static func statedActives(in text: String) -> [String] {
        let pattern = #"\d{1,2}(\.\d+)?\s?%\s?[A-Za-z][A-Za-z\-]+( [A-Za-z][A-Za-z\-]+){0,2}"#
        var found: [String] = []
        var cursor = text.startIndex
        while cursor < text.endIndex,
              let r = text.range(of: pattern, options: .regularExpression, range: cursor..<text.endIndex) {
            found.append(String(text[r]))
            cursor = r.upperBound
        }
        return found
    }

    static func category(in text: String) -> ProductCategory {
        if claimsSPF(text) { return .sunscreen }

        // Directions name other products: "apply after cleansing", "follow with moisturizer".
        // Drop those so a serum label doesn't read as a cleanser or a moisturizer.
        let cleaned = text.replacingOccurrences(
            of: #"(after|before|follow with|followed by|then|under|over|with your)\s+(\w+\s+){0,2}?(cleans\w*|serums?|moisturi\w*|toners?|sunscreen|spf|creams?|oils?)"#,
            with: " ",
            options: .regularExpression
        )

        // Earliest mention wins: the product name sits near the top of a label, descriptions come later.
        // List order only breaks ties.
        let keywords: [(ProductCategory, [String])] = [
            (.sunscreen, ["mineral sunscreen", "sunscreen lotion", "sunscreen fluid", "sunscreen stick"]),
            (.eyeCream, ["eye cream", "eye serum", "eye gel", "eye balm"]),
            (.cleanser, ["cleanser", "cleansing", "face wash", "facial wash", "micellar"]),
            (.mask, ["mask"]),
            (.toner, ["toner", "essence", "tonic", "mist"]),
            (.serum, ["serum", "ampoule", "booster", "concentrate", "elixir", "drops"]),
            (.treatment, ["treatment", "exfoliant", "peeling solution", "spot gel"]),
            (.oil, ["face oil", "facial oil"]),
            (.moisturizer, ["moisturizer", "moisturiser", "cream", "creme", "crème", "lotion", "balm", "gel-cream", "hydrator"]),
        ]
        var best: (category: ProductCategory, position: Int, priority: Int)?
        for (priority, (category, words)) in keywords.enumerated() {
            for word in words {
                // Whole words only, so "mist" doesn't fire on "chemist"
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
                guard let r = cleaned.range(of: pattern, options: .regularExpression) else { continue }
                let position = cleaned.distance(from: cleaned.startIndex, to: r.lowerBound)
                if best == nil || position < best!.position || (position == best!.position && priority < best!.priority) {
                    best = (category, position, priority)
                }
            }
        }
        if let best { return best.category }

        // No product-type word anywhere: the directions usually give it away
        let directions: [(ProductCategory, [String])] = [
            (.cleanser, ["rinse", "lather", "wash off"]),
            (.serum, ["few drops", "2-3 drops", "dropper", "pipette"]),
            (.toner, ["cotton pad", "sweep over"]),
            (.moisturizer, ["apply generously", "massage into skin", "final step", "last step"]),
        ]
        if let hit = directions.first(where: { rule in rule.1.contains { text.contains($0) } }) {
            return hit.0
        }

        // Jars and tubs are sold by weight ("50 g"), serums and toners by volume ("30 ml")
        if text.range(of: #"\b\d+(\.\d+)?\s?g\b"#, options: .regularExpression) != nil, !text.contains("ml") {
            return .moisturizer
        }
        return .other
    }

    // "SPF 30" on the front means sunscreen. "Use SPF 30 or higher" in a retinol warning doesn't.
    static func claimsSPF(_ text: String) -> Bool {
        let advice = ["use", "apply", "wear", "alert", "sunburn", "with a"]
        var cursor = text.startIndex
        while cursor < text.endIndex,
              let r = text.range(of: #"spf\s?\d{2}"#, options: .regularExpression, range: cursor..<text.endIndex) {
            // Spelled out on purpose: `a ?? b..<c` parses as `a ?? (b..<c)` and chokes the type checker
            let beforeStart = text.index(r.lowerBound, offsetBy: -30, limitedBy: text.startIndex) ?? text.startIndex
            let afterEnd = text.index(r.upperBound, offsetBy: 15, limitedBy: text.endIndex) ?? text.endIndex
            let before = String(text[beforeStart..<r.lowerBound])
            let after = String(text[r.upperBound..<afterEnd])
            if !advice.contains(where: { before.contains($0) }) && !after.contains("or higher") { return true }
            cursor = r.upperBound
        }
        return false
    }

    // Weak guess. The on-device model does much better at this.
    private static func looksLikeName(_ line: String) -> Bool {
        let letters = line.filter(\.isLetter).count
        return (3...40).contains(line.count)
            && letters >= line.count / 2
            && line.range(of: INCIParser.headerPattern, options: .regularExpression) == nil
    }
}
