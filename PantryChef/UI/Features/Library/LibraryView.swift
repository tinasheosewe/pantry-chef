import SwiftUI

/// Library — the plate gallery (spec §3/§6). Readiness is the first-class fact on
/// every cell (live via ReadinessService); allergens surface from the catalog, and
/// a dietary profile filters and flags. Filter bar narrows the gallery.
struct LibraryView: View {
    var store: KitchenStore
    var onCook: (Dish) -> Void = { _ in }

    @State private var filter: LibraryFilter = .all
    @State private var showProfile = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var dishes: [Dish] {
        store.library.filter { dish in
            switch filter {
            case .all: return true
            case .ready: return store.readiness(for: dish).isMakeableNow
            case .under30: return (dish.minutes ?? .max) <= 30
            case .favorites: return dish.isFavorite
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                filterBar
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(dishes) { dish in
                        LibraryCell(dish: dish,
                                    readiness: store.readiness(for: dish),
                                    conflicts: DishInsights.conflicts(dish, with: store.profile),
                                    allergens: DishInsights.allergens(for: dish))
                            .onTapGesture { onCook(dish) }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 96)
        }
        .background(KitchenBackground())
        .sheet(isPresented: $showProfile) {
            ProfileEditorView(profile: Binding(get: { store.profile }, set: { store.profile = $0 }))
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Library").font(Theme.Typography.dish(26)).foregroundStyle(Theme.Palette.ink)
            Spacer()
            Button { showProfile = true } label: {
                Image(systemName: store.profile.isEmpty ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                    .font(.system(size: 20)).foregroundStyle(store.profile.isEmpty ? Theme.Palette.warmGraySoft : Theme.Palette.sage)
            }
            .accessibilityLabel("Dietary profile")
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { f in
                    let selected = filter == f
                    Button { withAnimation(.easeOut(duration: 0.2)) { filter = f } } label: {
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

    var body: some View {
        VStack(spacing: 10) {
            PlateView(composition: dish.plate, size: 70)
                .overlay(alignment: .topTrailing) {
                    if dish.isFavorite {
                        Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(Theme.Palette.paprika)
                            .padding(5).background(Circle().fill(Theme.Palette.cream)).offset(x: 6, y: -4)
                    }
                }
            VStack(spacing: 3) {
                Text(dish.name).font(Theme.Typography.dish(14)).foregroundStyle(Theme.Palette.ink)
                    .multilineTextAlignment(.center).lineLimit(2)
                statusLine
                allergenLine
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 8)
        .glassCard(cornerRadius: 20)
    }

    @ViewBuilder private var statusLine: some View {
        switch readiness {
        case .ready:
            Text("\(dish.time) · ready").font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage)
        case .readyWithSwaps(let swaps):
            Text("ready · \(swaps.first.map { "\($0.fromName) → \($0.toName)" } ?? "with a swap")")
                .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage).lineLimit(1)
        case .needs(let items):
            Text(dish.isYours ? "your dish · \(dish.time)" : "needs \(items.count)")
                .font(Theme.Typography.fact(11))
                .foregroundStyle(dish.isYours ? Theme.Palette.paprika : Theme.Palette.ochre)
        }
    }

    @ViewBuilder private var allergenLine: some View {
        if !conflicts.isEmpty {
            Label("contains \(conflicts.map(\.title).joined(separator: ", ").lowercased())", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon).font(Theme.Typography.fact(10))
                .foregroundStyle(Theme.Palette.ochre).lineLimit(1)
        } else if !allergens.isEmpty {
            Text(allergens.map(\.title).joined(separator: " · ").lowercased())
                .font(Theme.Typography.fact(10)).foregroundStyle(Theme.Palette.warmGraySoft.opacity(0.8)).lineLimit(1)
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
