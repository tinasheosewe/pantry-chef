import SwiftUI

/// The Today feed's intent lenses (the chips). "For you" is the curated default —
/// the pinned hero + named rails + one editorial feature; the rest collapse the feed
/// to a single filtered grid. Pantry-aware lenses (Ready now / Use it up) are the
/// app's moat, so they lead.
enum FeedLens: String, CaseIterable, Identifiable {
    case all, readyNow, useItUp, quick, highProtein

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "For you"
        case .readyNow: return "Ready now"
        case .useItUp: return "Use it up"
        case .quick: return "Quick"
        case .highProtein: return "High-protein"
        }
    }
}

/// Secondary filters (the "More filters" sheet) — catalog-derived facets that layer on
/// top of the active lens. Single-select per dimension; recommended set from the
/// filter-taxonomy research (cuisine · diet · meal type · time).
struct FeedFilters: Equatable {
    var cuisine: String?
    var diet: String?
    var mealType: String?
    var maxMinutes: Int?

    var isEmpty: Bool { cuisine == nil && diet == nil && mealType == nil && maxMinutes == nil }
    var activeCount: Int { [cuisine != nil, diet != nil, mealType != nil, maxMinutes != nil].filter { $0 }.count }

    func accepts(_ dish: Dish) -> Bool {
        if let c = cuisine, dish.cuisine?.caseInsensitiveCompare(c) != .orderedSame { return false }
        if let m = mealType, dish.mealType?.caseInsensitiveCompare(m) != .orderedSame { return false }
        if let d = diet, !dish.diets.contains(where: { $0.caseInsensitiveCompare(d) == .orderedSame }) { return false }
        if let mins = maxMinutes, (dish.minutes ?? .max) > mins { return false }
        return true
    }
}

/// One card in the feed: a dish plus the pre-computed line of facts and an optional
/// stamp ("READY") — the caller (which has the store) bakes in readiness so the tile
/// stays a dumb renderer.
struct FeedItem: Identifiable {
    var id: UUID { dish.id }
    let dish: Dish
    let meta: String
    let stamp: String?
}

/// A named horizontal rail of feed items ("Ready now", "Fast tonight"…).
struct FeedRail: Identifiable {
    var id: String { title }
    let title: String
    let subtitle: String?
    let items: [FeedItem]
}

/// The intent chips — squared, printed, horizontally scrollable. One selected at a time.
struct IntentPills: View {
    @Binding var selected: FeedLens
    var filterCount: Int = 0
    var onOpenFilters: () -> Void = {}

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedLens.allCases) { lens in
                    pill(lens.title, on: lens == selected) {
                        withAnimation(.easeOut(duration: 0.15)) { selected = lens }
                    }
                }
                // The "More filters" door — tomato when filters are active.
                Button(action: onOpenFilters) {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 10, weight: .semibold))
                        Text(filterCount > 0 ? "FILTERS · \(filterCount)" : "FILTERS")
                            .font(.system(size: 10.5, weight: filterCount > 0 ? .semibold : .regular)).tracking(1.2)
                    }
                    .foregroundStyle(filterCount > 0 ? Theme.Palette.cream : Theme.Palette.paprika)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Rectangle().fill(filterCount > 0 ? Theme.Palette.paprika : .clear))
                    .overlay(Rectangle().strokeBorder(Theme.Palette.paprika.opacity(filterCount > 0 ? 0 : 0.6), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Metric.lg)
        }
    }

    private func pill(_ title: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: on ? .semibold : .regular)).tracking(1.2)
                .foregroundStyle(on ? Theme.Palette.cream : Theme.Palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Rectangle().fill(on ? Theme.Palette.ink : .clear))
                .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(on ? 0 : 0.4), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One painted-plate card. Fixed width in a rail; fills its column in the grid (nil).
struct RecipeTile: View {
    let item: FeedItem
    var onOpen: (Dish) -> Void
    var fixedWidth: CGFloat? = nil

    private var plateSize: CGFloat { fixedWidth.map { $0 * 0.5 } ?? 78 }
    private var bandHeight: CGFloat { fixedWidth.map { $0 * 0.68 } ?? 108 }

