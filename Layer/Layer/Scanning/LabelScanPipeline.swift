import Foundation
import UIKit

nonisolated struct ParsedIngredient: Identifiable, Sendable {
    let id = UUID()
    let raw: String
    var match: IngredientReference?
    var isNew = false   // not in the database yet; gets learned when you save
}

nonisolated struct ScanResult: Sendable {
    var fields: LabelFields
    var ingredients: [ParsedIngredient]
    var rawText: String
    var usedOnDeviceModel: Bool
    var barcode: String? = nil
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
        let ingredients = names.map { raw -> ParsedIngredient in
            if let known = database.match(raw) {
                return ParsedIngredient(raw: raw, match: known)
            }
            // New to us: classify from the INCI name now, learn it when the user saves
            return ParsedIngredient(raw: raw, match: IngredientClassifier.classify(raw), isNew: true)
        }

        // Barcode is how we find the real product photo later
        var barcode: String?
        for image in images where barcode == nil {
            barcode = try? await BarcodeReader.firstProductCode(in: image)
        }

        // Rules first, then the model fills gaps. If the model fails we still have a usable draft.
        var fields = HeuristicExtractor.extract(perImage: perImage)
        var usedModel = false
        if LabelExtractor.isAvailable, let draft = try? await LabelExtractor().extract(from: rawText) {
            fields.fill(from: draft)
            usedModel = true
        }

        return ScanResult(fields: fields, ingredients: ingredients, rawText: rawText, usedOnDeviceModel: usedModel, barcode: barcode)
    }
}
