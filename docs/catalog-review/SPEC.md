# Catalog quality review — mis-resolution & search hygiene

The "pulled BBQ jackfruit" bug (a recipe's "canned tomatoes" resolved to a jackfruit
variant) exposed catalog items that the name/alias resolver mis-matches. Your job: find
items IN YOUR CATEGORY that would cause a common ingredient to resolve to the wrong thing,
or that pollute search, and emit fixes as edit ops.

Read `PantryChef/Resources/catalog.json` (a flat array of items: id, name, category,
parentIds, aliases, …) and emit `docs/catalog-review/<category>.json` using the SAME op
schema as `docs/catalog-tier32/OPS_SPEC.md` (read it for the exact op shapes + hard rules):
`{ "category": "<display name>", "structural": [ <ops> ], "cleanups": [ <ops> ] }`.

## What to look for (only emit an op when you've verified it against the live data)
- **Ambiguous / bare-token names** — an item NAMED a bare modifier or generic fragment
  ("ripe", "young", "mixed", "original", "pearl", "long grain", "whole", "light") that will
  exact-match an unrelated ingredient query. Fix with `rename` to the full specific name
  (and `reid` if the id is just as bare), e.g. name "ripe" → "canned ripe jackfruit".
- **Over-broad / wrong aliases** — an alias that matches a DIFFERENT common ingredient
  (e.g. a jackfruit item aliased "canned tomatoes", a vinegar aliased "red wine"). `removeAlias`.
- **Wrong parentage** — item parented to an unrelated base (a real defect, not a nuance).
  `reparent`.
- **True duplicates** — two items that are the same thing. `merge` the lesser into the better.
- **Mis-category** — clearly in the wrong FoodCategory. `recategorize`.

Be conservative: a real, specific name that happens to be short (e.g. "cod", "egg") is FINE.
Don't touch items that are already clear and correctly placed. Don't deprecate "Frozen Foods".
Verify every id you reference exists. Put identity/shape changes in `structural`, alias/name
tidy-ups in `cleanups`. Report counts + the notable fixes; flag anything you're unsure about
rather than guessing.
