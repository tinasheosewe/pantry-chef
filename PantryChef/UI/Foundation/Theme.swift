import SwiftUI
import UIKit
import Observation

/// Field Notes: one visual world (spec §10). Green ink on paper — the ink IS the
/// text color; tomato means act-or-hurry; gold appears only for wins. After dark
/// the page inverts: deep green paper, cream ink, the tomato warmed a shade. The
/// inversion follows the clock — there is no user-facing theme switch.
struct ThemeSpec: Sendable {
    /// True for the inverted evening page — keeps system chrome legible.
    let isDark: Bool
    // Surfaces
    let cream: Color          // the page
    let creamRaised: Color    // raised sheets (tickets, fields)
    // Text
    let ink: Color            // primary text
    let warmGray: Color       // secondary text
    let warmGraySoft: Color   // tertiary text
    // Meaning
    let paprika: Color        // tomato — act or hurry
    let sage: Color           // gold — wins only
    let ochre: Color          // time pressure (same tomato in this world)
    let hairline: Color
    // Sheet furniture
    let glassFill: Color
    let glassBorder: Color
    let glassShadow: Color

    static let day = ThemeSpec(
        isDark: false,
        cream: Color(red: 0.968, green: 0.965, blue: 0.933),       // #F7F6EE paper
        creamRaised: Color(red: 1.0, green: 0.996, blue: 0.973),   // #FFFEF8
        ink: Color(red: 0.141, green: 0.251, blue: 0.169),         // #24402B  10.5:1 AAA
        warmGray: Color(red: 0.290, green: 0.404, blue: 0.318),    // secondary 5.8:1 AA
        // Tertiary darkened from #738B78 (3.4:1, failed AA) so functional small
        // text actually passes — same green family, just less faded (UI agents §4).
        warmGraySoft: Color(red: 0.345, green: 0.451, blue: 0.376), // ~4.6:1 AA
        paprika: Color(red: 0.753, green: 0.231, blue: 0.169),     // #C03B2B  5.0:1 AA
        // "Wins" gold darkened from #A87B2F (3.5:1, failed AA) to ~#8A6420 so it
        // can carry text/status, not just decoration.
        sage: Color(red: 0.541, green: 0.392, blue: 0.125),        // ~4.6:1 AA
        ochre: Color(red: 0.753, green: 0.231, blue: 0.169),
        hairline: Color(red: 0.141, green: 0.251, blue: 0.169).opacity(0.28),
        glassFill: Color(red: 1.0, green: 0.996, blue: 0.973),
        glassBorder: Color(red: 0.141, green: 0.251, blue: 0.169).opacity(0.30),
        glassShadow: .clear
    )

    static let evening = ThemeSpec(
        isDark: true,
        cream: Color(red: 0.110, green: 0.141, blue: 0.118),       // #1C241E
        creamRaised: Color(red: 0.149, green: 0.184, blue: 0.157),
        ink: Color(red: 0.937, green: 0.918, blue: 0.851),         // #EFEAD9 cream ink
        warmGray: Color(red: 0.788, green: 0.769, blue: 0.698),
        warmGraySoft: Color(red: 0.616, green: 0.600, blue: 0.533),
        paprika: Color(red: 0.878, green: 0.376, blue: 0.290),     // #E0604A warmed
        sage: Color(red: 0.761, green: 0.604, blue: 0.294),
        ochre: Color(red: 0.878, green: 0.376, blue: 0.290),
        hairline: Color(red: 0.937, green: 0.918, blue: 0.851).opacity(0.25),
        glassFill: Color(red: 0.149, green: 0.184, blue: 0.157),
        glassBorder: Color(red: 0.937, green: 0.918, blue: 0.851).opacity(0.28),
        glassShadow: .clear
    )
}

/// Picks day or evening by the clock; @Observable so every token read re-renders
/// when the page inverts. Refreshed on app foreground.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    private(set) var spec: ThemeSpec

    func refresh(now: Date = Date()) {
        spec = Self.spec(for: now)
    }

    static func spec(for date: Date) -> ThemeSpec {
        // Env override for screenshots/CI only.
        if let forced = ProcessInfo.processInfo.environment["PC_THEME"] {
            return forced == "evening" ? .evening : .day
        }
        let hour = Calendar.current.component(.hour, from: date)
        return (hour >= 20 || hour < 5) ? .evening : .day
    }

    private init() {
        spec = Self.spec(for: Date())
    }
}

/// The redesign's token namespace; every token reads through the live ThemeSpec.
enum Theme {

