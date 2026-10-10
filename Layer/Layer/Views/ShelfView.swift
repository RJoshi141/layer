import SwiftUI
import UIKit
import SwiftData

struct ShelfView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Product.addedAt, order: .reverse) private var products: [Product]
    @Environment(ProfileStore.self) private var profileStore
    @State private var isAdding = false
    @State private var isEditingProfile = false
    @State private var filter: ProductCategory?

    private var shown: [Product] {
        guard let filter else { return products }
        return products.filter { $0.category == filter }
    }

    // Only offer filters for types that are actually on the shelf
    private var categories: [ProductCategory] {
        ProductCategory.allCases.filter { category in products.contains { $0.category == category } }
    }

    private var expiringCount: Int {
        products.filter { product in
            switch product.expiryStatus {
            case .expired, .soon: return true
            case .good, .notOpened: return false
            }
        }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if products.isEmpty {
                        emptyState
                    } else {
                        if categories.count > 1 { filterBar }
                        list
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .pageBackground()
            .navigationDestination(for: Product.self) { ProductDetailView(product: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("My skin", systemImage: "person") { isEditingProfile = true }
                        .buttonStyle(InkCircleStyle())
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) {
                    Button("Add product", systemImage: "plus") { isAdding = true }
                        .buttonStyle(InkCircleStyle())
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Wordmark()
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $isAdding) {
                AddProductView()
            }
            .sheet(isPresented: $isEditingProfile) {
                OnboardingView(initial: profileStore.profile) { profileStore.save($0) }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TwoToneTitle(top: "Your", bottom: "Shelf", size: 40)
            if !products.isEmpty {
                HStack(spacing: 6) {
                    Text("\(products.count) products")
                    if expiringCount > 0 {
                        Text("·")
                        Text("\(expiringCount) need attention").foregroundStyle(Theme.warning)
                    }
                }
                .font(Theme.caption)
                .foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 4)
    }

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip(title: "All", icon: nil, isOn: filter == nil) { filter = nil }
                ForEach(categories) { category in
                    FilterChip(title: category.label, icon: category.iconName, isOn: filter == category) {
                        filter = filter == category ? nil : category
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .animation(.snappy, value: filter)
    }

    private var list: some View {
        VStack(spacing: 4) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, product in
                NavigationLink(value: product) {
                    ProductRow(product: product, index: index + 1)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        withAnimation { context.delete(product) }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(Theme.card)
                HStack(spacing: 22) {
                    LayerIcon(name: "cleanser", size: 40)
                    LayerIcon(name: "serum", size: 40)
                    LayerIcon(name: "jar", size: 40)
                    LayerIcon(name: "sunscreen", size: 40)
                }
                .foregroundStyle(Theme.ink.opacity(0.7))
            }
            .frame(height: 220)

            Text("Scan the back of a bottle and Layer reads the ingredients, flags what clashes, and builds your routine.")
                .font(Theme.body)
                .foregroundStyle(Theme.muted)

            Button("Scan your first product") { isAdding = true }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}

// MARK: - Rows

struct ProductRow: View {
    let product: Product
    var index: Int = 1

    private var actives: [IngredientReference] {
        product.matchedKeys
            .compactMap { IngredientDatabase.shared.reference(for: $0) }
            .filter { $0.role == .active }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ProductThumbnail(product: product, size: 72)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    IndexLabel(number: index)
                    if !product.brand.isEmpty {
                        Text(product.brand.uppercased())
                            .font(Theme.label)
                            .tracking(1)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                Text(product.name)
                    .font(Theme.display(20))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                if !actives.isEmpty {
                    Text(actives.prefix(3).map(\.name).joined(separator: " · "))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.olive)
                        .lineLimit(1)
                } else {
                    Text(product.category.label)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.muted)
                }
            }

            Spacer(minLength: 0)

            ExpiryDot(status: product.expiryStatus)
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}

struct ExpiryDot: View {
    let status: ExpiryStatus

    var body: some View {
        switch status {
        case .expired:
            Circle().fill(Theme.warning).frame(width: 8, height: 8).accessibilityLabel("Expired")
        case .soon:
            Circle().strokeBorder(Theme.warning, lineWidth: 1.5).frame(width: 8, height: 8).accessibilityLabel("Expires soon")
        case .good, .notOpened:
            EmptyView()
        }
    }
}

struct ProductThumbnail: View {
    let product: Product
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Theme.card
            if let data = product.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LayerIcon(name: product.category.iconName, size: size * 0.42)
                    .foregroundStyle(Theme.ink.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.2))
    }
}

struct FilterChip: View {
    let title: String
    let icon: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { LayerIcon(name: icon, size: 16) }
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isOn ? Theme.onInk : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(isOn ? Theme.ink : Theme.card, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
