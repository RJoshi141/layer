import Foundation

// Pulls the ingredient section out of raw OCR lines and splits it into individual INCI names.
// Deterministic on purpose: an LLM can "helpfully" invent ingredients, a parser can't.
nonisolated enum INCIParser {
    static let headerPattern = #"(?i)\b(ingredients|ingrédients|ingredientes|inci)\b\s*[:：]?"#

    // Where an ingredient list usually ends on a label
    static let terminators = [
        "may contain", "+/-", "inactive", "purpose", "warning", "caution", "directions", "how to use",
        "made in", "manufactured", "distributed", "for external use", "keep out of reach", "store in", "net wt", "lot:",
    ]

    static func parse(lines: [String]) -> [String] {
        let text = joinLines(lines)
        var seen = Set<String>()
        // Front-of-pack "Key ingredients:" blurbs can repeat names from the real list
        return sections(in: text)
            .flatMap { split($0) }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    // Rejoins words that OCR broke across lines. "Sodium Hyal-" + "uronate" → "Sodium Hyaluronate"
    static func joinLines(_ lines: [String]) -> String {
        var out = ""
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if out.hasSuffix("-"), let first = line.first, first.isLowercase {
                out.removeLast()
                out += line
            } else if out.isEmpty || out.hasSuffix("-") {
                out += line   // "PEG-" + "40" keeps its hyphen
            } else {
                out += " " + line
            }
        }
        return out
    }

    // Labels can have more than one list (US sunscreens: "Active ingredients" + "Inactive ingredients")
    static func sections(in text: String) -> [Substring] {
        var headers: [Range<String.Index>] = []
        var cursor = text.startIndex
        while cursor < text.endIndex,
              let r = text.range(of: headerPattern, options: .regularExpression, range: cursor..<text.endIndex) {
            headers.append(r)
            cursor = r.upperBound
        }

        guard !headers.isEmpty else {
            // No header (OCR missed it or the label skips it). Comma-heavy text is probably the list.
            return text.filter { $0 == "," }.count >= 4 ? [cutAtTerminator(text[...])] : []
        }

        return headers.indices.map { i in
            let end = i + 1 < headers.count ? headers[i + 1].lowerBound : text.endIndex
            return cutAtTerminator(text[headers[i].upperBound..<end])
        }
    }

    static func cutAtTerminator(_ body: Substring) -> Substring {
        let cut = terminators
            .compactMap { body.range(of: $0, options: .caseInsensitive)?.lowerBound }
            .min() ?? body.endIndex
        return body[..<cut]
    }

    static func split(_ section: Substring) -> [String] {
        let chars = Array(section)
        var items: [String] = []
        var current = ""
        var depth = 0

        for (i, c) in chars.enumerated() {
            switch c {
            case "(", "[":
                depth += 1
                current.append(c)
            case ")", "]":
                depth = max(0, depth - 1)
                current.append(c)
            case ",", ";", "•", "·", "|":
                // "1,2-Hexanediol" is one ingredient
                let betweenDigits = c == "," && i > 0 && i + 1 < chars.count
                    && chars[i - 1].isNumber && chars[i + 1].isNumber
                // An unclosed "(" from bad OCR shouldn't swallow the rest of the list
                let runaway = depth > 0 && current.count > 80
                if (depth == 0 || runaway) && !betweenDigits {
                    items.append(current)
                    current = ""
                    depth = 0
                } else {
                    current.append(c)
                }
            default:
                current.append(c)
            }
        }
        items.append(current)
        return items.compactMap(clean)
    }

    static func clean(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".*†‡:•· ").union(.whitespacesAndNewlines))
        let collapsed = trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count >= 2, collapsed.contains(where: \.isLetter) else { return nil }
        return collapsed
    }
}
