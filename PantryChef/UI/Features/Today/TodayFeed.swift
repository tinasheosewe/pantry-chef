import SwiftUI

/// The Today feed's intent lenses (the chips). "For you" is the curated default —
/// the pinned hero + named rails + one editorial feature; the rest collapse the feed
/// to a single filtered grid. Pantry-aware lenses (Ready now / Use it up) are the
/// app's moat, so they lead.
enum FeedLens: String, CaseIterable, Identifiable {
    case all, readyNow, useItUp, quick, family, highProtein

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "For you"
        case .readyNow: return "Ready now"
        case .useItUp: return "Use it up"
        case .quick: return "Quick"
        case .family: return "Family"
        case .highProtein: return "High-protein"
        }
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedLens.allCases) { lens in
                    let on = lens == selected
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { selected = lens }
                    } label: {
                        Text(lens.title.uppercased())
                            .font(.system(size: 10.5, weight: on ? .semibold : .regular))
                            .tracking(1.2)
                            .foregroundStyle(on ? Theme.Palette.cream : Theme.Palette.ink)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Rectangle().fill(on ? Theme.Palette.ink : .clear))
                            .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(on ? 0 : 0.4), lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Metric.lg)
        }
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
