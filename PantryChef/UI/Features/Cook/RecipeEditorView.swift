import SwiftUI

/// Edit a recipe: name, time, servings, ingredient lines, and steps. Works on a
/// local copy; Save hands the edited dish back. Amounts use a fixed unit picker
/// (never freeform), and ingredients resolve through the one intake pipeline —
/// catalog match or a validated custom item — so a recipe can't hold a freeform
/// ingredient that maps to nothing.
struct RecipeEditorView: View {
    @State private var dish: Dish
    /// Header label — "Edit recipe" by default, "New recipe" for the write-from-scratch door.
    var heading: String = "Edit recipe"
    var autofill: (String) async -> AIIngredientDefinition? = { _ in nil }
    /// AI clean-up of the whole rough recipe (fill amounts, step timers, structure). When
    /// nil the "Polish with AI" button is hidden.
    var polish: ((Dish) async -> Dish?)? = nil
    var onSave: (Dish) -> Void

    @State private var newIngredient = ""
    @State private var resolving: Resolving?
    @State private var aiBusy = false
    /// Steps whose phase the cook set by hand — those keep their tag through later
    /// text edits; untouched steps re-infer their phase from the wording.
    @State private var phaseTagged: Set<UUID> = []

    init(dish: Dish,
         heading: String = "Edit recipe",
         autofill: @escaping (String) async -> AIIngredientDefinition? = { _ in nil },
         polish: ((Dish) async -> Dish?)? = nil,
         onSave: @escaping (Dish) -> Void) {
        _dish = State(initialValue: dish)
        self.heading = heading
        self.autofill = autofill
        self.polish = polish
        self.onSave = onSave
    }

    /// On-hand essentials with no catalog identity — the "new to your kitchen" set.
    private var unknownLines: [RecipeLine] {
        dish.ingredients.filter { $0.catalogItemID == nil && !$0.isStaple && !$0.name.trimmed.isEmpty }
    }

