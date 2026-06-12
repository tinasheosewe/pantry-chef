import SwiftUI

/// Library — the plate gallery (spec §3/§6). Readiness is the first-class fact on
/// every cell (live via ReadinessService); allergens surface from the catalog, and
/// a dietary profile filters and flags. Filter bar narrows the gallery.
struct LibraryView: View {
    var store: KitchenStore
    var onCook: (Dish) -> Void = { _ in }
    var onCookTogether: ([Dish]) -> Void = { _ in }

    @State private var showProfile = false
    @State private var selecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var query = ""

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

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

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                header
                searchField
                filterBar
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(dishes) { dish in
                        Button { tap(dish) } label: {
                            LibraryCell(dish: dish,
                                        readiness: store.readiness(for: dish),
                                        conflicts: DishInsights.conflicts(dish, with: store.profile),
                                        allergens: DishInsights.allergens(for: dish),
                                        selecting: selecting,
                                        isSelected: selectedIDs.contains(dish.id),
                                        onToggleFavorite: { store.toggleFavorite(dish.id) })
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 96)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Library").font(Theme.Typography.dish(26)).foregroundStyle(Theme.Palette.ink)
            Spacer()
            Button {
                withAnimation { selecting.toggle(); selectedIDs = [] }
            } label: {
                Text(selecting ? "Cancel" : "Cook together").font(Theme.Typography.fact(12, weight: .medium))
                    .foregroundStyle(selecting ? Theme.Palette.ochre : Theme.Palette.paprika)
            }
            .buttonStyle(.plain)
            Button { showProfile = true } label: {
                Image(systemName: store.profile.isEmpty ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                    .font(.system(size: 20)).foregroundStyle(store.profile.isEmpty ? Theme.Palette.warmGraySoft : Theme.Palette.sage)
            }
            .buttonStyle(.plain).padding(.leading, 12)
            .accessibilityLabel("Dietary profile")
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
        HStack {
            Text("\(selectedIDs.count) selected").font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGraySoft)
            Spacer()
            PaprikaButton(title: "Cook \(selectedIDs.count) together") {
                let chosen = store.library.filter { selectedIDs.contains($0.id) }
                selecting = false; selectedIDs = []
                onCookTogether(chosen)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14).background(.ultraThinMaterial)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13))
                .foregroundStyle(Theme.Palette.warmGraySoft)
            TextField("Search recipes", text: $query)
                .font(Theme.Typography.fact(14))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                        .foregroundStyle(Theme.Palette.warmGraySoft.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Capsule().fill(Theme.Palette.creamRaised))
        .overlay(Capsule().strokeBorder(Theme.Palette.hairline))
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { f in
                    let selected = filter == f
                    Button { withAnimation(.easeOut(duration: 0.2)) { store.libraryFilter = f } } label: {
                        Text(label(f)).font(Theme.Typography.fact(12, weight: selected ? .medium : .regular))
                            .foregroundStyle(selected ? Theme.Palette.cream : Theme.Palette.warmGray)
                            .padding(.horizontal, 13).padding(.vertical, 6)
                            .background(Capsule().fill(selected ? Theme.Palette.ink : Color.clear))
                            .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func label(_ f: LibraryFilter) -> String {
        switch f {
        case .all: return "All · \(store.library.count)"
        case .ready: return "Ready · \(store.library.filter { store.readiness(for: $0).isMakeableNow }.count)"
        case .under30: return "Under 30"
        case .favorites: return "Favorites"
        }
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, ready, under30, favorites
    var id: String { rawValue }
}

private struct LibraryCell: View {
    let dish: Dish
    let readiness: Readiness
    let conflicts: [Allergen]
    let allergens: [Allergen]
    var selecting = false
    var isSelected = false
    var onToggleFavorite: () -> Void = {}

    var body: some View {
        VStack(spacing: 7) {
            PlateView(name: dish.name, composition: dish.plate, size: 54)
                .overlay(alignment: .topTrailing) {
                    if !selecting {
                        Button(action: onToggleFavorite) {
                            Image(systemName: dish.isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 10))
                                .foregroundStyle(dish.isFavorite ? Theme.Palette.paprika : Theme.Palette.warmGraySoft.opacity(0.7))
                                .padding(4).background(Circle().fill(Theme.Palette.cream))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 8, y: -5)
                        .accessibilityLabel(dish.isFavorite ? "Unfavorite" : "Favorite")
                    }
                }
            VStack(spacing: 2) {
                Text(dish.name).font(Theme.Typography.dish(13)).foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.center).lineLimit(2)
                    .frame(minHeight: 32, alignment: .top)
                statusLine
                if !conflicts.isEmpty {
                    Label(conflicts.map(\.title).joined(separator: ", ").lowercased(),
                          systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.titleAndIcon).font(Theme.Typography.fact(10))
                        .foregroundStyle(Theme.Palette.ochre).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11).padding(.horizontal, 5)
        .glassCard(cornerRadius: 18)
        .overlay {
            if selecting {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Palette.paprika : Theme.Palette.hairline,
                                  lineWidth: isSelected ? 2 : 1)
            }
        }
        .overlay(alignment: .topLeading) {
            if selecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Theme.Palette.paprika : Theme.Palette.warmGraySoft.opacity(0.6))
                    .padding(6)
            }
        }
        .opacity(selecting && !isSelected ? 0.7 : 1)
    }

    @ViewBuilder private var statusLine: some View {
        switch readiness {
        case .ready:
            Text("\(dish.time) · ready").font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage)
                .lineLimit(1)
        case .readyWithSwaps:
            Text("\(dish.time) · swap-ready")
                .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage).lineLimit(1)
        case .needs(let items):
            Text(dish.isYours ? "yours · \(dish.time)" : "\(dish.time) · needs \(items.count)")
                .font(Theme.Typography.fact(11))
                .foregroundStyle(dish.isYours ? Theme.Palette.paprika : Theme.Palette.ochre)
                .lineLimit(1)
        }
    }
}

/// Edit the household's avoided allergens — filters and flags across the app.
private struct ProfileEditorView: View {
    @Binding var profile: DietaryProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10)
            Text("What do you avoid?").font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)
            Text("Dishes containing these get flagged across your library.")
                .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGraySoft)

            FlowChips(items: Allergen.allCases) { allergen in
                let on = profile.avoided.contains(allergen)
                Button {
                    if on { profile.avoided.remove(allergen) } else { profile.avoided.insert(allergen) }
                } label: {
                    Text(allergen.title).font(Theme.Typography.fact(13))
                        .foregroundStyle(on ? Theme.Palette.cream : Theme.Palette.warmGray)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(on ? Theme.Palette.ochre : Color.clear))
                        .overlay(Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: on ? 0 : 1))
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
        // Two-column wrap keeps it simple and avoids a custom layout.
        let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items) { content($0) }
        }
    }
}
