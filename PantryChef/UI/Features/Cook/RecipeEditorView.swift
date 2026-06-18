import SwiftUI

/// Edit a recipe: name, time, servings, ingredient lines, and steps. Works on a
/// local copy; Save hands the edited dish back. Amounts use a fixed unit picker
/// (never freeform), and ingredients resolve through the one intake pipeline —
/// catalog match or a validated custom item — so a recipe can't hold a freeform
/// ingredient that maps to nothing.
struct RecipeEditorView: View {
    @State private var dish: Dish
    var autofill: (String) async -> AIIngredientDefinition? = { _ in nil }
    var onSave: (Dish) -> Void

    @State private var newIngredient = ""
    @State private var resolving: Resolving?
    /// Steps whose phase the cook set by hand — those keep their tag through later
    /// text edits; untouched steps re-infer their phase from the wording.
    @State private var phaseTagged: Set<UUID> = []

    init(dish: Dish,
         autofill: @escaping (String) async -> AIIngredientDefinition? = { _ in nil },
         onSave: @escaping (Dish) -> Void) {
        _dish = State(initialValue: dish)
        self.autofill = autofill
        self.onSave = onSave
    }

    /// An ingredient phrase being resolved — for adding, or re-mapping a line.
    private enum Resolving: Identifiable {
        case pick(phrase: String, lineID: UUID?, candidates: [IntakeCandidate])
        case custom(phrase: String, lineID: UUID?)
        var id: String {
            switch self {
            case .pick(let p, let l, _): return "pick:\(p):\(l?.uuidString ?? "new")"
            case .custom(let p, let l): return "custom:\(p):\(l?.uuidString ?? "new")"
            }
        }
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
                        field("Serves") { Stepper("\(dish.servings)", value: $dish.servings, in: 1...24) }
                    }
                    ingredientsSection
                    stepsSection
                }
                .padding(20)
            }
        }
        .background(KitchenBackground())
        .sheet(item: $resolving) { r in
            switch r {
            case .pick(let phrase, let lineID, let candidates):
                IngredientPicker(
                    phrase: phrase, candidates: candidates,
                    onPick: { applyResolved(name: $0.name, key: $0.id, catalogItemID: $0.id, lineID: lineID); resolving = nil },
                    onCustom: { resolving = .custom(phrase: phrase, lineID: lineID) },
                    onCancel: { resolving = nil })
            case .custom(let phrase, let lineID):
                CustomIngredientForm(
                    name: phrase, autofill: autofill,
                    onSave: { def in applyResolved(name: def.name, key: def.id, catalogItemID: def.id, lineID: lineID); resolving = nil },
                    onCancel: { resolving = nil })
            }
        }
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Ingredients")
            ForEach($dish.ingredients) { $line in
                HStack(spacing: 8) {
                    AmountField(amount: Binding(
                        get: { line.amount },
                        set: { line = line.withAmount(qty: AmountText.qty($0), unit: AmountText.unit($0)) }))
                    Button {
                        beginResolve(phrase: line.name, lineID: line.id)
                    } label: {
                        Text(line.name.isEmpty ? "choose…" : line.name)
                            .foregroundStyle(line.name.isEmpty ? Theme.Palette.warmGraySoft : Theme.Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Button { dish.ingredients.removeAll { $0.id == line.id } } label: {
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
            // Add ingredient — resolved through the pipeline, never freeform.
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.Palette.paprika)
                TextField("Add an ingredient", text: $newIngredient)
                    .font(Theme.Typography.fact(14)).onSubmit(commitNewIngredient)
                if !newIngredient.trimmed.isEmpty {
                    Button("Add", action: commitNewIngredient)
                        .font(Theme.Typography.fact(12, weight: .medium)).foregroundStyle(Theme.Palette.paprika)
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
    }

    private func commitNewIngredient() {
        let phrase = newIngredient.trimmed
        guard !phrase.isEmpty else { return }
        newIngredient = ""
        beginResolve(phrase: phrase, lineID: nil)
    }

    private func beginResolve(phrase: String, lineID: UUID?) {
        guard !phrase.isEmpty else { return }
        let (intake, decision) = IntakePipeline.resolve(phrase, using: { IntakeParser().parse($0) })
        switch decision {
        case .confident:
            let resolvedName = intake.suggestedName ?? intake.name
            applyResolved(name: resolvedName,
                          key: intake.resolvedItemID ?? IngredientLexicon.lookupKey(intake.name),
                          catalogItemID: IntakePipeline.bestCatalogID(for: resolvedName, resolvedItemID: intake.resolvedItemID),
                          lineID: lineID)
        case .ambiguous(let candidates):
            resolving = .pick(phrase: phrase, lineID: lineID, candidates: candidates)
        case .custom:
            resolving = .custom(phrase: phrase, lineID: lineID)
        }
    }

    /// Apply a resolved ingredient — update the line, or add a new one. `catalogItemID`
    /// is the catalog identity the line resolved to (nil only for freeform), so the
    /// line matches readiness by id, not by name.
    private func applyResolved(name: String, key: String, catalogItemID: String?, lineID: UUID?) {
        let display = name.prefix(1).capitalized + name.dropFirst()
        if let lineID, let i = dish.ingredients.firstIndex(where: { $0.id == lineID }) {
            let old = dish.ingredients[i]
            dish.ingredients[i] = RecipeLine(id: old.id, key: key, amount: old.amount,
                                             name: display, isStaple: old.isStaple,
                                             essential: old.essential, catalogItemID: catalogItemID)
        } else {
            dish.ingredients.append(RecipeLine(key: key, amount: nil, name: display,
                                               catalogItemID: catalogItemID))
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
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("step", text: Binding(
                            get: { step.instruction },
                            set: { text in
                                // A hand-tagged step keeps its phase/attention; an
                                // untouched one re-infers from the new wording.
                                if phaseTagged.contains(step.id) {
                                    step = CookStep(id: step.id, text, timerSeconds: step.timerSeconds,
                                                    phase: step.phase, attention: step.attention,
                                                    ingredient: step.ingredient)
                                } else {
                                    step = CookStep(id: step.id, text, timerSeconds: step.timerSeconds)
                                }
                            }),
                            axis: .vertical)
                            .lineLimit(1...4)
                        phaseChip($step)
                    }
                    Button {
                        dish.steps.removeAll { $0.id == step.id }
                        phaseTagged.remove(step.id)
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
            addButton("Add step") { dish.steps.append(CookStep("")) }
        }
    }

    /// One-tap phase toggle — shows the step's phase (inferred until tapped), cycles
    /// prep → cook → finish, and marks the step hand-tagged so it stops re-inferring.
    private func phaseChip(_ step: Binding<CookStep>) -> some View {
        let phase = step.wrappedValue.phase
        let color = phaseColor(phase)
        return Button {
            let s = step.wrappedValue
            step.wrappedValue = CookStep(id: s.id, s.instruction, timerSeconds: s.timerSeconds,
                                         phase: phase.next, attention: s.attention, ingredient: s.ingredient)
            phaseTagged.insert(s.id)
        } label: {
            Text(phase.rawValue.uppercased())
                .font(.system(size: 9, weight: .medium)).tracking(1.2)
                .foregroundStyle(color)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func phaseColor(_ phase: StepPhase) -> Color {
        switch phase {
        case .prep: return Theme.Palette.sage
        case .cook: return Theme.Palette.paprika
        case .finish: return Theme.Palette.warmGray
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
