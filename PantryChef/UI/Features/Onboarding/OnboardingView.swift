import SwiftUI

/// Whether the first-run sweep has been completed. A single local flag — onboarding is
/// about getting *their* kitchen in, not accounts.
enum OnboardingState {
    private static let key = "pc.hasOnboarded"
    static var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// The common staples the sweep offers as one-tap chips — resolved to catalog ids once.
enum OnboardingStaples {
    static let names = [
        "Eggs", "Milk", "Butter", "Cheese", "Chicken", "Ground beef", "Salmon",
        "Onion", "Garlic", "Tomatoes", "Carrots", "Potatoes", "Spinach", "Broccoli",
        "Lemon", "Pasta", "Rice", "Bread", "Olive oil", "Canned tomatoes",
        "Black beans", "Chickpeas", "Flour", "Yogurt",
    ]
    static let resolved: [(name: String, id: String?)] =
        names.map { ($0, IntakePipeline.bestCatalogID(for: $0)) }
}

/// First-run onboarding — the "Pantry Sweep" (spec §"live unlock"). Its only job is to
/// make the headline true: get enough of the user's real kitchen in that "what can I cook
/// tonight" fires on *their* fridge instead of a stranger's demo. Deterministic and free
/// (no AI): tap common staples, watch the recipe count climb, done. Ungated — the trial
/// comes later, after the value has landed.
struct OnboardingView: View {
    var store: KitchenStore
    /// Keep the demo kitchen instead of building one (the "explore a sample" escape hatch).
    var onExploreSample: () -> Void
    /// Finish with whatever the user added (possibly nothing).
    var onFinish: () -> Void

    private enum Step { case welcome, sweep }
    @State private var step: Step = .welcome
    @State private var typed = ""
    @State private var showScanner = false
    @FocusState private var typing: Bool

    private let staples = OnboardingStaples.resolved

    var body: some View {
        ZStack {
            KitchenBackground()
            switch step {
            case .welcome: welcome.transition(.opacity)
            case .sweep: sweep.transition(.opacity)
            }
        }
    }

    // MARK: - Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Eyebrow(text: "PantryChef", tone: .win)
            Text("What’s in your\nkitchen?")
                .font(Theme.Typography.dish(34)).foregroundStyle(Theme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            Text("Tell me what you’ve got and I’ll tell you what to cook tonight — with this fridge, before it spoils. Takes about a minute.")
                .font(Theme.Typography.note(15)).foregroundStyle(Theme.Palette.warmGray)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            Spacer()
            DashedRule()
            VStack(spacing: 10) {
                PaprikaButton(title: "Set up my kitchen") {
                    withAnimation { step = .sweep }
                }
                .frame(maxWidth: .infinity)
                Button("Explore a sample kitchen first") { onExploreSample() }
                    .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.warmGray)
                    .buttonStyle(.plain)
            }
            .padding(.top, 16)
        }
        .padding(28).padding(.bottom, 12)
    }

    // MARK: - Sweep

    private var sweep: some View {
        VStack(spacing: 0) {
            unlockHeader
            DashedRule().padding(.horizontal, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    typedAdd
                    scanRow
                    Text("COMMON STAPLES").font(Theme.Typography.eyebrow)
                        .tracking(Theme.Metric.eyebrowTracking).foregroundStyle(Theme.Palette.warmGraySoft)
                        .padding(.top, 4)
                    chipGrid
                }
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
            }
            footer
        }
        .sheet(isPresented: $showScanner) {
            BarcodeScanSheet(store: store, onClose: { showScanner = false })
        }
    }

    private var scanRow: some View {
        Button { showScanner = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "barcode.viewfinder").font(.system(size: 15)).foregroundStyle(Theme.Palette.paprika)
                Text("Scan barcodes").font(Theme.Typography.fact(14, weight: .medium)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Palette.warmGraySoft)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.creamRaised))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.Palette.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var unlockHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                (Text("\(store.makeableCount) ").font(Theme.Typography.dish(30, weight: .semibold))
                    + Text(store.makeableCount == 1 ? "recipe you can make" : "recipes you can make")
                        .font(Theme.Typography.dish(19)))
                    .foregroundStyle(Theme.Palette.ink)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: store.makeableCount)
                Spacer()
            }
            Text(store.stock.isEmpty
                 ? "Tap what’s in your kitchen — the count climbs as you go."
                 : "\(store.stock.count) \(store.stock.count == 1 ? "item" : "items") in your kitchen")
                .font(Theme.Typography.note(12.5)).foregroundStyle(Theme.Palette.warmGray)
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typedAdd: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.Palette.paprika)
            TextField("Anything else — “300g spinach”", text: $typed)
                .font(Theme.Typography.fact(14)).focused($typing)
                .submitLabel(.done).onSubmit(commitTyped)
            if !typed.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add", action: commitTyped)
                    .font(Theme.Typography.fact(12, weight: .medium)).foregroundStyle(Theme.Palette.paprika)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.creamRaised))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.Palette.hairline))
    }

    private var chipGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(staples, id: \.name) { staple in
                let on = store.hasStaple(id: staple.id, name: staple.name)
                Button {
                    withAnimation(.snappy) { store.toggleStaple(id: staple.id, name: staple.name) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: on ? "checkmark" : "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(staple.name).font(.system(size: 12.5, weight: on ? .medium : .regular))
                            .lineLimit(1)
                    }
                    .foregroundStyle(on ? Theme.Palette.cream : Theme.Palette.ink)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(Rectangle().fill(on ? Theme.Palette.ink : Color.clear))
                    .overlay(Rectangle().strokeBorder(on ? Color.clear : Theme.Palette.hairline, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(staple.name)\(on ? ", in your kitchen" : "")")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            SolidRule()
            HStack {
                Button("Skip") { onFinish() }
                    .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.warmGray)
                    .buttonStyle(.plain)
                Spacer()
                PaprikaButton(title: store.stock.isEmpty ? "Do this later" : "Start cooking") { onFinish() }
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .background(Theme.Palette.cream)
    }

    private func commitTyped() {
        let phrase = typed.trimmingCharacters(in: .whitespaces)
        guard !phrase.isEmpty else { return }
        typed = ""
        withAnimation(.snappy) { store.addToStock(store.parse(phrase)) }
    }
}
