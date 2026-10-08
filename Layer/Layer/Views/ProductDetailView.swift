import SwiftUI
import SwiftData

struct ProductDetailView: View {
    @Bindable var product: Product
    @Query private var shelf: [Product]

    private var references: [IngredientReference] {
        product.matchedKeys.compactMap { IngredientDatabase.shared.reference(for: $0) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if !product.brand.isEmpty {
                        Text(product.brand.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(product.name).font(.title2.bold())
                    Label(product.category.label, systemImage: product.category.symbol)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            shelfLifeSection

            let actives = references.filter { $0.role == .active }
            if !actives.isEmpty || !product.statedActives.isEmpty {
                Section("Actives") {
                    ForEach(product.statedActives, id: \.self) { Text($0).font(.subheadline.weight(.medium)) }
                    ForEach(actives) { IngredientRow(raw: $0.name, match: $0) }
                }
            }

            // Same rules as the Routine tab, run against everything else on the shelf
            let clashes = ConflictChecker.clashes(
                of: product.routineItem,
                with: shelf.filter { $0.persistentModelID != product.persistentModelID }.map(\.routineItem),
                rules: IngredientDatabase.shared.rules
            )
            if !clashes.isEmpty {
                Section {
                    ForEach(clashes) { FindingRow(finding: $0) }
                } header: {
                    Text("Don't layer with")
                } footer: {
                    Text("Fine on different nights or in different routines.")
                }
            }

            let watch = references.filter { $0.role == .caution }
            if !watch.isEmpty {
                Section("Watch for") {
                    ForEach(watch) { IngredientRow(raw: $0.name, match: $0) }
                }
            }

            Section("Full ingredient list (\(product.ingredients.count))") {
                ForEach(Array(product.ingredients.enumerated()), id: \.offset) { index, name in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .trailing)
                        IngredientRow(raw: name, match: IngredientDatabase.shared.match(name))
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var shelfLifeSection: some View {
        Section("Shelf life") {
            if let openedAt = product.openedAt {
                LabeledContent("Opened", value: openedAt.formatted(date: .abbreviated, time: .omitted))
                if let expiresAt = product.expiresAt {
                    LabeledContent(product.isExpired ? "Expired" : "Good until") {
                        Text(expiresAt.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(product.isExpired ? Color.orange : Color.secondary)
                    }
                }
            } else {
                Button("I opened it today") { product.openedAt = .now }
            }
            if product.paoMonths == nil {
                Text("No period-after-opening symbol found on the label.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
