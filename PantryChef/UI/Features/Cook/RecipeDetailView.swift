import SwiftUI

/// The recipe itself (spec §6) — what you see when you tap a dish anywhere. Shows
/// the plate, readiness, allergens, ingredients (with on-hand status, gram hints,
/// and tappable substitutions), the method, a servings scaler, and the action row:
/// favorite, edit, and the explicit AI actions (make healthier / tweak — invoked
/// only on demand, so they cost nothing until tapped). "Cook" leads into mise en
/// place with scaling and swaps baked in.
struct RecipeDetailView: View {
    let dish: Dish
    let readiness: Readiness
    var isOnHand: (String) -> Bool = { _ in true }
    var onToggleFavorite: () -> Void = {}
    var onUpdateDish: (Dish) -> Void = { _ in }
    var onAddMissingToList: ([String]) -> Void = { _ in }
    /// Explicit AI actions; nil result = unavailable or failed (handled softly).
    var makeHealthier: ((Dish) async -> HealthierSuggestion?)?
    var tweak: ((Dish, String) async -> Dish?)?
    /// Receives the dish to cook — scaling and applied swaps baked in.
    var onCook: (Dish) -> Void
    var onClose: () -> Void

    @State private var currentDish: Dish
    @State private var servings: Int
    @State private var appliedSwaps: [UUID: SwapChoice] = [:]
    @State private var showEditor = false
    @State private var healthierResult: HealthierSuggestion?
    @State private var showTweakPrompt = false
    @State private var aiBusy = false
    @State private var aiNote: String?

    struct SwapChoice: Equatable { let key: String; let name: String }

    init(dish: Dish, readiness: Readiness,
         isOnHand: @escaping (String) -> Bool = { _ in true },
         onToggleFavorite: @escaping () -> Void = {},
         onUpdateDish: @escaping (Dish) -> Void = { _ in },
         onAddMissingToList: @escaping ([String]) -> Void = { _ in },
         makeHealthier: ((Dish) async -> HealthierSuggestion?)? = nil,
         tweak: ((Dish, String) async -> Dish?)? = nil,
         onCook: @escaping (Dish) -> Void,
         onClose: @escaping () -> Void) {
        self.dish = dish
        self.readiness = readiness
        self.isOnHand = isOnHand
        self.onToggleFavorite = onToggleFavorite
        self.onUpdateDish = onUpdateDish
        self.onAddMissingToList = onAddMissingToList
        self.makeHealthier = makeHealthier
        self.tweak = tweak
        self.onCook = onCook
        self.onClose = onClose
        _currentDish = State(initialValue: dish)
        _servings = State(initialValue: dish.servings)
    }

    /// The dish as it will actually be cooked: scaled, then swaps applied.
    private var effectiveDish: Dish {
        appliedSwaps.reduce(currentDish.scaled(to: servings)) { partial, entry in
            partial.applyingSwap(to: entry.key, key: entry.value.key, name: entry.value.name)
        }
    }

