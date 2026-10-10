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

    // First launch: a short tour of what Layer does, then the skin questions
    private var welcome: some View {
        IntroTour { advance() }
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
                            .fill(Theme.primary)
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
                if isEditing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel", systemImage: "xmark") { dismiss() }.tint(Theme.ink)
                    }
                }
                if step.rawValue > Step.skinType.rawValue {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.left") {
                            step = Step(rawValue: step.rawValue - 1) ?? .skinType
                        }
                        .tint(Theme.ink)
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
                                .foregroundStyle(isOn ? Theme.onPrimary : Theme.ink)
                            if let detail {
                                Text(option[keyPath: detail])
                                    .font(Theme.caption)
                                    .foregroundStyle(isOn ? Theme.onPrimary.opacity(0.8) : Theme.muted)
                            }
                        }
                        Spacer()
                        ZStack {
                            // Lime mark on dark green when selected
                            if isMulti {
                                RoundedRectangle(cornerRadius: 6).strokeBorder(isOn ? Theme.lime : Theme.ink.opacity(0.3), lineWidth: 1.2)
                                if isOn { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                            } else {
                                Circle().strokeBorder(isOn ? Theme.lime : Theme.ink.opacity(0.3), lineWidth: 1.2)
                                if isOn { Circle().fill(Theme.lime).padding(5) }
                            }
                        }
                        .foregroundStyle(Theme.lime)
                        .frame(width: 22, height: 22)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)
                    .background(isOn ? Theme.primary : Theme.card, in: .rect(cornerRadius: 16))
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
            .foregroundStyle(isSelected ? Theme.onPrimary : Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(14)
            .background(isSelected ? Theme.primary : Theme.card, in: .rect(cornerRadius: 18))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Intro tour

private struct IntroPage: Identifiable {
    let id: Int
    let art: IntroArt.Kind
    let top: String
    let bottom: String
    let body: String
    let points: [String]
}

struct IntroTour: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pages: [IntroPage] = [
        IntroPage(id: 0, art: .brand, top: "Skincare that", bottom: "makes sense",
                  body: "Layer reads your products, explains what's inside, and builds a morning and night routine that works for your skin.",
                  points: []),
        IntroPage(id: 1, art: .system("text.viewfinder"), top: "Scan any", bottom: "label",
                  body: "Snap the ingredient list on a bottle, tube or box. Layer reads it right on your phone and finds the product photo.",
                  points: ["Turn the bottle for 2 or 3 angles", "Learns new ingredients as you scan"]),
        IntroPage(id: 2, art: .icon("ingredient"), top: "Know what's", bottom: "inside",
                  body: "Every ingredient is checked against your skin type and concerns, so you see what helps and what to watch.",
                  points: ["Key actives in plain words", "Shelf life and expiry reminders"]),
        IntroPage(id: 3, art: .icon("layers"), top: "Layer it", bottom: "right",
                  body: "Pick products for morning and night. Layer puts them in order and flags pairs that clash, like retinol with acids.",
                  points: ["Routine review with swaps", "Your routine on your home screen"]),
        IntroPage(id: 4, art: .system("mic"), top: "Check in by", bottom: "voice",
                  body: "Say how your skin feels after a routine. Layer keeps the notes so you can spot what's working.",
                  points: ["Everything stays on your phone"]),
    ]

    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Wordmark(size: 26)
                Spacer()
                if !isLast {
                    Button("Skip") { withAnimation(.snappy) { page = pages.count - 1 } }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 44)

            TabView(selection: $page) {
                ForEach(pages) { item in
                    pageView(item).tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Dots that stretch into a pill on the current page
            HStack(spacing: 6) {
                ForEach(pages) { item in
                    Capsule()
                        .fill(item.id == page ? Theme.primary : Theme.faint)
                        .frame(width: item.id == page ? 22 : 7, height: 7)
                }
            }
            .animation(.snappy(duration: 0.25), value: page)
            .padding(.bottom, 18)

            Button(isLast ? "Set up my skin" : "Next") {
                if isLast { onFinish() } else { withAnimation(.snappy) { page += 1 } }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Theme.page.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: page)
    }

    private func pageView(_ item: IntroPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                IntroArt(kind: item.art)

                VStack(alignment: .leading, spacing: 12) {
                    if item.id > 0 { IndexLabel(number: item.id) }
                    TwoToneTitle(top: item.top, bottom: item.bottom, size: 38)
                    Text(item.body)
                        .font(Theme.body)
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !item.points.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(item.points, id: \.self) { point in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.onLime)
                                    .frame(width: 20, height: 20)
                                    .background(Theme.lime, in: .circle)
                                Text(point)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
    }
}

// Forest panel with the app's swatch circles and one big icon in lime
private struct IntroArt: View {
    enum Kind {
        case brand
        case icon(String)
        case system(String)
    }

    let kind: Kind

    var body: some View {
        ZStack {
            Theme.olive
            // Same overlapping swatches as the app icon, drifting off the edge
            Circle().fill(Theme.primary).frame(width: 220).offset(x: -110, y: 70)
            Circle().fill(Theme.lime.opacity(0.18)).frame(width: 180).offset(x: 120, y: -70)

            switch kind {
            case .brand:
                ZStack {
                    Circle().fill(Color(light: 0x5F6651, dark: 0x5F6651)).frame(width: 96).offset(x: 34, y: 22)
                    Circle().fill(Theme.page.opacity(0.9)).frame(width: 96).offset(x: -34, y: 22)
                    Circle().fill(Theme.lime.opacity(0.92)).frame(width: 96).offset(y: -30)
                }
            case .icon(let name):
                LayerIcon(name: name, size: 92).foregroundStyle(Theme.lime)
            case .system(let name):
                Image(systemName: name)
                    .font(.system(size: 76, weight: .light))
                    .foregroundStyle(Theme.lime)
            }
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 30))
        .accessibilityHidden(true)
    }
}
