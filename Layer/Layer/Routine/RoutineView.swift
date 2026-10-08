import SwiftUI
import SwiftData

struct RoutineView: View {
    @Query private var products: [Product]
    @State private var period: RoutinePeriod = Calendar.current.component(.hour, from: .now) < 15 ? .am : .pm
    @State private var isEditing = false

    // Order comes from category, so we never have to store or drag-sort it
    private var steps: [Product] {
        products
            .filter { $0.isIn(period) }
            .sorted { $0.category.layerRank < $1.category.layerRank }
    }

    private var findings: [Finding] {
        ConflictChecker.check(steps.map(\.routineItem), period: period, rules: IngredientDatabase.shared.rules)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Routine", selection: $period) {
                        Text("Morning").tag(RoutinePeriod.am)
                        Text("Night").tag(RoutinePeriod.pm)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if steps.isEmpty {
                    ContentUnavailableView {
                        Label("No \(period == .am ? "morning" : "night") routine yet", systemImage: period == .am ? "sun.horizon" : "moon.stars")
                    } description: {
                        Text("Pick products from your shelf and Layer will put them in order.")
                    } actions: {
                        Button("Build routine") { isEditing = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    if !findings.isEmpty {
                        Section("Heads up") {
                            ForEach(findings) { FindingRow(finding: $0) }
                        }
                    }

                    Section("Steps") {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, product in
                            StepRow(number: index + 1, product: product)
                        }
                    }
                }
            }
            .navigationTitle("Routine")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { isEditing = true }
                        .disabled(products.isEmpty)
                }
            }
            .sheet(isPresented: $isEditing) {
                RoutineEditorView(period: period)
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let product: Product

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.15), in: .circle)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                Text(product.category.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FindingRow: View {
    let finding: Finding

    private var style: (symbol: String, color: Color) {
        switch finding.severity {
        case .avoid: ("xmark.octagon.fill", .red)
        case .caution: ("exclamationmark.triangle.fill", .orange)
        case .fine: ("checkmark.seal.fill", .green)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: style.symbol).foregroundStyle(style.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.title).font(.subheadline.weight(.semibold))
                Text(finding.advice)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
