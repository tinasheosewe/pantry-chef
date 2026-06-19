import SwiftUI

/// PantryChef Plus paywall. Sells the *anti-waste* value — the recurring reason to pay —
/// not the AI. "Pays for itself in a month of groceries not wasted." Field Notes furniture:
/// a ruled page, a ledger of what's included, the ❧ tailpiece. Reached from Settings (and
/// later, from any Pro feature a free user taps).
struct PaywallView: View {
    var subscription: SubscriptionService
    var onClose: () -> Void

    @State private var busy = false

    private let benefits: [(String, String, String)] = [
        ("tray.full", "Your whole kitchen", "Track every shelf — no cap — so “what can I cook” always knows."),
        ("bell.badge", "Never bin food again", "Use-it-up reminders on the last good morning, before it turns."),
        ("calendar", "Plan the week", "Future meals, auto-routed shopping list, leftovers tracked."),
        ("heart.text.square", "Your cookbook", "Favorites, ratings, notes, and what you’ve made before."),
        ("wand.and.stars", "Smart tweaks", "Make any recipe healthier or adjust it to taste."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4).padding(.top, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    DashedRule().padding(.vertical, 16)
                    ledger
                    if subscription.isPlus { activeBanner.padding(.top, 18) }
                }
                .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
            }
            footer
        }
        .background(KitchenBackground())
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.Palette.warmGray).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "PantryChef Plus", tone: .win)
            Text("Stop binning food.")
                .font(Theme.Typography.dish(30)).foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("PantryChef tells you what to cook with what you have — before it spoils. Plus pays for itself in a month of groceries you don’t throw away.")
                .font(Theme.Typography.note(14)).foregroundStyle(Theme.Palette.warmGray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 10)
    }

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(benefits, id: \.0) { icon, title, detail in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.Palette.sage)
                        .frame(width: 24, height: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Theme.Typography.fact(15, weight: .medium)).foregroundStyle(Theme.Palette.ink)
                        Text(detail).font(Theme.Typography.fact(12.5)).foregroundStyle(Theme.Palette.warmGray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var activeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.Palette.sage)
            Text("You’re on Plus — thank you.").font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Rectangle().fill(Theme.Palette.sage.opacity(0.10)))
        .overlay(Rectangle().strokeBorder(Theme.Palette.sage.opacity(0.4), lineWidth: 1))
    }

    @ViewBuilder private var footer: some View {
        VStack(spacing: 0) {
            SolidRule()
            if subscription.isPlus {
                VStack(spacing: 8) {
                    Tailpiece(text: "Manage your subscription in the App Store")
                    OutlineButton(title: "Done") { onClose() }.padding(.horizontal, 24)
                }
                .padding(.vertical, 14)
            } else {
                VStack(spacing: 10) {
                    PaprikaButton(title: busy ? "…" : startTitle) { startTrial() }
                        .frame(maxWidth: .infinity).padding(.horizontal, 24)
                        .disabled(busy || subscription.product == nil)
                    Text(subTitle).font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                    Button(busy ? "…" : "Restore purchases") { restore() }
                        .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGray)
                        .buttonStyle(.plain).disabled(busy)
                }
                .padding(.top, 12).padding(.bottom, 14)
            }
        }
        .background(Theme.Palette.cream)
    }

    private var startTitle: String {
        subscription.trialText.map { _ in "Start your free trial" } ?? "Go Plus"
    }
    private var subTitle: String {
        if subscription.loadFailed { return "Pricing unavailable right now — check your connection." }
        let price = subscription.priceText ?? "—"
        if let trial = subscription.trialText { return "\(trial), then \(price). Cancel anytime." }
        return "\(price). Cancel anytime."
    }

    private func startTrial() {
        busy = true
        Task { _ = await subscription.purchase(); busy = false; if subscription.isPlus { onClose() } }
    }
    private func restore() {
        busy = true
        Task { await subscription.restore(); busy = false; if subscription.isPlus { onClose() } }
    }
}
