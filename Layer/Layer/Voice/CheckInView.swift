import SwiftUI
import SwiftData

struct CheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Product.name) private var products: [Product]

    @State private var recorder = SpeechRecorder()
    @State private var text = ""
    @State private var stage: Stage = .compose

    private enum Stage {
        case compose, parsing, review
    }

    // Review state, prefilled by the parser and fully editable
    @State private var period: RoutinePeriod = .pm
    @State private var selected = Set<String>()
    @State private var skinFeel: [String] = []
    @State private var reactions: [String] = []
    @State private var usedModel = false

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .compose: composeView
                case .parsing: ProgressView("Making sense of it…")
                case .review: reviewForm
                }
            }
            .pageBackground()
            .navigationTitle("Check in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Clear glass X on the left, same as the system back button
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", systemImage: "xmark") {
                        Task { await recorder.stop() }
                        dismiss()
                    }
                    .tint(Theme.ink)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    switch stage {
                    case .compose:
                        Button("Next") { Task { await parse() } }
                            .buttonStyle(InkPillStyle())
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || recorder.isRecording)
                    case .review:
                        Button("Save", action: save)
                            .buttonStyle(InkPillStyle())
                    case .parsing:
                        EmptyView()
                    }
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
    }

    // MARK: - Compose

    private var composeView: some View {
        VStack(spacing: 20) {
            if recorder.isRecording {
                ScrollView {
                    Text(recorder.transcript.isEmpty ? "Listening…" : recorder.transcript)
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                // Typing works everywhere, including the simulator
                TextEditor(text: $text)
                    .font(.title3)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Try: “Used the cleanser and the retinol. Skin feels a little tight, small breakout on my chin.”")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }

            if let error = recorder.errorMessage {
                Text(error).font(.footnote).foregroundStyle(Theme.warning)
            }

            micButton
        }
        .padding()
    }

    private var micButton: some View {
        Button {
            Task {
                if recorder.isRecording {
                    await recorder.stop()
                    // Append, so you can talk, edit, then talk again
                    text = [text, recorder.transcript].filter { !$0.isEmpty }.joined(separator: " ")
                } else {
                    await recorder.start()
                }
            }
        } label: {
            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                .font(.title)
                .foregroundStyle(Theme.onPrimary)
                .frame(width: 72, height: 72)
                .background(recorder.isRecording ? Theme.warning : Theme.primary, in: .circle)
                .symbolEffect(.pulse, isActive: recorder.isRecording)
        }
        .disabled(!SpeechRecorder.isAvailable || recorder.isPreparing)
        .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
    }

    // MARK: - Review

    private var reviewForm: some View {
        Form {
            Section {
                Picker("Routine", selection: $period) {
                    Text("Morning").tag(RoutinePeriod.am)
                    Text("Night").tag(RoutinePeriod.pm)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(usedModel ? "Filled in by the on-device model. Fix anything it got wrong." : "Filled in with keyword rules.")
            }

            Section("Used") {
                ForEach(products) { product in
                    let id = product.shelfEntry.id
                    Toggle(product.name, isOn: Binding(
                        get: { selected.contains(id) },
                        set: { if $0 { selected.insert(id) } else { selected.remove(id) } }
                    ))
                }
            }

            tagSection("Skin feels", tags: $skinFeel)
            tagSection("Reactions", tags: $reactions)

            Section("You said") {
                Text(text).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func tagSection(_ title: String, tags: Binding<[String]>) -> some View {
        Section(title) {
            ForEach(tags.wrappedValue, id: \.self) { Text($0) }
                .onDelete { tags.wrappedValue.remove(atOffsets: $0) }
            if tags.wrappedValue.isEmpty {
                Text("Nothing noted").foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Actions

    private func parse() async {
        stage = .parsing
        let result = await CheckInParser.parse(text, shelf: products.map(\.shelfEntry))
        period = result.period
        selected = Set(result.productIDs)
        skinFeel = result.skinFeel
        reactions = result.reactions
        usedModel = result.usedModel
        stage = .review
    }

    private func save() {
        let used = products.filter { selected.contains($0.shelfEntry.id) }
        context.insert(RoutineLog(
            period: period,
            products: used,
            skinFeel: skinFeel,
            reactions: reactions,
            transcript: text
        ))
        dismiss()
    }
}

extension Product {
    var shelfEntry: ShelfEntry {
        let actives = matchedKeys
            .compactMap { IngredientDatabase.shared.reference(for: $0) }
            .filter { $0.role == .active }
        return ShelfEntry(
            id: String(describing: persistentModelID),
            name: name,
            brand: brand,
            category: category,
            activeNames: actives.flatMap { [$0.name] + $0.aliases }
        )
    }
}
