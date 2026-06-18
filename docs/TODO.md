# PantryChef — running TODO

Deferred work and decisions, flagged as they come up. Newest context at the bottom of
each item.

## Open

### Live-data audit follow-ups (from the two-agent audit)
The store is `@Observable` and views read live through computed props — cook/eat/shop/
storage-move all propagate. Fixed already: Stock editor used `Date()` not `store.today`.
Remaining (in priority order):
1. ~~Plan timeline frozen seed data~~ **DONE** — `timelineEntries` now derives expiry
   diamonds from `expiringSoon(within:7)` and the leftover whisper from `leftovers`, so
   Plan agrees with Pantry/Feed live.
2. **`store.today` only re-ticks on app foreground**, so certainty decay, day-part, the
   expiry badge/bands won't roll over while the app stays open overnight. Consistent
   across views (not a divergence) but stale. Consider a midnight/periodic refresh —
   weigh against the deliberate knowledge-clock freeze ([[pantrychef-two-freshness-clocks]]).
3. Low: `readinessReady` is a one-shot latch (no recovery if the warm Task never runs —
   in practice it always does); `fanOptions` is a stored snapshot that can go stale on the
   open fan (mostly moot now the idle fan is gone from Today). Add a comment on
   `readinessFingerprint` asserting readiness must depend only on presence, never expiry.

