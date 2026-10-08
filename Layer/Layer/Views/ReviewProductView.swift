import SwiftUI
import SwiftData

// Human-in-the-loop: nothing hits the shelf until you've looked at it
struct ReviewProductView: View {
    @Environment(\.modelContext) private var context

    let result: ScanResult
    var onSaved: () -> Void

    @State private var name: String
    @State private var brand: String
    @State private var category: ProductCategory
    @State private var paoMonths: Int?
    @State private var openedToday = true
    @State private var ingredients: [ParsedIngredient]

    init(result: ScanResult, onSaved: @escaping () -> Void) {
        self.result = result
        self.onSaved = onSaved
        _name = State(initialValue: result.fields.name)
        _brand = State(initialValue: result.fields.brand)
        _category = State(initialValue: result.fields.category)
        _paoMonths = State(initialValue: result.fields.paoMonths)
        _ingredients = State(initialValue: result.ingredients)
    }

    private var matchedCount: Int { ingredients.filter { $0.match != nil }.count }

    var body: some View {
        Form {
            Section {
                TextField("Product name", text: $name)
                TextField("Brand", text: $brand)
                Picker("Type", selection: $category) {
                    ForEach(ProductCategory.allCases) { category in
                        Label(category.label, systemImage: category.symbol).tag(category)
                    }
                }
            } header: {
                Text("Product")
            } footer: {
                Text(result.usedOnDeviceModel
                     ? "Filled in by the on-device model. Give it a quick check."
                     : "Apple Intelligence isn't available, so these came from simple text rules.")
            }

            Section("Shelf life") {
                Picker("After opening", selection: $paoMonths) {
                    Text("Not listed").tag(Int?.none)
                    ForEach([3, 6, 9, 12, 18, 24, 36], id: \.self) { months in
                        Text("\(months) months").tag(Int?.some(months))
                    }
                }
                Toggle("Opened today", isOn: $openedToday)
            }

            if !result.fields.statedActives.isEmpty {
                Section("On the label") {
                    ForEach(result.fields.statedActives, id: \.self) { Text($0) }
                }
            }

            Section {
                if ingredients.isEmpty {
                    Text("Couldn't find an ingredient list. Try scanning the back of the bottle in good light.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ingredients) { IngredientRow(raw: $0.raw, match: $0.match) }
                        .onDelete { ingredients.remove(atOffsets: $0) }
                }
            } header: {
                Text("Ingredients (\(ingredients.count))")
            } footer: {
                if !ingredients.isEmpty {
                    Text("\(matchedCount) recognized. Swipe to remove anything that isn't an ingredient.")
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        var seen = Set<String>()
        let keys = ingredients.compactMap { $0.match?.key }.filter { seen.insert($0).inserted }

        let product = Product(
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces),
            category: category,
            ingredients: ingredients.map(\.raw),
            matchedKeys: keys,
            statedActives: result.fields.statedActives,
            paoMonths: paoMonths,
            openedAt: openedToday ? .now : nil,
            rawLabelText: result.rawText
        )
        context.insert(product)
        onSaved()
    }
}
