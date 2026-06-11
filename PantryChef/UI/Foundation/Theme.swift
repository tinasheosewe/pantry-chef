import SwiftUI

/// The redesign's visual language — "cream & glass" (spec §10). One warm palette
/// family, a serif for food and a quiet sans for facts, glass layered over light.
/// Tokens only: this namespace holds no logic, just the constants every redesign
/// view reads so the language stays consistent and tunable in one place.
enum Theme {

    // MARK: Palette
    /// Colour appears only as meaning: paprika for action, sage for readiness,
    /// ochre for time pressure. Everything else is cream, ink, and warm grey.
    enum Palette {
        static let cream = Color(red: 0.965, green: 0.945, blue: 0.910)   // #F6F1E8 base surface
        static let creamRaised = Color(red: 0.988, green: 0.969, blue: 0.937) // #FCF7EF glass tint
        static let ink = Color(red: 0.141, green: 0.118, blue: 0.090)     // #241E17 primary text / dark fills
        static let paprika = Color(red: 0.737, green: 0.322, blue: 0.063) // #BC5210 THE accent
        static let sage = Color(red: 0.369, green: 0.439, blue: 0.314)    // #5E7050 readiness / positive
        static let ochre = Color(red: 0.659, green: 0.396, blue: 0.059)   // #A8650F time pressure
        static let warmGray = Color(red: 0.478, green: 0.435, blue: 0.376)     // #7A6F60 secondary text
        static let warmGraySoft = Color(red: 0.608, green: 0.561, blue: 0.490) // #9B8F7D tertiary text
        static let hairline = Color(red: 0.471, green: 0.353, blue: 0.196).opacity(0.12)

        // Glass surfaces.
        static let glassFill = creamRaised.opacity(0.62)
        static let glassBorder = Color.white.opacity(0.85)
    }

    // MARK: Typography
    /// Appetite and information never share a font (spec §10): a serif carries dish
    /// names, greetings, and the sommelier note; a quiet sans carries every fact.
    enum Typography {
        /// Serif — for dish names and editorial moments.
        static func dish(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .serif)
        }
        /// Serif italic — the sommelier reasoning line.
        static func note(_ size: CGFloat = 13) -> Font {
            .system(size: size, weight: .regular, design: .serif).italic()
        }
        /// Sans — all functional text, metadata, labels.
        static func fact(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .default)
        }
        /// Sans with tabular figures — counts, quantities, timers, countdowns.
        static func numeral(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight, design: .default).monospacedDigit()
        }
        /// Uppercase eyebrow label ("Tonight", "Use soon").
        static let eyebrow = Font.system(size: 11, weight: .regular, design: .default)
    }

    // MARK: Metrics
    enum Metric {
        static let screenCornerRadius: CGFloat = 36
        static let cardCornerRadius: CGFloat = 24
        static let chipCornerRadius: CGFloat = 999
        static let dockHeight: CGFloat = 64
        static let spineWidth: CGFloat = 40        // gutter width for the timeline ruler
        static let eyebrowTracking: CGFloat = 1.4

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

    // MARK: Glass
    enum Glass {
        static let cornerRadius: CGFloat = Metric.cardCornerRadius
        static let borderWidth: CGFloat = 1
        static let shadowColor = Color(red: 0.47, green: 0.31, blue: 0.16).opacity(0.13)
        static let shadowRadius: CGFloat = 24
        static let shadowY: CGFloat = 12
    }
}
