import CoreImage
import UIKit
import Vision

// Same tech as long-pressing a photo to lift the subject. Turns your photo of the bottle
// into a clean product shot with a clear background. Fully on-device, free, works without internet.
nonisolated enum SubjectCutout {
    static func productShot(from photo: UIImage) -> UIImage? {
        guard let cgImage = photo.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(photo.imageOrientation))

        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let masked = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: masked)
            guard let cut = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
            let subject = UIImage(cgImage: cut)

            // Pad it but keep the background clear, so it sits on whatever panel shows it
            let pad = max(subject.size.width, subject.size.height) * 0.08
            let canvas = CGSize(width: subject.size.width + pad * 2, height: subject.size.height + pad * 2)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
                subject.draw(at: CGPoint(x: pad, y: pad))
            }
        } catch {
            return nil
        }
    }
}
