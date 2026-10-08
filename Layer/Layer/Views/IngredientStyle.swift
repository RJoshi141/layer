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
        case .cleanser, .base, .preservative: .secondary
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
                } else {
                    Text("Not in database")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let match, match.role != .base, match.role != .preservative {
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
