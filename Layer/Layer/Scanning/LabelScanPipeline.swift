import Foundation
import UIKit

nonisolated struct ParsedIngredient: Identifiable, Sendable {
    let id = UUID()
    let raw: String
    let match: IngredientReference?
}

nonisolated struct ScanResult: Sendable {
    var fields: LabelFields
    var ingredients: [ParsedIngredient]
    var rawText: String
    var usedOnDeviceModel: Bool
}

nonisolated enum ScanError: LocalizedError {
    case unreadableImage, noText

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "Couldn't read that image."
        case .noText: "No text found. Try again with better light and the label filling the frame."
        }
    }
}

// image(s) → OCR → (ingredients via parser + DB) and (fields via rules + on-device model) → draft for human review
nonisolated struct LabelScanPipeline {
    var database: IngredientDatabase = .shared

    func run(images: [UIImage]) async throws -> ScanResult {
        // OCR each photo separately, so the end of one angle doesn't get glued onto the start of the next
        var perImage: [[String]] = []
        for image in images {
            perImage.append(try await TextRecognizer.lines(in: image))
        }
        let lines = perImage.flatMap { $0 }
        guard !lines.isEmpty else { throw ScanError.noText }
        let rawText = perImage.map { $0.joined(separator: "\n") }.joined(separator: "\n\n---\n\n")

        // Ingredients never go through the LLM, so the list can't be hallucinated
        let names = INCIParser.merge(perImage.map { INCIParser.parse(lines: $0) })
        let ingredients = names.map {
            ParsedIngredient(raw: $0, match: database.match($0))
        }

        // Rules first, then the model fills gaps. If the model fails we still have a usable draft.
        var fields = HeuristicExtractor.extract(from: lines)
        var usedModel = false
        if LabelExtractor.isAvailable, let draft = try? await LabelExtractor().extract(from: rawText) {
            fields.fill(from: draft)
            usedModel = true
        }

        return ScanResult(fields: fields, ingredients: ingredients, rawText: rawText, usedOnDeviceModel: usedModel)
    }
}
