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

    private var actives: [IngredientReference] { references.filter { $0.role == .active } }
    private var watch: [IngredientReference] { references.filter { $0.role == .caution } }

    private var fit: [Finding] {
        profileStore.profile.map { FitChecker(profile: $0).findings(forLabel: labelMatches) } ?? []
    }

    // Same rules as the Routine tab, run against everything else on the shelf
    private var clashes: [Finding] {
        ConflictChecker.clashes(
            of: product.routineItem,
            with: shelf.filter { $0.persistentModelID != product.persistentModelID }.map(\.routineItem),
            rules: db.rules
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                hero
                VStack(alignment: .leading, spacing: 22) {
                    titleBlock
                    routineToggles
                }
                shelfLifeTiles

                if !fit.isEmpty {
                    section(top: "For your", bottom: "Skin") {
                        ForEach(fit) { FindingRow(finding: $0) }
                    }
                }

                if !clashes.isEmpty {
                    section(top: "Don't layer", bottom: "With") {
                        ForEach(clashes) { FindingRow(finding: $0) }
                        Text("Fine on different nights or in different routines.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }

                if !actives.isEmpty || !product.statedActives.isEmpty {
                    keyIngredients
                }

                details
            }
            .padding(.bottom, 24)
        }
        .pageBackground()
        .navigationBarTitleDisplayMode(.inline)
        // Edit + rescan sit together top right, out of the way of reading the page
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Rescan label", systemImage: "camera.viewfinder") { isRescanning = true }
                    .buttonStyle(InkCircleStyle())
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit details", systemImage: "pencil") { isEditing = true }
                    .buttonStyle(InkCircleStyle())
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                ReviewProductView(result: ScanResult(product: product), existing: product) { isEditing = false }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel", systemImage: "xmark") { isEditing = false }
                                .buttonStyle(InkCircleStyle())
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
            }
        }
        .sheet(isPresented: $isRescanning) {
            AddProductView(existing: product)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            Theme.card
            if let data = product.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(24)
            } else {
                LayerIcon(name: product.category.iconName, size: 96)
                    .foregroundStyle(Theme.ink.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 28))
        .padding(.horizontal, 16)
        .accessibilityHidden(true)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            BracketLabel(product.category.label)

            VStack(alignment: .leading, spacing: 6) {
                Text(product.name)
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !product.brand.isEmpty {
                    Text(product.brand.uppercased())
                        .font(Theme.label)
                        .tracking(1.5)
                        .foregroundStyle(Theme.muted)
                }
            }

            if let summary {
                Text(summary)
                    .font(Theme.body)
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, 20)
    }

    // The main thing you do here: put it in a routine. Two labeled pills, not bare icons.
    private var routineToggles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("USE IT IN")
                .font(Theme.label)
                .tracking(1.5)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                RoutineToggle(title: "Morning", icon: "sun.max", isOn: $product.inAM)
                RoutineToggle(title: "Night", icon: "moon", isOn: $product.inPM)
            }
        }
        .padding(.horizontal, 20)
    }

    // One readable sentence instead of a wall of chemistry
    private var summary: String? {
        var parts: [String] = []
        if !actives.isEmpty {
            parts.append("Key actives: \(ListFormatter.localizedString(byJoining: actives.prefix(3).map(\.name))).")
        }
        let goodFor = fit.filter { $0.severity == .fine }.map { $0.title.replacingOccurrences(of: "Good for ", with: "") }
        if !goodFor.isEmpty {
            parts.append("Good for \(ListFormatter.localizedString(byJoining: goodFor)).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Shelf life tiles (the olive "feature cards")

    private var shelfLifeTiles: some View {
        HStack(spacing: 10) {
            statusTile
            if let openedAt = product.openedAt {
                InfoTile(icon: "absorb", title: "Opened", value: openedAt.formatted(.dateTime.month(.abbreviated).day().year()))
            } else {
                Button { product.openedAt = .now } label: {
                    InfoTile(icon: "absorb", title: "Not opened", value: "Tap if you opened it today")
                }
                .buttonStyle(.plain)
            }
            InfoTile(
                icon: "layers",
                title: "Use within",
                value: "\(product.effectivePAOMonths) months" + (product.paoIsEstimated ? " (typical)" : "")
            )
        }
        .padding(.horizontal, 16)
    }

    private var statusTile: some View {
        let (title, value, tint): (String, String, Color) = switch product.expiryStatus {
        case .expired(let since): ("Past its date", "Expired \(since.formatted(.relative(presentation: .named)))", Theme.warning)
        case .soon(let until): ("Use it up", "Good until \(until.formatted(.dateTime.month(.abbreviated).day()))", Theme.warning)
        case .good(let until): ("Good to use", "Fresh until \(until.formatted(.dateTime.month(.abbreviated).year()))", Theme.olive)
        case .notOpened: ("Sealed", "Clock starts when you open it", Theme.olive)
        }
        return VStack(alignment: .leading, spacing: 8) {
            LayerIcon(name: "glow", size: 20)
            Spacer(minLength: 0)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(value).font(.system(size: 11)).opacity(0.85).lineLimit(3)
        }
        .foregroundStyle(Theme.oliveText)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(tint, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Key ingredients

    private var keyIngredients: some View {
        VStack(alignment: .leading, spacing: 16) {
            TwoToneTitle(top: "Key", bottom: "Ingredients")
                .padding(.horizontal, 20)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(product.statedActives, id: \.self) { stated in
                        IngredientCard(name: stated, summary: "Strength printed on the label.", icon: "serum")
                    }
                    ForEach(actives) { active in
                        IngredientCard(name: active.name, summary: active.summary, icon: icon(for: active))
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func icon(for ref: IngredientReference) -> String {
        if !Set(ref.tags).isDisjoint(with: ["aha", "bha", "pha", "exfoliant"]) { return "glow" }
        if ref.tags.contains("retinoid") { return "layers" }
        if ref.tags.contains("vitamin-c") { return "drops" }
        return "serum"
    }

    // MARK: - Details accordions

    private var details: some View {
        let unknown = labelMatches.filter { $0 == nil }.count
        return VStack(alignment: .leading, spacing: 10) {
            TwoToneTitle(top: "The", bottom: "Details")
                .padding(.bottom, 4)

            if !watch.isEmpty {
                Accordion("Watch for", subtitle: "\(watch.count)", isOpen: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(watch) { IngredientRow(raw: $0.name, match: $0) }
                    }
                }
            }

            Accordion("Full ingredient list", subtitle: "\(product.ingredients.count)") {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(zip(product.ingredients, labelMatches).enumerated()), id: \.offset) { index, pair in
                        IngredientRow(raw: pair.0, match: pair.1, number: index + 1)
                    }
                    if unknown > 0 {
                        Text("\(unknown) couldn't be identified, usually because the scan garbled the name. You can fix or remove them in Edit details.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }

            Accordion("Shelf life") {
                VStack(alignment: .leading, spacing: 12) {
                    if let openedAt = product.openedAt {
                        detailLine("Opened", openedAt.formatted(date: .abbreviated, time: .omitted))
                        if let expiresAt = product.expiresAt {
                            detailLine(product.isExpired ? "Expired" : "Good until", expiresAt.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    detailLine("Use within", "\(product.effectivePAOMonths) months")
                    if product.paoIsEstimated {
                        Text("No open-jar symbol on the label, so this uses what's typical for this type of product. You can change it in Edit details.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(Theme.label)
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.ink)
        }
    }

    private func section<Content: View>(top: String, bottom: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TwoToneTitle(top: top, bottom: bottom)
            content()
        }
        .padding(.horizontal, 20)
    }
}

// Half-width pill: espresso with a check when on, sand with a plus when off
private struct RoutineToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) { isOn.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn ? icon + ".fill" : icon)
                Text(title).font(.system(size: 15, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: isOn ? "checkmark" : "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(isOn ? Theme.onInk : Theme.ink)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isOn ? Theme.ink : Theme.card, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel("\(title) routine")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// Sand tile with an icon, title and value
private struct InfoTile: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LayerIcon(name: icon, size: 20)
            Spacer(minLength: 0)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(value).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(3)
        }
        .foregroundStyle(Theme.ink)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

// Like the reference's "Key Ingredients" cards
private struct IngredientCard: View {
    let name: String
    let summary: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Circle().fill(Theme.page)
                LayerIcon(name: icon, size: 30).foregroundStyle(Theme.olive)
            }
            .frame(width: 64, height: 64)
            Spacer(minLength: 0)
            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(summary)
                .font(Theme.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(4)
        }
        .padding(16)
        .frame(width: 180, height: 210, alignment: .topLeading)
        .background(Theme.card, in: .rect(cornerRadius: 20))
    }
}
