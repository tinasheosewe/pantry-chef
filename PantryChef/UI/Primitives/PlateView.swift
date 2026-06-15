import SwiftUI

/// A dish's face: the AI-painted plate when one exists (spec §10 tier 1, cached by
/// PlateRenderLibrary), else its emoji seated on the app's ceramic plate — instant,
/// free, offline, recognizable at any size (tier 0). Decorative: the dish name
/// carries the meaning, so the plate is hidden from assistive tech.
struct PlateView: View {
    let name: String
    var composition: PlateComposition = PlateComposition(categories: [], seed: 0)
    var size: CGFloat = Theme.Metric.plateRow

    private var emoji: String {
        EmojiPlate.face(for: name, categories: composition.weights.map(\.category))
    }

    /// The plate is the one object the flat page lets feel real — at hero/detail
    /// sizes it gets a soft contact shadow so it sits *on* the page like a printed
    /// photograph; small row plates stay clean and flat.
    private var isHero: Bool { size >= 70 }

    var body: some View {
        ZStack {
            if let painted = PlateRenderLibrary.shared.render(for: name) {
                Image(uiImage: painted)
                    .resizable()
                    .scaledToFit()
                    .shadow(color: Theme.Palette.ink.opacity(isHero ? 0.18 : 0),
                            radius: size * 0.05, x: 0, y: size * 0.035)
                    .transition(.opacity)
            } else {
                ceramicWithEmoji
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: name) { PlateRenderLibrary.shared.request(name) }
    }

    private var ceramicWithEmoji: some View {
        ZStack {
            // White china with a fine green ring — but lit: a warm highlight from the
            // top-left and a soft shade at the foot give it the depth of a real dish,
            // not a flat disc. Kept quiet to fit the printed page.
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.Palette.creamRaised,
                             Theme.Palette.creamRaised,
                             Theme.Palette.ink.opacity(0.06)],
                    center: .init(x: 0.36, y: 0.30), startRadius: 0, endRadius: size * 0.62))
                .overlay(Circle().strokeBorder(Theme.Palette.ink.opacity(0.45),
                                               lineWidth: max(0.75, size * 0.014)))
                .shadow(color: Theme.Palette.ink.opacity(isHero ? 0.16 : 0),
                        radius: size * 0.05, x: 0, y: size * 0.035)
            // The rim's inner well ring.
            Circle()
                .strokeBorder(Theme.Palette.ink.opacity(0.22),
                              lineWidth: max(0.5, size * 0.01))
                .padding(size * 0.12)
            // A soft seat shadow so the food sits *in* the plate, not on a sticker.
            Ellipse()
                .fill(Theme.Palette.ink.opacity(0.10))
                .frame(width: size * 0.46, height: size * 0.14)
                .offset(y: size * 0.17)
                .blur(radius: size * 0.03)
            Text(emoji)
                .font(.system(size: size * 0.48))
                .offset(y: -size * 0.01)
        }
    }
}

#Preview("Plates") {
    let demos: [(String, [FoodCategory])] = [
        ("Spinach & feta orzo", [.produce, .dairy, .pasta]),
        ("Shakshuka", [.protein, .produce, .spices]),
        ("Lamb ragù", [.protein, .pasta]),
        ("Miso butter salmon", [.protein, .oils]),
        ("Girl dinner", [.dairy, .snacks]),
        ("Mystery leftovers", [])
    ]
    return ScrollView {
        VStack(spacing: 20) {
            ForEach(Array(demos.enumerated()), id: \.offset) { i, demo in
                HStack(spacing: 16) {
                    PlateView(name: demo.0,
                              composition: .init(categories: demo.1, seed: UInt64(i + 1)),
                              size: Theme.Metric.plateHero)
                    PlateView(name: demo.0, composition: .init(categories: demo.1, seed: 1),
                              size: Theme.Metric.plateMini)
                    Text(demo.0).font(Theme.Typography.dish(18))
                    Spacer()
                }
            }
        }
        .padding(24)
    }
    .background(Theme.Palette.cream)
}
