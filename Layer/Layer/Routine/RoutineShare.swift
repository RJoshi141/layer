import SwiftUI
import UIKit

// Share your routine as a card image (for stories / texts) plus a plain list (for notes / chats).
struct RoutineSharePayload: Identifiable {
    let id = UUID()
    let image: UIImage
    let text: String

    // periods: [.am], [.pm] or both. steps comes from the Routine tab so ordering matches.
    @MainActor
    static func make(periods: [RoutinePeriod], steps: (RoutinePeriod) -> [Product]) -> RoutineSharePayload? {
        let card = RoutineShareCard(sections: periods.map { ($0, steps($0)) })
            .environment(\.colorScheme, .light)   // card always reads the same in someone else's chat
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }

        let text = periods.map { period in
            let list = steps(period).enumerated().map { index, product in
                "\(index + 1). \(product.name)" + (product.brand.isEmpty ? "" : " (\(product.brand))")
            }
            return (["My \(period.shareName) routine"] + (list.isEmpty ? ["Nothing yet"] : list)).joined(separator: "\n")
        }
        .joined(separator: "\n\n") + "\n\nBuilt with Layer"

        return RoutineSharePayload(image: image, text: text)
    }
}

extension RoutinePeriod {
    var shareName: String { self == .am ? "morning" : "night" }
}

// The image that gets shared. Same look as the app: sage page, sand cards, serif names.
struct RoutineShareCard: View {
    let sections: [(RoutinePeriod, [Product])]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Wordmark(size: 28)
                Spacer()
                Text(Date.now.formatted(.dateTime.month(.wide).day()))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.muted)
            }

            ForEach(sections, id: \.0) { period, products in
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        TwoToneTitle(top: "My \(period.shareName)", bottom: "Ritual", size: 28)
                        Spacer()
                        Image(systemName: period == .am ? "sun.max" : "moon")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.lime)
                            .frame(width: 34, height: 34)
                            .background(Theme.primary, in: .circle)
                    }

                    if products.isEmpty {
                        Text("Nothing here yet")
                            .font(Theme.body)
                            .foregroundStyle(Theme.muted)
                    }
                    ForEach(Array(products.enumerated()), id: \.offset) { index, product in
                        HStack(spacing: 12) {
                            IndexLabel(number: index + 1)
                                .frame(width: 28, alignment: .leading)
                            ProductThumbnail(product: product, size: 44)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(product.name)
                                    .font(Theme.display(19))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text(product.brand.isEmpty ? product.category.label : "\(product.brand) · \(product.category.label)")
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(18)
                .background(Theme.card, in: .rect(cornerRadius: 22))
            }

            Text("INGREDIENT-SMART SKINCARE · MADE WITH LAYER")
                .font(.system(size: 9, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
        }
        .padding(22)
        .frame(width: 390)
        .background(Theme.page)
    }
}

// System share sheet: Messages, Instagram, Save Image, Notes...
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
