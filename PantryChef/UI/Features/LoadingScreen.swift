import SwiftUI

/// The opening screen shown while the app proactively loads everything (catalog
/// indices + readiness for the whole library) before the real UI appears — so you
/// never land on a half-built, frozen page. On-brand Field Notes: a breathing ceramic
/// plate, the wordmark, and a quietly cycling status line. The motion is Core-Animation
/// driven, so it stays smooth even while the main thread is busy warming.
struct LoadingScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false
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
                plate
                Text("PantryChef")
                    .font(Theme.Typography.dish(28))
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.top, 24)
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
                SweepBar()
                    .frame(width: 150, height: 2)
                    .padding(.top, 16).padding(.bottom, 64)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation(.easeInOut(duration: 0.4)) { phase = (phase + 1) % lines.count }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    /// A lit white-china plate with the app's fine green ring — the same object the
    /// feed uses, gently breathing so the screen feels alive while it loads.
    private var plate: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Theme.Palette.creamRaised, Theme.Palette.creamRaised,
                             Theme.Palette.ink.opacity(0.06)],
                    center: .init(x: 0.36, y: 0.30), startRadius: 0, endRadius: 66))
                .overlay(Circle().strokeBorder(Theme.Palette.ink.opacity(0.45), lineWidth: 1.5))
            Circle().strokeBorder(Theme.Palette.ink.opacity(0.20), lineWidth: 1).padding(13)
            Text("🍽️").font(.system(size: 46)).offset(y: -1)
        }
        .frame(width: 108, height: 108)
        .scaleEffect(breathe ? 1.0 : 0.93)
        .shadow(color: Theme.Palette.ink.opacity(0.14), radius: 9, x: 0, y: 6)
    }
}

/// A thin indeterminate progress sweep — a paprika segment gliding back and forth on a
/// faint track. Pure Core-Animation, so it never stutters under main-thread work.
private struct SweepBar: View {
    @State private var go = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Capsule().fill(Theme.Palette.ink.opacity(0.10))
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.Palette.paprika)
                        .frame(width: w * 0.38)
                        .offset(x: go ? w * 0.62 : 0)
                }
                .clipShape(Capsule())
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { go = true }
        }
    }
}
