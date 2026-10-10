import Foundation
import Observation

nonisolated enum SkinType: String, Codable, CaseIterable, Identifiable, Sendable {
    case dry, oily, combination, normal
    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var detail: String {
        switch self {
        case .dry: "Feels tight or flaky, rarely shiny"
        case .oily: "Shiny all over by midday"
        case .combination: "Oily T-zone, normal or dry cheeks"
        case .normal: "Comfortable most of the time"
        }
    }
}

nonisolated enum Sensitivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case rarely, sometimes, often
    var id: String { rawValue }

    var label: String {
        switch self {
        case .rarely: "Rarely"
        case .sometimes: "Sometimes"
        case .often: "Often"
        }
    }

    var detail: String {
        switch self {
        case .rarely: "New products don't usually bother me"
        case .sometimes: "Some products sting or make me red"
        case .often: "My skin reacts to a lot of things"
        }
    }
}

nonisolated enum SkinConcern: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakouts, darkSpots, fineLines, redness, dryness, texture, pores, dullness
    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakouts: "Breakouts"
        case .darkSpots: "Dark spots"
        case .fineLines: "Fine lines"
        case .redness: "Redness"
        case .dryness: "Dryness"
        case .texture: "Texture"
        case .pores: "Visible pores"
        case .dullness: "Dullness"
        }
    }

    var symbol: String {
        switch self {
        case .breakouts: "circle.dotted"
        case .darkSpots: "circle.lefthalf.filled"
        case .fineLines: "water.waves"
        case .redness: "flame"
        case .dryness: "drop"
        case .texture: "square.grid.3x3"
        case .pores: "circle.grid.3x3"
        case .dullness: "sun.min"
        }
    }

    // Ingredient tags that are known to help. Kept here so the whole mapping is reviewable in one place.
    var helpfulTags: Set<String> {
        switch self {
        case .breakouts: ["bha", "benzoyl-peroxide", "azelaic", "sulfur", "retinoid", "niacinamide", "oil-control"]
        case .darkSpots: ["vitamin-c", "brightening", "azelaic", "niacinamide", "aha"]
        case .fineLines: ["retinoid", "peptide", "retinol-alternative"]
        case .redness: ["azelaic", "cica", "niacinamide"]
        case .dryness: ["humectant", "ceramide", "emollient", "occlusive"]
        case .texture: ["aha", "bha", "pha", "retinoid", "enzyme"]
        case .pores: ["bha", "niacinamide", "retinoid", "oil-control"]
        case .dullness: ["aha", "pha", "vitamin-c", "brightening"]
        }
    }
}

nonisolated enum ActivesExperience: String, Codable, CaseIterable, Identifiable, Sendable {
    case new, some, experienced
    var id: String { rawValue }

    var label: String {
        switch self {
        case .new: "New to it"
        case .some: "A little"
        case .experienced: "Experienced"
        }
    }

    var detail: String {
        switch self {
        case .new: "I haven't used retinol or acids before"
        case .some: "I've tried retinol or acids now and then"
        case .experienced: "I use retinoids or acids regularly"
        }
    }
}

nonisolated enum AvoidPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case fragrance, essentialOils, alcohol
    var id: String { rawValue }

    var label: String {
        switch self {
        case .fragrance: "Fragrance"
        case .essentialOils: "Essential oils"
        case .alcohol: "Drying alcohol"
        }
    }
}

nonisolated struct SkinProfile: Codable, Equatable, Sendable {
    var skinType: SkinType = .normal
    var sensitivity: Sensitivity = .rarely
    var concerns: [SkinConcern] = []
    var experience: ActivesExperience = .some
    var avoid: Set<AvoidPreference> = []

    var isSensitive: Bool { sensitivity != .rarely }
}

// One profile per device, so UserDefaults is plenty. No need for SwiftData here.
@Observable
final class ProfileStore {
    private(set) var profile: SkinProfile?
    private let key = "skinProfile"

    init() {
        if let data = UserDefaults.standard.data(forKey: key) {
            profile = try? JSONDecoder().decode(SkinProfile.self, from: data)
        }
    }

    func save(_ profile: SkinProfile) {
        self.profile = profile
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