    // MARK: Palette
    enum Palette {
        static var cream: Color { ThemeManager.shared.spec.cream }
        static var creamRaised: Color { ThemeManager.shared.spec.creamRaised }
        static var ink: Color { ThemeManager.shared.spec.ink }
        static var paprika: Color { ThemeManager.shared.spec.paprika }
        static var sage: Color { ThemeManager.shared.spec.sage }
        static var ochre: Color { ThemeManager.shared.spec.ochre }
        static var warmGray: Color { ThemeManager.shared.spec.warmGray }
        static var warmGraySoft: Color { ThemeManager.shared.spec.warmGraySoft }
        static var hairline: Color { ThemeManager.shared.spec.hairline }
        static var glassFill: Color { ThemeManager.shared.spec.glassFill }
        static var glassBorder: Color { ThemeManager.shared.spec.glassBorder }
    }

    // MARK: Typography
    /// Appetite and information never share a font (spec §10): Fraunces — a warm,
    /// high-contrast display serif — carries dish names, greetings, and the
    /// sommelier note; a quiet sans carries every fact. Falls back to the system
    /// serif if the bundled font ever fails to register.
    /// Every face scales with the user's Dynamic Type setting (accessibility gap
    /// flagged by the UI research): Fraunces via `relativeTo:`, the sans via
    /// UIFontMetrics. These are functions/computed vars so they re-read the live
    /// content-size category on each body pass. The root clamps the maximum so
    /// the editorial layout still holds at large sizes.
    enum Typography {
        /// One global multiplier on every face — testers found the app small and
        /// text-heavy ("larger words"), so the whole type system reads a step bigger.
        /// Kept as a single knob so the scale is trivial to retune from a screenshot.
        static let scale: CGFloat = 1.12

        /// Display serif — for dish names and editorial moments.
        static func dish(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            let s = size * scale
            return FontLoader.frauncesAvailable
                ? .custom("Fraunces", size: s, relativeTo: .body).weight(weight)
                : .system(size: s, weight: weight, design: .serif)
        }
        /// Display serif italic — the sommelier reasoning line.
        static func note(_ size: CGFloat = 13) -> Font {
            let s = size * scale
            return FontLoader.frauncesAvailable
                ? .custom("Fraunces-Italic", size: s, relativeTo: .body)
                : .system(size: s, weight: .regular, design: .serif).italic()
        }
        /// Sans — all functional text, metadata, labels. Scaled for Dynamic Type.
        static func fact(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            scaledSystem(size: size, weight: weight)
        }
        /// Sans with tabular figures — counts, quantities, timers, countdowns.
        static func numeral(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            scaledSystem(size: size, weight: weight, monospacedDigit: true)
        }
        /// Uppercase eyebrow label ("TONIGHT", "ON THE CLOCK").
        static var eyebrow: Font { scaledSystem(size: 11, weight: .regular) }

        /// A system font that tracks Dynamic Type, built through UIFontMetrics so
        /// our fixed point sizes still grow with the user's setting.
        private static func scaledSystem(size: CGFloat, weight: Font.Weight,
                                         monospacedDigit: Bool = false) -> Font {
            let size = size * scale
            let base = monospacedDigit
                ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: uiWeight(weight))
                : UIFont.systemFont(ofSize: size, weight: uiWeight(weight))
            return Font(UIFontMetrics(forTextStyle: .body).scaledFont(for: base))
        }

        private static func uiWeight(_ w: Font.Weight) -> UIFont.Weight {
            switch w {
            case .ultraLight: return .ultraLight
            case .thin: return .thin
            case .light: return .light
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            case .heavy: return .heavy
            case .black: return .black
            default: return .regular
            }
        }
    }

    // MARK: Metrics
    enum Metric {
        static let screenCornerRadius: CGFloat = 36
        static let cardCornerRadius: CGFloat = 3   // printed sheets, not pillows
        static let chipCornerRadius: CGFloat = 0   // tags are squared in print
        static let dockHeight: CGFloat = 64
        static let spineWidth: CGFloat = 40        // gutter width for the timeline ruler
        static let eyebrowTracking: CGFloat = 2.2

        // Plate sizes across surfaces (spec §10).
        static let plateHero: CGFloat = 104
        static let plateRow: CGFloat = 48
        static let plateMini: CGFloat = 34

        // Spacing scale.
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: Glass (legacy name; now the printed sheet)
    enum Glass {
        static let cornerRadius: CGFloat = Metric.cardCornerRadius
        static let borderWidth: CGFloat = 1
        static var shadowColor: Color { ThemeManager.shared.spec.glassShadow }
        static let shadowRadius: CGFloat = 0
        static let shadowY: CGFloat = 0
    }
}
