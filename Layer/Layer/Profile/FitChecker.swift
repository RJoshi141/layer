import Foundation

// Personal layer on top of the ingredient data: "good for your breakouts", "has fragrance and you're sensitive".
// Same philosophy as ConflictChecker: plain rules you can read, no model guessing.
nonisolated struct FitChecker {
    let profile: SkinProfile

    // `label` is the product's ingredient list in label order (nil = not recognized).
    // Order matters: alcohol at #2 is a different product than alcohol at #30.
    func findings(forLabel label: [IngredientReference?]) -> [Finding] {
        let refs = label.compactMap { $0 }
        var out: [Finding] = []

        // What it's good for, based on the concerns they picked
        for concern in profile.concerns {
            let helpers = unique(refs.filter { $0.hasAnyTag(concern.helpfulTags) })
            // Glycerin is in everything, so dryness needs more than one hydrating ingredient to count
            let needed = concern == .dryness ? 2 : 1
            guard helpers.count >= needed else { continue }
            out.append(Finding(
                id: "good-\(concern.rawValue)",
                severity: .fine,
                title: "Good for \(concern.label.lowercased())",
                advice: "Has \(list(helpers.prefix(3).map(\.name)))."
            ))
        }

        // Heads-ups based on skin type, sensitivity and what they want to avoid
        let fragrance = refs.filter { $0.tags.contains("fragrance") && !$0.tags.contains("essential-oil") }
        if !fragrance.isEmpty, profile.isSensitive || profile.avoid.contains(.fragrance) {
            out.append(Finding(
                id: "fit-fragrance",
                severity: .caution,
                title: "Contains fragrance",
                advice: profile.avoid.contains(.fragrance)
                    ? "You said you'd rather avoid fragrance. This has \(list(fragrance.prefix(3).map(\.name)))."
                    : "Fragrance is a common trigger for sensitive skin. Patch test first."
            ))
        }

        let oils = refs.filter { $0.tags.contains("essential-oil") }
        if !oils.isEmpty, profile.isSensitive || profile.avoid.contains(.essentialOils) {
            out.append(Finding(
                id: "fit-essential-oils",
                severity: .caution,
                title: "Contains essential oils",
                advice: "Has \(list(oils.prefix(3).map(\.name))). These can irritate, especially with sun."
            ))
        }

        // Drying alcohol only matters when it's high in the list
        if let index = label.firstIndex(where: { $0?.tags.contains("drying-alcohol") == true }),
           index < 6 || profile.avoid.contains(.alcohol),
           profile.skinType == .dry || profile.isSensitive || profile.avoid.contains(.alcohol) {
            out.append(Finding(
                id: "fit-alcohol",
                severity: .caution,
                title: index < 6 ? "Alcohol near the top" : "Contains drying alcohol",
                advice: index < 6
                    ? "It's ingredient #\(index + 1), so there's a fair amount. Can feel drying on \(profile.skinType == .dry ? "dry" : "sensitive") skin."
                    : "It's low in the list (#\(index + 1)), so likely a small amount."
            ))
        }

        if refs.contains(where: { $0.tags.contains("harsh-surfactant") }), profile.skinType == .dry || profile.isSensitive {
            out.append(Finding(
                id: "fit-surfactant",
                severity: .caution,
                title: "Strong cleanser",
                advice: "Has sodium lauryl sulfate, which can strip dry or sensitive skin."
            ))
        }

        if refs.contains(where: { $0.tags.contains("sensitizer") }), profile.isSensitive {
            out.append(Finding(
                id: "fit-sensitizer",
                severity: .caution,
                title: "Common allergen",
                advice: "Has a preservative with a higher allergy rate. Patch test first."
            ))
        }

        let strong = refs.contains { $0.hasAnyTag(["retinoid", "exfoliant"]) }
        if strong, profile.experience == .new || profile.sensitivity == .often {
            out.append(Finding(
                id: "fit-start-slow",
                severity: .caution,
                title: "Start slow",
                advice: profile.experience == .new
                    ? "New to retinoids or acids? Use it 2 or 3 nights a week and build up."
                    : "Your skin reacts easily. Start 2 nights a week and watch how it feels."
            ))
        }

        // Cautions first, then the good news
        return out.sorted { $0.severity == .caution && $1.severity == .fine }
    }

    // Routine-wide check: lots of strong actives on reactive or new skin
    func routineFindings(_ items: [RoutineItem]) -> [Finding] {
        let strong = items.filter { !$0.tags.isDisjoint(with: ["retinoid", "exfoliant"]) }
        guard strong.count >= 2, profile.isSensitive || profile.experience == .new else { return [] }
        return [Finding(
            id: "fit-routine-strong",
            severity: .caution,
            title: "A lot for your skin",
            advice: "\(strong.count) strong actives in one routine. For \(profile.experience == .new ? "skin that's new to actives" : "reactive skin"), try one per night."
        )]
    }

    private func unique(_ refs: [IngredientReference]) -> [IngredientReference] {
        var seen = Set<String>()
        return refs.filter { seen.insert($0.key).inserted }
    }

    private func list(_ names: [String]) -> String {
        ListFormatter.localizedString(byJoining: names)
    }
}

nonisolated extension IngredientReference {
    // `tags` is an array (it's decoded from JSON), so no Set.isDisjoint here
    func hasAnyTag(_ wanted: Set<String>) -> Bool {
        tags.contains { wanted.contains($0) }
    }
}
