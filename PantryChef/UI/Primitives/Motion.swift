import SwiftUI

/// Print-native motion (motion research, "make it feel like a living printed
/// object"): paper physics, not glassy bounce. These are the shared signatures —
/// the ink-stroke check, the page-turn between spaces, and a bloom for completion.
/// All honor Reduce Motion.

// MARK: - Paper springs

extension Animation {
    /// The house spring: quick, near-critical damping so nothing overshoots —
    /// paper settles, it doesn't boing.
    static let paper = Animation.spring(response: 0.34, dampingFraction: 0.96)
    static let paperQuick = Animation.spring(response: 0.24, dampingFraction: 1.0)
}

// MARK: - Ink check

/// A checkbox whose tick is *drawn* like a pen stroke, not popped in. Used wherever
/// the user checks something off (cook gathering, the shopping run).
struct InkCheck: View {
    var on: Bool
    var size: CGFloat = 22
    var tint: Color = Theme.Palette.sage

    @State private var draw: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .strokeBorder(on ? tint : Theme.Palette.ink.opacity(0.45), lineWidth: 1.5)
            if on || draw > 0.001 {
                CheckStroke()
                    .trim(from: 0, to: draw)
                    .stroke(tint, style: StrokeStyle(lineWidth: max(2, size * 0.10),
                                                     lineCap: .round, lineJoin: .round))
                    .padding(size * 0.26)
            }
        }
        .frame(width: size, height: size)
        .onAppear { draw = on ? 1 : 0 }
        .onChange(of: on) { _, now in
            if reduceMotion { draw = now ? 1 : 0 }
            else { withAnimation(.easeOut(duration: 0.22)) { draw = now ? 1 : 0 } }
        }
    }

    /// A checkmark in a unit square, drawn left-dip-right so trim animates as a pen.
    private struct CheckStroke: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return p
        }
    }
}

// MARK: - Bloom

/// A one-shot ring that blooms outward and fades — for completion moments (a timer
/// finishing). Quiet and warm, never a flash.
struct Bloom: View {
    var color: Color = Theme.Palette.paprika
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .strokeBorder(color.opacity(animate ? 0 : 0.5), lineWidth: 2)
            .scaleEffect(animate ? 1.8 : 0.5)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.9)) { animate = true }
            }
            .allowsHitTesting(false)
    }
}

#Preview("Ink check") {
    struct H: View {
        @State var on = false
        var body: some View {
            VStack(spacing: 24) {
                InkCheck(on: on, size: 40)
                Button("toggle") { on.toggle() }
            }.padding(40).background(Theme.Palette.cream)
        }
    }
    return H()
}
