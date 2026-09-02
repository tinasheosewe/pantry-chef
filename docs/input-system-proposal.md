# Exact or Ask — the input system proposal

**Status:** proposal for decision · 2026-09-02
**Basis:** a 30-agent research program — an empirical sweep of the shipped parser (230 inputs through the real code and catalog), code archaeology of every entry door and downstream consumer, external research (ingredient-parsing state of the art, Apple's on-device FoundationModels tested on this Mac, the interaction patterns of the apps people trust), four championed architectures, 16 adversarial judges, a completeness critic, and a synthesis — all run against the seven hard requirements from the brainstorm.

---

## The decision in one paragraph

**Replace the parser's core and redesign the entry surface; keep the catalog and the search engine (fixed).** The new system is a *catalog-first Counter*. Identity is settled by construction: the capture bar is a catalog search whose ranked list is always visible, and an identity binds **only** through an exact hit on a normalized alias key or a pick on a visible row — the type system has no path from a score to an identity. Everything else the user types (item boundaries, quantity, storage, expiry, non-add commands) goes through **closed, accept-or-reject grammars** that can pre-fill but never guess. Every door — typed, dictated, pasted, barcode, checked-off list, AI import — lands lines on **the Counter**, a persisted place, put away in one act. **Quantity is set after identity** with a structured control, backed by a structured `Quantity` model downstream. Apple's on-device model is demoted to an optional, gated segmentation experiment; cloud AI stays where it is (explicit paste-a-recipe / photo). Deterministic, offline, iOS 17, identical on every device.

**Rework or replace?** Both, staged. Phase 1 is a one-week rework of the existing code that closes the trust bug and ships alone. Phases 2–4 replace the parser, add the Counter, and change the data model — each shippable on its own, the app better after every one.

---

## 1. What the evidence showed

### The shipped parser, measured
230 realistic inputs across 18 classes, through the real `IntakeParser` + `IntakePipeline` + catalog on the simulator:

| Verdict | Count | Share |
|---|---:|---:|
| Correct | 86 | 37% |
| Wrong but flagged (picker / custom) | 108 | 47% |
| **Wrong and confident** | **36** | **16%** |

The split underneath is the whole argument. **The exact-alias path was right 83 of 83 times. The fuzzy path was promoted to "confident" 40 times and was wrong on 35 of them (87.5%).** Every silent bad item came from a guess; none came from an exact hit.

Whole classes at zero: multi-item 0/12, quantity-after-name 0/12 (`eggs 12` → Powdered Eggs, `onions 3` → Omega-3 Egg, `flour 1kg` → Peanut Flour, all confident), non-add intents 0/12 (three *silently added the wrong product*: `used the last of the eggs` → adds Powdered Eggs), expiry 0/12, dictation 0/12.

### Three root causes nobody would find by reading
1. **The confidence gate never looks at the input.** `IntakePipeline.resolve` scores the *guessed catalog name against the catalog* (which matches itself at 1.00), so the 0.82 bar is applied to the guess, not to what was typed. `asdfgh` scored 0.65 against "Afghan Saffron" and shipped confident. The ambiguity signal is *inverted*: good guesses are questioned when their name has catalog siblings ("Broccoli" vs "Broccoli Rabe"); bad guesses with no siblings sail through.
2. **Resolution is non-deterministic across launches.** The same binary resolved `tomatos` to Stewed Tomatoes on 3 of 5 runs and Tomato on 2 of 5 — ties break on Swift's per-process dictionary hash order.
3. **The gate is bypassed at commit anyway.** `flushPreview`, onboarding's `commitTyped`, `purchase()` and `addScannedProduct` never consult the decision, and confidence is erased on commit: a stock item has no provenance, so a bad resolution can't be audited later. A facet-scoring defect ("chicken" counted as name *and* variant) is why `500g chicken` alone confidently becomes "Chicken Chicken Sausage" — a comma fix would not have cured it.

### What the research settled
- **Every state-of-the-art ingredient parser assumes one item per string** (NYT tagger, the best CRF at 95.6% on clean recipe lines, all of them). Run locally on our sentence, the best of them collapsed the way ours does. Segmentation is its own stage. Grocery entry is also a different distribution from recipe lines: 76% bare names, only 43% with any quantity.
- **No shipping grocery app splits typed commas.** The convention users trust is type-ahead against a catalog, one item per Return, a structured quantity field, and paste as an explicit list mode. The apps that parse sentences silently (Fantastical's title-stripping, Reminders' un-disableable suggestions) carry multi-year complaint threads; the ones with visible chips and one-tap un-parse (Todoist) are the ones people mourn when removed.
- **Apple's on-device model, tested on this Mac:** guided generation guarantees shape, not content — 40% all-slots-right, phantom items copied from its own examples on empty/meta notes, 2 of 14 intents wrong, invented units, 1.3 s median on an M-series Mac (2–5 s on phones), uncancellable, available on roughly a third of active iPhones. As a **segmenter** it was excellent (23/24 verbatim spans). Once identity still has to bind via the alias index, it rescued 1 of 25 escalated notes.
- **Downstream is thin.** The app consumes identity, storage, and a date. Quantity is free text in three places (`StockItem.Measure.perishable(detail:)`, `ShoppingEntry.amount`, `RecipeLine.amount`) and re-parsed by five. Readiness is presence-only. The catalog already carries `gramsPerPiece` for 424 countable items and `gramsPerCup` for 2,391 — unused.
- **The catalog is not yet load-bearing.** 66 alias-key collisions (last writer wins), 43 "frozen X" aliases pointing at non-frozen items, 32 duplicate items, ~350 facet-template key collisions, US-only naming with no locale layer.

---

## 2. The requirements (design law)

1. **Structurally impossible to be wrong-and-confident.** No code path from a score to a committed identity. Identity binds only via (a) an exact hit on a normalized alias key or (b) a user pick from a visible list. Fuzzy matching ranks; it never binds. Enforced at the type level and by a property test on every build. Programmatic paths (barcode, AI import) get no exemption.
2. **Always choose.** A visible choice in every case — the doctor picks from the formulary. Return on a highlighted, *settled* row is that choice.
3. **Identity is not required.** A visibly unlinked item is allowed: tracked for expiry, never powering readiness until linked.
4. **English, but every one of the ~2,888 catalog items reachable** by a reasonable variant, diacritics and apostrophes included. Normalization is a total, fuzz-tested function.
5. **Quantity comes after identity.** Pick the item, then set how much with a structured control; a closed grammar may pre-fill from a typed prefix, never guess. Structured `Quantity` downstream.
6. **The Counter is a place.** State in `KitchenStore`, never view `@State`; reached via the ＋ door; capture-first when empty, review-first when populated. **The shopping list stays separate**: list (need) → counter (have, not yet stored) → storage, one direction.
7. **Non-add intents via a closed verb grammar**; lists and dictation segment into Counter lines and never auto-commit.

---

## 3. The design

### 3.1 Five outcomes — and nothing else
Whatever the user types, pastes, or dictates, each resulting Counter line is exactly one of:

| Outcome | Mark | When | What happens |
|---|---|---|---|
| **Linked** | ✓ | The head text is a unique exact *primary* key (item name, curated alias, learned alias, or its folded/depluralized form) — or the user tapped/Returned a highlighted row | Bound. Proof recorded on the line (`exactKey` or `userPick`). |
| **Suggested** | ✎ | No primary hit; ranked rows shown (derived keys, prefix, edit-distance, token overlap; max 6; deterministic order) | Nothing bound. A tap binds; Return keeps the text as typed. |
| **Unlinked** | ┄ | Kept as typed, or nothing useful ranked | Tracked for expiry with a required shelf-life chip; excluded from readiness; "make it a proper item" optional. |
| **Inert** | — | No alphabetic token exists anywhere in the catalog vocabulary (`asdfgh`, `x`, `e g g s`) | Nothing lands. "I don't recognise this" with an explicit *keep as new item* button only. |
| **Command** | ▸ | A closed verb matched (`out of milk`, `move chicken to freezer`, `need eggs`) | A proposal — *Finish · Milk* — executed only on put-away, with a "No — add it instead" escape. |

Plus **Unsettled**: a sentence with negation or absence markers that matched no idiom (`no milk left`, `eggs all gone`) shows the item rows and residue chips with *nothing* highlighted; Return does nothing; the user taps Finish, Discard, or Add. This closes the judges' most common silent failure — 18 of 20 negation paraphrases defaulting to an *add* of the item the user just said they lack.

### 3.2 The always-choose list and the settled-highlight rule
The suggestion list is visible from the first keystroke, never hidden, never modal: max 6 rows deduped by item, each showing name · category · storage and a tier badge (*exact* / *also known as "mince"* / *starts with* / *did you mean* / *split*), plus a last row *Keep "<typed>" as new item*.

**The top row is highlighted only when it is settled**: (a) the head text is a unique primary exact key, or (b) in the prefix tier, the top row is the unique name-starts-with match or leads the runner-up by a recency/frequency/seed-prior margin (`tom` → Tomato by prior, never Tomatillo by alphabet). Otherwise nothing is highlighted and Return does nothing (a subtle shake) — the user types one more character or taps. Return on a highlighted row is a user pick and is recorded as one. Exact-name rows look different from exact-alias rows ("Ground beef — also: mince"). Collision keys (`pepper`, `chilli`, `tin of tomatoes` vs fresh) are never highlighted; every claimant is shown.

The one sentence for the user: *"Type what you've got, pick it from the list, set how much, put it away."*

### 3.3 Closed grammars (accept or reject, never guess)
- **Quantity pre-fill** — an ordered cascade of closed rules: glued units (`500g`, `1.5kg`, `2L`, `4pk`), decimal comma (`1,5` = 1.5; `1,000` = thousands), unicode fractions, ranges (`2-3`), multipliers (`2 x 400g tins`, `x3`, `(6)`), pack sizes (`500g tub` = 1 tub of 500 g), containers without a number (`bag of`, `tin of`), **trailing** quantities (`eggs 12`, `milk 2L`) with guards (a bare trailing number over 48 or a 4–5-digit PLU is residue, not a count). Number words pre-fill only when the residual is itself an exact key or a unit follows (`four cheese pizza` stays a name). Vague words (`a few`, `some`, `lots`, `most of`) become a **qualifier**, never a fabricated 3.
- **Storage is positional only** — trailing `, fridge` / `in the freezer` / `(freezer)`, leading `fridge:`. A storage word inside a name stays in the name for matching (`frozen peas` finds the catalog's frozen-pea items) and pre-fills the chip.
- **Expiry suffix** — `use by` / `best before` / `bb` / `exp` / `use today|tomorrow|<weekday>|<date>`, with an ambiguous-date chip.
- **Receipt guards** — `@` prices, `£/$` amounts, `/kg`, PLUs → residue chips, never counts.
- **Whole-text exact key always wins** over every slot rule (`half and half`, `milk 2%`, `cream of tartar`).
- Every token not consumed by identity appears as a **chip** — prefill, residue, prep (`chopped`), storage — and tapping a prefill chip reverts it to plain text (Todoist's rule). Nothing is silently dropped; a debug disclosure shows the rule trace.

### 3.4 Lists, paste, dictation
Segmentation is its own stage, before any resolution, and is door-aware.
- **Always split** on newline, semicolon, bullets/ordinals, and a comma — unless it is a decimal comma, or the piece is a bare storage/expiry phrase (which attaches to the previous line), or the door is the recipe editor (where `1 onion, finely chopped` is a prep chip).
- **`and` / `&` / `+`** split *only* when the whole text is not a key **and every piece is, in its entirety, a primary exact key** (`milk and eggs` → Milk · Egg). Otherwise the input stays **one unlinked line** with a visible *"Split into: cheese · onion crisps?"* proposal — never three bound lines. This closes the class every judge found: `cheese and onion crisps` → Cheese + Onion + Potato chip.
- **Space-only lists** (`milk eggs bread`) are never auto-split. A dynamic program over primary exact keys produces a *"Split into 3?"* proposal only when every token is covered. Dismissed proposals for text the user then binds become learned aliases, so it never asks twice.
- **Paste** never dumps the clipboard into the field. A list-shaped clipboard opens a *"N items found"* sheet with per-row remove; exact-key lines land Linked, suggested lines are pinned to the top under *"N need a look"*, and *Put N away* confirms how many will go unlinked.
- **Dictation** (the keyboard mic can't be removed): on submit, fold spoken punctuation, Title Case, preambles (`so I have like`, `um`); number words via the closed table; homophones (`flower`, `time`, `leaks`) are ranking-only aliases that show as suggestions, never exact. Everything lands on the Counter.

### 3.5 Commands
A closed, ordered, whole-token-anchored idiom table (~40 rows in v1, each citing the corpus line that motivates it) applied to the whole folded line before segmentation: finish (`out of`, `used up`, `no more`, `ran out of`), discard (`threw out`, `binned`, `went off`, `mouldy`), move (`put X in the freezer`, `took X out of the freezer` — longest match wins), list (`need`, `buy`, `add X to the list`), set level (`running low on`), set count (`only 3 eggs left`), log meal (`had X for dinner`, `ate`), plan (`making X tonight`), expiry, undo, question.

Four guards the judges demanded: (1) a whole-phrase catalog key skips the table (`cooked ham`, `grab bag crisps`); (2) a build-time test that no idiom fires on any of the ~9k catalog keys or a 349-name weekly shop (`half a cabbage` must not trip `bb`); (3) a destructive verb whose object matches no stock row lands Unsettled, not as a command; (4) the negation/absence lexicon routes to Unsettled. Commands target the user's own stock rows first; two matches → pick; all run through one `KitchenStore.apply` with one undo entry per put-away. A dictated or pasted command is staged like anything else — never auto-executed.

### 3.6 The Counter
```
Shopping list  (what you NEED)  — its own place, unchanged
      │  checked off → "Put N away"
      ▼
The Counter    (what you HAVE, not yet stored)
      │  identity · quantity · destination → "Put away" (one act, undoable)
      ▼
Storage        (fridge / freezer / pantry)
```
- `KitchenStore.counter: [CounterLine]`, persisted (the first field of `PantrySnapshot` v2). A half-finished unload survives a phone call. The ＋ door opens the Counter as a full space — never a dismissible sheet — capture-first when empty, review-first when populated, with a count badge on ＋ and an *"On the counter — N"* strip in Pantry whenever non-empty.
- **Sources:** typed, dictated, pasted, barcode (linked or visibly unlinked — never Coke → cheese), checked-off list items, AI-imported ingredient lines (in the recipe editor's own review flow — the Counter is for stock only).
- **List mode** in the capture bar writes straight to the shopping list with the same choose-a-visible-row rule; `need milk` routes there with an undoable toast. A Counter line can be *moved* to the list as an edit; the list is never a Counter destination.
- The three-state visual vocabulary is kept and re-mapped: check = linked, pencil = suggested, dashed = unlinked. A global **Smart detection** toggle turns prefills and intent chips off everywhere.

### 3.7 Quantity after identity
After the pick, the line shows a quantity control pre-set to the item's **natural kind and default** (eggs → count; milk → volume; spinach → mass or bag; staples → a gauge, never asked), stepper/keypad + unit picker. Return skips it (a quiet *some*, never a fabricated number). A typed prefix (`2 eggs`) shows `2 · Egg` in the row before Return as a chip. Behind it, `struct Quantity { value, unit, kind: count|mass|volume|container, packSize, range, approximate, qualifier, rawText }` replaces the three free-text strings.

### 3.8 Normalization and the alias index
- **`TextFold.key`** — one total normalizer for index keys and input: NFKC → locale-fixed (`en_US_POSIX`) case/diacritic/width fold → apostrophe and curly-quote unification (`za'atar`, `bird's eye`) → `&`→`and`, `×`→`x`, dashes and NBSP → unicode fractions to text → digits via `Character.wholeNumberValue` → `%` glued to a digit becomes a percent token (so `1 milk` can never hit `1% milk`) → punctuation classified by Unicode category (separators *survive*) → word boundaries by category, `NLTokenizer` only for space-less scripts → the **owned** depluralizer on every token. Emoji table (~15 entries) and spoken-punctuation table live here. Property-tested: total, idempotent, stable under random combining marks, NBSP, quotes, width variants, Arabic-Indic digits.
- **Why not `NLTagger` lemma in the key** (requirement 4 names it): its output changes by OS release and mangles loanwords (`crème fraîche` → `creme frais`), so a lemma-built index would silently stop exact-matching after an iOS update — the opposite of not fragile. It runs only as a query-time secondary variant ranked below the owned key, and an acceptance test fails the build if a lemma variant ever binds a different item.
- **`AliasIndex`** — two key classes. **Primary** = item names + curated aliases + per-device learned aliases + their folded/depluralized forms (~9k keys). **Derived** = facet-template keys (minus options that duplicate a name word — no more "Chicken Chicken Sausage") and storage-prefixed aliases carrying an override; derived keys never outrank a primary key and are never Return-highlighted. Multi-owner keys are **collisions** kept as data: a collision never binds, always yields a choice. **One `bind()`** with no fallthrough — every reduced form (prep-stripped, storage-prefix-stripped, `tinned X`) is just another key through the same collision-checked binder. Sorted keys with total tie-breaks (deterministic across launches), built once off the main thread (~0.3 s on an A12), incremental inserts.
- **`LearnedAliases`** — a per-device store of `foldedText → itemID` created when the user picks a row for an unlinked text (auto after two picks, or one tap on *remember*). Participates as a primary key with collision detection; visible in Settings, undoable, exportable as alias candidates. The household teaches the catalog: the always-choose glance tax is a *decaying* cost, and the two-thirds of devices without the on-device model get the same improvement.
- **The ranker** (`CatalogSearchEngine`, kept and fixed) returns `Ranking` only: it scores the *user's* span, drops the facet double-count, is container-aware (`tin` re-ranks canned rows first), gates the overlap rung on a real vocabulary token (gibberish ranks nothing), and orders prefix hits exact > name-starts-with > token-starts-with > per-user recency > seed-recipe prior > shorter > alphabetical. Edit distance never runs per keystroke.

### 3.9 Deliberately not in the design
- **FoundationModels as a parser** — measured, above. It survives only as a Phase 6 *offer-only* segmenter behind a gate (build only if ≥5% of Counter lines escalate *and* recorded evals show it rescuing ≥20% of them; today: 1 in 25).
- **Cloud AI on a pantry note** — never per keystroke, never for a note; explicit paste-a-recipe/photo stays, and a later explicit *Read this* for receipt photos through the same Counter path.
- **Any auto-accept threshold.** `decide()`'s 0.82/0.12/0.55 stack is deleted, not tuned.
- **Non-English** — out of scope; unknown brands, slang and receipt codes close as data (aliases, learned aliases) or an explicit cloud action, never as parser rules.

---

## 4. Worked examples (the embarrassing fifteen, plus the sweep's worst)

| Input | Outcome |
|---|---|
| `2 eggs, a bunch of spinach, 500g chicken thighs` | Egg ×2 · Spinach 1 bunch · Chicken thigh 500 g — three linked lines |
| `Two eggs, a bunch of spinach, and 500 g of chicken thighs.` | same three lines (period folded, `, and` before a quantity is a boundary, `Two` → 2) |
| `500g chicken thighs` | Chicken thigh, 500 g pre-filled (glued unit) |
| `milk and eggs` / `half and half` | Milk · Egg (both exact) / Half-and-half as one line (whole-text key wins) |
| `used up the milk` · `out of milk` | Finish · Milk |
| `put the chicken in the freezer` | Move · Chicken → Freezer (pick if thighs and whole chicken are both in stock) |
| `need milk` | To list · Milk (bypasses the Counter) |
| `1,5 kg potatoes` | Potato 1.5 kg |
| `frozen chips` | Suggested (the catalog alias points at Potato — shown as the top suggestion, *not* highlighted, storage chip Frozen, "keep as frozen chips" beneath); fixed as data in the alias audit |
| `pack of 12 eggs` | Egg ×12, container pack |
| `2 x 400g tins chopped tomatoes` | Canned diced tomatoes ×2 tin, pack 400 g, prep chip *chopped* |
| `4 pints semi skimmed` | 4 pint pre-filled; *semi skimmed* unlinked with Milk ranked — one tap, then a learned alias |
| `a few carrots` | Carrot, qualifier *a few* — no fabricated 3 |
| `eggs 12` · `onions 3` · `flour 1kg` · `milk 2L` | trailing quantity → exact items with counts (today: Powdered Eggs, Omega-3 Egg, Peanut Flour) |
| `bottle of olive oil` | Olive oil ×1 bottle (today: Bottle Gourd) |
| `tin of tomatoes` | canned rows re-ranked first, nothing highlighted — fresh Tomato is also exact, so it's a choice |
| `snow peas` · `tomatos` · `peppers` | Snow pea · Tomato (launch-stable) · declared collision (bell / peppercorn) → choice |
| `cheese and ham` | Cheese · Ham, with a *Ham and cheese (one item)* row |
| `cheese and onion crisps` | one unlinked line + *Split into: cheese · onion crisps?* — never three bound lines |
| `ate the leftover curry` | Log meal (resolved against the dish library first) — today: adds Curry Leaf |
| `we have no eggs` · `milk's gone` | Unsettled — Egg/Milk rows shown, nothing highlighted, Finish / Discard / Add buttons |
| `asdfgh` · `x` · `e g g s` | Inert (today: Afghan Saffron, XO Sauce, Bird's Eye Chili — all confident) |
| `🥑 x3` | Avocado ×3 (emoji table) |
| `Quorn mince` · `Lurpak` · `ORG BNLS SKNLS CHKN BRST` | Unlinked with rankings that may look silly; nothing binds; one pick teaches the device |

---

## 5. What changes in the code

| | Path | Note |
|---|---|---|
| **NEW** | `Services/Intake/TextFold.swift` | the one total normalizer + property tests |
| **NEW** | `Services/Intake/IntakeTokenizer.swift` | tokens with kinds; separators preserved |
| **NEW** | `Services/Intake/AliasIndex.swift`, `Models/Identity.swift` | primary/derived keys, collisions, single `bind()`; `BoundIdentity` (fileprivate init), `Ranking` (no path to identity) |
| **NEW** | `Services/Intake/LearnedAliases.swift` | per-device learned aliases |
| **NEW** | `Services/Intake/IntentGrammar.swift`, `Segmenter.swift` | closed idioms + negation lexicon; boundaries as a stage |
| **REWRITE** | `IntakeParser.swift` → `Services/Intake/SlotGrammar.swift` | explicit P0–P12 cascade, each rule a closed vocabulary, each firing traced |
| **NEW** | `Services/Intake/IntakeCoordinator.swift` | the one door for all six surfaces (`ingest(raw, source:) -> [CounterLine]`) |
| **KEEP + FIX** | `CatalogSearchEngine.swift`, `RankedTextSearchEngine.swift` | the ranker; returns `Ranking` only |
| **NEW** | `UI/Features/Counter/` | `CounterView`, `CaptureBar` + `SuggestionList`, `CounterLineCard`, `QuantityControl`, `ListPasteSheet`, `IntentBanner` — replaces `ComposerView` |
| **KEEP** | `makeStockItem` (as the one sink), `PantryCatalog` data, `registerUserItem`, `CustomIngredientForm`, `ExpiryEngine`, `ConfidenceEngine`, readiness, `SharedRecipeInbox`, `AIService.parseRecipe` | |
| **DELETE** | `IntakePipeline.swift` (thresholds, un-floored `bestCatalogID`), `ParsedIntake`, the three `Resolving` enums, five capitalisation sites, five string amount re-parsers, dead scaffolding | |
| **OPTIONAL (Phase 6)** | `Services/Intake/FMSegmenter.swift` behind `protocol NoteSegmenter`, `#if canImport(FoundationModels)` | offer-only, substring-verified, never binds |

---

## 6. Downstream changes (nothing is set in stone — priced)

| # | Change | Size | Unlocks |
|---|---|---|---|
| 1 | **The Counter as store state** — `counter: [CounterLine]`, `PantrySnapshot` v2 (tolerant decode exists; keep v1 until v2 has loaded once); atomic put-away using the line's `stagedAt` for `lastConfirmed` | M, 2–3 d | requirement 6; every door converges so gating can't diverge again |
| 2 | **Structured `Quantity`** replacing `Measure.perishable(detail: String)`, `ShoppingEntry.amount`, `RecipeLine.amount`; `.counted(n:)` for the 424 countables; lossless migration (unparsed text → note); delete the five string re-parsers; rewrite their tests; seed-recipe normalisation | L, 4–5 d | additive list math, duplicate merge on put-away, honest *some spinach*, lossless scaling/nutrition, decrement-on-cook, the runs-out clock, structured AI import |
| 3 | **`IntakeCommand` + `KitchenStore.apply` + undo** — one verb API over the existing operations; make `isKnownOut` real so *out of milk* changes readiness | M, 2–3 d | commands stop being theatre |
| 4 | **Provenance on committed items** — `origin { rawText, source, boundVia, facets }` | S, 1 d | *from "chiken thighs" — tap to fix* survives put-away; re-linking when aliases improve; editing a name unlinks by construction |
| 5 | **Readiness / expiry** — unlinked items excluded from presence; shelf-life defaults via the required chip; expiry seeds `daysLeft`; made lines link to the dish library first | S, 1 d | requirement 3 |
| 6 | **The other doors** — barcode carries OFF quantity/brand/categories → exact-or-unlinked + pack prefill; AI import structured; *Put N away* → Counter; onboarding and meal log through the coordinator; recipe editor keeps the typed quantity | S each, ~2 d | one rule everywhere |
| 7 | **Catalog data as a tested phase** — `tools/alias_audit.py`: 66 collision decisions, duplicate merges, the 43 frozen-alias fixes, locale-dependent aliases, the ~75-row alias pack the corpora surfaced, hygiene lint, reachability test | M, 2–3 d then hours/release | correctness now lives here |
| 8 | Dead code removal | XS | |

---

## 7. Build plan

| Phase | Scope | Size | Ships alone |
|---|---|---|---|
| **1 · Stop the bleeding + the binder** | No new UI. Score the *user's* phrase, never the guess (moves ~35 of 36 wrong-and-confident rows to flagged); sort the search keys (launch-stable); drop the facet double-count; introduce `BoundIdentity`/`Ranking` and route the pipeline through them — exact → bound, anything else → the existing picker on all three surfaces, `decide()`'s thresholds deleted; route `flushPreview`, onboarding, `purchase()`, `addScannedProduct` through the same gate; clear the id on name edit; minimal comma/newline segmentation with decimal-comma and trailing-storage exceptions; storage words positional-only; the identity property test + the 230-row sweep as a smoke test asserting structural wrong-and-confident = 0 | S · 3–5 days | yes |
| **2 · The identity core and the grammar** | `TextFold`, `AliasIndex` (primary/derived/collisions, single bind, sorted, off-main), ranker fixes, `IntakeTokenizer`, `SlotGrammar` P0–P12, `Segmenter`, `IntentGrammar` + negation lexicon, `CounterLine` with trace, `IntakeCoordinator` (old composer temporarily consumes lines); corpus curation (expected ids/kinds/acceptable outcomes for 276 + 230 rows) and the twelve deterministic test layers; alias pack v1 + audit + hygiene tests. Delete `IntakeParser`, `IntakePipeline`, `ParsedIntake`, the `Resolving` enums. Gate: strange corpus ≥75% correct, wrong-default ≤3% in Swift | M–L · 2 weeks | yes |
| **3 · The Counter and always-choose capture** | `counter` in the store + snapshot v2; ＋ → `CounterView`; `CaptureBar` with the always-visible list and the settled-highlight rule; line cards with chips, proposals, command banner, unsettled buttons; `ListPasteSheet`; `IntakeCommand` + apply + undo; `isKnownOut` real; unlinked excluded from readiness; learned aliases; list-mode and *Put N away* → Counter; Smart-detection toggle; provenance. The quantity control writes through a temporary bridge to the existing string so the migration isn't on this phase's critical path | L · 1.5–2 weeks | yes |
| **4 · Quantity after identity, for real** | `Models/Quantity.swift`; `Measure` change + `.counted`; `ShoppingEntry`/`RecipeLine` → `Quantity?`; migration with a fixture of every historical amount shape; delete the five re-parsers; rebind editors; merge on put-away; stock-unit smart defaults; remaining doors; expiry seeds `daysLeft`. Unlocks decrement-on-cook and the runs-out clock next | L · 1.5 weeks | yes |
| **5 · Data hygiene loop** | Collision decisions, duplicate merges, locale-dependent aliases, promotions, homophone/household/pet kinds, dish compounds, opt-in export of unlinked names and dismissed proposals as alias candidates. Rule: no grammar rule or idiom without a corpus row | S · 2–3 days, then hours per release | yes |
| **6 · Optional on-device segmenter** | Only if Phase 3 telemetry shows ≥5% of lines escalating *and* a recorded eval shows ≥20% rescue. Offer-only *Split differently?*, substring-verified, kill switch, prompts per model version | M · 1 week | gated |

Phases 2–4 are roughly 5–6 weeks of focused solo work after the one-week Phase 1.

---

## 8. Targets and the regression net

**The corpus is the spec, curated first**: hand-review the 276-row strange corpus (judges found expected ids that come from the catalog's own bad aliases) and hand-label the 230-row sweep, each row with an acceptable-outcome set; both run end to end through the production coordinator with the real catalog. Today no test exercises parser + pipeline + real search together — which is why every failure shipped.

**Verdicts** (machine-scored): Correct = intent, line count, every highlighted identity, and every pre-fill right (a dropped quantity is *not* correct); Asked = suggested/unsettled with the expected item in the top 3; Unlinked-OK; **Wrong-default** = a highlighted row, number, storage, or routed intent a blind Return would accept; **Structural-WAC** = any identity bound from text without an exact key or a gesture — must be 0.

**Gates per release:** strange corpus Correct ≥78% (prototype 81.5% in-sample; honest out-of-sample expectation 70–75%), Asked ≤18% with ≥70% one-tap, Wrong-default ≤2%, Structural-WAC = 0; sweep Correct-or-Asked ≥90%, Wrong-default ≤2%; per-class floors — multi-item, quantity-after, intent, expiry, dictation ≥85% correct (all 0/12 today); receipt/brand/non-English wrong-default = 0; the judges' 20-row negation set: add-default = 0. *Correct may drift; wrong-default may not.*

**Twelve deterministic test layers:** `TextFold` fuzz; catalog reachability over all 2,888 items; identity-binding property + compile-time constructibility; collision invariant; idiom-vs-catalog; prefix stability (no highlighted row mid-word that differs from the settled row); determinism across three fresh processes; chip accounting (nothing silently dropped); a curated *must-not-highlight* list (`frozen chips` ≠ Potato, `eggs bread` ≠ Challah, `four cheese pizza` ≠ qty 4, `1,000 g` ≠ 1 g); migration fixtures; door parity; latency.

**Latency (p95, A12 iPhone XS; 3–4× better on an iPhone 17):** keystroke path <4 ms; exact-bind submit <1 ms/line; ranked submit <40 ms on iPhone 17 / <150 ms on A12; 15-line paste <500 ms; index build <400 ms off-main; put-away write <50 ms.

---

## 9. Objections, answered

- **"The one-line fix plus comma splitting removes 35 of 36 wrong-and-confident rows in a day. Why six weeks?"** Agreed — that *is* Phase 1, and it ships alone. But it leaves the six zero-correct classes at zero, the ambiguity signal inverted, quantities as strings five places re-parse, the Counter as view state, and "guessed but flagged" as the everyday experience. Phases 2–4 are the difference between *not embarrassing* and *the system you described*.
- **"Always-choose moves the error to the user's eye; by the tenth item nobody looks."** Three mechanisms narrow it: the highlight rule refuses to gamble (nothing highlighted unless settled), alias rows look different from name rows and collisions always show all claimants, and the residual — a wrong *curated* alias — is a data class capped by the must-not-highlight test, targeted ≤2%, and correctable a week later from provenance. Today's outcome-identical rate is 16% and unrecoverable.
- **"The catalog becomes the parser."** Yes, and that is the right place: a wrong alias is a one-row, testable, explainable fix; a wrong fuzzy score was an untestable threshold interaction. The design adds the guards a data-driven system needs, and learned aliases mean users aren't waiting on App Store releases.
- **"The coverage numbers are in-sample."** Stated plainly: expect 70–75% correct out of sample and hold wrong-default, not correct, as the gate. The judges' hostile walks were the most valuable input — every silent class they found is closed by a named rule and a regression row. The structural guarantee doesn't degrade out of sample at all.
- **"Rule accretion never closes the tail."** Correct, so the tail isn't closed with rules: brands and slang close as data, receipts get an explicit cloud action, non-English is out of scope. Rules live in one ordered file; each cites a corpus row; no rule without a row.
- **"Why not Apple's free on-device model?"** It's in the plan as a gated, offer-only segmenter, because the measurements say it shouldn't be a pillar: 40% all-slots-right, phantom items, invented units, 1–5 s, a third of devices, three model versions already, and 1-in-25 rescue once identity still binds via the index. Building it first would double the test surface for a feature most users can't get.
- **"The Quantity migration is the likeliest thing to slip."** Which is why it is its own phase with a bridge, a fixture set of every historical amount shape, and the v1 snapshot retained until v2 has loaded once. Its payoff is what the redesign is for.
- **"Return on an exact hit adds a keystroke; users punish friction on the common case."** Per item the cost is one glance plus, for perishables, one Return to skip the amount — and the household's top items become two or three characters within a week via recency, fewer keystrokes than today's full phrases. If usability testing still finds the glance too costly, the retreat is already sketched: exact-*name* hits bind on Return with a stronger visual while exact-*alias* hits require a tap — a softer rule, not a redesign.

---

## 10. Decisions I need from you

1. **Return on a settled, highlighted row counts as the choice** (vs. a literal tap only). Recommendation: yes — it's a visible choice and keeps the unload rhythm.
2. **A locale switch (UK/US)**, defaulting from the device: it decides `pepper`, `chips`, `coriander`, `jelly`, and `pint`/`litre` in one setting instead of N alias edits or permanent choice moments. Recommendation: yes, in Phase 5.
3. **What an unlinked item is downstream.** The critic's sharpest point: if unlinked is a dead end, users will force-link to a plausible wrong row to get readiness back — reintroducing wrong identity through the one path the rule blesses. Recommendation: design provenance now (Phase 3) and add a lightweight product layer (a user item with a parent link, optional brand and pack size) in Phase 5.
4. **Phase 6** — keep as a gated experiment, or drop entirely. Recommendation: keep the gate, build nothing until it passes.
5. **Start Phase 1 now.** It is a week, fixes the trust bug, and ships alone while Phases 2–4 are scheduled.

---

## Appendix — how the four architectures scored (out of 40, four adversarial lenses each)

| Architecture | Fragility | UX | Maintenance | Cost | Total |
|---|---:|---:|---:|---:|---:|
| Counter Grammar — rebuilt deterministic intake | 7 | 6 | 6 | 8 | **27** |
| Structure-by-construction — autocomplete-first | 5 | 6 | 6 | 8 | 25 |
| Escalation ladder — grammar + on-device segmentation for the tail | 6 | 6 | 6 | 7 | 25 |
| FM-first note reader — on-device model as reader of record | 5 | 5 | 4 | 5 | 19 |

The recommendation is a composite of the first three (their differences were inside the noise, and each judge found a hole the others closed); the fourth is demoted to Phase 6 on measurement. Raw artifacts (prototypes, judge walks, the two corpora) are in the session scratchpad; the two corpora become test fixtures in Phase 2.
