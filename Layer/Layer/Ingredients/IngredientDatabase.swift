import Foundation
import Synchronization

nonisolated final class IngredientDatabase: Sendable {
    static let shared = IngredientDatabase(bundle: .main, learnedURL: defaultLearnedURL)

    // Ingredients learned from your scans live next to the app's data, not in the bundle
    static var defaultLearnedURL: URL {
        URL.applicationSupportDirectory.appending(path: "learned_ingredients.json")
    }

    let ingredients: [IngredientReference]   // bundled with the app
    let rules: [ConflictRule]
    private let byKey: [String: IngredientReference]
    private let index: [String: IngredientReference]   // normalized name or alias → reference
    private let learned: Mutex<[String: IngredientReference]>   // learned key → reference
    private let learnedURL: URL?

    convenience init(bundle: Bundle, learnedURL: URL? = nil) {
        let learned: [IngredientReference] = learnedURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([IngredientReference].self, from: $0) } ?? []
        self.init(
            ingredients: Self.load("ingredients", from: bundle) ?? [],
            rules: Self.load("conflict_rules", from: bundle) ?? [],
            learned: learned,
            learnedURL: learnedURL
        )
    }

    init(ingredients: [IngredientReference], rules: [ConflictRule], learned: [IngredientReference] = [], learnedURL: URL? = nil) {
        self.ingredients = ingredients
        self.rules = rules
        self.byKey = Dictionary(ingredients.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        self.learned = Mutex(Dictionary(learned.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last }))
        self.learnedURL = learnedURL

        var index: [String: IngredientReference] = [:]
        for ref in ingredients {
            for name in [ref.name] + ref.aliases {
                let key = Self.normalize(name)
                if index[key] == nil { index[key] = ref }
            }
        }
        self.index = index
    }

    var learnedIngredients: [IngredientReference] {
        learned.withLock { Array($0.values) }
    }

    func reference(for key: String) -> IngredientReference? {
        if let bundled = byKey[key] { return bundled }
        return learned.withLock { $0[key] }
    }

    // Labels are messy: "Water (Aqua)", "Water/Aqua/Eau", "Zinc Oxide 20%", plus OCR typos
    func match(_ raw: String) -> IngredientReference? {
        let candidates = Self.candidates(for: raw)
        for candidate in candidates {
            if let hit = index[Self.normalize(candidate)] { return hit }
        }
        // Something you scanned before that the bundled list didn't know
        let learnedKeys = candidates.map(Self.learnedKey(for:))
        let learnedHit = learned.withLock { dict -> IngredientReference? in
            for key in learnedKeys {
                if let hit = dict[key] { return hit }
            }
            return nil
        }
        if let learnedHit { return learnedHit }
        return fuzzyMatch(Self.normalize(raw))
    }

    // Adds (or reclassifies) ingredients and saves them, so the next scan already knows them
    func learn(_ refs: [IngredientReference]) {
        guard !refs.isEmpty else { return }
        let snapshot = learned.withLock { dict -> [IngredientReference] in
            for ref in refs { dict[ref.key] = ref }
            return Array(dict.values)
        }
        guard let learnedURL else { return }
        do {
            try FileManager.default.createDirectory(at: learnedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: learnedURL, options: .atomic)
        } catch {
            assertionFailure("Couldn't save learned ingredients: \(error)")
        }
    }

    static func learnedKey(for raw: String) -> String {
        "learned-" + normalize(raw).replacingOccurrences(of: " ", with: "-")
    }

    private func fuzzyMatch(_ normalized: String) -> IngredientReference? {
        // Short names fuzz into false positives ("urea" vs "urca"), so only fuzz longer ones
        guard normalized.count >= 6 else { return nil }
        let budget = max(1, normalized.count / 7)
        var best: (ref: IngredientReference, distance: Int)?
        for (key, ref) in index where abs(key.count - normalized.count) <= budget {
            let d = Self.levenshtein(key, normalized)
            if d <= budget, d < (best?.distance ?? .max) { best = (ref, d) }
        }
        return best?.ref
    }

    // MARK: - Helpers

    static func candidates(for raw: String) -> [String] {
        var out = [raw]
        // Drop strength markers: "Zinc Oxide 20%" → "Zinc Oxide"
        let noPercent = raw.replacingOccurrences(of: #"\s*\d+(\.\d+)?\s*%"#, with: "", options: .regularExpression)
        out.append(noPercent)
        // "Water (Aqua)" → "Water", "Aqua"
        if let open = noPercent.firstIndex(of: "("), let close = noPercent.lastIndex(of: ")"), open < close {
            out.append(String(noPercent[..<open]) + String(noPercent[noPercent.index(after: close)...]))
            out.append(String(noPercent[noPercent.index(after: open)..<close]))
        }
        // "Water/Aqua/Eau" → each part
        if noPercent.contains("/") {
            out += noPercent.split(separator: "/").map(String.init)
        }
        return out
    }

    // Lowercase, strip accents and punctuation, collapse spaces. "1,2-Hexanediol" → "1 2 hexanediol"
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let spaced = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }

    private static func load<T: Decodable>(_ name: String, from bundle: Bundle) -> T? {
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("Missing \(name).json in bundle")
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            assertionFailure("Bad \(name).json: \(error)")
            return nil
        }
    }
}
