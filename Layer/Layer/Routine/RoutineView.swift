import SwiftUI
import SwiftData

struct RoutineView: View {
    @Query private var products: [Product]
    @Environment(ProfileStore.self) private var profileStore
    @Query(sort: \RoutineLog.date, order: .reverse) private var logs: [RoutineLog]
    @State private var isCheckingIn = false
    @State private var period: RoutinePeriod = Calendar.current.component(.hour, from: .now) < 15 ? .am : .pm
    @State private var isEditing = false
    @State private var isReviewing = false

    // Order comes from category, so we never have to store or drag-sort it
    private var steps: [Product] {
        products
            .filter { $0.isIn(period) }
            .sorted { $0.category.layerRank < $1.category.layerRank }
    }

    private var findings: [Finding] {
        let items = steps.map(\.routineItem)
        let personal = profileStore.profile.map { FitChecker(profile: $0).routineFindings(items) } ?? []
        return personal + ConflictChecker.check(items, period: period, rules: IngredientDatabase.shared.rules)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    periodTabs

                    if steps.isEmpty {
                        emptyState
                    } else {
                        stepList
                        if !findings.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                TwoToneTitle(top: "Heads", bottom: "Up", size: 26)
                                ForEach(findings) { FindingRow(finding: $0) }
                            }
                        }
                    }

                    if !products.isEmpty { reviewCard }

                    if !logs.isEmpty { checkIns }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .animation(.snappy, value: period)
            }
            .pageBackground()
            .toolbar {
                // Same layout as Shelf: one action left, one action + wordmark right
                ToolbarItem(placement: .topBarLeading) {
                    Button("Check in", systemImage: "mic") { isCheckingIn = true }
                        .buttonStyle(InkCircleStyle())
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit routine", systemImage: "pencil") { isEditing = true }
                        .buttonStyle(InkCircleStyle())
                        .disabled(products.isEmpty)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Wordmark()
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $isEditing) {
                RoutineEditorView(period: period)
            }
            .sheet(isPresented: $isCheckingIn) {
                CheckInView()
            }
            .sheet(isPresented: $isReviewing) {
                RoutineAssistantView(period: period)
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TwoToneTitle(top: period == .am ? "Your morning" : "Your nighttime", bottom: "Ritual", size: 40)
            Text(steps.isEmpty ? "Nothing here yet" : "\(steps.count) steps, in layering order")
                .font(Theme.caption)
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 4)
    }

    // Underlined text tabs, like the reference's "Product Details / Key Benefits"
    private var periodTabs: some View {
        HStack(spacing: 24) {
            ForEach([RoutinePeriod.am, .pm], id: \.self) { option in
                Button {
                    period = option
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: option == .am ? "sun.max" : "moon")
                            Text(option == .am ? "Morning" : "Night")
                        }
                        .font(.system(size: 15, weight: period == option ? .semibold : .regular))
                        .foregroundStyle(period == option ? Theme.ink : Theme.muted)
                        Rectangle()
                            .fill(period == option ? Theme.ink : .clear)
                            .frame(height: 1.5)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(period == option ? .isSelected : [])
            }
            Spacer()
        }
    }

    private var stepList: some View {
        VStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, product in
                StepRow(number: index + 1, product: product)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                LayerIcon(name: "rinse", size: 34)
                LayerIcon(name: "serum", size: 34)
                LayerIcon(name: "jar", size: 34)
                LayerIcon(name: period == .am ? "sunscreen" : "mask", size: 34)
            }
            .foregroundStyle(Theme.ink.opacity(0.6))
            Text("Pick products from your shelf and Layer puts them in the right order.")
                .font(Theme.body)
                .foregroundStyle(Theme.muted)
            Button("Build this routine") { isEditing = true }
                .buttonStyle(OutlineButtonStyle())
                .disabled(products.isEmpty)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 24))
    }

    // Olive feature card that opens the assistant
    private var reviewCard: some View {
        Button {
            isReviewing = true
        } label: {
            HStack(alignment: .top, spacing: 14) {
                LayerIcon(name: "glow", size: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review this routine")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Improvements, swaps and what each step does")
                        .font(Theme.caption)
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .light))
            }
            .foregroundStyle(Theme.oliveText)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.olive, in: .rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private var checkIns: some View {
        VStack(alignment: .leading, spacing: 12) {
            TwoToneTitle(top: "Recent", bottom: "Check-ins", size: 26)
            VStack(spacing: 4) {
                ForEach(logs.prefix(5)) { log in
                    LogRow(log: log)
                }
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
        HStack(spacing: 14) {
            Image(systemName: log.period == .am ? "sun.max" : "moon")
                .foregroundStyle(Theme.muted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(log.date.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(summary)
                    .font(Theme.caption)
                    .foregroundStyle(log.reactions.isEmpty ? Theme.muted : Theme.warning)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }
}

private struct StepRow: View {
    let number: Int
    let product: Product

    var body: some View {
        HStack(spacing: 14) {
            IndexLabel(number: number)
                .frame(width: 30, alignment: .leading)
            ProductThumbnail(product: product, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(Theme.display(19))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    LayerIcon(name: product.category.iconName, size: 13)
                    Text(product.category.label)
                }
                .font(Theme.caption)
                .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            ExpiryDot(status: product.expiryStatus)
        }
        .padding(.vertical, 12)
    }
}

// Used on the Routine tab and on product pages
struct FindingRow: View {
    let finding: Finding

    private var style: (symbol: String, color: Color) {
        switch finding.severity {
        case .avoid: ("xmark.octagon", Theme.warning)
        case .caution: ("exclamationmark.triangle", Theme.warning)
        case .fine: ("checkmark.seal", Theme.good)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: style.symbol)
                .font(.system(size: 15))
                .foregroundStyle(style.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(finding.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(finding.advice)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}
