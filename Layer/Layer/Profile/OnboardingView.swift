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
        if step == .welcome {
            welcome
        } else {
            questions
        }
    }

    // MARK: - Welcome

    private var welcome: some View {
        ZStack {
            // Warm skin-tone wash instead of a stock photo
            LinearGradient(
                colors: [Color(light: 0xF3E6D8, dark: 0x2A211B), Color(light: 0xDDBFA4, dark: 0x3B2C22), Color(light: 0xC49A7C, dark: 0x4A3628)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 14) {
                    LayerIcon(name: "layers", size: 40)
                    Text("Layer")
                        .font(Theme.display(76))
                        .tracking(-1)
                    Text("INGREDIENT-SMART SKINCARE")
                        .font(.system(size: 12, weight: .regular))
                        .tracking(4)
                }
                .foregroundStyle(Color(light: 0xFFFBF6, dark: 0xF3E6D8))
                Spacer()

                VStack(alignment: .leading, spacing: 18) {
                    Text("A few quick questions about your skin, so Layer can tell you what on your shelf works for you and what to watch out for.")
                        .font(Theme.body)
                        .foregroundStyle(Color(light: 0x2A1E1B, dark: 0xF3EEE6))
                    Text("About 30 seconds. Your answers stay on your phone.")
                        .font(Theme.caption)
                        .foregroundStyle(Color(light: 0x2A1E1B, dark: 0xF3EEE6).opacity(0.7))
                    Button("Get started") { advance() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(24)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 28))
                .padding(16)
            }
        }
    }

    // MARK: - Questions

    private var questions: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Thin progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.hairline)
                        Rectangle()
                            .fill(Theme.ink)
                            .frame(width: geo.size.width * CGFloat(step.rawValue) / CGFloat(Step.allCases.count - 1))
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 20)
                .animation(.snappy, value: step)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        content
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(step == .avoid ? (isEditing ? "Save" : "Done") : "Continue") { advance() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(step == .concerns && profile.concerns.isEmpty)
                    .opacity(step == .concerns && profile.concerns.isEmpty ? 0.4 : 1)
                    .padding(20)
            }
            .pageBackground()
            .animation(.snappy, value: step)
            .toolbar {
                if step.rawValue > Step.skinType.rawValue {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.left") {
                            step = Step(rawValue: step.rawValue - 1) ?? .skinType
                        }
                        .buttonStyle(InkCircleStyle())
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                if isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel", systemImage: "xmark") { dismiss() }.buttonStyle(InkCircleStyle())
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
        }
        .interactiveDismissDisabled(!isEditing)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            EmptyView()

        case .skinType:
            Header(number: 1, top: "Your skin", bottom: "type", subtitle: "Think about how it feels a few hours after washing.")
            ChoiceList(options: SkinType.allCases, selected: { profile.skinType == $0 }, title: \.label, detail: \.detail) {
                profile.skinType = $0
            }

        case .sensitivity:
            Header(number: 2, top: "Does it react", bottom: "easily?", subtitle: "Stinging, redness or itching from new products.")
            ChoiceList(options: Sensitivity.allCases, selected: { profile.sensitivity == $0 }, title: \.label, detail: \.detail) {
                profile.sensitivity = $0
            }

        case .concerns:
            Header(number: 3, top: "What to", bottom: "work on", subtitle: "Pick up to 3.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(SkinConcern.allCases) { concern in
                    ConcernTile(concern: concern, isSelected: profile.concerns.contains(concern)) {
                        toggle(concern)
                    }
                }
            }

        case .experience:
            Header(number: 4, top: "Your history", bottom: "with actives", subtitle: "Retinol, AHAs, BHAs and similar.")
            ChoiceList(options: ActivesExperience.allCases, selected: { profile.experience == $0 }, title: \.label, detail: \.detail) {
                profile.experience = $0
            }

        case .avoid:
            Header(number: 5, top: "Anything to", bottom: "avoid?", subtitle: "Optional. Layer will flag these on your products.")
            ChoiceList(options: AvoidPreference.allCases, selected: { profile.avoid.contains($0) }, title: \.label, detail: nil, isMulti: true) { item in
                if profile.avoid.contains(item) { profile.avoid.remove(item) } else { profile.avoid.insert(item) }
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
            withAnimation(.snappy) { step = next }
        } else {
            onDone(profile)
            if isEditing { dismiss() }
        }
    }
}

private struct Header: View {
    let number: Int
    let top: String
    let bottom: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IndexLabel(number: number)
            TwoToneTitle(top: top, bottom: bottom, size: 36)
            Text(subtitle)
                .font(Theme.body)
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 8)
    }
}

// Hairline list of options
private struct ChoiceList<Option: Identifiable>: View {
    let options: [Option]
    let selected: (Option) -> Bool
    let title: KeyPath<Option, String>
    let detail: KeyPath<Option, String>?
    var isMulti = false
    let pick: (Option) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                let isOn = selected(option)
                Button {
                    withAnimation(.snappy) { pick(option) }
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option[keyPath: title])
                                .font(Theme.display(21))
                                .foregroundStyle(Theme.ink)
                            if let detail {
                                Text(option[keyPath: detail])
                                    .font(Theme.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                        ZStack {
                            if isMulti {
                                RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.ink.opacity(isOn ? 1 : 0.3), lineWidth: 1.2)
                                if isOn { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
                            } else {
                                Circle().strokeBorder(Theme.ink.opacity(isOn ? 1 : 0.3), lineWidth: 1.2)
                                if isOn { Circle().fill(Theme.ink).padding(5) }
                            }
                        }
                        .foregroundStyle(Theme.ink)
                        .frame(width: 22, height: 22)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)
                    .background(Theme.card, in: .rect(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isOn ? Theme.ink : .clear, lineWidth: 1.2)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

private struct ConcernTile: View {
    let concern: SkinConcern
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: concern.symbol)
                    .font(.system(size: 20, weight: .light))
                Text(concern.label)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Theme.oliveText : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(14)
            .background(isSelected ? Theme.olive : Theme.card, in: .rect(cornerRadius: 18))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
