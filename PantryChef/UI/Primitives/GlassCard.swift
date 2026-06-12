import SwiftUI

/// The redesign's signature surface: warm glass over light (spec §10). A cream-
/// tinted translucent material with a specular border — bright where light catches
/// the top edge, fading down — and a soft warm shadow.
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = Theme.Glass.cornerRadius

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Theme.Palette.glassFill))
            }
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.30)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: Theme.Glass.borderWidth)
            )
            .clipShape(shape)
            .shadow(color: Theme.Glass.shadowColor,
                    radius: Theme.Glass.shadowRadius, x: 0, y: Theme.Glass.shadowY)
    }
}

extension View {
    /// Wraps the view in the redesign's warm-glass surface.
    func glassCard(cornerRadius: CGFloat = Theme.Glass.cornerRadius) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}

/// The app's universal press response: a quick, springy compress under the finger.
/// Every tappable card and row should feel like this — alive, not inert.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
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
