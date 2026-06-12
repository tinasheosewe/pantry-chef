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
                    .shadow(color: Color(red: 0.43, green: 0.27, blue: 0.12).opacity(0.20),
                            radius: size * 0.12, x: 0, y: size * 0.08)
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
            // Ceramic: warm gradient with light from the top-left, a fine rim, and
            // a soft seat shadow under the food.
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 1.0, green: 0.99, blue: 0.97),
                             Color(red: 0.94, green: 0.91, blue: 0.85),
                             Color(red: 0.86, green: 0.82, blue: 0.73)],
                    center: .init(x: 0.35, y: 0.28), startRadius: 0, endRadius: size * 0.85))
                .overlay(Circle().strokeBorder(Color(red: 0.75, green: 0.67, blue: 0.55).opacity(0.5),
                                               lineWidth: max(0.5, size * 0.012)))
                .shadow(color: Color(red: 0.43, green: 0.27, blue: 0.12).opacity(0.20),
                        radius: size * 0.12, x: 0, y: size * 0.08)
            // The plate's inner well ring.
            Circle()
                .strokeBorder(Color(red: 0.70, green: 0.62, blue: 0.50).opacity(0.25),
                              lineWidth: max(0.5, size * 0.01))
                .padding(size * 0.14)
            // Soft seat shadow so the food sits *in* the plate, not on a sticker.
            Ellipse()
                .fill(Color(red: 0.35, green: 0.25, blue: 0.12).opacity(0.14))
                .frame(width: size * 0.52, height: size * 0.18)
                .offset(y: size * 0.20)
                .blur(radius: size * 0.04)
            Text(emoji)
                .font(.system(size: size * 0.5))
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
