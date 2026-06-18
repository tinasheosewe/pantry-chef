import SwiftUI

/// Browse every dish — the SAME pantry lenses, "More filters" sheet, and painted-plate
/// tiles as the Today feed, so the two share one filter model. A two-column tile grid
/// with search and a "cook together" multi-select. (Tapping a feed tier's "see all"
/// filters the feed in place; this is the full, searchable index.)
struct LibraryView: View {
    var store: KitchenStore
    var onCook: (Dish) -> Void = { _ in }
    var onCookTogether: ([Dish]) -> Void = { _ in }

    @State private var lens: FeedLens
    @State private var filters = FeedFilters()
    @State private var query = ""
    @State private var showFilters = false
    @State private var selecting = false
    @State private var selectedIDs: Set<UUID> = []

    init(store: KitchenStore, onCook: @escaping (Dish) -> Void = { _ in },
         onCookTogether: @escaping ([Dish]) -> Void = { _ in }, initialLens: FeedLens = .all) {
        self.store = store
        self.onCook = onCook
        self.onCookTogether = onCookTogether
        _lens = State(initialValue: initialLens)
    }

    /// The library through the active lens + secondary filters + the name search.
    private var dishes: [Dish] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.library.filter { dish in
            store.matches(dish, lens: lens) && filters.accepts(dish)
                && (q.isEmpty || dish.name.lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, Theme.Metric.lg).padding(.top, 6)
            searchField.padding(.horizontal, Theme.Metric.lg).padding(.top, 8)
            IntentPills(selected: $lens, filterCount: filters.activeCount,
                        onOpenFilters: { showFilters = true })
                .padding(.top, 10)
            DashedRule().padding(.horizontal, Theme.Metric.lg).padding(.top, 8)
            ScrollView {
                if dishes.isEmpty {
                    Text("Nothing matches — clear a filter or your search.")
                        .font(Theme.Typography.note(12.5)).foregroundStyle(Theme.Palette.warmGray)
                        .frame(maxWidth: .infinity).padding(.top, 28)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                              alignment: .leading, spacing: 16) {
                        ForEach(dishes) { dish in tile(dish) }
                    }
                    .padding(.horizontal, Theme.Metric.lg).padding(.top, 14).padding(.bottom, 24)
                }
            }
        }
        .background(KitchenBackground())
        .safeAreaInset(edge: .bottom) {
            if selecting && !selectedIDs.isEmpty { cookTogetherBar }
        }
        .sheet(isPresented: $showFilters) {
            FeedFiltersSheet(
                filters: $filters,
                cuisines: store.libraryCuisines(),
                diets: store.libraryDiets(),
                mealTypes: store.libraryMealTypes(),
                resultCount: dishes.count,
                onClose: { showFilters = false })
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Header & search

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("Dishes").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
            Text("\(store.library.count)").font(Theme.Typography.numeral(12, weight: .semibold))
                .foregroundStyle(Theme.Palette.warmGray)
            Spacer()
            Button { withAnimation { selecting.toggle(); selectedIDs = [] } } label: {
                Text(selecting ? "CANCEL" : "COOK TOGETHER")
                    .font(.system(size: 9, weight: .medium)).tracking(1.8)
                    .foregroundStyle(Theme.Palette.paprika).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
                .foregroundStyle(Theme.Palette.ink.opacity(0.45))
            TextField("Search dishes", text: $query)
                .font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ink)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.ink.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Grid

    @ViewBuilder private func tile(_ dish: Dish) -> some View {
        let selected = selectedIDs.contains(dish.id)
        RecipeTile(item: store.feedItem(dish)) { tapped in
            if selecting {
                if selected { selectedIDs.remove(dish.id) } else { selectedIDs.insert(dish.id) }
            } else {
                onCook(tapped)
            }
        }
        .overlay(alignment: .topTrailing) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Theme.Palette.paprika : Theme.Palette.ink.opacity(0.35))
                    .padding(8)
            }
        }
        .opacity(selecting && !selected ? 0.6 : 1)
    }

    private var cookTogetherBar: some View {
        VStack(spacing: 0) {
            SolidRule()
            HStack {
                Text("\(selectedIDs.count) SELECTED")
                    .font(.system(size: 9)).tracking(1.8).foregroundStyle(Theme.Palette.ink.opacity(0.55))
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
