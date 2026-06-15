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
    /// Certainty for an on-hand ingredient, so the spread can hedge ("check?")
    /// instead of asserting a confident ✓ on a stale item (spec §7).
    var certaintyForKey: (String) -> ItemCertainty? = { _ in nil }
    var onToggleFavorite: () -> Void = {}
    var onUpdateDish: (Dish) -> Void = { _ in }
    /// Receives the missing ingredient lines so the list can keep their amounts.
    var onAddMissingToList: ([RecipeLine]) -> Void = { _ in }
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
         certaintyForKey: @escaping (String) -> ItemCertainty? = { _ in nil },
         onToggleFavorite: @escaping () -> Void = {},
         onUpdateDish: @escaping (Dish) -> Void = { _ in },
         onAddMissingToList: @escaping ([RecipeLine]) -> Void = { _ in },
         makeHealthier: ((Dish) async -> HealthierSuggestion?)? = nil,
         tweak: ((Dish, String) async -> Dish?)? = nil,
         onCook: @escaping (Dish) -> Void,
         onClose: @escaping () -> Void) {
        self.dish = dish
        self.readiness = readiness
        self.isOnHand = isOnHand
        self.certaintyForKey = certaintyForKey
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

    private var missingLines: [RecipeLine] {
        effectiveDish.ingredients
            .filter { !isOnHand($0.key) && !$0.isStaple && appliedSwaps[$0.id] == nil }
    }
    private var missingNames: [String] { missingLines.map(\.name) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                actionRow
                ingredients
                if !effectiveDish.steps.isEmpty { method }
            }
            .padding(20).padding(.bottom, 24)
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
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: kicker, tone: .urgent)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(currentDish.name).font(Theme.Typography.dish(27)).foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let blurb = currentDish.blurb {
                        Text(blurb).font(Theme.Typography.note(13)).foregroundStyle(Theme.Palette.warmGray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                PlateView(name: currentDish.name, composition: currentDish.plate, size: 84)
            }
            .padding(.top, 6)
            factsBand.padding(.top, 14)
        }
        .padding(.top, 14)
    }

    /// "WEEKNIGHT · DAIRY" — pace plus what it contains.
    private var kicker: String {
        let pace = (currentDish.minutes ?? 999) <= 30 ? "WEEKNIGHT" : "A PROJECT"
        let contains = DishInsights.allergens(for: currentDish).prefix(2).map { $0.title.uppercased() }
        return ([pace] + contains).joined(separator: " · ")
    }

    /// The fact line between solid rules: time · serves −/+ · readiness.
    private var factsBand: some View {
        VStack(spacing: 0) {
            SolidRule()
            HStack {
                bandText(currentDish.time.uppercased())
                Spacer()
                HStack(spacing: 10) {
                    bandStepper("−") { if servings > 1 { servings -= 1 } }
                    bandText("SERVES \(servings)")
                    bandStepper("＋") { if servings < 24 { servings += 1 } }
                }
                Spacer()
                readinessLabel
            }
            .padding(.vertical, 8)
            SolidRule()
        }
    }

    private func bandText(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).tracking(1.6)
            .foregroundStyle(Theme.Palette.ink.opacity(0.75))
    }

    private func bandStepper(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Palette.paprika)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    /// Bordered icon chips — real, legible, ≥44pt targets (was a row of 9.5pt
    /// tracked-caps text-buttons, the worst tap cluster per the UI research).
    private var actionRow: some View {
        HStack(spacing: 9) {
            actionChip(currentDish.isFavorite ? "heart.fill" : "heart",
                       currentDish.isFavorite ? "Saved" : "Save",
                       tint: currentDish.isFavorite ? Theme.Palette.paprika : Theme.Palette.ink) {
                currentDish.isFavorite.toggle()
                onToggleFavorite()
            }
            actionChip("pencil", "Edit", tint: Theme.Palette.ink) { showEditor = true }
            actionChip("leaf", "Healthier", tint: Theme.Palette.sage) { runHealthier() }
            actionChip("wand.and.stars", "Tweak", tint: Theme.Palette.ink) { showTweakPrompt = true }
        }
        .overlay(alignment: .center) { if aiBusy { ProgressView().controlSize(.small) } }
    }

    private func actionChip(_ icon: String, _ title: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 16))
                Text(title).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity).frame(height: 52)
            .overlay(Rectangle().strokeBorder(Theme.Palette.ink.opacity(0.28), lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(aiBusy ? 0.4 : 1)
        }
        .buttonStyle(.pressable)
        .disabled(aiBusy)
    }

    @ViewBuilder private var readinessLabel: some View {
        switch readiness {
        case .ready:
            Text("READY").font(.system(size: 10)).tracking(1.6).foregroundStyle(Theme.Palette.sage)
        case .readyWithSwaps:
            Text("SWAP-READY").font(.system(size: 10)).tracking(1.6).foregroundStyle(Theme.Palette.sage)
        case .needs(let items):
            Text("NEEDS \(items.count)").font(.system(size: 10)).tracking(1.6).foregroundStyle(Theme.Palette.paprika)
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

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionTitle("Ingredients")
                Spacer()
                if !missingNames.isEmpty {
                    Button {
                        onAddMissingToList(missingLines)
                    } label: {
                        Label("list the \(missingNames.count) missing", systemImage: "cart.badge.plus")
                            .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.paprika)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(effectiveDish.ingredients) { line in
                ingredientRow(line)
                if line.id != effectiveDish.ingredients.last?.id { DashedRule(opacity: 0.45) }
            }
        }
    }

    private func ingredientRow(_ line: RecipeLine) -> some View {
        let applied = appliedSwaps[line.id]
        let onHand = applied != nil || isOnHand(line.key) || line.isStaple
        let swaps = onHand ? [] : DishInsights.swaps(forKey: line.key)
        // On hand, but the knowledge clock has gone stale — don't assert a
        // confident check; ask the cook to verify (spec §7).
        let uncertain = onHand && applied == nil && !line.isStaple
            && (certaintyForKey(line.key) ?? .confirmed) <= .uncertain
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(onHand ? (uncertain ? "?" : "✓") : "○")
                    .font(Theme.Typography.fact(13, weight: .medium))
                    .foregroundStyle(uncertain ? Theme.Palette.paprika
                                     : onHand ? Theme.Palette.sage : Theme.Palette.paprika)
                    .frame(width: 16)
                Text(line.display).font(Theme.Typography.fact(13.5)).foregroundStyle(Theme.Palette.ink)
                if let grams = UnitConversion.gramHint(for: line) {
                    Text("≈\(grams)").font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
                }
                Spacer()
                if !onHand && !line.isStaple {
                    Text("NEED").font(.system(size: 9)).tracking(1.6).foregroundStyle(Theme.Palette.paprika)
                } else if uncertain {
                    Text("CHECK?").font(.system(size: 9)).tracking(1.6).foregroundStyle(Theme.Palette.paprika)
                }
            }
            if let applied {
                Button {
                    withAnimation { appliedSwaps[line.id] = nil }
                } label: {
                    Text("↻ using \(applied.name) — tap to undo")
                        .font(Theme.Typography.fact(10.5)).foregroundStyle(Theme.Palette.sage).padding(.leading, 26)
                }
                .buttonStyle(.plain)
            } else if let swap = swaps.first {
                Button {
                    withAnimation { appliedSwaps[line.id] = SwapChoice(key: swap.key, name: swap.name) }
                } label: {
                    Text("↻ swap: \(swap.name)\(swap.notes.map { " — \($0)" } ?? "")")
                        .font(Theme.Typography.fact(10.5)).foregroundStyle(Theme.Palette.sage)
                        .multilineTextAlignment(.leading).padding(.leading, 26)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 9)
    }

    private var method: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("Method")
            ForEach(Array(effectiveDish.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text("\(index + 1)")
                        .font(Theme.Typography.dish(15, weight: .semibold))
                        .foregroundStyle(Theme.Palette.paprika)
                        .frame(width: 14, alignment: .trailing)
                    (Text(step.instruction)
                        + Text(step.timerSeconds.map { "  — \($0 / 60)'" } ?? "")
                            .foregroundColor(Theme.Palette.ink.opacity(0.45)))
                        .font(Theme.Typography.fact(13.5)).foregroundStyle(Theme.Palette.ink)
                        .lineSpacing(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ text: String) -> some View {
        Eyebrow(text: text).padding(.bottom, 4)
    }

    private var cookBar: some View {
        VStack(spacing: 0) {
            SolidRule()
            BlockButton(title: "Cook", fullWidth: true) { onCook(effectiveDish) }
                .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Theme.Palette.cream)
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
