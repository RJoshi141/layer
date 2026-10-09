import SwiftUI
import SwiftData

struct RoutineView: View {
    @Query private var products: [Product]
    @Query(sort: \RoutineLog.date, order: .reverse) private var logs: [RoutineLog]
    @State private var isCheckingIn = false
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

                if !logs.isEmpty {
                    Section("Recent check-ins") {
                        ForEach(logs.prefix(5)) { LogRow(log: $0) }
                    }
                }
            }
            .navigationTitle("Routine")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Check in", systemImage: "mic") { isCheckingIn = true }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { isEditing = true }
                        .disabled(products.isEmpty)
                }
            }
            .sheet(isPresented: $isEditing) {
                RoutineEditorView(period: period)
            }
            .sheet(isPresented: $isCheckingIn) {
                CheckInView()
            }
        }
    }
}

private struct LogRow: View {
    let log: RoutineLog

    private var summary: String {
        let parts = log.skinFeel + log.reactions
        return parts.isEmpty ? "\(log.products.count) products" : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: log.period == .am ? "sun.horizon" : "moon.stars")
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(log.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                    .font(.subheadline.weight(.medium))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(log.reactions.isEmpty ? Color.secondary : Color.orange)
                    .lineLimit(2)
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
