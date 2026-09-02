import SwiftUI
import UIKit

/// Paste a recipe in whatever messy shape it arrived — a blog dump, a Notes scrawl, a
/// text from a friend — and let AI format it: structured ingredients, inferred step
/// timers, filled-in amounts. The result opens in the editor to review before saving.
struct RecipeImportSheet: View {
    var store: KitchenStore
    /// The formatted recipe, handed back to open in the editor for review.
    var onParsed: (Dish) -> Void
    var onClose: () -> Void

    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4).padding(.top, 10)
            header
            DashedRule().padding(.horizontal, 20).padding(.top, 8)
            editor
            footer
        }
        .background(KitchenBackground())
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Paste a recipe").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                Text("A link, or any messy text — AI cleans it up for you.")
                    .font(Theme.Typography.note(11.5)).foregroundStyle(Theme.Palette.warmGray)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.warmGray).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("Close")
        }
        .padding(.horizontal, 20).padding(.top, 14)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused($focused)
                .font(Theme.Typography.fact(14)).foregroundStyle(Theme.Palette.ink)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.creamRaised))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.Palette.hairline))
            if text.isEmpty {
                Text("Paste a recipe link, or the recipe text…")
                    .font(Theme.Typography.fact(14)).foregroundStyle(Theme.Palette.warmGraySoft)
                    .padding(.horizontal, 15).padding(.vertical, 18).allowsHitTesting(false)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 20).padding(.top, 14)
        .overlay(alignment: .bottomTrailing) {
            if UIPasteboard.general.hasStrings && text.isEmpty {
                Button("Paste") { text = UIPasteboard.general.string ?? "" }
                    .font(Theme.Typography.fact(12, weight: .medium)).foregroundStyle(Theme.Palette.paprika)
                    .buttonStyle(.plain).padding(.trailing, 32).padding(.bottom, 12)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            SolidRule()
            if let error {
                Text(error).font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.paprika)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
            }
            PaprikaButton(title: busy ? "Reading the recipe…" : "Format with AI") { format() }
                .frame(maxWidth: .infinity).padding(.horizontal, 20)
                .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.bottom, 12)
        }
        .padding(.top, 10)
        .background(Theme.Palette.cream)
    }

    private func format() {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil; busy = true; focused = false
        Task {
            // A bare link → fetch & import; anything else → parse the pasted text.
            let parsed = isLink(input)
                ? await store.ai.importRecipe(urlString: input)
                : await store.ai.parseRecipe(text: text, into: .draft())
            busy = false
            if let parsed { onParsed(parsed) }
            else { error = isLink(input)
                ? "Couldn’t read a recipe from that link — try pasting the recipe text instead."
                : "Hmm — that didn’t look like a recipe, or the kitchen’s offline. Give it another try." }
        }
    }

    private func isLink(_ s: String) -> Bool {
        !s.contains(where: \.isNewline) && (s.hasPrefix("http://") || s.hasPrefix("https://"))
    }
}
