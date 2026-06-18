import SwiftUI

/// The opening screen shown while the app proactively loads everything (catalog
/// indices + readiness for the whole library) before the real UI appears — so you
/// never land on a half-built, frozen page. On-brand Field Notes: an ink herb sprig
/// that *grows from nothing* as load progresses (the stem draws up, leaves unfurl, a
/// paprika bud opens), under the serif wordmark and a quietly cycling status line.
struct LoadingScreen: View {
    /// 0→1 load progress; the sprig grows to match.
    var progress: Double

    @State private var phase = 0
    private let lines = [
        "Reading your pantry",
        "Checking what's fresh",
        "Finding what you can cook tonight"
    ]

    var body: some View {
        ZStack {
            Theme.Palette.cream.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                SprigMark(growth: CGFloat(min(max(progress, 0), 1)))
                    .frame(width: 96, height: 104)
                    .animation(.easeOut(duration: 0.6), value: progress)
                Text("PantryChef")
                    .font(Theme.Typography.dish(28))
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.top, 18)
                Text("COOK WHAT YOU HAVE")
                    .font(.system(size: 10, weight: .medium)).tracking(2.4)
                    .foregroundStyle(Theme.Palette.paprika)
                    .padding(.top, 7)
                Spacer()
                Text(lines[phase] + "…")
                    .font(Theme.Typography.note(13))
                    .foregroundStyle(Theme.Palette.warmGray)
                    .id(phase)
                    .transition(.opacity)
                    .padding(.bottom, 70)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation(.easeInOut(duration: 0.4)) { phase = (phase + 1) % lines.count }
            }
        }
    }
}

/// A fine ink sprig that draws itself as `growth` goes 0→1: the stem trims upward, the
/// leaves unfurl as the stem passes them, and the paprika bud opens at the top.
private struct SprigMark: View {
    var growth: CGFloat

    /// Each leaf's anchor along the stem (0 = base, 1 = tip) and which side it springs to.
    private let leaves: [(frac: CGFloat, side: CGFloat)] = [(0.32, -1), (0.52, 1), (0.70, -1)]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let baseX = w * 0.5
            ZStack {
                Stem()
                    .trim(from: 0, to: growth)
                    .stroke(Theme.Palette.ink,
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                ForEach(Array(leaves.enumerated()), id: \.offset) { _, leaf in
                    let u = unfurl(leaf.frac)
                    Leaf()
                        .fill(Theme.Palette.ink.opacity(0.12))
                        .overlay(Leaf().stroke(Theme.Palette.ink, lineWidth: 1.4))
                        .frame(width: 28, height: 14)
                        .scaleEffect(x: u, y: u, anchor: leaf.side < 0 ? .trailing : .leading)
                        .rotationEffect(.degrees(leaf.side < 0 ? -32 : 32),
                                        anchor: leaf.side < 0 ? .trailing : .leading)
                        .opacity(Double(u))
                        .position(x: baseX + leaf.side * 1, y: h * (1 - leaf.frac))
                }
                Circle().fill(Theme.Palette.paprika)
                    .frame(width: 9, height: 9)
                    .scaleEffect(bud).opacity(Double(bud))
                    .position(x: baseX, y: h * 0.07)
            }
        }
    }

    /// A leaf is closed until the stem reaches its anchor, then unfurls over a short span.
    private func unfurl(_ frac: CGFloat) -> CGFloat { clamp((growth - frac) / 0.14) }
    private var bud: CGFloat { clamp((growth - 0.9) / 0.1) }
    private func clamp(_ x: CGFloat) -> CGFloat { min(max(x, 0), 1) }
}

/// The stem, drawn base → tip so a `trim(to:)` grows it upward.
private struct Stem: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let x = r.midX
        p.move(to: CGPoint(x: x, y: r.maxY))
        p.addCurve(to: CGPoint(x: x, y: r.minY + r.height * 0.07),
                   control1: CGPoint(x: x - 8, y: r.midY + r.height * 0.18),
                   control2: CGPoint(x: x + 8, y: r.midY - r.height * 0.18))
        return p
    }
}

/// A simple two-curve leaf, base at the left edge, tip at the right.
private struct Leaf: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}
