import SwiftUI
import UIKit
import SwiftData

struct ProductDetailView: View {
    @Bindable var product: Product
    @Query private var shelf: [Product]
    @Environment(ProfileStore.self) private var profileStore

    @State private var isEditing = false
    @State private var isRescanning = false

    private var db: IngredientDatabase { .shared }

    // Label order kept, so the fit check knows alcohol at #2 vs #30
    private var labelMatches: [IngredientReference?] {
        product.ingredients.map { db.match($0) }
    }

    private var references: [IngredientReference] {
        product.matchedKeys.compactMap { db.reference(for: $0) }
    }

    var body: some View {
        List {
            Section {
                if let data = product.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 260)
                        .clipShape(.rect(cornerRadius: 16))
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 4, trailing: 12))
                }
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

            ExpiryBanner(product: product)

            shelfLifeSection

            if let profile = profileStore.profile {
                let fit = FitChecker(profile: profile).findings(forLabel: labelMatches)
                if !fit.isEmpty {
                    Section("For your skin") {
                        ForEach(fit) { FindingRow(finding: $0) }
                    }
                }
            }

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
                rules: db.rules
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

            let unknown = labelMatches.filter { $0 == nil }.count
            Section {
                ForEach(Array(zip(product.ingredients, labelMatches).enumerated()), id: \.offset) { index, pair in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .trailing)
                        IngredientRow(raw: pair.0, match: pair.1)
                    }
                }
            } header: {
                Text("Full ingredient list (\(product.ingredients.count))")
            } footer: {
                if unknown > 0 {
                    Text("\(unknown) couldn't be identified, usually because the scan garbled the name. You can fix or remove them in Edit details.")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit details", systemImage: "pencil") { isEditing = true }
                    Button("Rescan label", systemImage: "camera.viewfinder") { isRescanning = true }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                ReviewProductView(result: ScanResult(product: product), existing: product) { isEditing = false }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isEditing = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isRescanning) {
            AddProductView(existing: product)
        }
    }

    @ViewBuilder
    private var shelfLifeSection: some View {
        Section {
            if let openedAt = product.openedAt {
                LabeledContent("Opened", value: openedAt.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Use within", value: "\(product.effectivePAOMonths) months")
                if let expiresAt = product.expiresAt {
                    LabeledContent(product.isExpired ? "Expired" : "Good until") {
                        Text(expiresAt.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(product.isExpired ? Color.orange : Color.secondary)
                    }
                }
            } else {
                Text("Not opened yet").foregroundStyle(.secondary)
                Button("I opened it today") { product.openedAt = .now }
            }
        } header: {
            Text("Shelf life")
        } footer: {
            if product.paoIsEstimated {
                Text("No open-jar symbol on the label, so this uses \(product.effectivePAOMonths) months, typical for this type of product. You can change it in Edit details.")
            }
        }
    }
}

// Loud when it matters, invisible when it doesn't
private struct ExpiryBanner: View {
    let product: Product

    var body: some View {
        switch product.expiryStatus {
        case .expired(let since):
            banner(
                symbol: "exclamationmark.triangle.fill",
                color: .orange,
                title: "Past its date",
                message: "Expired \(since.formatted(.relative(presentation: .named))). Actives lose strength after opening, and old products can irritate. Time to replace it."
            )
        case .soon(let until):
            banner(
                symbol: "clock.badge.exclamationmark",
                color: .yellow,
                title: "Use it up",
                message: "Good until \(until.formatted(date: .abbreviated, time: .omitted)), which is \(until.formatted(.relative(presentation: .named)))."
            )
        case .good(let until):
            banner(
                symbol: "checkmark.seal.fill",
                color: .green,
                title: "Good to use",
                message: "Fresh until \(until.formatted(.dateTime.month(.wide).year())), \(until.formatted(.relative(presentation: .named)))."
            )
        case .notOpened:
            EmptyView()
        }
    }

    private func banner(symbol: String, color: Color, title: String, message: String) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: symbol).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(color.opacity(0.12))
        }
    }
}
