import SwiftUI

extension IngredientReference.Role {
    var color: Color {
        switch self {
        // Earthy palette to match the app, no system colors
        case .active: Color(light: 0x8A4F3D, dark: 0xD99A84)        // terracotta
        case .hydrator: Color(light: 0x5C6E73, dark: 0xA5B8BD)      // slate
        case .barrier: Color(light: 0x8C6A45, dark: 0xD2B08A)       // caramel
        case .soothing: Color(light: 0x6B7256, dark: 0xB9C29E)      // olive
        case .antioxidant: Color(light: 0xA27B2E, dark: 0xD9B66A)   // ochre
        case .sunscreen: Color(light: 0xB4602F, dark: 0xE09A6A)     // burnt orange
        case .caution: Color(light: 0xA2453A, dark: 0xE08B7F)       // brick
        case .botanical: Color(light: 0x7E8F6A, dark: 0xB7C7A2)     // sage
        case .cleanser, .base, .preservative, .other: Theme.muted
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
    var number: Int? = nil          // label position, shown in the full list

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let number {
                IndexLabel(number: number)
                    .frame(width: 30, alignment: .leading)
                    .padding(.top, 3)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(match?.role.color ?? Theme.faint)
                        .frame(width: 7, height: 7)
                    Text(raw)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(match == nil ? Theme.muted : Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let match, ![.base, .preservative, .other].contains(match.role) {
                        Text(match.role.label)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(match.role.color.opacity(0.15), in: .capsule)
                            .foregroundStyle(match.role.color)
                            .fixedSize()
                    }
                }
                Group {
                    if let match {
                        Text(match.summary)
                        if match.isLearned {
                            Label("Learned from your scans", systemImage: "sparkles")
                        }
                    } else {
                        Text("Couldn't identify this one")
                    }
                }
                .font(Theme.caption)
                .foregroundStyle(Theme.muted)
                .padding(.leading, 15)      // lines up under the name, past the dot
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