    private var missingNames: [String] {
        effectiveDish.ingredients
            .filter { !isOnHand($0.key) && !$0.isStaple && appliedSwaps[$0.id] == nil }
            .map(\.name)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                actionRow
                if !DishInsights.allergens(for: currentDish).isEmpty { allergenChips }
                ingredients
                if !effectiveDish.steps.isEmpty { method }
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
        .sheet(isPresented: $showEditor) {
            RecipeEditorView(dish: currentDish) { edited in
                currentDish = edited
                servings = edited.servings
                onUpdateDish(edited)
                showEditor = false
            }
        }
        .sheet(item: $healthierResult) { suggestion in
            HealthierSheet(suggestion: suggestion)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTweakPrompt) {
            TweakSheet(busy: aiBusy) { feedback in
                runTweak(feedback)
            }
            .presentationDetents([.medium])
        }
        .alert("The chef is off duty", isPresented: Binding(
            get: { aiNote != nil }, set: { if !$0 { aiNote = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(aiNote ?? "")
        }
    }

    // MARK: - Hero & actions

    private var hero: some View {
        VStack(spacing: 12) {
            PlateView(name: currentDish.name, composition: currentDish.plate, size: 150)
            Text(currentDish.name).font(Theme.Typography.dish(30)).foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Text(currentDish.time).font(Theme.Typography.fact(13)).foregroundStyle(Theme.Palette.warmGray)
                Text("·").foregroundStyle(Theme.Palette.warmGraySoft)
                readinessLabel
            }
            servingsStepper
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private var servingsStepper: some View {
        HStack(spacing: 14) {
            stepperButton("minus") { if servings > 1 { servings -= 1 } }
            Text("serves \(servings)").font(Theme.Typography.numeral(13))
                .foregroundStyle(servings == currentDish.servings ? Theme.Palette.warmGray : Theme.Palette.paprika)
            stepperButton("plus") { if servings < 24 { servings += 1 } }
        }
        .padding(.top, 2)
    }

    private func stepperButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.Palette.creamRaised))
                .overlay(Circle().strokeBorder(Theme.Palette.hairline))
        }
        .buttonStyle(.plain)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            actionChip(currentDish.isFavorite ? "heart.fill" : "heart",
                       currentDish.isFavorite ? "Saved" : "Save",
                       tint: currentDish.isFavorite ? Theme.Palette.paprika : Theme.Palette.warmGray) {
                currentDish.isFavorite.toggle()
                onToggleFavorite()
            }
            actionChip("pencil", "Edit", tint: Theme.Palette.warmGray) { showEditor = true }
            actionChip("leaf", "Healthier", tint: Theme.Palette.sage) { runHealthier() }
            actionChip("wand.and.stars", "Tweak", tint: Theme.Palette.warmGray) { showTweakPrompt = true }
            if aiBusy { ProgressView().controlSize(.small) }
        }
        .frame(maxWidth: .infinity)
    }

    private func actionChip(_ icon: String, _ title: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16))
                Text(title).font(Theme.Typography.fact(11))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Palette.creamRaised))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Palette.hairline))
        }
        .buttonStyle(.plain)
        .disabled(aiBusy)
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

    // MARK: - AI actions (explicit, on-demand)

    private func runHealthier() {
        guard let makeHealthier else { return }
        aiBusy = true
        Task {
            let result = await makeHealthier(effectiveDish)
            aiBusy = false
            if let result {
                healthierResult = result
            } else {
                aiNote = "Couldn't get suggestions — add an OpenAI key in Config.plist, or try again."
            }
        }
    }

    private func runTweak(_ feedback: String) {
        guard let tweak else { showTweakPrompt = false; return }
        aiBusy = true
        Task {
            let result = await tweak(effectiveDish, feedback)
            aiBusy = false
            showTweakPrompt = false
            if let result {
                currentDish = result
                servings = result.servings
                appliedSwaps = [:]
                onUpdateDish(result)
            } else {
                aiNote = "Couldn't tweak it — add an OpenAI key in Config.plist, or try again."
            }
        }
    }

    // MARK: - Sections

    private var allergenChips: some View {
        FlowRow(DishInsights.allergens(for: currentDish).map(\.title)) { title in
            Text(title).font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGray)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Theme.Palette.creamRaised))
                .overlay(Capsule().strokeBorder(Theme.Palette.hairline))
        }
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionTitle("Ingredients")
                Spacer()
                if !missingNames.isEmpty {
                    Button {
                        onAddMissingToList(missingNames)
                    } label: {
                        Label("list the \(missingNames.count) missing", systemImage: "cart.badge.plus")
                            .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.paprika)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(effectiveDish.ingredients) { line in
                ingredientRow(line)
                if line.id != effectiveDish.ingredients.last?.id { Divider().background(Theme.Palette.hairline) }
            }
        }
        .padding(14).glassCard(cornerRadius: 22)
    }

    private func ingredientRow(_ line: RecipeLine) -> some View {
        let applied = appliedSwaps[line.id]
        let onHand = applied != nil || isOnHand(line.key) || line.isStaple
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
            if let applied {
                Button {
                    withAnimation { appliedSwaps[line.id] = nil }
                } label: {
                    Label("using \(applied.name) — tap to undo", systemImage: "arrow.uturn.backward")
                        .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage).padding(.leading, 25)
                }
                .buttonStyle(.plain)
            } else if let swap = swaps.first {
                Button {
                    withAnimation { appliedSwaps[line.id] = SwapChoice(key: swap.key, name: swap.name) }
                } label: {
                    Label("swap: \(swap.name)\(swap.notes.map { " — \($0)" } ?? "")", systemImage: "arrow.2.squarepath")
                        .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.sage)
                        .multilineTextAlignment(.leading).padding(.leading, 25)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 9)
    }

    private var method: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Method")
            ForEach(Array(effectiveDish.steps.enumerated()), id: \.element.id) { index, step in
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
        PaprikaButton(title: "Cook") { onCook(effectiveDish) }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .background(.ultraThinMaterial)
    }
}

// MARK: - AI sheets

/// The make-it-healthier result: tweaks with benefits, and the overall impact.
private struct HealthierSheet: View {
    let suggestion: HealthierSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10)
            Label("A lighter \(suggestion.originalRecipeTitle)", systemImage: "leaf")
                .font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)
            if let calories = suggestion.estimatedCalorieReduction {
                Text("≈ \(calories) fewer calories per serving")
                    .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.sage)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(suggestion.suggestions) { tweak in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tweak.change).font(Theme.Typography.fact(14)).foregroundStyle(Theme.Palette.ink)
                            Text(tweak.benefit).font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGray)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.Palette.creamRaised))
                    }
                    Text(suggestion.overallImpact).font(Theme.Typography.note(13))
                        .foregroundStyle(Theme.Palette.warmGray).padding(.top, 4)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KitchenBackground())
    }
}

/// Freeform "tweak it" prompt — make it spicier, swap the carbs, halve the dairy…
private struct TweakSheet: View {
    var busy: Bool
    var onGo: (String) -> Void
    @State private var feedback = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(Theme.Palette.hairline).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 10)
            Text("Tweak this recipe").font(Theme.Typography.dish(20)).foregroundStyle(Theme.Palette.ink)
            Text("Tell the chef what to change — \u{201C}make it spicier\u{201D}, \u{201C}no dairy\u{201D}, \u{201C}one pot\u{201D}…")
                .font(Theme.Typography.fact(12)).foregroundStyle(Theme.Palette.warmGraySoft)
            TextField("What should change?", text: $feedback, axis: .vertical)
                .font(Theme.Typography.fact(15)).lineLimit(3...5).focused($focused)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.Palette.creamRaised))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.Palette.hairline))
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                PaprikaButton(title: busy ? "Thinking…" : "Tweak it") {
                    guard !busy, !feedback.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onGo(feedback)
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KitchenBackground())
        .onAppear { focused = true }
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
