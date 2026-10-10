import Foundation
import UIKit

// Lives in Secrets.plist, which is gitignored so the key never lands on GitHub
nonisolated enum Secrets {
    static var serpApiKey: String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let key = plist["SerpApiKey"] as? String,
              !key.isEmpty, key != "PASTE_YOUR_KEY_HERE" else { return nil }
        return key
    }
}

nonisolated struct LensMatch: Sendable {
    let title: String
    let imageURL: URL
    let source: String      // "Amazon.com", "Ulta Beauty"...
}

// Google Lens on your photo, through SerpApi (free plan: 250 searches a month, no card needed).
// Two calls: upload the photo, then search by the returned image id.
nonisolated enum VisualProductSearch {
    static var isConfigured: Bool { Secrets.serpApiKey != nil }

    static func search(_ photo: UIImage) async throws -> [LensMatch] {
        guard let key = Secrets.serpApiKey,
              // SerpApi caps uploads at 500 KB
              let jpeg = photo.jpegUnder(bytes: 480_000),
              let uploadURL = URL(string: "https://serpapi.com/image") else { return [] }

        // 1. Upload
        let boundary = "Layer-\(UUID().uuidString)"
        var upload = URLRequest(url: uploadURL, timeoutInterval: 20)
        upload.httpMethod = "POST"
        upload.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        upload.httpBody = multipartBody(boundary: boundary, fields: ["api_key": key], fileField: "image", fileData: jpeg)
        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: upload)
        guard (uploadResponse as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let imageID = try JSONDecoder().decode(SerpUpload.self, from: uploadData).image_id

        // 2. Lens search
        var components = URLComponents(string: "https://serpapi.com/search.json")
        components?.queryItems = [
            URLQueryItem(name: "engine", value: "google_lens"),
            URLQueryItem(name: "image_id", value: imageID),
            URLQueryItem(name: "hl", value: "en"),
            URLQueryItem(name: "country", value: "us"),
            URLQueryItem(name: "api_key", value: key),
        ]
        guard let searchURL = components?.url else { return [] }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: searchURL, timeoutInterval: 25))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        return (try JSONDecoder().decode(SerpLens.self, from: data).visual_matches ?? []).compactMap { match in
            guard let raw = match.image ?? match.thumbnail, let url = URL(string: raw) else { return nil }
            return LensMatch(title: match.title ?? "", imageURL: url, source: match.source ?? "Google Lens")
        }
    }

    private static func multipartBody(boundary: String, fields: [String: String], fileField: String, fileData: Data) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}

// SerpApi responses, trimmed to the fields we use
nonisolated private struct SerpUpload: Decodable {
    let image_id: String
}

nonisolated private struct SerpLens: Decodable {
    nonisolated struct Match: Decodable {
        let title: String?
        let image: String?
        let thumbnail: String?
        let source: String?
    }
    let visual_matches: [Match]?
}

extension UIImage {
    // Steps quality and size down until it fits, for APIs with upload limits
    nonisolated func jpegUnder(bytes limit: Int) -> Data? {
        for maxDimension in [1600, 1200, 900, 700] as [CGFloat] {
            for quality in [0.8, 0.6, 0.45] as [CGFloat] {
                if let data = resizedForUpload(maxDimension: maxDimension).jpegData(compressionQuality: quality), data.count <= limit {
                    return data
                }
            }
        }
        return nil
    }

    nonisolated private func resizedForUpload(maxDimension: CGFloat) -> UIImage {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
