import SwiftUI
import SwiftData

struct ShelfView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Product.addedAt, order: .reverse) private var products: [Product]
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            Group {
                if products.isEmpty {
                    ContentUnavailableView {
                        Label("Your shelf is empty", systemImage: "drop")
                    } description: {
                        Text("Scan the back of a bottle to add your first product.")
                    } actions: {
                        Button("Scan a label") { isAdding = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(products) { product in
                            NavigationLink(value: product) {
                                ProductRow(product: product)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Shelf")
            .navigationDestination(for: Product.self) { ProductDetailView(product: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add product", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) {
                AddProductView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(products[index]) }
    }
}

struct ProductRow: View {
    let product: Product

    // Only surface actives in the row. That's what people scan their shelf for.
    private var actives: [IngredientReference] {
        product.matchedKeys
            .compactMap { IngredientDatabase.shared.reference(for: $0) }
            .filter { $0.role == .active }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: product.category.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                if !product.brand.isEmpty {
                    Text(product.brand.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(product.name).font(.headline)
                if !actives.isEmpty {
                    Text(actives.prefix(3).map(\.name).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(IngredientReference.Role.active.color)
                }
            }

            Spacer()

            if product.isExpired {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Expired")
            }
        }
        .padding(.vertical, 2)
    }
}
