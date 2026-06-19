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
    var isOnHand: (RecipeLine) -> Bool = { _ in true }
    /// Certainty for an on-hand ingredient, so the spread can hedge ("check?")
    /// instead of asserting a confident ✓ on a stale item (spec §7).
    var certaintyForKey: (String) -> ItemCertainty? = { _ in nil }
    /// "Still here" in the readiness moment — resets the knowledge clock for the
    /// stock item behind this ingredient key, so a hedge becomes a confident ✓.
    var onReconfirm: (String) -> Void = { _ in }
    var onToggleFavorite: () -> Void = {}
    var onUpdateDish: (Dish) -> Void = { _ in }
    /// Save the tweaked/edited recipe as a brand-new dish (leaving this one intact).
    var onSaveAsNew: (Dish) -> Void = { _ in }
    /// Receives the missing ingredient lines so the list can keep their amounts.
    var onAddMissingToList: ([RecipeLine]) -> Void = { _ in }
    /// Explicit AI actions; nil result = unavailable or failed (handled softly).
    var makeHealthier: ((Dish) async -> HealthierSuggestion?)?
    var tweak: ((Dish, String) async -> Dish?)?
    /// AI fill for the custom-ingredient form reached from the editor.
    var autofill: (String) async -> AIIngredientDefinition? = { _ in nil }
    /// Receives the dish to cook — scaling and applied swaps baked in.
    var onCook: (Dish) -> Void
    /// "I made this" without walking the cook steps — banks the (scaled) servings as
    /// leftovers and journals it, same as finishing the instrument.
    var onLogCooked: (Dish) -> Void = { _ in }
    /// Your take on this recipe — a 1–5 rating, a free note, and how often/when you've
    /// cooked it. Persisted per recipe (survives a reseed) by the store.
    var rating: Int? = nil
    var onRate: (Int?) -> Void = { _ in }
    var savedNote: String? = nil
    var onSaveNote: (String) -> Void = { _ in }
    var timesCooked: Int = 0
    var lastCooked: Date? = nil
    var onClose: () -> Void

    @State private var currentDish: Dish
    @State private var noteDraft: String = ""
    @State private var servings: Int
    @State private var appliedSwaps: [UUID: SwapChoice] = [:]
    @State private var showEditor = false
    @State private var healthierResult: HealthierSuggestion?
    @State private var showTweakPrompt = false
    @State private var aiBusy = false
    @State private var aiNote: String?
    @State private var listedConfirm = false
    /// The last committed version; "discard" reverts to it. Pending = there's an
    /// unsaved tweak/edit awaiting discard / save / save-as-new.
    @State private var baseline: Dish
    @State private var pendingChanges = false

    struct SwapChoice: Equatable { let key: String; let name: String; let catalogItemID: String?; let note: String? }

    init(dish: Dish, readiness: Readiness,
         isOnHand: @escaping (RecipeLine) -> Bool = { _ in true },
         certaintyForKey: @escaping (String) -> ItemCertainty? = { _ in nil },
         onReconfirm: @escaping (String) -> Void = { _ in },
         onToggleFavorite: @escaping () -> Void = {},
         onUpdateDish: @escaping (Dish) -> Void = { _ in },
         onSaveAsNew: @escaping (Dish) -> Void = { _ in },
         onAddMissingToList: @escaping ([RecipeLine]) -> Void = { _ in },
         makeHealthier: ((Dish) async -> HealthierSuggestion?)? = nil,
         tweak: ((Dish, String) async -> Dish?)? = nil,
         autofill: @escaping (String) async -> AIIngredientDefinition? = { _ in nil },
         onCook: @escaping (Dish) -> Void,
         onLogCooked: @escaping (Dish) -> Void = { _ in },
         rating: Int? = nil,
         onRate: @escaping (Int?) -> Void = { _ in },
         savedNote: String? = nil,
         onSaveNote: @escaping (String) -> Void = { _ in },
         timesCooked: Int = 0,
         lastCooked: Date? = nil,
         onClose: @escaping () -> Void) {
        self.dish = dish
        self.readiness = readiness
        self.isOnHand = isOnHand
        self.certaintyForKey = certaintyForKey
        self.onReconfirm = onReconfirm
        self.onToggleFavorite = onToggleFavorite
        self.onUpdateDish = onUpdateDish
        self.onSaveAsNew = onSaveAsNew
        self.onAddMissingToList = onAddMissingToList
        self.makeHealthier = makeHealthier
        self.tweak = tweak
        self.autofill = autofill
        self.onCook = onCook
        self.onLogCooked = onLogCooked
        self.rating = rating
        self.onRate = onRate
        self.savedNote = savedNote
        self.onSaveNote = onSaveNote
        self.timesCooked = timesCooked
        self.lastCooked = lastCooked
        self.onClose = onClose
        _currentDish = State(initialValue: dish)
        _baseline = State(initialValue: dish)
        _servings = State(initialValue: dish.servings)
        _noteDraft = State(initialValue: savedNote ?? "")
    }

    /// The dish as it will actually be cooked: scaled, then swaps applied.
    private var effectiveDish: Dish {
        appliedSwaps.reduce(currentDish.scaled(to: servings)) { partial, entry in
            partial.applyingSwap(to: entry.key, key: entry.value.key, name: entry.value.name,
                                 catalogItemID: entry.value.catalogItemID, note: entry.value.note)
        }
    }

    private var missingLines: [RecipeLine] {
        effectiveDish.ingredients
            .filter { !isOnHand($0) && !$0.isStaple && $0.essential && appliedSwaps[$0.id] == nil }
    }
    private var missingNames: [String] { missingLines.map(\.name) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                actionRow
                ingredients
                if !effectiveDish.steps.isEmpty { method }
                yourTake
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
        .safeAreaInset(edge: .bottom) { pendingChanges ? AnyView(pendingBar) : AnyView(cookBar) }
        .sheet(isPresented: $showEditor) {
            RecipeEditorView(dish: currentDish, autofill: autofill) { edited in
                currentDish = edited
                servings = edited.servings
                showEditor = false
                withAnimation { pendingChanges = true }   // editing stages a change, doesn't commit
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
            if let line = cookHistoryLine {
                Text(line).font(Theme.Typography.fact(11.5)).foregroundStyle(Theme.Palette.sage)
                    .padding(.top, 8)
            }
            factsBand.padding(.top, 14)
        }
        .padding(.top, 14)
    }

    /// "Cooked 3 times · last made Tuesday" — your own history with this dish, drawn
    /// from the journal. Hidden until you've made it at least once.
    private var cookHistoryLine: String? {
        guard timesCooked > 0 else { return nil }
        let count = timesCooked == 1 ? "Cooked once" : "Cooked \(timesCooked) times"
        guard let last = lastCooked else { return count }
        let f = DateFormatter(); f.doesRelativeDateFormatting = true
        f.dateStyle = .medium; f.timeStyle = .none
        return "\(count) · last made \(f.string(from: last))"
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
                bandText(currentDish.timeText.uppercased())
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
                       currentDish.isFavorite ? "Favorited" : "Favorite",
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

    /// "Wants": everything you'd shop for to cook it *exactly as written* — essential
    /// and optional alike, ignoring substitutes (staples you keep on hand don't count).
    /// Mirrors `ReadinessService.wants` over this page's own on-hand check.
    private var wantsCount: Int {
        currentDish.ingredients.filter { !isOnHand($0) && !$0.isStaple }.count
    }

    @ViewBuilder private var readinessLabel: some View {
        switch readiness {
        case .ready:
            band(wantsCount > 0 ? "READY · WANTS \(wantsCount)" : "READY", Theme.Palette.sage)
        case .readyWithSwaps(let swaps):
            band("READY · \(SwapPhrase.count(swaps.count).uppercased())", Theme.Palette.sage)
        case .needs(let items):
            // Needs blocks it; Wants rides alongside when it adds beyond the blockers.
            band(ShopPhrase.stamp(needs: items.count, wants: max(wantsCount, items.count)) ?? "NEEDS \(items.count)",
                 Theme.Palette.paprika)
        }
    }

    private func band(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 10)).tracking(1.6).foregroundStyle(color)
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
                withAnimation { pendingChanges = true }   // a tweak is a proposal, not a commit
            } else {
                aiNote = "Couldn't tweak it — add an OpenAI key in Config.plist, or try again."
            }
        }
    }

    // MARK: - Sections

    /// On-hand essentials the knowledge clock has gone quiet on — the dish *reads*
    /// ready but leans on these, so the readiness moment hedges instead of asserting.
    private var uncertainLines: [RecipeLine] {
        effectiveDish.ingredients.filter { line in
            line.essential && !line.isStaple && appliedSwaps[line.id] == nil
                && isOnHand(line) && (certaintyForKey(line.key) ?? .confirmed) <= .uncertain
        }
    }

    /// A hedge in the readiness moment: when "ready" rests on items we haven't seen
    /// lately, say so and let the cook confirm them right here in one tap each — a
    /// confident ✓ replaces the "?" without leaving the recipe.
    @ViewBuilder private var confidenceHedge: some View {
        let lines = uncertainLines
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(lines.count == 1
                     ? "Leans on something you haven’t seen lately."
                     : "Leans on \(lines.count) things you haven’t seen lately.")
                    .font(Theme.Typography.note(13)).foregroundStyle(Theme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines) { line in
                        Button { withAnimation { onReconfirm(line.key) } } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                Text("\(line.name) — still here")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(Theme.Palette.sage)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .overlay(Rectangle().strokeBorder(Theme.Palette.sage.opacity(0.55), lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Rectangle().fill(Theme.Palette.paprika.opacity(0.06)))
            .overlay(Rectangle().strokeBorder(Theme.Palette.paprika.opacity(0.25), lineWidth: 1))
        }
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 0) {
            confidenceHedge.padding(.bottom, 14)
            HStack {
                sectionTitle("Ingredients")
                Spacer()
                if !missingNames.isEmpty {
                    Button {
                        onAddMissingToList(missingLines)
                        withAnimation { listedConfirm = true }
                        Task { try? await Task.sleep(for: .seconds(2.5)); withAnimation { listedConfirm = false } }
                    } label: {
                        Label(listedConfirm ? "added to your list"
                                            : "list the \(missingNames.count) missing",
                              systemImage: listedConfirm ? "checkmark.circle.fill" : "cart.badge.plus")
                            .font(Theme.Typography.fact(11))
                            .foregroundStyle(listedConfirm ? Theme.Palette.sage : Theme.Palette.paprika)
                    }
                    .buttonStyle(.plain)
                    .disabled(listedConfirm)
                }
            }
            ForEach(effectiveDish.ingredients) { line in
                ingredientRow(line)
                if line.id != effectiveDish.ingredients.last?.id { DashedRule(opacity: 0.45) }
            }
        }
    }

    /// A catalog substitute paired with whether you actually have it on hand, so the
    /// list can lead with the swaps that work tonight.
    private struct RankedSwap: Identifiable {
        let suggestion: DishInsights.SwapSuggestion
        let onHand: Bool
        var id: String { suggestion.id }
    }

    /// Every recorded substitute for a missing line, the ones you have first —
    /// preserving the catalog's confidence order (curated → sibling → family) within
    /// each group.
    private func rankedSwaps(for line: RecipeLine) -> [RankedSwap] {
        let ranked = DishInsights.swaps(for: line).map { s in
            RankedSwap(suggestion: s,
                       onHand: isOnHand(RecipeLine(key: s.key, name: s.name, catalogItemID: s.catalogItemID)))
        }
        return ranked.filter(\.onHand) + ranked.filter { !$0.onHand }
    }

    private func ingredientRow(_ line: RecipeLine) -> some View {
        let applied = appliedSwaps[line.id]
        let onHand = applied != nil || isOnHand(line) || line.isStaple
        // On hand, but the knowledge clock has gone stale — don't assert a
        // confident check; ask the cook to verify (spec §7).
        let uncertain = onHand && applied == nil && !line.isStaple
            && (certaintyForKey(line.key) ?? .confirmed) <= .uncertain
        // Optional (non-load-bearing) lines — garnishes, "to taste" finishes — never
        // read as a blocker: dimmed, tagged OPTIONAL, and not pushed a swap.
        let optional = !line.essential
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(onHand ? (uncertain ? "?" : "✓") : "○")
                    .font(Theme.Typography.fact(13, weight: .medium))
                    .foregroundStyle(uncertain ? Theme.Palette.paprika
                                     : onHand ? Theme.Palette.sage
                                     : optional ? Theme.Palette.warmGraySoft : Theme.Palette.paprika)
                    .frame(width: 16)
                Text(line.display).font(Theme.Typography.fact(13.5))
                    .foregroundStyle(optional && !onHand ? Theme.Palette.warmGray : Theme.Palette.ink)
                if let grams = UnitConversion.gramHint(for: line) {
                    Text("≈\(grams)").font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGraySoft)
                }
                Spacer()
                if optional {
                    Text("OPTIONAL").font(.system(size: 9)).tracking(1.6).foregroundStyle(Theme.Palette.warmGraySoft)
                } else if !onHand && !line.isStaple {
                    Text("NEED").font(.system(size: 9)).tracking(1.6).foregroundStyle(Theme.Palette.paprika)
                } else if uncertain {
                    // Tap to reconfirm right here — the "?" becomes a confident ✓.
                    Button { withAnimation { onReconfirm(line.key) } } label: {
                        Text("STILL HERE?").font(.system(size: 9, weight: .medium)).tracking(1.6)
                            .foregroundStyle(Theme.Palette.paprika)
                            .padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let applied {
                Button { withAnimation { appliedSwaps[line.id] = nil } } label: {
                    Text("↻ using \(applied.name)\(applied.note.map { " — \($0)" } ?? "") · tap to undo")
                        .font(Theme.Typography.fact(10.5)).foregroundStyle(Theme.Palette.sage).padding(.leading, 26)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
            } else if !onHand && !line.isStaple && !optional {
                // Only surface substitutes you actually have on hand — listing every
                // possible swap for every missing line buries the page. If nothing on
                // hand subs in, the line just reads NEED (no swap clutter). Optional
                // garnishes don't nag for a swap either — they're droppable.
                let onHandSwaps = rankedSwaps(for: line).filter(\.onHand)
                if !onHandSwaps.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(onHandSwaps.prefix(3)) { entry in swapCandidate(line: line, entry: entry) }
                    }
                    .padding(.leading, 26)
                }
            }
        }
        .padding(.vertical, 9)
    }

    private func swapCandidate(line: RecipeLine, entry: RankedSwap) -> some View {
        let s = entry.suggestion
        return Button {
            withAnimation { appliedSwaps[line.id] = SwapChoice(key: s.key, name: s.name, catalogItemID: s.catalogItemID, note: s.notes) }
        } label: {
            HStack(spacing: 6) {
                // Just the substitute name to choose from; its note/guidance appears
                // once accepted (the "using …" line), not on every option.
                Text("↻ \(s.name)")
                    .font(Theme.Typography.fact(10.5))
                    .foregroundStyle(entry.onHand ? Theme.Palette.sage : Theme.Palette.warmGray)
                    .multilineTextAlignment(.leading)
                if entry.onHand {
                    Text("· HAVE").font(.system(size: 8.5, weight: .medium)).tracking(1)
                        .foregroundStyle(Theme.Palette.sage)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var method: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("Method")
            ForEach(Array(effectiveDish.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text("\(index + 1)")
                        .font(Theme.Typography.dish(15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.paprika)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: 24, alignment: .trailing)
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

    // MARK: - Your take (rating + notes)

    private var yourTake: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Your take")
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        // Tapping the current rating clears it; otherwise set it.
                        withAnimation(.snappy) { onRate(rating == star ? nil : star) }
                    } label: {
                        Image(systemName: (rating ?? 0) >= star ? "star.fill" : "star")
                            .font(.system(size: 20))
                            .foregroundStyle((rating ?? 0) >= star ? Theme.Palette.sage : Theme.Palette.warmGraySoft)
                            .frame(width: 34, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                }
                if rating != nil {
                    Spacer()
                    Button("Clear") { withAnimation { onRate(nil) } }
                        .font(Theme.Typography.fact(11)).foregroundStyle(Theme.Palette.warmGray)
                        .buttonStyle(.plain)
                }
            }
            // A free note — saved on commit (return) or when the field loses focus.
            TextField("Notes — tweaks, what to serve it with…", text: $noteDraft, axis: .vertical)
                .font(Theme.Typography.fact(13.5)).foregroundStyle(Theme.Palette.ink)
                .lineLimit(1...5)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.creamRaised))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.Palette.hairline))
                .onSubmit { onSaveNote(noteDraft) }
                .submitLabel(.done)
            if noteDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (savedNote ?? "") {
                Button("Save note") { onSaveNote(noteDraft) }
                    .font(Theme.Typography.fact(12, weight: .medium)).foregroundStyle(Theme.Palette.paprika)
                    .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cookBar: some View {
        VStack(spacing: 0) {
            SolidRule()
            HStack(spacing: 12) {
                // "I made this" without the step-by-step — bordered companion (clearly a
                // button) next to the filled primary Cook.
                OutlineButton(title: "Cooked it") { onLogCooked(effectiveDish) }
                BlockButton(title: "Cook", fullWidth: true) { onCook(effectiveDish) }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Theme.Palette.cream)
    }

    /// Shown while a tweak/edit is unsaved: keep the change on this recipe, fork it
    /// into a new one, or throw it away.
    private var pendingBar: some View {
        VStack(spacing: 6) {
            SolidRule()
            Text("UNSAVED CHANGES").font(.system(size: 9, weight: .medium)).tracking(1.8)
                .foregroundStyle(Theme.Palette.paprika)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.top, 8)
            HStack(spacing: 10) {
                Button { discardChanges() } label: {
                    Text("DISCARD").font(.system(size: 11, weight: .medium)).tracking(1.6)
                        .foregroundStyle(Theme.Palette.warmGray)
                        .padding(.vertical, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                OutlineButton(title: "Save as new") { saveAsNew() }
                BlockButton(title: "Save") { saveChanges() }
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .background(Theme.Palette.cream)
    }

    private func discardChanges() {
        withAnimation {
            currentDish = baseline
            servings = baseline.servings
            appliedSwaps = [:]
            pendingChanges = false
        }
    }

    private func saveChanges() {
        onUpdateDish(currentDish)
        baseline = currentDish
        withAnimation { pendingChanges = false }
    }

    private func saveAsNew() {
        onSaveAsNew(currentDish.copyAsNew())
        // Leave this recipe as it was before the edit.
        discardChanges()
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
                        .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.creamRaised))
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
                .background(RoundedRectangle(cornerRadius: 3).fill(Theme.Palette.creamRaised))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.Palette.hairline))
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