### Move heavy services to a backend server (consider later)
On-device is wrong for the compute-heavy / cost-bearing pieces. Candidates to move
server-side, with reasons:
- **AI recipe generation / "make it healthier" / tweak** — model cost + key safety +
  caching (can't ship API keys in the app; serverside lets us cache + rate-limit).
- **Recipe photo / painted-plate generation** — bundle this WITH custom-recipe parsing
  (paste a URL / text → structured Dish + a generated plate) as one ingestion service.
  Image gen is expensive + slow; do it once server-side, cache the asset, serve the URL.
- **Custom recipe parsing / import** — NLP + catalog mapping; benefits from the full
  catalog + shared improvements without an app update.
- **The catalog itself** — currently a 3.9MB bundled `catalog.json`. A server catalog
  means expansions/fixes ship without an app release (but breaks pure-offline; needs a
  bundled fallback + sync). Tension with offline ingredient-add (see below).
- **Consider also:** readiness/substitution compute if it grows; telemetry/crash
  aggregation; nutrition lookups; usage-based personalization/ranking for the feed.
**Open question to decide later:** the offline boundary — what MUST work with no network
(viewing saved recipes, pantry edits, cook mode) vs. what can require it (generation,
import). Decide the split before building. (Not now — capture only.)

### Require hand-painted plate art (validation) + drop the emoji fallback — weigh risks
Only ~5 dishes have bundled `Resources/PlateArt/*.png`; the other ~190 fall back to
emoji-on-plate. Idea: generate painted plates for ALL recipes (an AI-render pipeline —
belongs in the backend ingestion service above, NOT doable by text subagents) and make
"has plate art" a validation, removing the emoji fallback so the feed is uniformly rich.
**Risks:** generation cost/time for 200+; no fallback means a missing/failed render = a
blank tile (worse than emoji); offline new recipes would have no art until the server
paints them. Same idea for **ingredient art**, but riskier: a no-fallback rule removes
the ability to add an ingredient offline (you couldn't render its face) — likely keep a
fallback for ingredients even if recipes go strict. Decide per-surface.

### Load-bearing vs droppable ingredients (suggestion-framework enhancement)
Mark each recipe ingredient as **load-bearing** (the dish's identity — can't drop, maybe
can't swap beyond a very close sibling) vs **droppable** (e.g. "¼ tsp paprika" — fine to
omit). Then readiness/"can I make this" only blocks on missing *load-bearing* items; a
missing droppable one still reads as makeable (with a note). Sharpens the whole pantry
suggestion engine — missing a garnish ≠ can't cook. Needs: a per-line flag (default from
heuristics: tiny quantities / "to taste" / garnish verbs → droppable; the protein/the
defining sauce → load-bearing), surfaced in the editor + AI ingestion. **UI:** explorer —
readiness counts droppables as optional, so more dishes qualify as "make now"; recipe page
— droppable lines dimmed / marked "optional", load-bearing maybe bolded; cook mode — gather
screen separates "essential" from "optional/skip if short", and the swap chooser only
offers swaps for swappable lines. (From feed review — decide model + UI before building.)

### AI-generated recipe ideas in the feed (cost-gated — needs consideration)
The Today feed is currently powered by the **existing recipe library**, categorized
into lenses (`RedesignRootView.defaultRails` / `matches`). A richer "always fresh"
feed would **generate new recipe ideas on demand** via the AI service, tailored to the
pantry (what's on hand / expiring) and the active lens. Distinct from the 200-recipe
static seed (which gives breadth without per-view cost). **Cost is the open question:**
generating ideas on every feed view could massively increase operating cost — needs a
strategy before building (e.g. cache/precompute per day, generate only on explicit
"surprise me", cap per session, cheaper model for ideation). Decide the cost model
first. Layers onto the same feed UI; no UI rework needed. (From feed-redesign review.)

### Persistence — nothing survives a cold relaunch
The whole `KitchenStore` is in-memory only (see the seam comment at
`PantryChef/UI/Features/KitchenStore.swift` ~L190, "the single seam where real
persistence wires in later"). Stock, plans (`events`), the shopping list, and the
now-module state all reset to the seeded sample on relaunch. Consequence: e.g. a meal
cooked but not yet logged, or any logged change, is lost on a cold start. Wire real
persistence at that seam (Codable + disk, or SwiftData/CoreData).

### Decrement raw ingredients when cooking
Cooking *banks* the result (leftovers) but doesn't *consume* the raw ingredients it
used (e.g. cook a frittata → eggs/spinach aren't drawn down). Deferred as the hard
half of the decrement discussion: raw amounts are free-text (`.perishable` detail like
"300 g") with no structured quantity, so gram-level subtraction is unreliable. Needs a
structured quantity model first; until then cooking leaves readiness to the certainty
clock. (Eat-time draw-down of leftover *portions* is already done.)

### Family-tier swaps count toward readiness (currently chooser-only)
`CatalogSwaps` family tier (same trailing base word, e.g. almond milk ↔ milk) shows in
the recipe chooser but is **not** counted in the "ready · N swaps" readiness (only
curated + sibling are, to keep that badge trustworthy). Decide whether to widen the
auto-count to include family. Deferred when the substitution tiers landed.

### A "whole week at a glance" plan view
Busy weeks now read as day-grouped blocks in the timeline (good), but there's still no
single surface to see the whole week's plan at once. Deferred in favour of the grouping
fix; revisit if scanning the feed still feels like work.

### Reassign a planned meal to a different day
The meal sheet supports change-part (morning/midday/evening within the same day) and
remove, but not moving a plan to a *different day*. Deferred when remove/reassign landed.

### Procedural proposal generator (rebuy / run-out synthesis, density-capped)
The "Your list hit 5 items — milk runs out around Monday" invitation is currently a
hardcoded seed string (the spec's own example; milk isn't even in stock). Make it real:
a generator that synthesizes the list state + the nearest run-out into ONE invitation,
with density as a first-class constraint — aggregate (don't emit per-item), threshold +
require an action, rank and hard-cap (~1 in the visible window), respect dismissals,
and anchor to the consequence date. Distinct from per-item spoilage, which the expiry
diamonds already show. Two "runs out" senses: spoilage (food clock — have it) vs
depletion (rebuy rhythm — needs purchase history we don't track yet; spec's "rebuy
inference still TODO"). Easy first cut: list-count + soonest food-clock run-out.

### Cooked dishes appear under both Stores and Dishes (dedupe)
A made/leftover dish shows in Stores ("Made by you") *and* as a recipe in Dishes — reads
as duplication. Consider restricting cooked/leftover dishes to just the Dishes screen
(or otherwise disambiguating inventory-vs-recipe). Decision needed: leftovers-as-
inventory in Stores is useful, so weigh that against the redundancy. (From testing.)

### Substitution notes accessible during the cook
Swaps chosen on the recipe (and their notes, e.g. ratios / "same family as…") aren't
surfaced in the cook flow, so mid-cook users lose track of what they substituted and
why. Carry the applied swaps + notes into the cook instrument (gathering + steps).
(From testing.)

### Structured, numeric swap quantities (translatable units)
*Partly addressed:* the substitute's quantity guidance now rides through to the cook —
the swap note (e.g. "¼ cup applesauce per egg") shows on the gathering screen and on
the recipe's applied line (`RecipeLine.swapNote`). **Remaining:** that guidance is still
free-form prose; the catalog `ratio` is mostly "1:1" and the real quantities live in
notes. Make swap quantities **numeric in real, convertible units** so a swap can
actually adjust the gathered amount (not just annotate it). Needs the structured-
quantity model — shared with "decrement raw ingredients when cooking". (From testing.)

## Done

### Auto-log cooked food + log-from-recipe (done — `logCooked`)
Cooking is now *production*: finishing the instrument auto-banks the dish's servings
as leftovers + journals it (`KitchenStore.logCooked`), then returns to the fan where it
shows as ready-made — no extra tap. "Mark as made" on the recipe screen funnels into
the same op without walking the steps. Eating is logged separately (the eat-path
how-much-left draw-down). This also **resolved** the "Done card blocks the now slot"
item — there's no pending cook Done card anymore.
