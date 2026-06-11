import SwiftUI

/// The recipe itself (spec §6) — what you see when you tap a dish anywhere. Shows
/// the plate, readiness, ingredients (with on-hand status and substitutions for
/// what's missing), and the method. The "Cook" button leads into mise en place.
struct RecipeDetailView: View {
    let dish: Dish
    let readiness: Readiness
    var isOnHand: (String) -> Bool = { _ in true }
    var onCook: () -> Void
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if !DishInsights.allergens(for: dish).isEmpty { allergens }
                ingredients
                if !dish.steps.isEmpty { method }
            }
            .padding(20).padding(.bottom, 90)
        }
        .background(KitchenBackground())
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Palette.warmGray)
                    .padding(10).background(Circle().fill(Theme.Palette.creamRaised))
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) { cookBar }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            PlateView(composition: dish.plate, size: 140)
            Text(dish.name).font(Theme.Typography.dish(26)).foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Text(dish.time).font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.warmGray)
                Text("·").foregroundStyle(Theme.Palette.warmGraySoft)
                readinessLabel
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    @ViewBuilder private var readinessLabel: some View {
        switch readiness {
        case .ready:
            Text("everything on hand").font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.sage)
        case .readyWithSwaps:
            Text("ready with a swap").font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.sage)
        case .needs(let items):
            Text("needs \(items.count)").font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.ochre)
        }
    }

    private var allergens: some View {
        FlowRow(DishInsights.allergens(for: dish).map(\.title)) { title in
            Text(title).font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGray)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Theme.Palette.creamRaised))
                .overlay(Capsule().strokeBorder(Theme.Palette.hairline))
        }
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Ingredients")
            ForEach(dish.ingredients) { line in
                ingredientRow(line)
                if line.id != dish.ingredients.last?.id { Divider().background(Theme.Palette.hairline) }
            }
        }
        .padding(14).glassCard(cornerRadius: 22)
    }

    private func ingredientRow(_ line: RecipeLine) -> some View {
        let onHand = isOnHand(line.key) || line.isStaple
        let swaps = onHand ? [] : DishInsights.swaps(forKey: line.key)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: onHand ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(onHand ? Theme.Palette.sage : Theme.Palette.warmGraySoft.opacity(0.5))
                Text(line.display).font(Theme.Typography.fact(14)).foregroundStyle(Theme.Palette.ink)
                if let grams = UnitConversion.gramHint(for: line) {
                    Text(grams).font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
                }
                Spacer()
                if !onHand && !line.isStaple { Text("need").font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.ochre) }
            }
            if let swap = swaps.first {
                Text("swap: \(swap.name)\(swap.notes.map { " — \($0)" } ?? "")")
                    .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage).padding(.leading, 25)
            }
        }
        .padding(.vertical, 9)
    }

    private var method: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Method")
            ForEach(Array(dish.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)").font(Theme.Typography.numeral(13)).foregroundStyle(Theme.Palette.paprika)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.Palette.paprika.opacity(0.12)))
                    Text(step.instruction).font(Theme.Typography.fact(14)).foregroundStyle(Theme.Palette.ink)
                        .lineSpacing(3)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard(cornerRadius: 22)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(Theme.Typography.eyebrow).tracking(Theme.Metric.eyebrowTracking)
            .foregroundStyle(Theme.Palette.warmGraySoft).padding(.bottom, 6)
    }

    private var cookBar: some View {
        PaprikaButton(title: "Cook", action: onCook)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(.ultraThinMaterial)
    }
}

/// Minimal wrapping row for short chips.
private struct FlowRow<Content: View>: View {
    let items: [String]
    @ViewBuilder let content: (String) -> Content
    init(_ items: [String], @ViewBuilder content: @escaping (String) -> Content) {
        self.items = items; self.content = content
    }
    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 70), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}
