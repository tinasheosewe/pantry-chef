import SwiftUI

/// Edit a recipe: name, time, servings, ingredient lines, and steps. Works on a
/// local copy; Save hands the edited dish back.
struct RecipeEditorView: View {
    @State private var dish: Dish
    var onSave: (Dish) -> Void

    init(dish: Dish, onSave: @escaping (Dish) -> Void) {
        _dish = State(initialValue: dish)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4).padding(.top, 10)
            HStack {
                Text("Edit recipe").font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                PaprikaButton(title: "Save") { onSave(dish) }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Name") { TextField("Name", text: $dish.name) }
                    HStack(spacing: 12) {
                        field("Time") { TextField("25 min", text: $dish.time) }
                        field("Serves") {
                            Stepper("\(dish.servings)", value: $dish.servings, in: 1...24)
                        }
                    }
                    ingredientsSection
                    stepsSection
                }
                .padding(20)
            }
        }
        .background(KitchenBackground())
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Ingredients")
            ForEach($dish.ingredients) { $line in
                HStack(spacing: 8) {
                    TextField("amount", text: Binding(
                        get: { line.amount ?? "" },
                        set: { line = RecipeLine(id: line.id, key: line.key,
                                                 amount: $0.isEmpty ? nil : $0,
                                                 name: line.name, isStaple: line.isStaple) }))
                        .frame(width: 84)
                    TextField("ingredient", text: Binding(
                        get: { line.name },
                        set: { line = RecipeLine(id: line.id, key: $0.lowercased(),
                                                 amount: line.amount, name: $0, isStaple: line.isStaple) }))
                    Button {
                        dish.ingredients.removeAll { $0.id == line.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 16))
                            .foregroundStyle(Theme.Palette.warmGraySoft.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .font(Theme.Typography.fact(14))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.Palette.creamRaised))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.Palette.hairline))
            }
            addButton("Add ingredient") {
                dish.ingredients.append(RecipeLine(key: "", amount: nil, name: ""))
            }
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Method")
            ForEach(Array($dish.steps.enumerated()), id: \.element.id) { index, $step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)").font(Theme.Typography.numeral(12)).foregroundStyle(Theme.Palette.paprika)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Theme.Palette.paprika.opacity(0.12)))
                        .padding(.top, 8)
                    TextField("step", text: Binding(
                        get: { step.instruction },
                        set: { step = CookStep(id: step.id, $0, timerSeconds: step.timerSeconds) }),
                        axis: .vertical)
                        .lineLimit(1...4)
                    Button {
                        dish.steps.removeAll { $0.id == step.id }
                    } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 16))
                            .foregroundStyle(Theme.Palette.warmGraySoft.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .font(Theme.Typography.fact(14))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.Palette.creamRaised))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.Palette.hairline))
            }
            addButton("Add step") {
                dish.steps.append(CookStep(""))
            }
        }
    }

    // MARK: - Bits

    private func addButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.paprika)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(Theme.Typography.eyebrow).tracking(Theme.Metric.eyebrowTracking)
            .foregroundStyle(Theme.Palette.warmGraySoft)
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle(label)
            content()
                .font(Theme.Typography.fact(15)).foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.Palette.creamRaised))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.Palette.hairline))
        }
    }
}
