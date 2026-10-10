import CoreText
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Data from the app

// Same JSON shape as WidgetSnapshot in the app (Layer/WidgetSupport/WidgetSync.swift).
// The app writes it to the shared App Group whenever the routine changes.
struct RoutineSnapshot: Codable {
    struct Step: Codable, Hashable {
        let name: String
        let symbol: String
        let icon: String?         // optional so snapshots saved by older builds still decode
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
            Step(name: "Gentle Cleanser", symbol: "drop", icon: "cleanser", isExpired: false),
            Step(name: "Vitamin C Serum", symbol: "eyedropper", icon: "serum", isExpired: false),
            Step(name: "Daily Moisturizer", symbol: "humidity", icon: "jar", isExpired: false),
            Step(name: "SPF 50", symbol: "sun.max", icon: "sunscreen", isExpired: false),
        ],
        night: [
            Step(name: "Gentle Cleanser", symbol: "drop", icon: "cleanser", isExpired: false),
            Step(name: "Retinol 0.5%", symbol: "eyedropper", icon: "serum", isExpired: false),
            Step(name: "Barrier Cream", symbol: "humidity", icon: "jar", isExpired: true),
        ],
        morningHeadsUp: nil,
        nightHeadsUp: "Retinol + BHA"
    )
}

enum Period {
    case morning, night

    // Same switch time as the app's Routine tab: morning until 3pm
    init(_ date: Date) {
        self = Calendar.current.component(.hour, from: date) < 15 ? .morning : .night
    }

    var title: String { self == .morning ? "Morning" : "Tonight" }
    var symbol: String { self == .morning ? "sun.max" : "moon" }
}

// MARK: - Look (mirrors the app's Theme, the widget can't import it)

private enum Look {
    static let page = Color(light: 0xF3F4EF, dark: 0x121611)
    static let card = Color(light: 0xE4E7DC, dark: 0x1E231D)
    static let olive = Color(light: 0x323B31, dark: 0x2F3A2D)       // forest tile
    static let oliveText = Color(light: 0xEDF0E6, dark: 0xEDF0E6)
    static let lime = Color(light: 0xC4D97C, dark: 0xC4D97C)
    static let ink = Color(light: 0x1F261F, dark: 0xEDF0E6)
    static let muted = Color(light: 0x737A6D, dark: 0x9AA192)
    static let faint = Color(light: 0xADB3A4, dark: 0x5A6156)
    static let warning = Color(light: 0xB4602F, dark: 0xE09A6A)

    static let serifName = "InstrumentSerif-Regular"
    static func serif(_ size: CGFloat) -> Font { .custom(serifName, size: size) }

    // Registered once per extension process, no Info.plist entry needed
    static let registerFont: Void = {
        if let url = Bundle.main.url(forResource: serifName, withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        func ui(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
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

    init(entry: RoutineEntry) {
        _ = Look.registerFont
        self.entry = entry
    }

    var body: some View {
        switch family {
        case .accessoryRectangular: lockScreen
        case .systemMedium: medium
        default: small
        }
    }

    private var stepCount: String {
        entry.steps.count == 1 ? "1 step" : "\(entry.steps.count) steps"
    }

    private var emptyText: String {
        entry.hasData ? "Nothing here yet. Add steps in Layer." : "Open Layer to build your routine."
    }

    // MARK: Small: serif title, numbered steps, heads-up at the bottom

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.period.title)
                    .font(Look.serif(28))
                    .foregroundStyle(Look.ink)
                Spacer(minLength: 0)
                Image(systemName: entry.period.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Look.muted)
            }
            Text(entry.steps.isEmpty ? "No routine" : stepCount.uppercased())
                .font(.system(size: 9, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(Look.muted)
                .padding(.bottom, 10)

            if entry.steps.isEmpty {
                Text(emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(Look.muted)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(entry.steps.prefix(3).enumerated()), id: \.offset) { index, step in
                        StepLine(number: index + 1, step: step, showsIcon: false)
                    }
                }
            }

            Spacer(minLength: 0)
            footer
        }
    }

