import Foundation

// INCI names follow strict conventions, so the name alone says a lot:
// "...Seed Oil" is a plant oil, "...Leaf Oil" is usually an essential oil, "PEG-..." is an emulsifier.
// Used for anything the bundled database doesn't know yet. Rules only, so it works on every iPhone.
nonisolated enum IngredientClassifier {
    static func classify(_ raw: String) -> IngredientReference? {
        let n = IngredientDatabase.normalize(raw)
        // Skip obvious OCR junk: too short, too long, or not really words
        let words = n.split(separator: " ")
        guard n.filter(\.isLetter).count >= 3, words.count <= 8, raw.count <= 70 else { return nil }

        let guess = self.guess(n, words: words.map(String.init))
            ?? (.other, [], "Added from your scans. Layer doesn't know what this one does yet.")

        return IngredientReference(
            key: IngredientDatabase.learnedKey(for: raw),
            name: raw,
            aliases: [],
            role: guess.role,
            tags: guess.tags,
            summary: guess.summary
        )
    }

    typealias Guess = (role: IngredientReference.Role, tags: [String], summary: String)

    // Order matters: specific actives first, essential oils before plant oils,
    // preservatives and salts before the generic "-ate" ester rule
    static func guess(_ n: String, words: [String]) -> Guess? {
        let first = words.first ?? ""
        func ends(_ suffixes: String...) -> Bool { suffixes.contains { n.hasSuffix($0) } }
        func has(_ parts: String...) -> Bool { parts.contains { n.contains($0) } }

        if n.range(of: #"^ci \d{5}"#, options: .regularExpression) != nil {
            return (.base, ["colorant"], "Cosmetic colorant.")
        }
        if has("peptide") { return (.active, ["peptide"], "A peptide. Usually there for firmness or repair.") }
        if has("ceramide") { return (.barrier, ["ceramide"], "A ceramide. Helps repair the skin barrier.") }
        if has("retin") { return (.active, ["retinoid"], "Looks like a retinoid (vitamin A family). Use at night.") }
        if has("ascorb") { return (.active, ["vitamin-c"], "A form of vitamin C.") }
        if has("hyaluron") { return (.hydrator, ["humectant"], "A form of hyaluronic acid. Holds water in skin.") }
        if has("tocopher") { return (.antioxidant, [], "A form of vitamin E. Antioxidant.") }
        if has("panthen") { return (.soothing, [], "A form of vitamin B5. Soothing.") }
        if has("isothiazolinone", "hydantoin") { return (.caution, ["sensitizer"], "Preservative with a higher allergy rate.") }

        // Essential oils come from leaves, flowers, peels and bark. Carrier oils come from seeds and fruit.
        if ends("leaf oil", "flower oil", "peel oil", "bark oil", "herb oil", "root oil", "wood oil", "stem oil") || has("essential oil") {
            return (.caution, ["essential-oil", "fragrance"], "Looks like an essential oil. Can irritate sensitive skin.")
        }
        if ends("oil", "butter") { return (.barrier, ["emollient"], "A plant oil or butter. Softens and nourishes.") }
        if ends("wax") { return (.barrier, ["occlusive"], "A wax. Thickens and seals in moisture.") }
        if ends("extract", "leaf water", "flower water", "fruit water", "juice") {
            return (.botanical, [], "A plant extract.")
        }
        if has("ferment", "filtrate", "lysate") { return (.hydrator, ["humectant"], "A ferment. Usually hydrating.") }
        if ends("cone") || has("siloxane", "silsesquioxane") {
            return (.barrier, ["silicone"], "A silicone. Smooths and adds slip.")
        }
        if ends("alcohol"), ["cetyl", "stearyl", "cetearyl", "behenyl", "myristyl", "lauryl", "arachidyl", "oleyl", "isostearyl"].contains(first) {
            return (.base, ["fatty-alcohol"], "A fatty alcohol that thickens. Not drying.")
        }
        if ends("glycol") || words.last?.hasSuffix("diol") == true {
            return (.hydrator, ["humectant"], "A glycol. Light humectant and solvent.")
        }
        if has("paraben", "phenoxy") || ends("benzoate", "sorbate") {
            return (.preservative, [], "A preservative.")
        }
        if has("sulfate") { return (.cleanser, ["surfactant"], "A foaming cleanser.") }
        if ends("glucoside", "betaine", "taurate", "isethionate", "sarcosinate", "glutamate", "sultaine", "amphoacetate", "glycinate") {
            return (.cleanser, ["surfactant"], "A cleansing agent.")
        }
        if first == "peg" || first == "ppg" || has("polysorbate", "sorbitan", "polyglyceryl", "glyceryl")
            || n.range(of: #"[a-z]+eth \d+"#, options: .regularExpression) != nil {
            return (.base, ["emulsifier"], "Emulsifier. Keeps oil and water mixed.")
        }
        if ends("gum", "carbomer", "crosspolymer", "copolymer", "cellulose", "polymer") || has("acrylate") {
            return (.base, ["thickener"], "Thickener or film-former.")
        }
        if ["sodium", "potassium", "magnesium", "calcium", "zinc", "disodium", "trisodium", "tetrasodium"].contains(first) {
            return (.base, [], "A salt. Usually adjusts pH or stabilizes the formula.")
        }
        if ends("ic acid"), ["stearic", "palmitic", "myristic", "lauric", "oleic", "linoleic", "linolenic", "behenic"].contains(first) {
            return (.barrier, ["emollient"], "A fatty acid. Supports the skin barrier.")
        }
        if ends("acid") { return (.base, [], "An acid. In small amounts it usually just adjusts pH.") }
        // Most leftover "-ate" names are emollient esters (Ethylhexyl Palmitate, Isononyl Isononanoate...)
        if words.last?.hasSuffix("ate") == true { return (.barrier, ["emollient"], "An emollient. Gives a smooth feel.") }
        if ends("powder", "starch", "clay") { return (.base, ["absorbent"], "Absorbs oil and softens texture.") }
        return nil
    }
}
