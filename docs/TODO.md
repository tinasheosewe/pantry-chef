# PantryChef — running TODO

Deferred work and decisions, flagged as they come up. Newest context at the bottom of
each item.

## Open

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

### Structured, numeric swap quantities (translatable units) in the gathering screen
Substitutes can change the amount, but the swap `ratio` is a free-form string ("1:1").
Make quantity changes **numeric in real, convertible units** (not free text) so a swap
can adjust the gathered amount, and show the adjusted quantity on the ingredient-
gathering (mise en place) screen. Pairs with the structured-quantity model the
"decrement raw ingredients" item also needs. (From testing.)

## Done

### Auto-log cooked food + log-from-recipe (done — `logCooked`)
Cooking is now *production*: finishing the instrument auto-banks the dish's servings
as leftovers + journals it (`KitchenStore.logCooked`), then returns to the fan where it
shows as ready-made — no extra tap. "Mark as made" on the recipe screen funnels into
the same op without walking the steps. Eating is logged separately (the eat-path
how-much-left draw-down). This also **resolved** the "Done card blocks the now slot"
item — there's no pending cook Done card anymore.
