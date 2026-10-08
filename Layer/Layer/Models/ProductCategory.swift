import Foundation

// Stored as a raw string on Product so SwiftData migrations stay boring
nonisolated enum ProductCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case cleanser, toner, serum, treatment, moisturizer, sunscreen, eyeCream, mask, oil, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cleanser: "Cleanser"
        case .toner: "Toner"
        case .serum: "Serum"
        case .treatment: "Treatment"
        case .moisturizer: "Moisturizer"
        case .sunscreen: "Sunscreen"
        case .eyeCream: "Eye cream"
        case .mask: "Mask"
        case .oil: "Face oil"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .cleanser: "bubbles.and.sparkles"
        case .toner: "drop"
        case .serum: "eyedropper"
        case .treatment: "wand.and.stars"
        case .moisturizer: "humidity"
        case .sunscreen: "sun.max"
        case .eyeCream: "eye"
        case .mask: "theatermasks"
        case .oil: "drop.fill"
        case .other: "square.dashed"
        }
    }

    // Thinnest to thickest, sunscreen last
    var layerRank: Int {
        switch self {
        case .cleanser: 0
        case .mask: 1
        case .toner: 2
        case .serum: 3
        case .treatment, .other: 4
        case .eyeCream: 5
        case .moisturizer: 6
        case .oil: 7
        case .sunscreen: 8
        }
    }
}