    var body: some View {
        Button { onOpen(item.dish) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Theme.Palette.creamRaised)
                        .frame(height: bandHeight)
                        .overlay(PlateView(name: item.dish.name, composition: item.dish.plate, size: plateSize))
                        .overlay(Rectangle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
                    if let stamp = item.stamp {
                        Text(stamp)
                            .font(.system(size: 8.5, weight: .bold)).tracking(1)
                            .foregroundStyle(Theme.Palette.sage)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Rectangle().fill(Theme.Palette.cream))
                            .overlay(Rectangle().strokeBorder(Theme.Palette.sage.opacity(0.6), lineWidth: 1))
                            .padding(6)
                    }
                }
                Text(item.dish.name)
                    .font(Theme.Typography.dish(15)).foregroundStyle(Theme.Palette.ink).lineLimit(1)
                Text(item.meta)
                    .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGray).lineLimit(1)
            }
            .frame(width: fixedWidth)
            .frame(maxWidth: fixedWidth == nil ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A named rail: editorial title + italic note over a row of tiles.
struct RecipeRail: View {
    let rail: FeedRail
    var onOpen: (Dish) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 1) {
                Text(rail.title).font(Theme.Typography.dish(17)).foregroundStyle(Theme.Palette.ink)
                if let s = rail.subtitle {
                    Text(s).font(Theme.Typography.note(12)).foregroundStyle(Theme.Palette.warmGray)
                }
            }
            .padding(.horizontal, Theme.Metric.lg)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(rail.items) { item in
                        RecipeTile(item: item, onOpen: onOpen, fixedWidth: 142)
                    }
                }
                .padding(.horizontal, Theme.Metric.lg)
            }
        }
        .padding(.top, 18)
    }
}

/// The magazine interruption: one full-bleed editorial feature between rails.
struct FeatureCard: View {
    let item: FeedItem
    let eyebrow: String
    let subtitle: String
    var onOpen: (Dish) -> Void

    var body: some View {
        Button { onOpen(item.dish) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Theme.Palette.creamRaised)
                    .frame(height: 168)
                    .overlay(PlateView(name: item.dish.name, composition: item.dish.plate, size: 112))
                    .overlay(Rectangle().strokeBorder(Theme.Palette.hairline, lineWidth: 1))
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(2)
                    .foregroundStyle(Theme.Palette.paprika).padding(.top, 11)
                Text(item.dish.name)
                    .font(Theme.Typography.dish(24)).foregroundStyle(Theme.Palette.ink)
                Text(subtitle)
                    .font(Theme.Typography.note(13)).foregroundStyle(Theme.Palette.warmGray)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 3)
                Text(item.meta)
                    .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGray).padding(.top, 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The "More filters" sheet — catalog facets (meal type · cuisine · diet · time) that
/// layer on the active lens. Single-select per dimension; tapping a selected chip clears it.
struct FeedFiltersSheet: View {
    @Binding var filters: FeedFilters
    let cuisines: [String]
    let diets: [String]
    let mealTypes: [String]
    let resultCount: Int
    var onClose: () -> Void

    private let times: [(String, Int)] = [("15", 15), ("30", 30), ("45", 45), ("60", 60)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Filters").font(Theme.Typography.dish(22)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                if !filters.isEmpty {
                    Button { withAnimation { filters = FeedFilters() } } label: {
                        Text("CLEAR").font(.system(size: 11, weight: .medium)).tracking(1.2)
                            .foregroundStyle(Theme.Palette.paprika)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
            DashedRule().padding(.horizontal, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Meal type", mealTypes, selected: filters.mealType) { filters.mealType = toggled(filters.mealType, $0) }
                    section("Cuisine", cuisines, selected: filters.cuisine) { filters.cuisine = toggled(filters.cuisine, $0) }
                    section("Diet", diets, selected: filters.diet) { filters.diet = toggled(filters.diet, $0) }
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Time")
                        HStack(spacing: 8) {
                            ForEach(times, id: \.1) { entry in
                                chip("\(entry.0) min", on: filters.maxMinutes == entry.1) {
                                    filters.maxMinutes = filters.maxMinutes == entry.1 ? nil : entry.1
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            Button(action: onClose) {
                Text(resultCount == 1 ? "Show 1 recipe" : "Show \(resultCount) recipes")
                    .font(Theme.Typography.fact(14, weight: .medium)).foregroundStyle(Theme.Palette.cream)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Rectangle().fill(Theme.Palette.paprika))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.bottom, 16).padding(.top, 4)
        }
        .background(KitchenBackground())
    }

    private func toggled(_ current: String?, _ value: String) -> String? { current == value ? nil : value }

    @ViewBuilder private func section(_ title: String, _ values: [String], selected: String?, _ tap: @escaping (String) -> Void) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: title)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(values, id: \.self) { v in
                            chip(filterTitle(v), on: selected?.caseInsensitiveCompare(v) == .orderedSame) { tap(v) }
                        }
                    }
                }
            }
        }
    }

    private func filterTitle(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }

    private func chip(_ title: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title)
                .font(.system(size: 12, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.Palette.cream : Theme.Palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Rectangle().fill(on ? Theme.Palette.ink : .clear))
                .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(on ? 0 : 0.35), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
