# Recipe ingredient essentiality classification

Goal: realize the product model "CORE ingredients are essential; everything else is
skippable." Today every seed ingredient defaults to essential, so readiness barely uses
the load-bearing feature. This pass marks the genuinely *optional* (droppable) lines per
recipe, so more dishes read "make now" — WITHOUT ever falsely claiming a dish is makeable
when a defining ingredient is missing.

You classify a contiguous slice of recipes in `PantryChef/Resources/seed_recipes.json`
(a `{ "recipes": [ {name, ingredients:[{name, amount, staple, ...}], ...} ] }` array).

## The rule

For each ingredient, decide **optional** (droppable) vs **essential** (core):

- **ESSENTIAL (leave it)** — the dish is not itself without it:
  - the protein(s): chicken, beef, salmon, tofu, eggs, beans-as-the-main, etc.
  - the defining starch/base: the pasta, rice, tortilla, bread, noodles, gnocchi, oats…
  - the primary vegetable(s) a dish is built on (mushrooms in mushroom risotto, spinach
    in palak paneer, eggplant in pasta alla norma)
  - the defining sauce / dairy / flavour base (curry paste, miso, coconut milk, the cheese
    in mac & cheese, passata in a tomato sauce)
  - anything whose removal makes it a different dish

- **OPTIONAL (mark it)** — recognisably the same dish without it:
  - garnishes & finishes: fresh herbs to serve, sesame seeds, spring-onion/scallion
    garnish, a lime wedge, chilli flakes, a drizzle of oil to finish, grated cheese on top
  - "to taste" / "to serve" / "for garnish" items
  - optional add-ins and secondary toppings (avocado, sour cream, toasted nuts, a side
    pickle, extra veg that's clearly a bonus)
  - decorative/serving items

Be moderately generous toward optional (the point is more make-now), but **never** mark a
protein, the base starch, the primary vegetable, or the defining sauce optional, and
**never** mark every ingredient in a recipe optional — each recipe must keep its core.
Staples (those with `staple: true`) can be judged the same way (most seasonings are
"to taste" → optional); it won't change readiness but keeps labels honest.

## Output

Write `docs/recipe-essentiality/chunk-<START>.json` (START = your slice's first index):

```json
{ "recipes": [
    { "name": "<exact recipe name>", "index": <recipe index in the file>,
      "count": <number of ingredients>,
      "optional": [ { "i": <0-based ingredient index>, "name": "<exact ingredient name>" }, ... ] }
] }
```

Include EVERY recipe in your slice (even if `optional` is empty). The `i` index and `name`
must both come from the live file so the integrator can cross-check. Validate it parses.
Report: recipes done, total optional marks, and any recipe where you marked 0 optional
(and why).
