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

## Done

### Auto-log cooked food + log-from-recipe (done — `logCooked`)
Cooking is now *production*: finishing the instrument auto-banks the dish's servings
as leftovers + journals it (`KitchenStore.logCooked`), then returns to the fan where it
shows as ready-made — no extra tap. "Mark as made" on the recipe screen funnels into
the same op without walking the steps. Eating is logged separately (the eat-path
how-much-left draw-down). This also **resolved** the "Done card blocks the now slot"
item — there's no pending cook Done card anymore.
