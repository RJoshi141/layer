import SwiftUI

extension IngredientReference.Role {
    var color: Color {
        switch self {
        case .active: .purple
        case .hydrator: .blue
        case .barrier: .teal
        case .soothing: .green
        case .antioxidant: .yellow
        case .sunscreen: .orange
        case .caution: .red
        case .botanical: .mint
        case .cleanser, .base, .preservative, .other: .secondary
        }
    }

    var label: String {
        switch self {
        case .active: "Active"
        case .hydrator: "Hydrator"
        case .barrier: "Barrier"
        case .soothing: "Soothing"
        case .antioxidant: "Antioxidant"
        case .sunscreen: "UV filter"
        case .cleanser: "Cleanser"
        case .base: "Base"
        case .preservative: "Preservative"
        case .caution: "Watch"
        case .botanical: "Botanical"
        case .other: "Other"
        }
    }

    // Tags that come with a role when you reclassify an ingredient by hand
    var defaultTags: [String] {
        switch self {
        case .hydrator: ["humectant"]
        case .barrier: ["emollient"]
        default: []
        }
    }
}

struct IngredientRow: View {
    let raw: String
    let match: IngredientReference?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(match?.role.color ?? Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(raw)
                if let match {
                    Text(match.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if match.isLearned {
                        Label("Learned from your scans", systemImage: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                } else {
                    Text("Couldn't identify this one")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let match, ![.base, .preservative, .other].contains(match.role) {
                Text(match.role.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(match.role.color.opacity(0.15), in: .capsule)
                    .foregroundStyle(match.role.color)
            }
        }
    }
}
