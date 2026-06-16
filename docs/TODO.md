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

### Now-module: a cooked "Done" card blocks the now slot until resolved
After finishing a cook, the now-module sits in `.cooked` showing the Done card
(Dismiss / Log) and stays there until the user dismisses or logs — so the fan / plan
lead aren't reachable in the meantime. Decide whether the now-module should fall back
to the fan while keeping a pending-cook handle elsewhere.
*May be subsumed by the "auto-log cooked food" decision below.*

## Under discussion (not yet decided)

### Auto-log cooked food (lean: yes)
Idea: finishing a cook should **auto-log into the store** (bank the yield as
leftovers + record it), with no extra tap — you already clicked through the steps.
Then "log" in the fan would mean **eating only** (the how-much-left draw-down). This
splits *production* (cooking → auto-bank) from *consumption* (eating → logged), and
would also resolve the "Done card blocks the now slot" item above (cook → auto-bank →
back to the fan, where the dish shows as ready-made to eat). Would remove the
finish-cooking → "how much is left?" prompt (consumption moves entirely to the eat path).

### Log a recipe directly from the recipe (lean: yes)
A "log as cooked / mark as made" action on the recipe screen, without walking the
step-by-step cook instrument — funnels into the same auto-log (journal + bank) as
finishing a cook.
