# PantryChef Redesign Spec — "The Kitchen Timeline"

Source of truth for the full app redesign (flow + visual language + voice), as converged
in design sessions, June 2026. Supersedes the current 4-tab IA. Positioning: a $20/month
product — every decision below must visibly earn that price.

## 1. Product thesis

The app owns the kitchen loop: stock in → options out → cook → consequences → restock.
What the user pays for is the **brain** (catalog, can-make math, expiry rescue, scheduling,
generation) — so the brain must be *visible in the structure of the UI*, not narrated in
notifications. The redesign's job is to make intelligence load-bearing.

## 2. Personas (all four must be served by the same machinery)

| Persona | Behavior | What they get |
|---|---|---|
| Planner | Plans meals days ahead | Long future on the timeline; commits early |
| Explorer | Decides at 6pm, browses options | The fan; never forced to commit until cooking |
| Pantry manager | Tracks stock, rarely cooks from recipes | Item-led now-module; freeze = equal verb; journal of restocks |
| Improviser | Tracks stock, cooks ad-hoc without recipes | Sparks (combination ideas), recipe-less cook logging, ghost recipes |

Anti-goal: never let recipe features read as an agenda being pushed at non-recipe users.

## 3. Information architecture

Three spaces + one instrument + one global action:

- **Timeline** (home) — when. Replaces Today + Plan + expiry warnings + scheduled shopping.
- **Library** — what's possible. Replaces Recipes/Discover. Browsing = the plate gallery.
- **Stock** — what's true. Replaces Pantry + Shopping + Prepared, unified as one inventory
  with three states: **have / need / made**. A shopping list is stock you don't have yet;
  leftovers are stock you made.
- **Cook** — the full-screen instrument (single + multi). Entered from the timeline; the
  plate is the transition object.
- **+** — one global composer (add stock, add to list, import/create recipe; smart-routed).

Navigation: floating glass dock, 3 tabs + the plus button. No more segmented controls
hiding surfaces two taps deep.

## 4. Timeline grammar

**Past = record. Now = choice. Future = consequence.** Plans are optional structure, not
the premise. The timeline is not a calendar.

Node vocabulary:
- **Solid glass card/row** — real: committed meal, completed cook, completed shop.
- **Dashed border** — invitation: AI proposal (meal, batch-cook, shopping stop). Expires
  quietly if ignored. Never nags.
- **Diamond marker (ochre)** — deadline: an expiry consequence ("The spinach turns Thursday").
- **Paprika node + glow** — now.
- **Dotted fold** — compressed quiet time ("The weekend — nothing needs you"). Empty time
  renders as peace, never as blank scroll.
- **Week marker** — quiet boundary node ("Week of June 15 — 2 planned") carrying the
  weekly rollup (meals; nutrition as a quiet line).
- **Fade** — the past desaturates gently into the journal.

### The spine is a ruler

Every day exists on the scale, not just event days:
- **Minor notch** per day, with a quiet label ("Wednesday 11"); **major tick** at each
  week boundary; paprika node = now; diamonds and event nodes sit on their day's notch.
- **Bare days are tap targets**: tapping a notch unfurls the day inline — its mini-fan
  with a reason, "Plan this" / "Out" — then collapses to a solid node on commit.
- **Folds render as compressed tick clusters** (several notches tightly spaced): quiet
  time literally condenses on the scale. Tapping spreads the cluster into its days.
- **The spine doubles as a scrubber**: drag along it to fast-travel the timeline, one
  faint haptic tick per day passed.

### Density rules (no whitespace deserts)

- Bare-day rows are compact (≈28 pt), tight to the spine — a short run reads as ruler
  rhythm, not emptiness.
- **Auto-fold**: any run of ≥2 *silent* days (no node, no whisper) compresses into a
  tick cluster. Stacked empty rows are structurally impossible.
