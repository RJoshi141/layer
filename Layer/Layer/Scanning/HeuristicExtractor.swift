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
        let text = lines.joined(separator: " ")
        // Category words in the ingredient list ("Jojoba Seed Oil") would mislead us, so only read the front
        let front = text.range(of: INCIParser.headerPattern, options: .regularExpression)
            .map { String(text[..<$0.lowerBound]) } ?? text

        var fields = LabelFields()
        fields.paoMonths = paoMonths(in: text)
        fields.statedActives = statedActives(in: text)
        fields.category = category(in: front.lowercased())
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

    static func category(in front: String) -> ProductCategory {
        // Order matters: "cleansing oil" is a cleanser, "eye cream" is an eye cream
        let rules: [(ProductCategory, [String])] = [
            (.sunscreen, ["sunscreen", "spf", "sun screen", "uv defense"]),
            (.cleanser, ["cleanser", "cleansing", "face wash", "facial wash", "micellar"]),
            (.eyeCream, ["eye cream", "eye serum", "eye gel"]),
            (.mask, ["mask"]),
            (.toner, ["toner", "essence", "tonic"]),
            (.serum, ["serum", "ampoule", "booster"]),
            (.treatment, ["treatment", "spot", "peel", "exfoliant", "retinol"]),
            (.oil, ["face oil", "facial oil"]),
            (.moisturizer, ["moisturizer", "moisturiser", "cream", "lotion", "balm"]),
        ]
        return rules.first { rule in rule.1.contains { front.contains($0) } }?.0 ?? .other
    }

    // Weak guess. The on-device model does much better at this.
    private static func looksLikeName(_ line: String) -> Bool {
        let letters = line.filter(\.isLetter).count
        return (3...40).contains(line.count)
            && letters >= line.count / 2
            && line.range(of: INCIParser.headerPattern, options: .regularExpression) == nil
    }
}
