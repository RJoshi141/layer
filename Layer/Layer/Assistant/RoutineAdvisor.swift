import Foundation

// Everything the advisor needs to know about one product, as plain values (testable without SwiftData)
nonisolated struct AdvisorProduct: Identifiable, Sendable {
    let id: String
    let name: String
    let category: ProductCategory
    let tags: Set<String>
    let activeNames: [String]
    let isExpired: Bool
    let inAM: Bool
    let inPM: Bool
    let cautions: [String]          // personal heads-ups from FitChecker, e.g. "Contains fragrance"
    let helps: [SkinConcern]        // concerns from the user's profile this product targets

    func isIn(_ period: RoutinePeriod) -> Bool { period == .am ? inAM : inPM }

    var routineItem: RoutineItem {
        RoutineItem(id: id, name: name, category: category, tags: tags, isExpired: isExpired)
    }

    // Where this product naturally belongs, if anywhere
    var homePeriod: RoutinePeriod? {
        if !tags.isDisjoint(with: ["retinoid", "exfoliant", "aha", "bha"]) { return .pm }
        if tags.contains("vitamin-c") || category == .sunscreen { return .am }
        return nil
    }
}

nonisolated enum AdvisorAction: Sendable, Equatable {
    case add(productID: String, to: RoutinePeriod)
    case remove(productID: String, from: RoutinePeriod)
    case move(productID: String, from: RoutinePeriod, to: RoutinePeriod)
    case swap(remove: String, add: String, period: RoutinePeriod)

    var label: String {
        switch self {
        case .add(_, let period): "Add to \(period.label)"
        case .remove: "Remove"
        case .move(_, _, let to): "Move to \(to.label)"
        case .swap: "Swap"
        }
    }
}

nonisolated struct Suggestion: Identifiable, Sendable {
    nonisolated enum Kind: Int, Sendable { case fix, swap, gap, tip, good }   // raw value = display order

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    var action: AdvisorAction?
}

nonisolated extension RoutinePeriod {
    var label: String { self == .am ? "morning" : "night" }
    var other: RoutinePeriod { self == .am ? .pm : .am }
}

nonisolated extension SkinConcern {
    // What to shop for when nothing on the shelf covers it. Ingredients, never brands.
    var lookFor: String {
        switch self {
        case .breakouts: "salicylic acid (BHA), benzoyl peroxide, azelaic acid or niacinamide"
        case .darkSpots: "vitamin C, azelaic acid, niacinamide or tranexamic acid"
        case .fineLines: "a retinoid like retinol, or peptides"
        case .redness: "azelaic acid, centella (cica), niacinamide or panthenol"
        case .dryness: "ceramides, glycerin, hyaluronic acid or squalane"
        case .texture: "an AHA like glycolic or lactic acid, or a retinoid"
        case .pores: "salicylic acid (BHA), niacinamide or a retinoid"
        case .dullness: "vitamin C or a gentle AHA/PHA"
        }
    }
}

