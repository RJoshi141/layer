import Foundation
import SwiftData

nonisolated enum RoutinePeriod: String, CaseIterable, Codable, Sendable {
    case am, pm
}

// One AM or PM routine. Voice check-ins land here (next milestone).
@Model
final class RoutineLog {
    var date: Date
    var periodRaw: String
    var products: [Product] = []
    // Short tags like "tight", "oily", "calm"
    var skinFeel: [String]
    // e.g. "breakout: chin", "redness: cheeks"
    var reactions: [String]
    // Raw voice transcript, kept so we can re-parse later
    var transcript: String
    var notes: String

    init(
        date: Date = .now,
        period: RoutinePeriod,
        products: [Product] = [],
        skinFeel: [String] = [],
        reactions: [String] = [],
        transcript: String = "",
        notes: String = ""
    ) {
        self.date = date
        self.periodRaw = period.rawValue
        self.products = products
        self.skinFeel = skinFeel
        self.reactions = reactions
        self.transcript = transcript
        self.notes = notes
    }

    var period: RoutinePeriod {
        get { RoutinePeriod(rawValue: periodRaw) ?? .pm }
        set { periodRaw = newValue.rawValue }
    }
}
