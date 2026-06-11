import SwiftUI

/// The redesign's signature surface: warm glass over light (spec §10). A cream-
/// tinted translucent material, a hairline specular border, and a soft warm
/// shadow. Applied as a modifier so any container can become a glass card.
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
            .overlay(shape.strokeBorder(Theme.Palette.glassBorder, lineWidth: Theme.Glass.borderWidth))
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
