import SwiftUI
import WidgetKit

// MARK: - Data from the app

// Same JSON shape as WidgetSnapshot in the app (Layer/WidgetSupport/WidgetSync.swift).
// The app writes it to the shared App Group whenever the routine changes.
struct RoutineSnapshot: Codable {
    struct Step: Codable, Hashable {
        let name: String
        let symbol: String
        let isExpired: Bool
    }

    var morning: [Step]
    var night: [Step]
    var morningHeadsUp: String?
    var nightHeadsUp: String?

    static let appGroup = "group.com.ritikajoshi.layer"
    static let key = "routineSnapshot"

    static func load() -> RoutineSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RoutineSnapshot.self, from: data)
    }

    static let sample = RoutineSnapshot(
        morning: [
            Step(name: "Gentle Cleanser", symbol: "bubbles.and.sparkles", isExpired: false),
            Step(name: "Vitamin C Serum", symbol: "eyedropper", isExpired: false),
            Step(name: "Daily Moisturizer", symbol: "humidity", isExpired: false),
            Step(name: "SPF 50", symbol: "sun.max", isExpired: false),
        ],
        night: [
            Step(name: "Gentle Cleanser", symbol: "bubbles.and.sparkles", isExpired: false),
            Step(name: "Retinol 0.5%", symbol: "eyedropper", isExpired: false),
            Step(name: "Barrier Cream", symbol: "humidity", isExpired: false),
        ],
        morningHeadsUp: nil,
        nightHeadsUp: nil
    )
}

enum Period {
    case morning, night

    // Same switch time as the app's Routine tab: morning until 3pm
    init(_ date: Date) {
        self = Calendar.current.component(.hour, from: date) < 15 ? .morning : .night
    }

    var title: String { self == .morning ? "This morning" : "Tonight" }
    var symbol: String { self == .morning ? "sun.horizon.fill" : "moon.stars.fill" }
}

// MARK: - Timeline

struct RoutineEntry: TimelineEntry {
    let date: Date
    let period: Period
    let steps: [RoutineSnapshot.Step]
    let headsUp: String?
    let hasData: Bool
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> RoutineEntry {
        entry(for: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (RoutineEntry) -> Void) {
        // Widget gallery preview: show sample data if the app hasn't saved anything yet
        completion(entry(for: .now, snapshot: RoutineSnapshot.load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoutineEntry>) -> Void) {
        let snapshot = RoutineSnapshot.load()
        let now = Date.now

        // One entry now, one at the next morning/night switch, so the widget flips on its own.
        // The app also reloads the timeline whenever the routine changes.
        var entries = [entry(for: now, snapshot: snapshot)]
        if let next = nextSwitch(after: now) {
            entries.append(entry(for: next, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(for date: Date, snapshot: RoutineSnapshot?) -> RoutineEntry {
        let period = Period(date)
        return RoutineEntry(
            date: date,
            period: period,
            steps: (period == .morning ? snapshot?.morning : snapshot?.night) ?? [],
            headsUp: period == .morning ? snapshot?.morningHeadsUp : snapshot?.nightHeadsUp,
            hasData: snapshot != nil
        )
    }

    // Next 5am or 3pm
    private func nextSwitch(after date: Date) -> Date? {
        let calendar = Calendar.current
        return [5, 15]
            .compactMap { calendar.nextDate(after: date, matching: DateComponents(hour: $0, minute: 0), matchingPolicy: .nextTime) }
            .min()
    }
}

// MARK: - Views

struct LayerWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RoutineEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: lockScreen
        case .systemMedium: medium
        default: small
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.period.symbol)
                .foregroundStyle(entry.period == .morning ? .orange : .indigo)
            Text(entry.period.title)
                .font(.headline)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Text(entry.hasData ? "No steps yet. Build this routine in Layer." : "Open Layer to set up your routine.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if entry.steps.isEmpty {
                emptyState
            } else {
                Text("\(entry.steps.count) steps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(entry.steps.prefix(3).enumerated()), id: \.offset) { index, step in
                    StepLine(number: index + 1, step: step, compact: true)
                }
                if entry.steps.count > 3 {
                    Text("+\(entry.steps.count - 3) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if entry.headsUp != nil {
                Label("Heads up", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if entry.steps.isEmpty {
                emptyState
            } else {
                ForEach(Array(entry.steps.prefix(5).enumerated()), id: \.offset) { index, step in
                    StepLine(number: index + 1, step: step, compact: false)
                }
            }
            Spacer(minLength: 0)
            if let headsUp = entry.headsUp {
                Label(headsUp, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(entry.period.title, systemImage: entry.period.symbol)
                .font(.headline)
            if entry.steps.isEmpty {
                Text("No routine yet").font(.caption)
            } else {
                Text(entry.steps.prefix(3).map(\.name).joined(separator: " · "))
                    .font(.caption)
                    .lineLimit(2)
            }
        }
    }
}

private struct StepLine: View {
    let number: Int
    let step: RoutineSnapshot.Step
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 12)
            if !compact {
                Image(systemName: step.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            Text(step.name)
                .font(compact ? .caption : .subheadline)
                .lineLimit(1)
            if step.isExpired {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Expired")
            }
        }
    }
}

// MARK: - Widget

struct LayerWidget: Widget {
    let kind = "LayerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            LayerWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Routine")
        .description("Your morning or night routine, in layering order.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

#Preview(as: .systemMedium) {
    LayerWidget()
} timeline: {
    RoutineEntry(date: .now, period: .night, steps: RoutineSnapshot.sample.night, headsUp: "Retinol + BHA", hasData: true)
    RoutineEntry(date: .now, period: .morning, steps: RoutineSnapshot.sample.morning, headsUp: nil, hasData: true)
}
