import Foundation
import FoundationModels
import Observation

// Snapshot of the shelf + profile that both answer paths read from:
// quick questions (every iPhone) and the on-device model's tools (Apple Intelligence iPhones)
nonisolated struct AssistantContext: Sendable {
    let products: [AdvisorProduct]
    let profile: SkinProfile?
    let rules: [ConflictRule]

    var advisor: RoutineAdvisor { RoutineAdvisor(products: products, profile: profile, rules: rules) }

    func steps(_ period: RoutinePeriod) -> [AdvisorProduct] {
        products.filter { $0.isIn(period) }.sorted { $0.category.layerRank < $1.category.layerRank }
    }

    // MARK: - Answers in plain text (also what the model's tools return)

    func explainRoutine(_ period: RoutinePeriod) -> String {
        let steps = steps(period)
        guard !steps.isEmpty else { return "Your \(period.label) routine is empty. Tap Edit on the Routine tab to add products." }
        let lines = steps.enumerated().map { index, product in
            "\(index + 1). \(product.category.label): \(product.name). \(describe(product))"
        }
        return "Your \(period.label) routine, in layering order:\n" + lines.joined(separator: "\n")
    }

    func describe(_ product: AdvisorProduct) -> String {
        var parts: [String] = []
        if !product.activeNames.isEmpty { parts.append("Actives: \(product.activeNames.prefix(3).joined(separator: ", ")).") }
        if !product.helps.isEmpty { parts.append("Good for \(product.helps.map { $0.label.lowercased() }.joined(separator: " and ")).") }
        if !product.cautions.isEmpty { parts.append("Heads-up: \(product.cautions.joined(separator: ", ").lowercased()).") }
        if product.isExpired { parts.append("Past its date.") }
        return parts.isEmpty ? "A supporting step, no strong actives." : parts.joined(separator: " ")
    }

    func improvements(_ period: RoutinePeriod) -> String {
        let suggestions = advisor.suggestions(for: period).filter { $0.kind != .good }
        guard !suggestions.isEmpty else { return "Your \(period.label) routine looks solid. No clashes, nothing missing, nothing expired." }
        return suggestions.map { "• \($0.title). \($0.detail)" }.joined(separator: "\n")
    }

    func replacements(_ period: RoutinePeriod) -> String {
        let swaps = advisor.suggestions(for: period).filter { $0.kind == .swap }
        guard !swaps.isEmpty else { return "Nothing in your \(period.label) routine needs replacing right now." }
        return swaps.map { "• \($0.title). \($0.detail)" }.joined(separator: "\n")
    }

    func expiring() -> String {
        let expired = products.filter(\.isExpired).map(\.name)
        guard !expired.isEmpty else { return "Nothing on your shelf is past its date." }
        return "Past their date: \(ListFormatter.localizedString(byJoining: expired)). Replace these first, since old actives are weaker and more likely to irritate."
    }

    func shelfSummary() -> String {
        products.map { product in
            let routines = [product.inAM ? "morning" : nil, product.inPM ? "night" : nil].compactMap { $0 }
            return "- \(product.name) (\(product.category.label.lowercased())\(routines.isEmpty ? ", not in a routine" : ", in \(routines.joined(separator: " and "))")). \(describe(product))"
        }.joined(separator: "\n")
    }
}

// Quick questions work on every iPhone, no model needed
enum QuickQuestion: String, CaseIterable, Identifiable {
    case explain = "What does each step do?"
    case improve = "How can I improve it?"
    case replace = "What should I replace?"
    case expiring = "Is anything expired?"

    var id: String { rawValue }

    func answer(_ context: AssistantContext, period: RoutinePeriod) -> String {
        switch self {
        case .explain: context.explainRoutine(period)
        case .improve: context.improvements(period)
        case .replace: context.replacements(period)
        case .expiring: context.expiring()
        }
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let fromUser: Bool
    let text: String
}

@Observable
final class RoutineChat {
    private(set) var messages: [ChatMessage] = []
    private(set) var isThinking = false
    private var session: LanguageModelSession?

    static var canChat: Bool { SystemLanguageModel.default.isAvailable }

    func ask(_ question: QuickQuestion, context: AssistantContext, period: RoutinePeriod) {
        messages.append(ChatMessage(fromUser: true, text: question.rawValue))
        messages.append(ChatMessage(fromUser: false, text: question.answer(context, period: period)))
    }

    // Free-text questions go to the on-device model, which answers through tools over your real data
    func ask(_ question: String, context: AssistantContext) async {
        messages.append(ChatMessage(fromUser: true, text: question))
        isThinking = true
        defer { isThinking = false }

        // New snapshot per question, so tools always see the routine as it is right now
        let session = LanguageModelSession(
            tools: [
                RoutineTool(context: context),
                SuggestionsTool(context: context),
                ShelfTool(context: context),
            ],
            instructions: """
                You are Layer, a friendly skincare assistant inside an iOS app. \
                Always use the tools to look up the user's routines, shelf and suggestions before answering. \
                Only recommend products that are on their shelf. If something is missing, name ingredients to look for, never brands. \
                Keep answers short and practical. This is ingredient info, not medical advice; suggest a dermatologist for anything persistent or painful.
                """
        )
        self.session = session
        do {
            let response = try await session.respond(to: question)
            messages.append(ChatMessage(fromUser: false, text: response.content))
        } catch {
            messages.append(ChatMessage(fromUser: false, text: "I couldn't answer that one. Try one of the quick questions."))
        }
    }
}

// MARK: - Tools the model can call. Each one returns facts from the advisor, never guesses.

@Generable
nonisolated struct PeriodArgument {
    @Guide(description: "Which routine: am for morning, pm for night.", .anyOf(["am", "pm"]))
    var period: String
}

@Generable
nonisolated struct NoArgument {
    @Guide(description: "Leave empty.")
    var note: String
}

nonisolated struct RoutineTool: Tool {
    let name = "getRoutine"
    let description = "Gets the user's morning or night routine in layering order, with what each product does."
    let context: AssistantContext

    func call(arguments: PeriodArgument) async throws -> String {
        context.explainRoutine(RoutinePeriod(rawValue: arguments.period) ?? .pm)
    }
}

nonisolated struct SuggestionsTool: Tool {
    let name = "getSuggestions"
    let description = "Gets improvements, missing steps, clashes and replacement ideas for the morning or night routine."
    let context: AssistantContext

    func call(arguments: PeriodArgument) async throws -> String {
        context.improvements(RoutinePeriod(rawValue: arguments.period) ?? .pm)
    }
}

nonisolated struct ShelfTool: Tool {
    let name = "getShelf"
    let description = "Lists every product the user owns, which routine it's in, its actives, and whether it's expired."
    let context: AssistantContext

    func call(arguments: NoArgument) async throws -> String {
        context.shelfSummary()
    }
}
