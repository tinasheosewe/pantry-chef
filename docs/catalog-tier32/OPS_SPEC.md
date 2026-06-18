# Tier 3 / Tier 2 catalog edit ops

You are turning your category's audit (`docs/catalog-audit/<category>.json`) into a
**structured list of edit operations** that a central applier will run against
`PantryChef/Resources/catalog.json` (a flat JSON array of item objects). You do **not**
edit the catalog or app code yourself — you only emit ops.

Output ONE file: `docs/catalog-tier32/<category>.json`, shape:

```json
{
  "category": "<exact FoodCategory display name>",
  "structural": [ <op>, ... ],   // Tier 3: re-parenting, re-homing, merges, re-ids, renames, storage/freshness bugs
  "cleanups":   [ <op>, ... ]    // Tier 2: dietary mis-tags, allergen fixes, alias leaks, small data fixes
}
```

Apply order is: ALL agents' `structural` first (validated + committed), then ALL `cleanups`.
So put anything that changes identity/shape/parentage in `structural`, and pure
data-quality fixes in `cleanups`.

## Allowed ops (each targets an existing item by `id`)

- `{"op":"reparent","id":"grape","parentIds":["fruit"]}` — replace parentIds (use `[]` to make it a root).
- `{"op":"recategorize","id":"thai-basil","category":"Produce"}` — move to another category.
- `{"op":"setStorage","id":"...","defaultStorage":"Pantry|Refrigerated|Frozen"}`
- `{"op":"setFreshness","id":"...","freshnessByStorage":{"Refrigerated":[5,7],"Frozen":[180,365]}}`
- `{"op":"setDietaryTags","id":"...","dietaryTags":["Vegan","Gluten-Free",...]}` — full replacement list.
- `{"op":"setAllergens","id":"...","allergens":["gluten",...]}` — full replacement list.
- `{"op":"rename","id":"...","name":"<lowercase name>"}`
- `{"op":"addAlias","id":"...","alias":"..."}` / `{"op":"removeAlias","id":"...","alias":"..."}`
- `{"op":"merge","from":"A","into":"B"}` — fold redundant A into B: B gains A's name+aliases as
  aliases, every item's parentIds/swaps pointing at A are redirected to B, then A is removed.
  Use for `redundancies` (true duplicates). Pick the better-named/canonical id as `into`.
- `{"op":"reid","from":"old-id","to":"new-id"}` — rename an id (fixes a mangled/misleading id);
  repoints all parentIds/swaps references.
- `{"op":"drop","id":"..."}` — remove a bogus item; references are pruned. Use sparingly.

Optional `"note":"why"` on any op (kept for the diff log, ignored by the applier).

## Hard rules (the applier validates and will reject violations)

- Vocab must be exact:
  - category ∈ {Alcohol & Spirits, Baking & Sweeteners, Beverages, Breads & Bakery,
    Canned & Jarred, Condiments & Sauces, Dairy & Eggs, Frozen Foods, Grains & Cereals,
    Legumes & Beans, Nuts & Seeds, Oils & Fats, Other, Pasta & Noodles, Produce, Protein,
    Snacks, Spices & Herbs}
  - storage ∈ {Pantry, Refrigerated, Frozen}
  - allergens ⊆ {dairy, egg, gluten, peanut, tree-nut, soy, shellfish, fish, sesame}
  - dietaryTags ⊆ {Vegetarian, Vegan, Gluten-Free, Dairy-Free, Nut-Free, Low Carb,
    High Protein, Keto, Paleo, Pescatarian, Halal, Kosher}
- **Do NOT deprecate or empty the "Frozen Foods" category.** Frozen items stay in Frozen Foods
  and are fixed in place. (Storage is a separate axis; the category is being kept on purpose.)
- allergens must agree with dietaryTags (no Vegan+dairy/egg, no Gluten-Free+gluten,
  no Nut-Free+tree-nut/peanut, no Vegetarian/Vegan+fish/shellfish).
- A facet value lives under exactly one facet key catalog-wide — don't introduce a value under
  a new key. (If your audit wants a facet change, prefer setDietaryTags/setAllergens/rename;
  avoid facet edits unless clearly necessary.)
- `merge`/`drop`/`reid` must never leave a dangling reference — the applier repoints/prunes,
  but choose `into`/`to` targets that exist (or are created by another structural op).
- Every `id` you reference must already exist in catalog.json (read it to confirm). Skip audit
  suggestions whose target id isn't in the live catalog, and note that in the op's `note`.

## Method

1. Read `docs/catalog-audit/<category>.json` — work its `issues` + `redundancies` as `structural`,
   and its `cleanups` (+ any dietary/allergen/alias fixes) as `cleanups`.
2. For each, confirm the target id exists in `PantryChef/Resources/catalog.json` and that your op
   is correct against the live data (don't trust the audit blindly — verify the bug still exists).
3. Emit the ops file. Validate it is valid JSON. Report counts of structural vs cleanup ops and
   any audit items you skipped (with reason).