    private var canSave: Bool { !dish.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
            HStack(spacing: 12) {
                Text(heading).font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)
                Spacer()
                if polish != nil && !dish.ingredients.isEmpty {
                    Button { polishWithAI() } label: {
                        HStack(spacing: 5) {
                            if aiBusy { ProgressView().controlSize(.small) }
                            else { Image(systemName: "wand.and.stars").font(.system(size: 12)) }
                            Text(aiBusy ? "Polishing…" : "Polish")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Theme.Palette.sage)
                    }
                    .buttonStyle(.plain).disabled(aiBusy)
                }
                PaprikaButton(title: "Save") { if canSave { onSave(dish) } }
                    .opacity(canSave ? 1 : 0.4)
                    .disabled(!canSave)
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
                        set: { line = line.withAmount(qty: AmountText.qty($0), unit: AmountText.unit($0)) }),
                        defaultUnit: PantryCatalog.itemsByID[line.catalogItemID ?? ""]?.defaultUnit)
                    let isNew = line.catalogItemID == nil && !line.isStaple && !line.name.trimmed.isEmpty
                    Button {
                        // A known line re-resolves; a new one opens the define form.
                        if isNew { resolving = .custom(phrase: line.name, lineID: line.id) }
                        else { beginResolve(phrase: line.name, lineID: line.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(line.name.isEmpty ? "choose…" : line.name)
                                .foregroundStyle(line.name.isEmpty ? Theme.Palette.warmGraySoft : Theme.Palette.ink)
                            if isNew {
                                Text("NEW").font(.system(size: 8, weight: .bold)).tracking(0.8)
                                    .foregroundStyle(Theme.Palette.paprika)
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .overlay(Rectangle().strokeBorder(Theme.Palette.paprika.opacity(0.5), lineWidth: 1))
                            }
                            Spacer(minLength: 0)
                        }
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
                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.creamRaised))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.Palette.hairline))
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
            newIngredientsBanner
        }
    }

    /// A quiet flag for the catalog-misses, never blocking: Smart-fill them all with AI
    /// (so they get expiry/aisle/readiness), or tap any "NEW" line to define it by hand.
    @ViewBuilder private var newIngredientsBanner: some View {
        let unknowns = unknownLines
        if !unknowns.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(unknowns.count == 1 ? "1 ingredient is new to your kitchen."
                                         : "\(unknowns.count) ingredients are new to your kitchen.")
                    .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGray)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button { smartFillUnknowns() } label: {
                        HStack(spacing: 5) {
                            if aiBusy { ProgressView().controlSize(.small) }
                            else { Image(systemName: "wand.and.stars").font(.system(size: 11)) }
                            Text(aiBusy ? "Smart-filling…" : "Smart-fill with AI")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Theme.Palette.sage)
                        .padding(.horizontal, 10).frame(minHeight: 34)
                        .overlay(Rectangle().strokeBorder(Theme.Palette.sage.opacity(0.6), lineWidth: 1))
                    }
                    .buttonStyle(.plain).disabled(aiBusy)
                    Text("or tap a NEW line to define it")
                        .font(Theme.Typography.fact(10.5)).foregroundStyle(Theme.Palette.warmGraySoft)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Rectangle().fill(Theme.Palette.paprika.opacity(0.06)))
            .overlay(Rectangle().strokeBorder(Theme.Palette.paprika.opacity(0.22), lineWidth: 1))
            .padding(.top, 8)
        }
    }

    // MARK: - AI assists

    /// Run the whole rough recipe back through the AI formatter — fill amounts, infer
    /// step timers, clean structure — preserving this recipe's identity.
    private func polishWithAI() {
        guard let polish else { return }
        aiBusy = true
        Task {
            if let polished = await polish(dish) { dish = polished }
            aiBusy = false
        }
    }

    /// Define every "new" ingredient with one AI call each (category/storage/shelf life),
    /// register them as smart catalog items, and re-point the lines.
    private func smartFillUnknowns() {
        aiBusy = true
        Task {
            for line in unknownLines {
                guard let def = await autofill(line.name),
                      let id = SmartIngredient.register(name: line.name, definition: def),
                      let i = dish.ingredients.firstIndex(where: { $0.id == line.id }) else { continue }
                let old = dish.ingredients[i]
                dish.ingredients[i] = RecipeLine(id: old.id, key: old.key, amount: old.amount,
                                                 name: old.name, isStaple: old.isStaple,
                                                 essential: old.essential, catalogItemID: id)
            }
            aiBusy = false
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
            // Don't interrupt typing — stage it as a working freeform line. The
            // "new to your kitchen" banner then offers Smart-fill (AI) or Define (the
            // form), and tapping the line opens the form directly.
            let name = intake.suggestedName ?? intake.name
            applyResolved(name: name, key: IngredientLexicon.lookupKey(intake.name),
                          catalogItemID: nil, lineID: lineID)
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
                        HStack(spacing: 8) {
                            phaseChip($step)
                            timerChip($step)
                        }
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
                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.creamRaised))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.Palette.hairline))
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

    /// Set or clear a step's timer from a menu of common durations — so a hand-typed
    /// recipe can carry real countdowns into the cook instrument, not just prose.
    private func timerChip(_ step: Binding<CookStep>) -> some View {
        let seconds = step.wrappedValue.timerSeconds
        let tinted = seconds != nil
        return Menu {
            Button("No timer") { setTimer(step, nil) }
            ForEach([1, 2, 3, 5, 10, 15, 20, 25, 30, 45, 60], id: \.self) { m in
                Button("\(m) min") { setTimer(step, m * 60) }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer").font(.system(size: 10))
                Text(seconds.map(timerLabel) ?? "TIMER")
                    .font(.system(size: 9, weight: .medium)).tracking(1.0)
            }
            .foregroundStyle(tinted ? Theme.Palette.paprika : Theme.Palette.warmGraySoft)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder((tinted ? Theme.Palette.paprika : Theme.Palette.warmGraySoft).opacity(0.5), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Rewrite the step with a new timer, keeping a hand-tagged phase/attention but
    /// letting an untouched step re-infer its attention from the new timer.
    private func setTimer(_ step: Binding<CookStep>, _ seconds: Int?) {
        let s = step.wrappedValue
        if phaseTagged.contains(s.id) {
            step.wrappedValue = CookStep(id: s.id, s.instruction, timerSeconds: seconds,
                                         phase: s.phase, attention: s.attention, ingredient: s.ingredient)
        } else {
            step.wrappedValue = CookStep(id: s.id, s.instruction, timerSeconds: seconds, ingredient: s.ingredient)
        }
    }

    private func timerLabel(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) MIN" : String(format: "%d:%02d", seconds / 60, seconds % 60)
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
                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.creamRaised))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.Palette.hairline))
        }
    }
}
