import SwiftUI
import SwiftData

struct RoutineAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileStore.self) private var profileStore
    @Query private var products: [Product]

    @State private var period: RoutinePeriod
    @State private var context: AssistantContext?
    @State private var chat = RoutineChat()
    @State private var question = ""
    @State private var applied = Set<String>()

    init(period: RoutinePeriod) {
        _period = State(initialValue: period)
    }

    private var suggestions: [Suggestion] {
        context?.advisor.suggestions(for: period) ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Picker("Routine", selection: $period) {
                            Text("Morning").tag(RoutinePeriod.am)
                            Text("Night").tag(RoutinePeriod.pm)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }

                    Section {
                        ForEach(suggestions) { suggestion in
                            SuggestionRow(suggestion: suggestion, isApplied: applied.contains(suggestion.id)) {
                                if let action = suggestion.action { apply(action, for: suggestion.id) }
                            }
                            .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text("Review")
                    } footer: {
                        Text("Based on your shelf, your skin profile and Layer's ingredient rules. Ingredient info, not medical advice.")
                    }

                    Section("Ask Layer") {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(QuickQuestion.allCases) { quick in
                                    Button(quick.rawValue) {
                                        guard let context else { return }
                                        withAnimation { chat.ask(quick, context: context, period: period) }
                                    }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                                    .font(.subheadline)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                        ForEach(chat.messages) { message in
                            ChatBubble(message: message)
                                .listRowSeparator(.hidden)
                                .id(message.id)
                        }
                        if chat.isThinking {
                            ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .onChange(of: chat.messages.count) {
                    if let last = chat.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .pageBackground()
            .navigationTitle("Routine review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.buttonStyle(InkPillStyle())
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .task { refresh() }
        }
    }

    @ViewBuilder
    private var inputBar: some View {
        if RoutineChat.canChat {
            HStack {
                TextField("Ask about your routine", text: $question, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Button("Send", systemImage: "arrow.up.circle.fill") { send() }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || chat.isThinking)
            }
            .padding()
            .background(.bar)
        } else {
            Text("Typing your own questions needs Apple Intelligence (iPhone 15 Pro or newer). The quick questions and review work on any iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }

    private func send() {
        let text = question.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let context else { return }
        question = ""
        Task { await chat.ask(text, context: context) }
    }

    // Snapshot once, not on every keystroke. Matching every ingredient isn't free.
    private func refresh() {
        context = AssistantContext(
            products: products.map { $0.advisorProduct(profile: profileStore.profile) },
            profile: profileStore.profile,
            rules: IngredientDatabase.shared.rules
        )
    }

    // Human in the loop: the advisor proposes, you tap to apply
    private func apply(_ action: AdvisorAction, for suggestionID: String) {
        let product = { (id: String) in products.first { String(describing: $0.persistentModelID) == id } }
        switch action {
        case .add(let id, let period):
            product(id)?.setIn(period, true)
        case .remove(let id, let period):
            product(id)?.setIn(period, false)
        case .move(let id, let from, let to):
            product(id)?.setIn(from, false)
            product(id)?.setIn(to, true)
        case .swap(let remove, let add, let period):
            product(remove)?.setIn(period, false)
            product(add)?.setIn(period, true)
        }
        applied.insert(suggestionID)
        withAnimation { refresh() }
    }
}

private struct SuggestionRow: View {
    let suggestion: Suggestion
    let isApplied: Bool
    let onApply: () -> Void

    private var style: (symbol: String, color: Color) {
        switch suggestion.kind {
        case .fix: ("exclamationmark.triangle", Theme.warning)
        case .swap: ("arrow.triangle.2.circlepath", Theme.ink)
        case .gap: ("plus.circle", Theme.olive)
        case .tip: ("lightbulb", Theme.muted)
        case .good: ("checkmark.seal", Theme.good)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: style.symbol).foregroundStyle(style.color)
            VStack(alignment: .leading, spacing: 6) {
                Text(suggestion.title).font(.subheadline.weight(.semibold))
                Text(suggestion.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let action = suggestion.action {
                    Button(isApplied ? "Done" : action.label, systemImage: isApplied ? "checkmark" : "wand.and.stars", action: onApply)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isApplied)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.fromUser { Spacer(minLength: 40) }
            Text(message.text)
                .font(.subheadline)
                .padding(10)
                .background(
                    message.fromUser ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.fill.tertiary),
                    in: .rect(cornerRadius: 14)
                )
                .textSelection(.enabled)
            if !message.fromUser { Spacer(minLength: 40) }
        }
    }
}

extension Product {
    func advisorProduct(profile: SkinProfile?) -> AdvisorProduct {
        let db = IngredientDatabase.shared
        let refs = matchedKeys.compactMap { db.reference(for: $0) }
        let fit = profile.map { FitChecker(profile: $0).findings(forLabel: ingredients.map { db.match($0) }) } ?? []
        return AdvisorProduct(
            id: String(describing: persistentModelID),
            name: name,
            category: category,
            tags: tags,
            activeNames: refs.filter { $0.role == .active }.map(\.name),
            isExpired: isExpired,
            inAM: inAM,
            inPM: inPM,
            cautions: fit.filter { $0.severity != .fine }.map(\.title),
            // FitChecker's "good-<concern>" findings already apply the profile's rules (like dryness needing 2 helpers)
            helps: fit.compactMap { $0.id.hasPrefix("good-") ? SkinConcern(rawValue: String($0.id.dropFirst(5))) : nil }
        )
    }
}
