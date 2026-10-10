import CoreText
import SwiftUI
import UIKit

// Layer's design system. Warm cream pages, sand cards, olive accents, espresso buttons.
// Serif for product names, bold two-tone sans for section titles, bracket labels like "[Serum]".
enum Theme {
    // MARK: Colors (each one adapts to dark mode)

    static let page = Color(light: 0xFAF6F0, dark: 0x161513)        // cream background
    static let card = Color(light: 0xF1E9DE, dark: 0x22201C)        // sand surfaces, product image panels
    static let olive = Color(light: 0x6B7256, dark: 0xB9C29E)       // accent, feature tiles
    static let oliveText = Color(light: 0xF6F3EA, dark: 0x1A1C14)   // text on olive tiles
    static let ink = Color(light: 0x2A1E1B, dark: 0xF3EEE6)         // espresso: text + primary buttons
    static let onInk = Color(light: 0xFAF6F0, dark: 0x1A1614)       // text on primary buttons
    static let muted = Color(light: 0x8A8178, dark: 0x9C948A)       // secondary text
    static let faint = Color(light: 0xBDB5AB, dark: 0x5E5850)       // second line of two-tone titles
    static let hairline = Color(light: 0x2A1E1B, dark: 0xF3EEE6).opacity(0.1)
    static let warning = Color(light: 0xB4602F, dark: 0xE09A6A)
    static let good = Color(light: 0x5E7350, dark: 0xA9C29A)

    // MARK: Type

    // Instrument Serif (bundled, SIL Open Font License): tall, condensed, editorial
    static let displayFontName = "InstrumentSerif-Regular"
    static func display(_ size: CGFloat) -> Font { .custom(displayFontName, size: size, relativeTo: .title) }
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .default) }
    static let body = Font.system(size: 15, weight: .regular)
    static let caption = Font.system(size: 12, weight: .regular)
    static let label = Font.system(size: 11, weight: .medium)
}

// The app name in the display face, top right on the main tabs
struct Wordmark: View {
    var size: CGFloat = 30

    var body: some View {
        Text("Layer")
            .font(.custom(Theme.displayFontName, size: size))
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

enum FontRegistry {
    // Registered in code, so no Info.plist entry is needed
    static func registerBundledFonts() {
        guard let url = Bundle.main.url(forResource: Theme.displayFontName, withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Icons

// The line icon set lives in Assets.xcassets as template SVGs ("icon-jar", "icon-serum"...)
struct LayerIcon: View {
    let name: String
    var size: CGFloat = 22

    var body: some View {
        Image("icon-\(name)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

extension ProductCategory {
    var iconName: String {
        switch self {
        case .cleanser: "cleanser"
        case .toner: "absorb"
        case .serum: "serum"
        case .treatment: "mortar"
        case .moisturizer: "jar"
        case .sunscreen: "sunscreen"
        case .eyeCream: "tube"
        case .mask: "mask"
        case .oil: "drops"
        case .other: "botanical"
        }
    }
}

// MARK: - Building blocks

// "Key" / "Ingredients" style: bold first line, faint second line
struct TwoToneTitle: View {
    let top: String
    let bottom: String
    var size: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: -4) {
            Text(top).foregroundStyle(Theme.ink)
            Text(bottom).foregroundStyle(Theme.faint)
        }
        .font(Theme.heading(size))
        .tracking(-0.8)
        .accessibilityElement(children: .combine)
    }
}

// "[Serum]"
struct BracketLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text("[\(text)]")
            .font(Theme.caption)
            .foregroundStyle(Theme.muted)
    }
}

// "[01]"
struct IndexLabel: View {
    let number: Int

    var body: some View {
        Text(String(format: "[%02d]", number))
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.muted)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }
}

// Espresso block button, full width
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.onInk)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.ink.opacity(configuration.isPressed ? 0.8 : 1), in: .rect(cornerRadius: 26))
            .contentShape(.rect)
    }
}

// Small espresso pill for toolbar actions (Cancel, Save, Done...). Same look as the big button.
struct InkPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InkPill(configuration: configuration, isCircle: false)
    }
}

// Espresso circle for icon-only toolbar actions (+, mic, profile)
struct InkCircleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InkPill(configuration: configuration, isCircle: true)
    }
}

private struct InkPill: View {
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration
    let isCircle: Bool

    var body: some View {
        Group {
            if isCircle {
                configuration.label
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 38, height: 38)
                    .background(Theme.ink, in: .circle)
            } else {
                configuration.label
                    .labelStyle(.titleOnly)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()                      // never wrap ("Edi t")
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Theme.ink, in: .capsule)
            }
        }
        .foregroundStyle(Theme.onInk)
        .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)
        .contentShape(isCircle ? AnyShape(.circle) : AnyShape(.capsule))
    }
}

// Outline pill, like "Add to cart"
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: 40)
            .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.35), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(.capsule)
    }
}

// Square icon button (sun/moon toggles on the product page)
struct SquareToggleStyle: ButtonStyle {
    var isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isOn ? Theme.onInk : Theme.ink)
            .frame(width: 52, height: 52)
            .background(isOn ? Theme.ink : Theme.card, in: .rect(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

// Cream page behind any scroll view or list
struct PageBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .background(Theme.page.ignoresSafeArea())
    }
}

extension View {
    func pageBackground() -> some View { modifier(PageBackground()) }
}

// Expandable sand card. The card grows downward and the content fades in under a hairline.
struct Accordion<Content: View>: View {
    let title: String
    var subtitle: String?
    @State var isOpen: Bool
    @ViewBuilder let content: () -> Content

    init(_ title: String, subtitle: String? = nil, isOpen: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self._isOpen = State(initialValue: isOpen)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.3)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    if let subtitle {
                        // Count in a small sand-on-cream badge instead of floating grey text
                        Text(subtitle)
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.page, in: .capsule)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .rotationEffect(.degrees(isOpen ? -180 : 0))
                }
                .frame(minHeight: 56)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Collapse" : "Expand")

            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    Hairline()
                    content()
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: 18))
    }
}
