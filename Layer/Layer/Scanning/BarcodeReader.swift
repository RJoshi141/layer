import UIKit
import Vision

// Most bottles have a UPC/EAN barcode next to the ingredients, so the label photos usually catch it
nonisolated enum BarcodeReader {
    static func firstProductCode(in image: UIImage) async throws -> String? {
        guard let cgImage = image.cgImage else { return nil }
        let request = DetectBarcodesRequest()
        let observations = try await request.perform(
            on: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation)
        )
        // Retail product codes are 8 to 14 digits. Skips QR codes pointing at the brand's website.
        return observations
            .compactMap(\.payloadString)
            .first { code in (8...14).contains(code.count) && code.allSatisfy(\.isNumber) }
    }
}
