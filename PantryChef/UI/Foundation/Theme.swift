import SwiftUI
import Observation

/// One complete visual world: every color the redesign uses, named by *role* so
/// worlds can disagree about everything except meaning (spec §10). Two ship today:
/// cream-and-glass (the built look) and Green Ink (green-on-paper, tomato to act).
struct ThemeSpec: Sendable {
    let name: String
    // Surfaces
    let cream: Color          // page background
    let creamRaised: Color    // raised/inner surfaces
    // Text
    let ink: Color            // primary text
    let warmGray: Color       // secondary text
    let warmGraySoft: Color   // tertiary text
    // Meaning
    let paprika: Color        // THE action color (and urgency in worlds that merge them)
    let sage: Color           // readiness / wins
    let ochre: Color          // time pressure
    let hairline: Color
    // Glass
    let glassFill: Color
    let glassBorder: Color
    let glassShadow: Color

    static let creamGlass = ThemeSpec(
        name: "Cream & glass",
        cream: Color(red: 0.965, green: 0.945, blue: 0.910),
        creamRaised: Color(red: 0.988, green: 0.969, blue: 0.937),
        ink: Color(red: 0.141, green: 0.118, blue: 0.090),
        warmGray: Color(red: 0.478, green: 0.435, blue: 0.376),
        warmGraySoft: Color(red: 0.608, green: 0.561, blue: 0.490),
        paprika: Color(red: 0.737, green: 0.322, blue: 0.063),
        sage: Color(red: 0.369, green: 0.439, blue: 0.314),
        ochre: Color(red: 0.659, green: 0.396, blue: 0.059),
        hairline: Color(red: 0.471, green: 0.353, blue: 0.196).opacity(0.12),
        glassFill: Color(red: 0.988, green: 0.969, blue: 0.937).opacity(0.70),
        glassBorder: .white.opacity(0.85),
        glassShadow: Color(red: 0.47, green: 0.31, blue: 0.16).opacity(0.13)
    )

    /// Green ink on paper: green IS the text, tomato means act-or-hurry, gold is
    /// reserved for wins. (Structural restyle — dashed rules, footer furniture —
    /// follows once this world wins the in-hand trial.)
    static let greenInk = ThemeSpec(
        name: "Green ink",
        cream: Color(red: 0.968, green: 0.965, blue: 0.933),       // #F7F6EE paper
        creamRaised: Color(red: 1.0, green: 0.996, blue: 0.973),   // #FFFEF8
        ink: Color(red: 0.141, green: 0.251, blue: 0.169),         // #24402B
        warmGray: Color(red: 0.333, green: 0.420, blue: 0.345),
        warmGraySoft: Color(red: 0.486, green: 0.557, blue: 0.486),
        paprika: Color(red: 0.753, green: 0.231, blue: 0.169),     // #C03B2B tomato
        sage: Color(red: 0.659, green: 0.482, blue: 0.184),        // #A87B2F gold = wins
        ochre: Color(red: 0.753, green: 0.231, blue: 0.169),       // pressure = tomato
        hairline: Color(red: 0.141, green: 0.251, blue: 0.169).opacity(0.22),
        glassFill: Color(red: 1.0, green: 0.996, blue: 0.973).opacity(0.85),
        glassBorder: Color(red: 0.141, green: 0.251, blue: 0.169).opacity(0.25),
        glassShadow: Color(red: 0.14, green: 0.25, blue: 0.17).opacity(0.08)
    )

    static let all: [ThemeSpec] = [.creamGlass, .greenInk]
}

/// Holds the live theme; @Observable so any view that read a token re-renders on
/// switch (Observation tracks the `spec` access through the Theme statics).
@Observable
final class ThemeManager {
    static let shared = ThemeManager()
    private static let key = "theme.current"

    var spec: ThemeSpec {
        didSet { UserDefaults.standard.set(spec.name, forKey: Self.key) }
    }

    func cycle() {
        let names = ThemeSpec.all.map(\.name)
        let index = names.firstIndex(of: spec.name) ?? 0
        spec = ThemeSpec.all[(index + 1) % ThemeSpec.all.count]
    }

    private init() {
        // Env override for screenshots/CI, else the persisted choice, else default.
        let saved = ProcessInfo.processInfo.environment["PC_THEME"]
            ?? UserDefaults.standard.string(forKey: Self.key)
        spec = ThemeSpec.all.first { $0.name.lowercased().contains((saved ?? "").lowercased()) && saved?.isEmpty == false }
            ?? .creamGlass
    }
}

/// The redesign's token namespace. Static call sites stay unchanged; every token
/// now reads through the live ThemeSpec.
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
    enum Typography {
        /// Display serif — for dish names and editorial moments.
        static func dish(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            FontLoader.frauncesAvailable
                ? .custom("Fraunces", size: size).weight(weight)
                : .system(size: size, weight: weight, design: .serif)
        }
        /// Display serif italic — the sommelier reasoning line.
        static func note(_ size: CGFloat = 13) -> Font {
            FontLoader.frauncesAvailable
                ? .custom("Fraunces-Italic", size: size)
                : .system(size: size, weight: .regular, design: .serif).italic()
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
        static var shadowColor: Color { ThemeManager.shared.spec.glassShadow }
        static let shadowRadius: CGFloat = 24
        static let shadowY: CGFloat = 12
    }
}
