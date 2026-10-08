import UIKit
import Vision

nonisolated enum TextRecognizer {
    // On-device OCR with Vision's Swift API (iOS 18+)
    static func lines(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { throw ScanError.unreadableImage }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" INCI names into English words, so keep it off
        request.usesLanguageCorrection = false

        let observations = try await request.perform(
            on: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation)
        )
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}

nonisolated extension CGImagePropertyOrientation {
    // Photos from the camera roll are often rotated via metadata, not pixels
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