    @ViewBuilder
    private var footer: some View {
        if entry.headsUp != nil {
            Label("Heads up", systemImage: "exclamationmark.triangle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Look.warning)
                .widgetAccentable()
        } else if entry.steps.count > 3 {
            Text("+\(entry.steps.count - 3) more")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Look.muted)
        }
    }

    // MARK: Medium: olive tile on the left, the full list on the right

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: entry.period.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(entry.headsUp == nil ? Look.lime : Look.oliveText)
                Spacer(minLength: 0)
                Text(entry.period.title)
                    .font(Look.serif(30))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(entry.steps.isEmpty ? "No routine yet" : stepCount)
                    .font(.system(size: 11))
                    .opacity(0.85)
            }
            .foregroundStyle(Look.oliveText)
            .padding(12)
            .frame(width: 112, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)
            .background(entry.headsUp == nil ? Look.olive : Look.warning, in: .rect(cornerRadius: 16))
            .widgetAccentable()

            VStack(alignment: .leading, spacing: 6) {
                if entry.steps.isEmpty {
                    Spacer(minLength: 0)
                    Text(emptyText)
                        .font(.system(size: 13))
                        .foregroundStyle(Look.muted)
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(entry.steps.prefix(entry.headsUp == nil ? 5 : 4).enumerated()), id: \.offset) { index, step in
                        StepLine(number: index + 1, step: step, showsIcon: true)
                    }
                    Spacer(minLength: 0)
                    if let headsUp = entry.headsUp {
                        Label(headsUp, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Look.warning)
                            .lineLimit(1)
                            .widgetAccentable()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: Lock screen: system tints it, so stick to type and layout

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: entry.period.symbol)
                Text(entry.period.title)
                    .font(Look.serif(20))
                if !entry.steps.isEmpty {
                    Text("· \(stepCount)")
                        .font(.system(size: 11))
                        .opacity(0.7)
                }
            }
            .widgetAccentable()
            if entry.steps.isEmpty {
                Text("No routine yet").font(.system(size: 12))
            } else {
                Text(entry.steps.prefix(3).map(\.name).joined(separator: " → "))
                    .font(.system(size: 12))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// "[01]  Vitamin C Serum" in the app's bracket-number style
private struct StepLine: View {
    let number: Int
    let step: RoutineSnapshot.Step
    let showsIcon: Bool

    var body: some View {
        HStack(spacing: 7) {
            Text(String(format: "%02d", number))
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(Look.muted)
            if showsIcon {
                Group {
                    if let icon = step.icon {
                        Image("icon-\(icon)").renderingMode(.template).resizable().scaledToFit()
                    } else {
                        Image(systemName: step.symbol).resizable().scaledToFit()
                    }
                }
                .frame(width: 14, height: 14)
                .foregroundStyle(Look.ink.opacity(0.7))
            }
            Text(step.name)
                .font(.system(size: showsIcon ? 13 : 12, weight: .medium))
                .foregroundStyle(step.isExpired ? Look.muted : Look.ink)
                .strikethrough(step.isExpired, color: Look.muted)
                .lineLimit(1)
            if step.isExpired {
                Circle()
                    .fill(Look.warning)
                    .frame(width: 5, height: 5)
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
                .containerBackground(Look.page, for: .widget)
        }
        .configurationDisplayName("Routine")
        .description("Your morning or night routine, in layering order.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

#Preview(as: .systemSmall) {
    LayerWidget()
} timeline: {
    RoutineEntry(date: .now, period: .morning, steps: RoutineSnapshot.sample.morning, headsUp: nil, hasData: true)
    RoutineEntry(date: .now, period: .night, steps: RoutineSnapshot.sample.night, headsUp: "Retinol + BHA", hasData: true)
}

#Preview(as: .systemMedium) {
    LayerWidget()
} timeline: {
    RoutineEntry(date: .now, period: .night, steps: RoutineSnapshot.sample.night, headsUp: "Retinol + BHA", hasData: true)
    RoutineEntry(date: .now, period: .morning, steps: RoutineSnapshot.sample.morning, headsUp: nil, hasData: true)
}
