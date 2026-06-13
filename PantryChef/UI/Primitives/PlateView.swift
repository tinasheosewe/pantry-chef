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

    var body: some View {
        ZStack {
            if let painted = PlateRenderLibrary.shared.render(for: name) {
                Image(uiImage: painted)
                    .resizable()
                    .scaledToFit()
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
            // The Field Notes plate: white china with a fine green ring — like the
            // plates drawn into the printed pages.
            Circle()
                .fill(Theme.Palette.creamRaised)
                .overlay(Circle().strokeBorder(Theme.Palette.ink.opacity(0.45),
                                               lineWidth: max(0.75, size * 0.014)))
            // The rim's inner ring.
            Circle()
                .strokeBorder(Theme.Palette.ink.opacity(0.22),
                              lineWidth: max(0.5, size * 0.01))
                .padding(size * 0.12)
            Text(emoji)
                .font(.system(size: size * 0.48))
                .offset(y: -size * 0.005)
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
