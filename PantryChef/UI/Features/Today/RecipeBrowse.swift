import SwiftUI

/// The Today browse experience as a self-contained component — lens chips, search,
/// secondary filters, and a *sorted* two-column grid of recipe tiles. Extracted so
/// the meal-planner's recipe picker is the same UI as Today (filter · search · tiles
/// · readiness order), not a plain unsorted list. The caller decides what a tap does.
struct RecipeBrowse: View {
    var store: KitchenStore
    /// Candidate dishes — already dietary-filtered by the caller.
    var library: [Dish]
    /// What tapping a tile does: open it, plan it, …
    var onPick: (Dish) -> Void

    @State private var lens: FeedLens = .all
    @State private var search = ""
    @State private var filters = FeedFilters()
    @State private var showFilters = false

    /// Matching the lens + filters + search, then sorted make-now → with-a-swap →
    /// a-shop-away, then alphabetically — a clear, predictable order (the picker's old
    /// list had none).
    private var results: [Dish] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return library
            .filter {
                store.matches($0, lens: lens) && filters.accepts($0)
                    && (q.isEmpty || $0.name.lowercased().contains(q))
            }
            .sorted { a, b in
                let ra = rank(a), rb = rank(b)
                if ra != rb { return ra < rb }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    private func rank(_ dish: Dish) -> Int {
        switch store.readiness(for: dish) {
        case .ready: return 0
        case .readyWithSwaps: return 1
        case .needs: return 2
        }
    }

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            IntentPills(selected: $lens, filterCount: filters.activeCount,
                        onOpenFilters: { showFilters = true })
                .padding(.top, 4)
            searchField
                .padding(.horizontal, Theme.Metric.lg).padding(.top, 12).padding(.bottom, 6)
            ScrollView {
                if results.isEmpty {
                    Text("Nothing matches — clear a filter or your search.")
                        .font(Theme.Typography.note(13)).foregroundStyle(Theme.Palette.warmGray)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 16) {
                        ForEach(results) { dish in
                            RecipeTile(item: store.feedItem(dish)) { onPick($0) }
                        }
                    }
                    .padding(.horizontal, Theme.Metric.lg).padding(.top, 8).padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $showFilters) {
            FeedFiltersSheet(filters: $filters,
                             cuisines: distinct { $0.cuisine },
                             diets: distinctDiets,
                             mealTypes: distinct { $0.mealType },
                             resultCount: results.count,
                             onClose: { showFilters = false })
                .presentationDetents([.medium, .large])
        }
    }

    /// Inline editorial search (magnifier + text, no boxed field), matching Today.
    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
                .foregroundStyle(Theme.Palette.ink.opacity(0.45))
            TextField("Search dishes", text: $search)
                .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.ink.opacity(0.45))
                }.buttonStyle(.plain)
            }
        }
    }

    private func distinct(_ key: (Dish) -> String?) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for dish in library {
            guard let v = key(dish), !v.isEmpty else { continue }
            if seen.insert(v.lowercased()).inserted { out.append(v) }
        }
        return out.sorted()
    }
    private var distinctDiets: [String] {
        var seen = Set<String>(); var out: [String] = []
        for dish in library {
            for d in dish.diets where seen.insert(d.lowercased()).inserted { out.append(d) }
        }
        return out.sorted()
    }
}
