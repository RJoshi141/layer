import Foundation
import SwiftData

@Model
final class Product {
    var name: String
    var brand: String
    var categoryRaw: String
    // INCI list exactly as printed, in label order (label order ≈ concentration order)
    var ingredients: [String]
    // Keys into IngredientDatabase for everything we recognized
    var matchedKeys: [String]
    // Percentages printed on the label, e.g. "2% Salicylic Acid"
    var statedActives: [String]
    var paoMonths: Int?
    var openedAt: Date?
    var addedAt: Date
    // Raw OCR, kept so we can re-parse when the parser gets smarter
    var rawLabelText: String
    var notes: String

    @Relationship(deleteRule: .nullify, inverse: \RoutineLog.products)
    var logs: [RoutineLog] = []

    init(
        name: String,
        brand: String = "",
        category: ProductCategory = .other,
        ingredients: [String] = [],
        matchedKeys: [String] = [],
        statedActives: [String] = [],
        paoMonths: Int? = nil,
        openedAt: Date? = nil,
        rawLabelText: String = "",
        notes: String = ""
    ) {
        self.name = name
        self.brand = brand
        self.categoryRaw = category.rawValue
        self.ingredients = ingredients
        self.matchedKeys = matchedKeys
        self.statedActives = statedActives
        self.paoMonths = paoMonths
        self.openedAt = openedAt
        self.addedAt = .now
        self.rawLabelText = rawLabelText
        self.notes = notes
    }

    var category: ProductCategory {
        get { ProductCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    // PAO clock starts when you open it, not when you buy it
    var expiresAt: Date? {
        guard let openedAt, let paoMonths else { return nil }
        return Calendar.current.date(byAdding: .month, value: paoMonths, to: openedAt)
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < .now
    }
}
