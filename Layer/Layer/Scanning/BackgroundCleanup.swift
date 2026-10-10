import SwiftData
import UIKit

// One-time fix for photos saved before cutouts were transparent: if a product's photo
// sits on white, lift the product out and save it back as a clear PNG.
enum BackgroundCleanup {
    static func run(_ products: [Product]) async {
        for product in products {
            guard let data = product.imageData, let image = UIImage(data: data),
                  !image.hasAlpha, image.hasWhiteCorners else { continue }
            // Vision is heavy, keep it off the main thread
            let cleaned = await Task.detached(priority: .utility) { () -> Data? in
                SubjectCutout.productShot(from: image)?.thumbnailJPEG()
            }.value
            if let cleaned { product.imageData = cleaned }
        }
    }
}

extension UIImage {
    // All four corners close to white means a studio or old cutout background, not a real photo
    nonisolated var hasWhiteCorners: Bool {
        guard let cgImage else { return false }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let corners = [(0, 0), (side - 1, 0), (0, side - 1), (side - 1, side - 1)]
        return corners.allSatisfy { x, y in
            let i = (y * side + x) * 4
            return pixels[i] > 232 && pixels[i + 1] > 232 && pixels[i + 2] > 232
        }
    }
}
