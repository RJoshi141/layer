import Foundation

// Static reference data bundled with the app. Not SwiftData: it isn't user data and ships with each release.
nonisolated struct IngredientReference: Codable, Hashable, Identifiable, Sendable {
    let key: String
    let name: String          // canonical INCI name
    let aliases: [String]     // common names, old INCI names, marketing names
    let role: Role
    let tags: [String]        // drive conflict rules: "retinoid", "exfoliant", "fragrance"...
    let summary: String       // one plain-English line for the UI

    var id: String { key }

    enum Role: String, Codable, Sendable {
        case active, hydrator, barrier, soothing, antioxidant, sunscreen, cleanser, base, preservative, caution
    }
}

nonisolated struct ConflictRule: Codable, Identifiable, Sendable {
    let id: String
    let tagsA: [String]   // matches if a product has any of these tags...
    let tagsB: [String]   // ...and another product in the same routine has any of these
    let severity: Severity
    let advice: String

    enum Severity: String, Codable, Sendable {
        case avoid, caution, fine   // "fine" rules exist to bust myths (niacinamide + vitamin C)
    }
}
