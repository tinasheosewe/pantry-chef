import SwiftUI

/// A raised printed sheet (spec §10, Field Notes): near-white paper with a fine
/// ink border, squared like something set in a press. The world's only raised
/// surface — most content sits flat on the page, organized by rules.
struct SheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Metric.cardCornerRadius, style: .continuous)
        return content
            .background(shape.fill(Theme.Palette.creamRaised))
            .overlay(shape.strokeBorder(Theme.Palette.glassBorder, lineWidth: 1))
    }
}

extension View {
    /// Wraps the view in the printed-sheet surface. (Keeps the legacy call-site
    /// name; the radius parameter is ignored — sheets are squared in this world.)
    func glassCard(cornerRadius: CGFloat = Theme.Glass.cornerRadius) -> some View {
        modifier(SheetModifier())
    }
}

/// The app's universal press response — a *letterpress* feel, not a glassy bounce:
/// the element presses into the paper and settles with no overshoot (high damping),
/// because paper doesn't boing (motion research, print-native direction).
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        PressBody(scale: scale, isPressed: configuration.isPressed, label: configuration.label)
    }

    private struct PressBody<Label: View>: View {
        let scale: CGFloat
        let isPressed: Bool
        let label: Label
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .scaleEffect(reduceMotion ? 1 : (isPressed ? scale : 1))
                .brightness(isPressed ? -0.02 : 0)        // pressed into the page
                .opacity(isPressed ? 0.94 : 1)
                .animation(.spring(response: 0.26, dampingFraction: 0.95), value: isPressed)
        }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

#Preview("Glass card") {
    ZStack {
        Theme.Palette.cream.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 6) {
            Text("Tonight").font(Theme.Typography.eyebrow).foregroundStyle(Theme.Palette.paprika)
            Text("Spinach & feta orzo").font(Theme.Typography.dish(22))
            Text("25 min · serves 2").font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGray)
        }
        .padding(18)
        .frame(maxWidth: 280, alignment: .leading)
        .glassCard()
    }
}
