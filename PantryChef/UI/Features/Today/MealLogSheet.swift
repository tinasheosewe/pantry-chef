import SwiftUI

/// Log a meal you ate (the contextual home for what used to be the composer's "tonight's
/// meal" destination). Most meals log themselves — cooking a recipe and finishing a
/// leftover both record automatically — so this is the small catch-all for "I ate
/// something else." Type it, log it; it lands in your journal.
struct MealLogSheet: View {
    var store: KitchenStore
    var onClose: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10)
            VStack(alignment: .leading, spacing: 3) {
                Text("Log a meal").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                Text("What did you eat? It goes in your journal.")
                    .font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.warmGray)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12)

            HStack(spacing: 8) {
                TextField("leftover ragù, side salad", text: $text)
                    .font(Theme.Typography.fact(14)).focused($focused)
                    .submitLabel(.done).onSubmit(commit)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.creamRaised))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.Palette.hairline))
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
            PaprikaButton(title: "Log it", action: commit)
                .frame(maxWidth: .infinity).padding(20)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KitchenBackground())
        .onAppear { focused = true }
    }

    private func commit() {
        let items = text.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { store.parse($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !($0.suggestedName ?? $0.name).isEmpty }
        guard !items.isEmpty else { onClose(); return }
        store.logMeal(items)
        onClose()
    }
}
