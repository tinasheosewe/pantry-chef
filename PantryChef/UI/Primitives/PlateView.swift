import SwiftUI

extension RGBA {
    /// Bridge to SwiftUI at draw time (the pure logic never imports SwiftUI).
    var color: Color { Color(red: r, green: g, blue: b, opacity: a) }
}

/// Renders a dish's procedural plate (tier-0 imagery, spec §10) at any size.
/// Deterministic from its composition — no photo, no network, instant and offline,
/// and identical every time the same dish appears. Decorative: the dish name
/// carries the meaning, so the plate is hidden from assistive tech.
struct PlateView: View {
    let composition: PlateComposition
    var size: CGFloat = Theme.Metric.plateRow

    private enum Layout {
        static let foodFraction: CGFloat = 0.82   // food mound as a share of the plate
        static let rimStrokeFraction: CGFloat = 0.012
        static let highlightInset: CGFloat = 0.42
    }

    var body: some View {
        let spec = ProceduralPlateRenderer.render(composition)
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let plateR = s / 2
            let foodR = plateR * Layout.foodFraction

            let rim = Path(ellipseIn: CGRect(x: center.x - plateR, y: center.y - plateR,
                                             width: plateR * 2, height: plateR * 2))
            context.fill(rim, with: .color(spec.ceramic.color))
            context.stroke(rim, with: .color(spec.ceramic.darkened(0.12).color),
                           lineWidth: max(0.5, s * Layout.rimStrokeFraction))

            let foodRect = CGRect(x: center.x - foodR, y: center.y - foodR,
                                  width: foodR * 2, height: foodR * 2)
            let foodPath = Path(ellipseIn: foodRect)
            context.fill(foodPath, with: .color(spec.food.color))

            context.drawLayer { layer in
                layer.clip(to: foodPath)
                for fleck in spec.flecks {
                    let fx = center.x + CGFloat(fleck.x) * foodR
                    let fy = center.y + CGFloat(fleck.y) * foodR
                    let fr = max(0.5, CGFloat(fleck.radius) * foodR)
                    let rect = CGRect(x: fx - fr, y: fy - fr, width: fr * 2, height: fr * 2)
                    layer.fill(Path(ellipseIn: rect), with: .color(fleck.color.color))
                }
            }

            // Soft top-left sheen for a touch of ceramic depth.
            let hi = foodR * Layout.highlightInset
            let hiRect = CGRect(x: center.x - foodR * 0.5 - hi, y: center.y - foodR * 0.5 - hi,
                                width: hi * 2, height: hi * 2)
            context.fill(Path(ellipseIn: hiRect), with: .color(.white.opacity(0.10)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview("Plates") {
    let demos: [(String, [FoodCategory])] = [
        ("Spinach & feta orzo", [.produce, .dairy, .pasta]),
        ("Shakshuka", [.protein, .produce, .spices]),
        ("Lamb ragù", [.protein, .produce, .pasta, .oils]),
        ("Lemon greens", [.produce, .dairy]),
        ("Plain", [])
    ]
    return ScrollView {
        VStack(spacing: 20) {
            ForEach(Array(demos.enumerated()), id: \.offset) { i, demo in
                HStack(spacing: 16) {
                    PlateView(composition: .init(categories: demo.1, seed: UInt64(i + 1)),
                              size: Theme.Metric.plateHero)
                    Text(demo.0).font(Theme.Typography.dish(18))
                    Spacer()
                }
            }
        }
        .padding(24)
    }
    .background(Theme.Palette.cream)
}
