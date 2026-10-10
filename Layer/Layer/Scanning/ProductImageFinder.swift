import Foundation
import UIKit

nonisolated struct FoundPhoto: Sendable {
    let image: UIImage
    let source: String          // shown under the photo: "Open Beauty Facts", "sephora.com"...
}

nonisolated struct PhotoSearchOutcome: Sendable {
    var photos: [FoundPhoto] = []
    var name = ""               // from a database hit, when there is one
    var brand = ""
    var bestGuess: String?      // what Google thinks the product is
    var notes: [String] = []    // what was tried, shown when nothing turns up
}

// Finds the real product photo, most exact source first. Everything here is free, no credit card:
// 1. Barcode on Open Beauty Facts, then UPCitemdb (exact matches)
// 2. Google Lens on your photo via SerpApi (needs a free SerpApi key)
// 3. Brand + name search on Open Beauty Facts (strict)
// 4. Always: your own photo with the background lifted out on-device
nonisolated enum ProductImageFinder {
    private static let base = "https://world.openbeautyfacts.org"
    private static let fields = "product_name,brands,image_front_url,image_url"

    static func find(barcode: String?, name: String, brand: String, photos: [UIImage]) async -> PhotoSearchOutcome {
        var outcome = PhotoSearchOutcome()

        if let barcode {
            if let product = try? await lookup(barcode: barcode), let found = await download(product) {
                outcome.photos.append(found.photo)
                outcome.name = found.name
                outcome.brand = found.brand
            } else if let item = try? await upcItemDB(barcode: barcode), let image = await downloadImage(item.imageURL) {
                outcome.photos.append(FoundPhoto(image: image, source: "UPCitemdb"))
                outcome.name = item.title
                outcome.brand = item.brand
            } else {
                outcome.notes.append("Barcode \(barcode) isn't in the free product databases")
            }
        } else {
            outcome.notes.append("No barcode in your photos")
        }

        if VisualProductSearch.isConfigured {
            // One Lens search per tap keeps you well inside the free 250 a month
            if let photo = photos.first, let matches = try? await VisualProductSearch.search(photo), !matches.isEmpty {
                if outcome.bestGuess == nil { outcome.bestGuess = matches.first?.title }
                outcome.photos += await downloadLens(matches.prefix(5))
            }
            if outcome.photos.isEmpty { outcome.notes.append("Google Lens didn't find a match") }
        } else {
            outcome.notes.append("Google Lens is off (add a free SerpApi key to Secrets.plist)")
        }

        // Name search is a guess. "aloe" alone matches dozens of products, so it only runs
        // with a brand, and only trusts a result whose brand AND distinctive name words match.
        if outcome.photos.isEmpty {
            let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
            if trimmedBrand.isEmpty {
                outcome.notes.append("Add the brand so Layer can search by name")
            } else if let product = try? await search("\(trimmedBrand) \(name)", brand: trimmedBrand, name: name),
                      let found = await download(product) {
                outcome.photos.append(FoundPhoto(image: found.photo.image, source: "Open Beauty Facts (name match)"))
            } else {
                outcome.notes.append("No \(trimmedBrand) product with that name in Open Beauty Facts")
            }
        }
        if !outcome.photos.isEmpty { outcome.notes = [] }

        // Your own photo, cleaned up. Heavy Vision work, so off the main thread.
        if let photo = photos.first {
            let cutout = await Task.detached(priority: .userInitiated) { SubjectCutout.productShot(from: photo) }.value
            if let cutout { outcome.photos.append(FoundPhoto(image: cutout, source: "Your photo, background removed")) }
        }
        return outcome
    }

    // Lens results in their original order (best match first)
    private static func downloadLens(_ matches: ArraySlice<LensMatch>) async -> [FoundPhoto] {
        await withTaskGroup(of: (Int, FoundPhoto?).self) { group in
            for (rank, match) in matches.enumerated() {
                group.addTask {
                    guard let image = await downloadImage(match.imageURL) else { return (rank, nil) }
                    return (rank, FoundPhoto(image: image, source: match.source))
                }
            }
            var ranked: [(Int, FoundPhoto)] = []
            for await (rank, photo) in group {
                if let photo { ranked.append((rank, photo)) }
            }
            return ranked.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    // Free trial endpoint: no signup, 100 lookups a day. Good US coverage.
    private static func upcItemDB(barcode: String) async throws -> (imageURL: URL, title: String, brand: String)? {
        guard let url = URL(string: "https://api.upcitemdb.com/prod/trial/lookup?upc=\(barcode)") else { return nil }
        let response: UPCResponse = try await get(url)
        guard let item = response.items.first,
              let imageURL = (item.images ?? []).compactMap({ URL(string: $0) }).first else { return nil }
        return (imageURL, item.title ?? "", item.brand ?? "")
    }

    static func downloadImage(_ url: URL) async -> UIImage? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        guard let result = try? await URLSession.shared.data(for: request),
              let image = UIImage(data: result.0),
              // Skip logos and icons
              min(image.size.width, image.size.height) >= 250 else { return nil }
        return image
    }

    private static func lookup(barcode: String) async throws -> OBFProduct? {
        guard let url = URL(string: "\(base)/api/v2/product/\(barcode).json?fields=\(fields)") else { return nil }
        let response: OBFProductResponse = try await get(url)
        return response.status == 1 ? response.product : nil
    }

    private static func search(_ query: String, brand: String, name: String) async throws -> OBFProduct? {
        var components = URLComponents(string: "\(base)/cgi/search.pl")
        components?.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "10"),
            URLQueryItem(name: "fields", value: fields),
        ]
        guard let url = components?.url else { return nil }
        let response: OBFSearchResponse = try await get(url)

        // Search is fuzzy, so only accept a result that clearly matches what's on the bottle
        let brandKey = normalizedWords(brand).joined(separator: " ")
        let wanted = distinctiveWords(name)
        return response.products.first { product in
            guard product.imageURL != nil else { return false }
            let brandOK = normalizedWords(product.brands ?? "").joined(separator: " ").contains(brandKey)
            let found = distinctiveWords(product.product_name ?? "")
            // Every distinctive word you have must be in the result (at least one must exist)
            let nameOK = !wanted.isEmpty && wanted.isSubset(of: found)
            return brandOK && nameOK
        }
    }

    // Words that tell products apart. "Cream", "gel", "face" describe half the shelf.
    private static let genericWords: Set<String> = [
        "cream", "creme", "gel", "lotion", "serum", "essence", "toner", "face", "facial", "skin", "body",
        "hands", "with", "for", "and", "the", "soothing", "moisturizing", "moisturiser", "moisturizer", "hydrating",
        "daily", "care", "natural", "nature", "vera", "spf", "sun", "oil", "water", "mist", "mask",
    ]

    private static func normalizedWords(_ text: String) -> [String] {
        IngredientDatabase.normalize(text).split(separator: " ").map(String.init)
    }

    private static func distinctiveWords(_ text: String) -> Set<String> {
        Set(normalizedWords(text).filter { $0.count >= 3 && !genericWords.contains($0) && !$0.allSatisfy(\.isNumber) })
    }

    private static func download(_ product: OBFProduct?) async -> (photo: FoundPhoto, name: String, brand: String)? {
        guard let product, let url = product.imageURL, let image = await downloadImage(url) else { return nil }
        return (FoundPhoto(image: image, source: "Open Beauty Facts"), product.product_name ?? "", product.brands ?? "")
    }

    private static func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url, timeoutInterval: 8)
        // Open Beauty Facts asks apps to identify themselves
        request.setValue("Layer/1.0 (iOS portfolio app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// Field names match the API's JSON exactly
nonisolated private struct UPCResponse: Decodable {
    nonisolated struct Item: Decodable {
        let title: String?
        let brand: String?
        let images: [String]?
    }
    let items: [Item]
}

nonisolated private struct OBFProductResponse: Decodable {
    let status: Int?
    let product: OBFProduct?
}

nonisolated private struct OBFSearchResponse: Decodable {
    let products: [OBFProduct]
}

nonisolated private struct OBFProduct: Decodable {
    let product_name: String?
    let brands: String?
    let image_front_url: String?
    let image_url: String?

    var imageURL: URL? {
        (image_front_url ?? image_url).flatMap { URL(string: $0) }
    }
}

extension UIImage {
    // Small enough to keep in SwiftData without bloating it
    nonisolated func thumbnailJPEG(maxDimension: CGFloat = 900) -> Data? {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