- **Whispers**: a bare day may carry at most one muted, right-aligned fact, only when
  true ("ragù waiting · 3 portions", "yogurt's last good day", "flatbreads would use
  it"). A whispered day earns its line and does not fold.
- The now-section is always dense (the fan never renders empty) and the journal carries
  mass above — sparseness is bounded to short, intentional ruler runs.

### Planning (how the Plan tab's job gets done — on the timeline itself)

- **Tap any future day — including one inside a fold — and it expands to deal that
  day's fan inline** ("Thursday: you could…"), suggestions reasoned the usual way:
  leftovers first ("ragù from the freezer, 3 portions waiting"), rescues next ("uses
  the yogurt before it turns"). Commit → the day collapses to a solid node. "Out" is a
  first-class, guilt-free answer. Batch-planning a week is just doing this down the
  scroll.
- **Commit-ahead** from anywhere: recipe cards (Library, Explore, fan) offer "Plan it →
  tonight / tomorrow / pick a day". Missing ingredients route to the list
  *continuously* — the old "generate shopping list from week" button is replaced by
  never-stopping reconciliation.
- **Plan your own (assemblages)**: the day unfurl's third path beyond the fan and
  "Out" — pick items from stock chips or search the catalog, optional name ("girl
  dinner"), commit. Items not yet in stock route to the list on commit ("Plan it —
  olives join the list"). Verb: Eat. Plate composed procedurally from the chosen items.
- **Soft reservation**: committed meals — recipes and assemblages alike — reserve their
  ingredients. Conflicts surface as whispers with a fix attached: "the brie turns
  Thursday — it's in Friday's girl dinner; move that to Thursday?" / "the olives went
  into Tuesday's salad — re-plan Friday?"
- **Week marker**: quiet rollup node only ("Week of June 15 — 2 planned"); nutrition as
  a quiet line.
- **Plan-the-week sheet: deferred (v2, only if planner users ask).** The timeline path
  must stand alone.
- **Meal types**: dinner is the default slot; breakfast/lunch are optional tags on
  commit — no empty grid slots demanding to be filled.
- **Eaten-servings tracking** is absorbed by cook events + made-stock servings.

Rules:
- The future only shows consequences and invitations. Nothing is required.
- The journal is earned, never faked. No sample data, no demo plates, ever.
- Quiet stretches fold; the future is allowed to be short. Short ≠ broken.
- Cross-links are rendered, not notified: "needs 2 items → on Saturday's list",
  "Thursday — rescued by tonight's orzo". The connective tissue IS the intelligence.

## 5. The now-module (adaptive, behavior-keyed — no settings toggle)

State chosen by observed usage:

1. **Fan** (explorer/planner): "Tonight you could…" — 3–5 plates fanned, ranked but not
   dictated. Center plate carries the sommelier note; swiping re-centers and rewrites the
   reason. Reasons must be *defensibly different* (rescue pick / fastest / ambitious /
   uses-the-leftovers). Last card is a doorway → the Explore sheet. Committing collapses
   the fan onto the spine: **optionality before commitment; prescription only after.**
2. **Rescue** (pantry manager): item-led. "The spinach turns Thursday. 300 g left. Four
   dishes would use it up — or freeze it and buy two weeks." Freeze/use/discard are equal
   citizens; recipes appear only as solutions to inventory problems.
3. **Sparks** (improviser): combination-led, not recipe-led. "The spinach, feta and eggs
   want to be together — a 25-minute direction." Tap to expand into a full recipe *only if
   wanted*, or just "cooked it" to log. Inspiration without prescription.

### The now-module state machine

The lenses above apply only to the **Open** state. The module advances through four
states as the evening does, and the voice changes with it:

| State | Label | Supporting line | Actions |
|---|---|---|---|
| Open | "Tonight you could…" | the reason ("the rescue pick…") | Cook · see all / swap |
| Committed | "Tonight" | logistics: "Start by 6:50 to eat at 7:15." Prep nudges when real ("take the butter out around 6"). Morning variant: "Everything's on hand — nothing to do till evening." | Cook · Change (quiet) |
| Cooking | "On the stove" | "Step 3 of 7 · 02:00 on the timer" + live progress | Resume (tap glides back into the instrument) |
| Cooked | "Done tonight" | "Cooked at 7:20 — 2 servings into the fridge. Good for 3 days." Leftovers auto-become made stock. | Rate it (quiet) |

- "Could" language is banned outside the Open state — committed copy is logistics, never
  re-persuasion. Start-by times are computed from recipe time vs. usual dinner hour.
- Verbs follow the meal's preparation level (§8): Cook / Serve / Eat. The Cooking state
  only exists for instrument-backed meals; Served and Just-ate meals jump straight from
  Committed (or Open) to Done.
- Commitment is not a prison: "Change" reopens the fan in one tap.
- At midnight the Cooked card slides up into the journal and the module resets to Open
  (or Committed, if tomorrow is already planned).

## 6. Explore sheet ("From your pantry")

Opened from the fan (swipe past last plate, or tap "see all").
- Opening line states the promise flat: "**12 dishes ready right now.** 5 more are one stop away."
- Shelves are *reasons*, not categories: "Before the spinach turns", "Twenty minutes or
  less", "One stop away".
- "One stop away" rows render ghosted (dashed plate, reduced opacity) with "+ list" action —
  browsing doubles as shopping-list building.

### Readiness vocabulary (Library, Explore, fan — identical everywhere)

| State | Plate | Meta line | Color |
|---|---|---|---|
| Ready | solid | "25 min · ready" | sage |
| Ready with a swap | solid + small swap badge | "ready · burrata → mozzarella" | sage |
| Not yet | dashed, ~65% opacity | "needs 2 items" + "+ list" | warm gray / ochre action |

- Swap-readiness computed from SubstitutionRepository + the catalog `swaps` enrichment
  (its first consumer). Tap reveals the exact substitution before committing.
- Swaps never apply silently: committing confirms the swap, and the cook instrument
  shows the swapped ingredient line explicitly.
- Filter chip wording: "Ready · 12 · +3 with swaps". The fan may deal a "swap pick"
  as one of its reasons.

## 7. Trust layer (designed for unfaithful trackers — the default user)

Axiom: **absence is acceptable, questions are cheap, false claims are fatal.**

- **Certainty decay**: every stock item has two clocks — food freshness and knowledge
  freshness. Catalog shelf-life doubles as the information half-life prior (flour decays
  slowly in certainty; spinach fast). Internal states: have / probably have / unknown /
  probably gone. Never shown as words; shown as consequences.
- **Voice keyed to confidence**: "All 6 on hand" only at high certainty; else "Should be
  everything on hand — check the feta." Expiry milestones render only while certainty
  holds; they degrade to silence, never to false alarms.
- **Reconciliation by side effect** — never data entry as an activity:
  - Cooking in-app decrements ingredients.
  - Checking off the shopping list stocks the pantry.
  - Cook-mode ingredient gathering (already in codebase) = implicit confirmation;
    "don't have it" = correction.
  - Swap/dismiss reasons are signals.
- **Micro-questions, VOI-gated**: one-tap ("Still have spinach from June 2?") asked only
  when the answer would change a recommendation.
- **Zero-data floor**: the app learns the "usual kitchen" (staples rebought) from shopping
  and cooking patterns; with no live inventory the fan degrades to "ideas from what you
  usually keep" — modest wording, still useful. Tracking-free features (cook instrument,
  library, import, generation, journal) stand on their own.

### Resolution classes — track at decision resolution

False precision is a trust-killer like false claims. Each catalog entity carries a
tracking-semantics class (derived from its taxonomy):

| Class | Examples | Model | Decrement |
|---|---|---|---|
| Perishable | spinach, salmon, yogurt | quantity + expiry | per cook (real) |
| Staple | flour, oil, rice, spices | gauge: full/plenty/low/out | never per pinch |
| Semi-countable | eggs, butter, onions | honest units / gauge | per meaningful unit |

- **Meaningful-fraction rule**: staples decrement only when a single use consumes a real
  share of typical stock. Computed via density enrichment (`gramsPerCup`/`gramsPerPiece`):
  2 tsp flour ≈ 1% of a pound → no-op; 4 cups for bread → gauge drops a notch.
- **Gauge signals**: adding a staple to the shopping list = low/out; one-tap "running low"
  in cook-mode gathering or spoken mid-cook; rebuy-rhythm decay (bought every ~3 months,
  month 4 → "probably low"); rare VOI-gated check-ins.
- Can-make math assumes staples present unless flagged low/out (formalizes the existing
  presence-only quantity mode).
- Stock UI shows staples as a level indicator, never a fake gram count.

## 8. The meal event (cooked, served, or just eaten)

The primitive is **a meal**, not a cook. Four preparation levels, each first-class,
none judged:

| Level | What happens | CTA verb |
|---|---|---|
| Cooked | recipe → the instrument | Cook |
| Improvised | recipe-less log (below) | Cooked it |
| Served | made stock → servings decrement, no instrument | Serve |
| Just ate | direct consumption — an apple, a girl dinner | Eat / log it |

"Just ate" also has a *planned* form: the **assemblage** — a chosen set of items
committed to a day (§4 Planning, "plan your own"), with soft reservation and
list-routing for items not yet in stock.

- A committed no-cook night gets **Serve** as its verb and no start-by line (nothing to
  time); reheat guidance appears when known ("warm through, ten minutes"). Serving
  decrements made stock and logs the meal in one tap.
- **Just ate**: the meal log's third mode — pre-guessed item chips from stock, optional
  name ("girl dinner"), ~10 seconds. Decrements per resolution class (the apple goes;
  the cracker gauge doesn't care).
- Every meal gets a procedural plate composed from what was actually eaten; direct-eat
  entries render smaller and quieter in the journal (weight mirrors effort, tone never
  judges).
- Composer row label: **"Log tonight's meal"** (supersedes "Cooked tonight — log it"),
  opening the three modes: Cooked · Served leftovers · Just ate.
- The fan may deal a **no-cook pick** when appropriate (late hour, low stock): a served
  leftover or an assemblage spark ("brie, crackers, the pear — call it dinner").

Cooking without a recipe is a first-class event, not a gap:

- **Light log**: one tap ("Cooked tonight") → optional name ("veg stir-fry") → tap-off
  pre-guessed ingredient chips (guessed from stock + expiry: "the spinach? the eggs?").
  Target: under 15 seconds. Voice variant via the sweep engine: "used the spinach and
  half the feta."
- Effects: decrements inventory (fixes the systematic over-count of invisible consumption),
  creates a journal node ("Tuesday — you cooked. Used spinach, eggs, half the feta."),
  feeds taste learning.
- **Ghost recipes**: repeated improvised combinations get offered a name ("You've cooked
  this three times — name it?"); AI can draft a recipe from the ingredient set on request.
  The improviser's journal fills with *their* dishes.
- Optional plate photo: user's real plate, art-directed into the ceramic style.
- Never required. If cooks are never logged, certainty decay + rebuy inference
  (re-purchasing eggs implies the old ones went) keep the model honest.

## 9. First run — the Pantry Sweep

Day zero is the audition. Time-to-first-value target: ≤ 90 seconds.

- The day-zero timeline renders the real grammar, short: one italic line of past
  ("Your kitchen's story starts today."), one glowing Start-here card, one dashed promise
  ("Tonight — I'll show you what you can already make."). A quiet "Here for the recipes?
  Import your first one" door for recipe-first users.
- **The sweep**: talk or type the kitchen; items resolve live into catalog entries with
  shelf-life chips; an unlock counter ("4 dishes unlocked so far") ticks up as the fan
  assembles. Setup is the first magic trick — it teaches the loop (stock in → options out)
  with zero tutorial.
- Same mechanism = lapsed-user revival ("fresh sweep?"), never a guilt trip.

## 10. Visual language ("cream & glass")

The centroid of: liquid-glass structure + the current app's warmth + Crouton-grade character.

### Palette
| Token | Value | Use |
|---|---|---|
| cream (bg) | #F6F1E8 | base surface, with soft radial warm-white light |
| ink | #241E17 | primary text, active dock tab, dark buttons |
| paprika | #BC5210 | THE accent: primary action, now-node, active labels. Used sparingly |
| ochre | #A8650F / #C99B45 | expiry semantics only |
| sage | #5E7050 | readiness/positive semantics only |
| warm gray | #7A6F60 / #9B8F7D | secondary/tertiary text |
| glass | rgba(255,252,246,0.55–0.7), border rgba(255,255,255,0.85–0.92) | cards, dock |

Color appears only as meaning. No decorative tiles, no colored blocks, no hue-chaos —
unification comes from art direction, not from sameness of hue.

### Type
- **Serif** (display; Fraunces or New York class): dish names, greetings, the sommelier
  note (italic), big counters. Appetite and character.
- **Sans** (SF Pro): all facts, metadata, UI. Quiet.
- Rule: *appetite and information never share a font.* Numerals tabular.

### The plate system (imagery)
- Every dish renders top-down on the same ceramic, same light, same soft shadow:
  "one ceramic, one light — every dish in the same studio."
- Sources, three tiers with resolution order **photo > render > procedural**:
  1. **Procedural plate** (tier 0, always available): deterministic SwiftUI renderer
     composing a stylized top-down plate from catalog data — dominant ingredient
     category → base tone, secondary ingredients → flecks/garnish, ingredient count →
     texture density, recipe ID → seed. Instant, free, offline, covers every recipe
     including ghost recipes. Openly stylized; never imitates a photo.
  2. **AI render** (tier 1, async upgrade): generated once per kept recipe via locked
     prompt template; only the *food* is generated, then masked and composited onto the
     app's own ceramic ring asset with app-owned shadow and color grade (kills variance).
     Content-hash keyed, disk-cached forever. Bundled recipes pre-generated centrally by
     the existing Python pipeline and shipped — zero per-user cost. Lazy generation for
     user recipes (≈ $1–2 lifetime per heavy user). Soft crossfade when the render
     "develops". Failure → procedural remains, gracefully.
  3. **User photo** (tier 2, the truth): circular crop + grade toward the studio look,
     same ceramic ring. Always wins; fills the journal with the user's real cooking.
- Consistency is what separates premium gallery from messy camera roll, and lets
  colorful dishes coexist without clashing — enforced by the shared ceramic asset,
  light direction, and grade, not by hoping the model behaves.
- **v1 scope: tier 0 only.** Tiers 1–2 are designed but deferred; no UI may depend on
  their existence.
- Plate sizes: hero ~128pt (breaks the card frame, top-right), row 48pt, mini 34–44pt.
- The plate is the universal currency: timeline nodes, library cells, fan cards, journal.

### Material
- Glass cards: blur ~20pt + saturation boost, hairline white border, soft warm shadow.
- Floating glass dock: pill, 3 tabs, active = ink circle; plus button adjacent.
- Backdrop: cream with barely-there warm radial light; a whisper of paprika in one corner.

## 11. Voice & copy

The app is a confident sous-chef, not a butler.
Rules: **say the number, name the dish, state the fact, offer the verb.**
Banned: "maybe", "whenever suits", "you might want to", permission-seeking.
Voice modulates with data confidence (see §7) — confidence stays honest.

Examples (canon):
- "Your list hit 5 items — milk runs out around Monday."
- "The spinach turns Thursday. 300 g left."
- "Tonight's orzo or the frittata would use it up."
- "The weekend — nothing needs you."
- "12 dishes ready right now. 5 more are one stop away."

## 12. Motion (the half no mockup can show)

- Fan swipe: plates carousel with spring; the sommelier note rewrites on re-center.
- Commit: the chosen plate glides onto the spine; fan collapses; node solidifies.
- Cook entry: plate is the matched-geometry transition object into the instrument.
- Dock recedes on scroll-down, floats back on scroll-up.
- Sweep: chips resolve in; unlock counter ticks with haptics.
- Composer: cards crystallize from the bar with a spring pop on each item boundary;
  the empty-bar placeholder crossfades through examples on a ~2 s cycle.
- Day unfurl: tapping a bare notch opens the day with a spring; its tick warms to
  paprika. A fold's tick cluster spreads apart as its days separate.
- Spine scrubbing: dragging along the ruler fast-travels the timeline, one faint
  haptic tick per day passed.
- Timer: numerals roll; haptic ticks in the final ten seconds.
- Journal: past entries settle with a slight fade-in as you scroll up.

## 13. Composer & input resolution (offline-first)

### One component, four mounts (no new pages)

The composer is a single reusable component; "plan it" and "log it" are **contexts it
mounts in**, not screens. The destination is pre-bound by the mount:

| Mount | Opened from | Destination preset | Differences |
|---|---|---|---|
| Global | the + button | none (Stock/List/Cooked buttons) | full doorway rows |
| Day | day unfurl → "make your own" | that day (Plan) | stock chips first, commit = "Plan it" |
| Meal log | "Log tonight's meal" row | tonight's journal | mode chips (cooked·served·just ate), pre-guessed chips pre-crystallized |
| Sweep | onboarding / restock | Stock | mic held open, unlock counter |

- "Plan it" on a recipe card is not a composer mount — just an inline day picker
  (tonight / tomorrow / pick a day).
- **Date tokens are a fifth closed vocabulary** for the parser (weekdays, "tomorrow",
  "jun 14"). A parsed date in the global mount adds "Plan · Friday 13" as the predicted
  destination — "brie, olives, girl dinner friday" plans an assemblage in one line.
- Cook and Serve flows log themselves; the meal-log mount exists for everything else.

Layout: **one bar, living rows beneath — no second screen, no extra clicks.**
- **The mic lives on the bar.** Sweep = this composer with the mic held open; there is
  no Sweep row. (Day-zero "Pantry sweep" is this same surface, framed as onboarding.)
- Bar empty → rows, in order: **Log tonight's meal** (cooked · served leftovers · just
  ate — the 10–15 second log, §8) · **Add to the list** (flips the batch destination to
  List) · **Paste a recipe link or text** (plain label — no clipboard preview in the
  resting view).
- Typing → the top row becomes the live parse ("Spinach → Stock · fridge · ~5 days")
  with alternate destinations (List · Cooked) inline on the same row. Return commits
  the prediction; one tap redirects. Rows fade back but remain.
- URL pasted/typed → the import happens **in the card area**: a loading card ("Reading
  bonappetit.com…") crystallizes into a recipe preview card — procedural plate, title,
  time/servings/ingredient count, readiness preview ("7 of 9 on hand · 2 → list?") —
  with Save to Library as the commit. Offline, the card parks as queued ("Saved —
  importing when you're back online").
- One grammar: **everything the bar is given becomes a card** — ingredient phrases →
  item cards, recipe links → a recipe card, a spoken sweep → a stream of item cards.

Live card building (multi-item entry):
- Item boundaries — comma, "and", or return — crystallize the phrase into a **card**
  above the bar (spring pop); the bar clears for the next item. Cards accumulate and
  are individually correctable (unit pills, guess fixes) without blocking typing.
- Cards are the syntax teacher: you see how your phrase parsed and self-correct on the
  next one. **Teach, don't enforce** — the parser stays forgiving regardless.
- Empty-bar placeholder rotates real examples every ~2 s (soft crossfade), covering the
  pattern space: "300 g spinach, fridge" · "2 salmon fillets, freezer" · "olive oil" ·
  "half a bag of spinach" · "eggs, milk and butter" · "leftover ragù, 3 portions, frozen".
  Stops the moment typing starts.
- Destination applies to the batch (Stock default; List / Cooked one tap away). The
  commit button carries the count and the consequence: "Add 3 to Stock — 2 new dishes
  ready" (the sweep's unlock counter, generalized).
- The sweep IS this mechanism with voice as the input: same parser, same cards, same
  commit. One engine, two mouths.

### Parsing: three vocabularies, anchored slots

Phrase grammar: [quantity] [unit] [ingredient] [storage]. The vocabularies differ in
openness, and that asymmetry does the work:
- **Quantities** identify themselves lexically (digits, fractions, number words).
- **Units** are a closed lexicon we own (global culinary units + per-entity typical
  units derived from catalog density/piece data). Not in the lexicon → not a unit.
- **Ingredients** are validated by the on-device catalog fuzzy search; longest match
  wins ("chicken breasts" → the entity, not breast-as-unit).
- **Storage** words are a fourth closed set (fridge / freezer / frozen / pantry…).

Known tokens anchor their slots; an unknown inherits the slot left over — so the parser
knows *what kind* of unknown it has. "1 jgirjgr of salmon" → unrecognized **unit** →
targeted inline correction: the chip itself is the question, showing that ingredient's
typical units as one-tap pills (fillets · g · lb · keep "jgirjgr"). The item is saved
regardless; correction is optional. Implausible pairings (salmon in cups) downgrade to
guessed. Zero anchors → whole phrase saved as an unresolved custom item.

Resolution pipeline — fully on-device; AI is an enhancer, never a dependency:
1. Tokenize → quantity/unit grammar (local rules) → name via the on-device catalog
   fuzzy search (alias-aware) → storage keywords; gaps filled by catalog defaults
   (spinach → fridge, shelf-life prior attached).
2. Chip states: **resolved** (solid) · **guessed** (dotted underline, one tap to
   correct) · **unresolved** (dashed — added anyway, stored as a custom free-text item).
3. **Never block, never error.** Unparseable quantities keep the raw phrase as display
   text ("a glug") and fall back to presence/gauge semantics per resolution class.
   Unknown names become functional custom stock items instantly.
4. Deferred enrichment: when online, the existing AI ingredient-definition flow quietly
   upgrades unresolved items ("3 items identified" — one tap to confirm or fix).
5. Offline import: queued — "Saved. I'll import it when you're back online."
   Offline sweep: on-device speech + local resolution; fully functional offline.

## 14. Build plan

1. **Confidence data model** — certainty field + catalog-derived decay; consumption
   decrement paths; rebuy inference hooks. (Everything hangs off this.)
   ✅ *Done (uncommitted):* `ResolutionClass` + data-driven `ResolutionClassifier`
   (shelf-life → staple, countability → semi-countable, else perishable; category
   only as a no-data fallback), `ItemCertainty`, pure `ConfidenceEngine` (exp decay,
   half-life = shelf life × class factor), `KitchenConfig` typed tuning. 18 tests
   green incl. real-catalog spot checks. Decrement paths + rebuy inference still TODO.
2. **Design tokens + core components** — cream/ink/paprika tokens; GlassCard, PlateView
   (procedural tier 0 only in v1), Dock, SpineRail, node styles.
3. **Timeline scaffold + composer** — the feed-composition layer deciding what earns a
   node (make-or-break: a quiet day must render quiet, not noisy).
4. **Now-module** — fan + rescue + sparks states; behavior-keyed switching; Explore sheet.
5. **Cook-event + reconciliation** — recipe-less log, gathering-as-reconciliation,
   shopping check-off → stock.
6. **Composer + sweep** — shared resolution pipeline (§13), destination grammar,
   deferred enrichment; first-run onboarding + lapsed-user revival.
7. **Stock & Library** screens in the language (mockups pending).
8. **Migration** — Home/MealPlan VMs → Timeline; Pantry/Shopping/PreparedDish VMs → Stock;
   route old deep links; remove the Kitchen segmented control.

### Build status — 2026-06-10 (branch `redesign-kitchen-timeline`)

**The redesign runs on the simulator** as the sole app root, on a seeded
`KitchenStore` driving every surface through the pure engines. The legacy UX
(Views/ViewModels/AppState/Application — ~72 files) has been **removed**; the old
flow lives in git history. Builds clean; 159 tests pass (engine + service tests
kept; legacy view-model tests gone with their code).

Post-runnable refinements: honest staple presence (no fake fullness), infinite fan
carousel (swipe + tap), scroll-anchored timeline. See `docs/feature-audit.md` for
the old-vs-new feature accounting and the regressions still to restore (ingredient
gathering, composer editing, library filtering/enrichment, multi-cook, shopping,
persistence).

- ✅ Confidence model — `ResolutionClass`/classifier, `ConfidenceEngine`, `ItemCertainty`, `KitchenConfig`.
- ✅ Visual foundation — `Theme`, procedural `PlateView`+renderer, `GlassCard`, `Dock`.
- ✅ Timeline — pure `TimelineComposer` (fold/whisper/week policy), spine ruler, rows.
- ✅ Now-module — `ReadinessService`, 4-state machine, `FanView`.
- ✅ Parser — no-regex `IntakeParser` (anchored slots over the catalog engine).
- ✅ Runnable wiring — `KitchenStore`, `RedesignRootView`, Library/Stock/Composer/Cook screens.
- ⏳ Remaining (see task "Production wiring"): real SwiftData persistence in place of
  sample data; `MealEventService` + `ReservationLedger` + decrement-by-class; deferred
  UI (Explore sheet, rescue/sparks variants, day-unfurl planning, assemblages);
  `VoiceCopy` templates; motion/gesture polish.

## 15. Implementation architecture (SOLID, data-driven, no regex, no hardcodes)

**Governing rule: code contains mechanism only.** Domain knowledge (words, units, shelf
lives, decay priors, swap pairs, plate palettes) lives in the catalog pipeline as
validated, versioned data. Tuning (fold thresholds, whisper limits, spacing) lives in
one typed `Config`. Precedent: the `universalModifiers` removal — the normalization
vocabulary is already 100% catalog-derived; this extends that rule to the redesign.

### Parsing without regex
- Tokenizer = character-class scanner; no pattern language anywhere.
- Each slot vocabulary is a type conforming to `TokenVocabulary` (`match(token) →
  confidence`): Quantity (digits + number-word table from data), UnitLexicon (pipeline
  data, per-entity typical units), Catalog (wraps the existing RankedTextSearchEngine —
  reuse, never a second matcher), Storage, Date. The anchored-slot engine iterates
  registered vocabularies and scores segmentations — **adding a vocabulary is adding a
  type, never editing the engine** (Open/Closed).
- Fuzzy matching belongs to the search engine; structural matching to lexicon lookup.
  Keeping them apart is what makes regex unnecessary.

### One source of truth per computation
| Engine | Sole owner of |
|---|---|
| ReadinessService | ready / ready-with-swap / needs-N (Library, Explore, fan, import preview, conflicts all query it) |
| ConfidenceEngine | certainty decay; only reader/writer of item certainty |
| TimelineComposer | pure (kitchen state → [TimelineEntry]); node/whisper/tick/fold policy; golden-file tested |
| MealEventService | the single writer of meal events (all four levels) |
| ReservationLedger | soft reservations + conflict detection |
| ProceduralPlateRenderer | deterministic (composition, seed) → plate spec; palettes are pipeline data |
| VoiceCopy | every user-facing sentence, from typed templates that structurally require the number and the name (no slot for hedging) |

### Layering & testing
- Views → ViewModels → domain services/gateways (existing `Application/` pattern) →
  engines/stores. Engines pure and synchronous where possible, behind protocols
  (existing `Protocols.swift` pattern), injected; SwiftData/SwiftUI never leak in.
- The composer's four mounts = one component + injected context object.
- Tests as the contract, in the catalog-invariant tradition: parser corpus, composer
  golden files, decay property tests, readiness invariants.

## 16. Open questions

- Fan ranking quality bar — three visibly different, defensible reasons per night.
- Composer thresholds: exactly what earns a timeline node (suggestion frequency caps).
- Stock & Library detailed design (not yet mocked).
- Pricing-page storytelling: the journal and the sommelier note are the demo assets.
