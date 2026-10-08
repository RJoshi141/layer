import SwiftUI
import SwiftData

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.name) private var products: [Product]
    let period: RoutinePeriod

    var body: some View {
        NavigationStack {
            List(products) { product in
                Toggle(isOn: Binding(
                    get: { product.isIn(period) },
                    set: { product.setIn(period, $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(product.name)
                        Text(product.category.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(period == .am ? "Morning routine" : "Night routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
