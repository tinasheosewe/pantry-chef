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

## Done

### Auto-log cooked food + log-from-recipe (done — `logCooked`)
Cooking is now *production*: finishing the instrument auto-banks the dish's servings
as leftovers + journals it (`KitchenStore.logCooked`), then returns to the fan where it
shows as ready-made — no extra tap. "Mark as made" on the recipe screen funnels into
the same op without walking the steps. Eating is logged separately (the eat-path
how-much-left draw-down). This also **resolved** the "Done card blocks the now slot"
item — there's no pending cook Done card anymore.
