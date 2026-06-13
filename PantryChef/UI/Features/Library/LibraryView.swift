import SwiftUI

/// Dishes — the printed index (spec §3/§6, Field Notes). Every dish gets its
/// sentence and a fact line; sections group by *reason* (ready tonight / worth a
/// shop); the small-caps filter line narrows the page. Readiness is live via
/// ReadinessService; the dietary profile flags conflicts.
struct LibraryView: View {
    var store: KitchenStore
    var onCook: (Dish) -> Void = { _ in }
    var onCookTogether: ([Dish]) -> Void = { _ in }

    @State private var showProfile = false
    @State private var selecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var query = ""

    private var filter: LibraryFilter { store.libraryFilter }

    private var dishes: [Dish] {
        store.library.filter { dish in
            let passesFilter: Bool
            switch filter {
            case .all: passesFilter = true
            case .ready: passesFilter = store.readiness(for: dish).isMakeableNow
            case .under30: passesFilter = (dish.minutes ?? .max) <= 30
            case .favorites: passesFilter = dish.isFavorite
            }
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            return passesFilter && (q.isEmpty || dish.name.lowercased().contains(q))
        }
    }

    private var readyDishes: [Dish] { dishes.filter { store.readiness(for: $0).isMakeableNow } }
    private var shopDishes: [Dish] { dishes.filter { !store.readiness(for: $0).isMakeableNow } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                header
                filterLine
                searchField
                DashedRule()
            }
            .padding(.horizontal, 20).padding(.top, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !readyDishes.isEmpty {
                        Eyebrow(text: "Ready tonight", tone: .urgent).padding(.top, 12)
                        list(readyDishes)
                    }
                    if !shopDishes.isEmpty {
                        Eyebrow(text: "Worth a shop").padding(.top, 14)
                        list(shopDishes)
                    }
                    if dishes.isEmpty {
                        Text("Nothing here — clear the filter or add a dish with ＋.")
                            .font(Theme.Typography.note(12.5)).foregroundStyle(Theme.Palette.warmGray)
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .background(KitchenBackground())
        .safeAreaInset(edge: .bottom) {
            if selecting && !selectedIDs.isEmpty { cookTogetherBar }
        }
        .sheet(isPresented: $showProfile) {
            ProfileEditorView(profile: Binding(get: { store.profile }, set: { store.profile = $0 }))
                .presentationDetents([.medium])
        }
    }

    // MARK: - Header & filters

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Dishes").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
            Spacer()
            Button {
                withAnimation { selecting.toggle(); selectedIDs = [] }
            } label: {
                Text(selecting ? "CANCEL" : "COOK TOGETHER")
                    .font(.system(size: 9, weight: .medium)).tracking(1.8)
                    .foregroundStyle(Theme.Palette.paprika)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { showProfile = true } label: {
                Image(systemName: store.profile.isEmpty ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                    .font(.system(size: 17))
                    .foregroundStyle(store.profile.isEmpty ? Theme.Palette.ink.opacity(0.5) : Theme.Palette.sage)
            }
            .buttonStyle(.plain).padding(.leading, 12)
            .accessibilityLabel("Dietary profile")
        }
    }

    /// "24 — ALL · READY 6 · UNDER 30' · YOURS": the current cut underlined tomato.
    private var filterLine: some View {
        HStack(spacing: 0) {
            Text("\(store.library.count) — ")
                .font(.system(size: 10)).tracking(1.4)
                .foregroundStyle(Theme.Palette.ink.opacity(0.55))
            ForEach(LibraryFilter.allCases) { f in
                let selected = filter == f
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { store.libraryFilter = f }
                } label: {
                    Text(label(f))
                        .font(.system(size: 10, weight: selected ? .semibold : .regular)).tracking(1.4)
                        .foregroundStyle(selected ? Theme.Palette.paprika : Theme.Palette.ink.opacity(0.55))
                        .overlay(alignment: .bottom) {
                            if selected {
                                Rectangle().fill(Theme.Palette.paprika).frame(height: 1).offset(y: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if f != LibraryFilter.allCases.last {
                    Text(" · ").font(.system(size: 10)).foregroundStyle(Theme.Palette.ink.opacity(0.4))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func label(_ f: LibraryFilter) -> String {
        switch f {
        case .all: return "ALL"
        case .ready: return "READY \(store.library.filter { store.readiness(for: $0).isMakeableNow }.count)"
        case .under30: return "UNDER 30'"
        case .favorites: return "YOURS"
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
                .foregroundStyle(Theme.Palette.ink.opacity(0.45))
            TextField("Search the index", text: $query)
                .font(Theme.Typography.fact(13))
                .foregroundStyle(Theme.Palette.ink)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.ink.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - The index

    private func list(_ group: [Dish]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(group) { dish in
                Button { tap(dish) } label: {
                    DishLine(dish: dish,
                             readiness: store.readiness(for: dish),
                             conflicts: DishInsights.conflicts(dish, with: store.profile),
                             selecting: selecting,
                             isSelected: selectedIDs.contains(dish.id),
                             onToggleFavorite: { store.toggleFavorite(dish.id) })
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if dish.id != group.last?.id { DashedRule(opacity: 0.55) }
            }
        }
    }

    private func tap(_ dish: Dish) {
        if selecting {
            if selectedIDs.contains(dish.id) { selectedIDs.remove(dish.id) } else { selectedIDs.insert(dish.id) }
        } else {
            onCook(dish)
        }
    }

    private var cookTogetherBar: some View {
        VStack(spacing: 0) {
            SolidRule()
            HStack {
                Text("\(selectedIDs.count) SELECTED")
                    .font(.system(size: 9)).tracking(1.8)
                    .foregroundStyle(Theme.Palette.ink.opacity(0.55))
                Spacer()
                BlockButton(title: "Cook \(selectedIDs.count) together") {
                    let chosen = store.library.filter { selectedIDs.contains($0.id) }
                    selecting = false; selectedIDs = []
                    onCookTogether(chosen)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(Theme.Palette.cream)
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, ready, under30, favorites
    var id: String { rawValue }
}

/// One index line: plate · serif name (♥ YOURS rides along) · its sentence · the
/// fact line. The fact line tells the truth about readiness.
private struct DishLine: View {
    let dish: Dish
    let readiness: Readiness
    let conflicts: [Allergen]
    var selecting = false
    var isSelected = false
    var onToggleFavorite: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            if selecting {
                Rectangle()
                    .strokeBorder(isSelected ? Theme.Palette.paprika : Theme.Palette.ink.opacity(0.4), lineWidth: 1)
                    .background(Rectangle().fill(isSelected ? Theme.Palette.paprika : .clear))
                    .frame(width: 14, height: 14)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.Palette.cream)
                        }
                    }
                    .padding(.top, 12)
            }
            PlateView(name: dish.name, composition: dish.plate, size: 38)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(dish.name).font(Theme.Typography.dish(15)).foregroundStyle(Theme.Palette.ink)
                    if dish.isYours {
                        Text("♥ YOURS").font(.system(size: 8)).tracking(1.4)
                            .foregroundStyle(Theme.Palette.paprika)
                    }
                }
                if let blurb = dish.blurb {
                    Text(blurb).font(Theme.Typography.note(11.5)).foregroundStyle(Theme.Palette.warmGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                factLine
                if !conflicts.isEmpty {
                    Text("CONTAINS \(conflicts.map(\.title).joined(separator: ", ").uppercased())")
                        .font(.system(size: 8)).tracking(1.4)
                        .foregroundStyle(Theme.Palette.paprika)
                }
            }
            Spacer(minLength: 0)
            if !selecting {
                Button(action: onToggleFavorite) {
                    Image(systemName: dish.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 11))
                        .foregroundStyle(dish.isFavorite ? Theme.Palette.paprika : Theme.Palette.ink.opacity(0.35))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dish.isFavorite ? "Unfavorite" : "Favorite")
            }
        }
        .padding(.vertical, 9)
        .opacity(selecting && !isSelected ? 0.65 : 1)
    }

    @ViewBuilder private var factLine: some View {
        switch readiness {
        case .ready:
            line("\(dish.time) — all on hand", Theme.Palette.ink.opacity(0.55))
        case .readyWithSwaps:
            line("\(dish.time) — with a swap", Theme.Palette.sage)
        case .needs(let items):
            line("needs \(items.count) — \(items.prefix(2).joined(separator: ", "))", Theme.Palette.paprika)
        }
    }

    private func line(_ text: String, _ color: Color) -> some View {
        Text(text.uppercased()).font(.system(size: 8.5)).tracking(1.6).foregroundStyle(color)
            .padding(.top, 1)
    }
}

/// Edit the household's avoided allergens — filters and flags across the app.
private struct ProfileEditorView: View {
    @Binding var profile: DietaryProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What do you avoid?").font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)
                .padding(.top, 24)
            Text("Dishes containing these get flagged across the index.")
                .font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.warmGray)
            DashedRule()
            FlowChips(items: Allergen.allCases) { allergen in
                let on = profile.avoided.contains(allergen)
                Button {
                    if on { profile.avoided.remove(allergen) } else { profile.avoided.insert(allergen) }
                } label: {
                    Text(allergen.title.uppercased()).font(.system(size: 10)).tracking(1.4)
                        .foregroundStyle(on ? Theme.Palette.cream : Theme.Palette.ink.opacity(0.7))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Rectangle().fill(on ? Theme.Palette.paprika : .clear))
                        .overlay(Rectangle().strokeBorder(
                            on ? Theme.Palette.paprika : Theme.Palette.ink.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KitchenBackground())
    }
}

/// A simple wrapping row of chips.
private struct FlowChips<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items) { content($0) }
        }
    }
}
