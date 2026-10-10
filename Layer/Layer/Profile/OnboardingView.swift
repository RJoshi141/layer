import SwiftUI

// First launch: five quick questions. Also reused from the Shelf toolbar to edit answers later.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var isEditing = false
    var onDone: (SkinProfile) -> Void

    @State private var profile: SkinProfile
    @State private var step: Step

    private enum Step: Int, CaseIterable {
        case welcome, skinType, sensitivity, concerns, experience, avoid
    }

    init(initial: SkinProfile?, onDone: @escaping (SkinProfile) -> Void) {
        self.isEditing = initial != nil
        self.onDone = onDone
        _profile = State(initialValue: initial ?? SkinProfile())
        // Editing skips the welcome screen
        _step = State(initialValue: initial == nil ? .welcome : .skinType)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step != .welcome {
                    ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    advance()
                } label: {
                    Text(step == .avoid ? (isEditing ? "Save" : "Get started") : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(step == .concerns && profile.concerns.isEmpty)
                .padding()
            }
            .animation(.snappy, value: step)
            .toolbar {
                if step.rawValue > (isEditing ? Step.skinType.rawValue : Step.welcome.rawValue) {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.left") {
                            step = Step(rawValue: step.rawValue - 1) ?? .welcome
                        }
                    }
                }
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(!isEditing)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "drop.halffull")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .padding(.top, 40)
                Text("Welcome to Layer")
                    .font(.largeTitle.bold())
                Text("A few quick questions about your skin, so Layer can tell you what on your shelf works for you and what to watch out for.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Takes about 30 seconds. Your answers stay on your phone.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

        case .skinType:
            Header(title: "What's your skin type?", subtitle: "Think about how it feels a few hours after washing.")
            ForEach(SkinType.allCases) { type in
                ChoiceRow(title: type.label, detail: type.detail, isSelected: profile.skinType == type) {
                    profile.skinType = type
                }
            }

        case .sensitivity:
            Header(title: "Does your skin react easily?", subtitle: "Stinging, redness or itching from new products.")
            ForEach(Sensitivity.allCases) { level in
                ChoiceRow(title: level.label, detail: level.detail, isSelected: profile.sensitivity == level) {
                    profile.sensitivity = level
                }
            }

        case .concerns:
            Header(title: "What do you want to work on?", subtitle: "Pick up to 3.")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SkinConcern.allCases) { concern in
                    ConcernTile(concern: concern, isSelected: profile.concerns.contains(concern)) {
                        toggle(concern)
                    }
                }
            }

        case .experience:
            Header(title: "How familiar are you with actives?", subtitle: "Retinol, AHAs, BHAs and similar.")
            ForEach(ActivesExperience.allCases) { level in
                ChoiceRow(title: level.label, detail: level.detail, isSelected: profile.experience == level) {
                    profile.experience = level
                }
            }

        case .avoid:
            Header(title: "Anything you'd rather avoid?", subtitle: "Optional. Layer will flag these on your products.")
            ForEach(AvoidPreference.allCases) { item in
                ChoiceRow(title: item.label, detail: nil, isSelected: profile.avoid.contains(item), isMulti: true) {
                    if profile.avoid.contains(item) { profile.avoid.remove(item) } else { profile.avoid.insert(item) }
                }
            }
        }
    }

    private func toggle(_ concern: SkinConcern) {
        if let index = profile.concerns.firstIndex(of: concern) {
            profile.concerns.remove(at: index)
        } else if profile.concerns.count < 3 {
            profile.concerns.append(concern)
        }
    }

    private func advance() {
        if let next = Step(rawValue: step.rawValue + 1) {
            step = next
        } else {
            onDone(profile)
            if isEditing { dismiss() }
        }
    }
}

private struct Header: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }
}

private struct ChoiceRow: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    var isMulti = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected
                      ? (isMulti ? "checkmark.square.fill" : "checkmark.circle.fill")
                      : (isMulti ? "square" : "circle"))
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding()
            .background(.background.secondary, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ConcernTile: View {
    let concern: SkinConcern
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: concern.symbol)
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Text(concern.label).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .padding()
            .background(.background.secondary, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
