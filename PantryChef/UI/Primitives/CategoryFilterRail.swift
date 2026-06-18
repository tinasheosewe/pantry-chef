import SwiftUI

/// A pinned, horizontally-scrolling category filter: "All" then one chip per supplied
/// category (emoji + name, with an optional paprika dot to flag a category that needs
/// attention). Shared by the Pantry inventory and the shopping list so both filter
/// categories the same way.
struct CategoryFilterRail: View {
    let categories: [FoodCategory]
    @Binding var selected: FoodCategory?
    /// Categories to mark with a paprika dot (e.g. the Pantry flags ones with an
    /// expiring item). Empty = no dots.
    var flagged: Set<FoodCategory> = []

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", emoji: nil, on: selected == nil, dot: false) { selected = nil }
                ForEach(categories) { cat in
                    chip(cat.rawValue, emoji: EmojiPlate.categoryFace(cat),
                         on: selected == cat, dot: flagged.contains(cat)) { selected = cat }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chip(_ title: String, emoji: String?, on: Bool, dot: Bool,
                      _ tap: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { tap() } } label: {
            HStack(spacing: 5) {
                if let emoji { Text(emoji).font(.system(size: 12)) }
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: on ? .semibold : .regular)).tracking(1.0)
                if dot { Circle().fill(Theme.Palette.paprika).frame(width: 5, height: 5) }
            }
            .foregroundStyle(on ? Theme.Palette.cream : Theme.Palette.ink)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Rectangle().fill(on ? Theme.Palette.ink : .clear))
            .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(on ? 0 : 0.4), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