// Rule-based routine review. Every suggestion comes with a reason, and most with a one-tap fix.
// The on-device model (when there is one) explains these; it never invents its own.
nonisolated struct RoutineAdvisor {
    let products: [AdvisorProduct]
    let profile: SkinProfile?
    let rules: [ConflictRule]

    func suggestions(for period: RoutinePeriod) -> [Suggestion] {
        let routine = products.filter { $0.isIn(period) }
        guard !routine.isEmpty else {
            return [Suggestion(
                id: "empty",
                kind: .gap,
                title: "Start with the basics",
                detail: period == .am
                    ? "A morning routine can be as simple as cleanser, moisturizer and sunscreen."
                    : "A night routine can be as simple as cleanser and moisturizer. Add one active once that feels easy."
            )]
        }

        var out: [Suggestion] = []
        out += conflictFixes(routine, period: period)
        out += expiredSwaps(routine, period: period)
        out += fitSwaps(routine, period: period)
        out += missingEssentials(routine, period: period)
        out += concernGaps(period: period)
        out += activeLoad(routine)

        if !out.contains(where: { $0.kind == .fix }) {
            out += strengths(routine)
        }
        return out.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    // MARK: - Fixes

    private func conflictFixes(_ routine: [AdvisorProduct], period: RoutinePeriod) -> [Suggestion] {
        var out: [Suggestion] = []
        var handled = Set<String>()

        if period == .am {
            for product in routine where product.tags.contains("retinoid") {
                handled.insert(product.id)
                out.append(Suggestion(
                    id: "retinoid-am-\(product.id)",
                    kind: .fix,
                    title: "Move \(product.name) to night",
                    detail: "Retinoids break down in sunlight and make skin more sun-sensitive. They work best at night.",
                    action: .move(productID: product.id, from: .am, to: .pm)
                ))
            }
        }

        for i in routine.indices {
            for j in routine.indices where j > i {
                let a = routine[i], b = routine[j]
                guard let rule = rules.first(where: { $0.severity != .fine && ConflictChecker.matches($0, a.routineItem, b.routineItem) }) else { continue }

                let mover = whichToMove(a, b, from: period)
                guard !handled.contains(mover.id) else { continue }
                handled.insert(mover.id)

                // Only offer the move if it doesn't just create a clash in the other routine
                let otherRoutine = products.filter { $0.isIn(period.other) && $0.id != mover.id }.map(\.routineItem)
                let safeToMove = ConflictChecker.clashes(of: mover.routineItem, with: otherRoutine, rules: rules).isEmpty

                out.append(Suggestion(
                    id: "conflict-\(rule.id)-\(mover.id)",
                    kind: .fix,
                    title: "Split up \(a.name) and \(b.name)",
                    detail: rule.advice + (safeToMove
                        ? " Moving \(mover.name) to your \(period.other.label) routine keeps both."
                        : " Your \(period.other.label) routine clashes with it too, so use them on alternate days."),
                    action: safeToMove ? .move(productID: mover.id, from: period, to: period.other) : nil
                ))
            }
        }
        return out
    }

    // Retinoids and acids go to night, vitamin C to morning. Otherwise move the later one.
    private func whichToMove(_ a: AdvisorProduct, _ b: AdvisorProduct, from period: RoutinePeriod) -> AdvisorProduct {
        if a.homePeriod == period.other { return a }
        if b.homePeriod == period.other { return b }
        return b
    }

    private func expiredSwaps(_ routine: [AdvisorProduct], period: RoutinePeriod) -> [Suggestion] {
        routine.filter(\.isExpired).map { product -> Suggestion in
            if let replacement = alternative(for: product, period: period) {
                return Suggestion(
                    id: "expired-\(product.id)",
                    kind: .swap,
                    title: "Swap \(product.name) for \(replacement.name)",
                    detail: "\(product.name) is past its date, so its actives are weaker and it can irritate. \(replacement.name) is the same type and still fresh.",
                    action: .swap(remove: product.id, add: replacement.id, period: period)
                )
            }
            let actives = product.activeNames.prefix(2).joined(separator: " and ")
            return Suggestion(
                id: "expired-\(product.id)",
                kind: .swap,
                title: "Replace \(product.name)",
                detail: "It's past its date. Look for a new \(product.category.label.lowercased())"
                    + (actives.isEmpty ? "." : " with \(actives).")
            )
        }
    }

    private func fitSwaps(_ routine: [AdvisorProduct], period: RoutinePeriod) -> [Suggestion] {
        routine.filter { !$0.cautions.isEmpty && !$0.isExpired }.map { product -> Suggestion in
            let reason = product.cautions.prefix(2).joined(separator: ", ").lowercased()
            if let gentler = alternative(for: product, period: period), gentler.cautions.count < product.cautions.count {
                return Suggestion(
                    id: "fit-\(product.id)",
                    kind: .swap,
                    title: "Try \(gentler.name) instead of \(product.name)",
                    detail: "Based on your skin profile, \(product.name) has a heads-up (\(reason)). \(gentler.name) is the same type with fewer.",
                    action: .swap(remove: product.id, add: gentler.id, period: period)
                )
            }
            return Suggestion(
                id: "fit-\(product.id)",
                kind: .tip,
                title: "Keep an eye on \(product.name)",
                detail: "Based on your skin profile: \(reason). If your skin reacts, it's the first one to pause."
            )
        }
    }

    // MARK: - Gaps

    private func missingEssentials(_ routine: [AdvisorProduct], period: RoutinePeriod) -> [Suggestion] {
        var out: [Suggestion] = []
        let has = { (category: ProductCategory) in routine.contains { $0.category == category } }

        if period == .pm, !has(.cleanser) {
            out.append(essential(.cleanser, period: period,
                                 why: "Washing off sunscreen and the day helps everything after it work better.",
                                 generic: "Add a gentle cleanser as the first step at night."))
        }
        if !has(.moisturizer), !has(.oil) {
            out.append(essential(.moisturizer, period: period,
                                 why: "A moisturizer locks in the steps before it and protects your barrier.",
                                 generic: "Add a moisturizer as the last step\(period == .am ? " before sunscreen" : "")."))
        }
        let hasSPF = routine.contains { $0.category == .sunscreen || !$0.tags.isDisjoint(with: ["spf-mineral", "spf-chemical"]) }
        if period == .am, !hasSPF {
            out.append(essential(.sunscreen, period: period,
                                 why: "Daily SPF is the single biggest thing for dark spots and aging, and a must if you use acids or retinoids.",
                                 generic: "Add a broad-spectrum SPF 30 or higher as the last step every morning."))
        }
        return out
    }

    private func essential(_ category: ProductCategory, period: RoutinePeriod, why: String, generic: String) -> Suggestion {
        let candidate = products.first { $0.category == category && !$0.isIn(period) && !$0.isExpired }
        return Suggestion(
            id: "missing-\(category.rawValue)-\(period.rawValue)",
            kind: .gap,
            title: candidate.map { "Add \($0.name)" } ?? "No \(category.label.lowercased()) in this routine",
            detail: candidate == nil ? "\(why) \(generic)" : "\(why) It's already on your shelf.",
            action: candidate.map { AdvisorAction.add(productID: $0.id, to: period) }
        )
    }

    private func concernGaps(period: RoutinePeriod) -> [Suggestion] {
        guard let profile else { return [] }
        let inUse = products.filter { $0.inAM || $0.inPM }

        return profile.concerns.compactMap { concern -> Suggestion? in
            guard !inUse.contains(where: { $0.helps.contains(concern) }) else { return nil }

            if let helper = products.first(where: { $0.helps.contains(concern) && !$0.inAM && !$0.inPM && !$0.isExpired }) {
                let target = helper.homePeriod ?? period
                return Suggestion(
                    id: "concern-\(concern.rawValue)",
                    kind: .gap,
                    title: "Add \(helper.name) for \(concern.label.lowercased())",
                    detail: "Nothing in your routines targets \(concern.label.lowercased()) yet, and \(helper.name) does"
                        + (helper.activeNames.isEmpty ? "." : " (\(helper.activeNames.prefix(2).joined(separator: ", ")))."),
                    action: .add(productID: helper.id, to: target)
                )
            }
            return Suggestion(
                id: "concern-\(concern.rawValue)",
                kind: .gap,
                title: "Nothing for \(concern.label.lowercased()) yet",
                detail: "None of your products target it. Ingredients to look for: \(concern.lookFor)."
            )
        }
    }

    // MARK: - Tips

    private func activeLoad(_ routine: [AdvisorProduct]) -> [Suggestion] {
        let strong = routine.filter { !$0.tags.isDisjoint(with: ["retinoid", "exfoliant"]) }
        let gentle = profile?.isSensitive == true || profile?.experience == .new
        guard strong.count >= (gentle ? 2 : 3) else { return [] }
        let names = strong.map(\.name)
        return [Suggestion(
            id: "active-load",
            kind: .tip,
            title: "Alternate your actives",
            detail: "\(ListFormatter.localizedString(byJoining: names)) in one routine is a lot\(gentle ? " for your skin" : ""). Try them on different nights, like \(names[0]) Mon/Wed/Fri and \(names[1]) Tue/Sat."
        )]
    }

    private func strengths(_ routine: [AdvisorProduct]) -> [Suggestion] {
        var out: [Suggestion] = []
        for concern in profile?.concerns ?? [] {
            guard let helper = routine.first(where: { $0.helps.contains(concern) }) else { continue }
            out.append(Suggestion(
                id: "good-\(concern.rawValue)",
                kind: .good,
                title: "Covers \(concern.label.lowercased())",
                detail: "\(helper.name) targets it" + (helper.activeNames.isEmpty ? "." : " with \(helper.activeNames.prefix(2).joined(separator: " and ")).")
            ))
        }
        if out.isEmpty {
            out.append(Suggestion(id: "good-balanced", kind: .good, title: "No clashes", detail: "Nothing in this routine works against anything else."))
        }
        return Array(out.prefix(2))
    }

    // Same type, not in this routine, not expired. Prefer shared actives and fewer heads-ups.
    private func alternative(for product: AdvisorProduct, period: RoutinePeriod) -> AdvisorProduct? {
        products
            .filter { $0.id != product.id && $0.category == product.category && !$0.isIn(period) && !$0.isExpired }
            .max { score($0, like: product) < score($1, like: product) }
    }

    private func score(_ candidate: AdvisorProduct, like product: AdvisorProduct) -> Int {
        let sharedActives = Set(candidate.activeNames).intersection(product.activeNames).count
        let sharedConcerns = Set(candidate.helps).intersection(product.helps).count
        return sharedActives * 2 + sharedConcerns - candidate.cautions.count
    }
}
