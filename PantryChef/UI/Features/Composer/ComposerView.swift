import SwiftUI

/// The composer (spec §13): one bar, living cards. Typed phrases parse live and
/// crystallize into cards above the bar; the parser never rejects input. This is
/// the Stock mount; the same component serves log/plan/sweep via its context.
struct ComposerView: View {
    var store: KitchenStore
    var onDismiss: () -> Void = {}

    @State private var text = ""
    @State private var staged: [ParsedIntake] = []
    @FocusState private var focused: Bool

    private var preview: ParsedIntake? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : store.parse(text)
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add anything").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                        .padding(.bottom, 2)
                    ForEach(Array(staged.enumerated()), id: \.offset) { _, item in
                        IntakeCard(item: item)
                    }
                    bar
                    if let preview { IntakeCard(item: preview, isPreview: true) }
                    if staged.isEmpty && preview == nil { doorways }
                }
                .padding(20)
            }
            if !staged.isEmpty { commitBar }
        }
        .background(KitchenBackground())
        .onAppear { focused = true }
    }

    private var grabber: some View {
        Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4).padding(.top, 10)
    }

    private var bar: some View {
        HStack(spacing: 8) {
            TextField("300 g spinach, fridge", text: $text)
                .font(Theme.Typography.fact(14)).focused($focused)
                .submitLabel(.next).onSubmit(commitCurrent)
            Image(systemName: "microphone").font(.system(size: 16))
                .foregroundStyle(Theme.Palette.paprika)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Palette.creamRaised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Palette.hairline))
    }

    private var doorways: some View {
        VStack(spacing: 0) {
            doorway("Log tonight's meal", "fork.knife")
            Divider().background(Theme.Palette.hairline)
            doorway("Add to the list", "cart")
            Divider().background(Theme.Palette.hairline)
            doorway("Paste a recipe link or text", "link")
        }
        .padding(.horizontal, 4)
    }

    private func doorway(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Theme.Palette.warmGray).frame(width: 22)
            Text(title).font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink)
            Spacer()
        }
        .padding(.vertical, 11)
    }

    private var commitBar: some View {
        HStack {
            Text("Everything goes to Stock").font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
            Spacer()
            PaprikaButton(title: "Add \(staged.count) to Stock") {
                // Persistence wires in later; for now staging is the demonstrated flow.
                onDismiss()
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private func commitCurrent() {
        guard let item = preview else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
            staged.append(item)
            text = ""
        }
    }
}

/// One parsed item as a card — shows resolved / guessed / unrecognized-unit states.
private struct IntakeCard: View {
    let item: ParsedIntake
    var isPreview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                icon
                Text(title).font(Theme.Typography.fact(14)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                if let storage = item.storage {
                    Text(storageLabel(storage)).font(Theme.Typography.fact(11))
                        .foregroundStyle(Theme.Palette.warmGraySoft)
                }
            }
            if item.suggestedName != nil {
                Text("from \u{201C}\(item.name)\u{201D} — tap to fix")
                    .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.ochre)
                    .padding(.leading, 25)
            }
            if let unit = item.unrecognizedUnit {
                Text("\u{201C}\(unit)\u{201D} isn't a unit I know — keep it, or pick one")
                    .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.ochre)
                    .padding(.leading, 25)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Palette.creamRaised.opacity(isPreview ? 0.6 : 1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, style: StrokeStyle(lineWidth: 1, dash: item.confidence == .unresolved ? [4, 3] : []))
        )
    }

    private var title: String {
        var parts: [String] = []
        if let q = item.quantity { parts.append(formatQty(q)) }
        if let u = item.unit { parts.append(u.rawValue) }
        let display = item.suggestedName ?? (item.name.isEmpty ? "—" : item.name)
        parts.append(display)
        return parts.joined(separator: " ")
    }

    @ViewBuilder private var icon: some View {
        switch item.confidence {
        case .resolved: Image(systemName: "checkmark").foregroundStyle(Theme.Palette.sage)
        case .guessed: Image(systemName: "pencil").foregroundStyle(Theme.Palette.ochre)
        case .unresolved: Image(systemName: "sparkles").foregroundStyle(Theme.Palette.warmGraySoft)
        }
    }

    private var borderColor: Color {
        switch item.confidence {
        case .resolved: return Theme.Palette.hairline
        case .guessed: return Theme.Palette.ochre.opacity(0.4)
        case .unresolved: return Theme.Palette.warmGraySoft.opacity(0.6)
        }
    }

    private func formatQty(_ q: Double) -> String {
        q == q.rounded() ? String(Int(q)) : String(format: "%.2g", q)
    }
    private func storageLabel(_ s: PantryStorage) -> String {
        switch s { case .refrigerated: return "fridge"; case .frozen: return "freezer"; case .pantry: return "pantry" }
    }
}
