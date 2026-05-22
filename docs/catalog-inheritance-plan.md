# Catalog Inheritance Model — Locked Plan

> Status: authoritative migration plan, aligned with current product decisions.

## Locked decisions

- Catalog items are classes in a DAG.
- `parentIds: [String]` replaces `parentId` / `secondaryParentIds`.
- Every class is instantiable (no `isAbstract`).
- Kind becomes subclass; state remains facets.
- State facet inheritance is additive.
- Matching core is ancestor containment + facet subsumption.
- Strict matching is a subset of loose matching.
- Search and pickers show abstract class + matching leaves.
- UI exposes state facets via progressive "Customize" disclosure.
- `catalog_families.json` is deleted.

## Kind vs state

Use one test: is this a **kind** of the ingredient, or a **state** of it?

- Kind -> subclass (`walnut` is a kind of `nut`, `cheddar` is a kind of `cheese`)
- State -> facet (`chopped`, `roasted`, `dried`, `fresh`)

Default mapping:

- Move to subclass space: `variant`, `base`, `concentration`, and most taxonomy-like values currently represented as facets.
- Keep as facets: `form`, `processing`, `preservation`, `preparation`.

## Schema target (`PantryChef/Resources/catalog.json`)

Each item keeps existing metadata and adopts:

```json
{
  "id": "walnut",
  "name": "walnut",
  "parentIds": ["nut"],
  "category": "Nuts & Seeds",
  "aliases": ["walnuts", "english walnut"],
  "facetAliases": [
    {
      "text": "chopped walnuts",
      "facets": [{ "key": "form", "value": "chopped" }]
    }
  ],
  "facets": [
    { "key": "form", "options": ["whole", "halved", "chopped"] },
    { "key": "processing", "options": ["raw", "roasted"] }
  ]
}
```

Remove from schema:

- `isGenericBase`
- `parentId`
- `parentFacets`
- `excludedFromGenericMatch`

## Runtime target

### `PantryCatalog` APIs

- `ancestors(of:) -> Set<String>`
- `descendants(of:) -> Set<String>`
- `inheritanceDistance(from:to:) -> Int?`
- `effectiveFacets(for:) -> [PantryFacetDefinition]`

Implementation notes:

- Build parent/child adjacency maps at index rebuild.
- Precompute transitive closure caches with cycle safety.
- Keep O(1) lookup maps by item id for hot paths.

### Matching model

Single core rule:

1. Pantry item class must be same as, or descendant of, required class.
2. Pantry facets must satisfy required non-`none` facets.

Strict path:

- Uses only structured identity/facets.

Loose path:

- Strict path first, then text/synonym fallback, then substitution fallback.
- Substitutions use descendants-aware checks, not exact-id-only checks.

## UI target

### State facets

- Hidden behind "Customize" across pantry add/edit and shopping add.
- Default is "no preference".
- Only render state facets in display names when explicitly chosen.

### Search disambiguation

- Do not collapse matches by catalog id when query matched different leaf classes.
- For abstract query (`nut`, `cheese`), show abstract class row and matched leaf rows.

### Surfaces to update

- `PantryChef/Views/Pantry/PantryView.swift`
- `PantryChef/ViewModels/PantryViewModel.swift`
- `PantryChef/Views/Shopping/ShoppingListView.swift`
- `PantryChef/Models/Recipe.swift`
- `PantryChef/Views/Settings/IngredientCatalogSettingsView.swift`

## Validation target (`Scripts/validate_catalog.py`)

- All `parentIds` must exist.
- No cycles in inheritance graph.
- Additive facet inheritance only (children may add options, not remove inherited options).
- Alias uniqueness maintained.
- Remove all family-based validation.

## Script target

- Add `Scripts/apply_inheritance_migration.py` (dry-run default).
- Update `Scripts/catalog_lib.py` with `ancestors_of` / `descendants_of`.
- Remove obsolete migration scripts:
  - `Scripts/apply_generic_specific_model.py`
  - `Scripts/apply_parent_child_pilot.py`

## Migration order

1. `nut`
2. `oil`
3. `cheese`
4. `beef`
5. `rice`, `flour`, `broth`, `pasta`, `bread`, `sugar`, `cream`, `yogurt`, `milk`, `pork`, `lamb`, `turkey`, `fish`, `shrimp`, `mushroom`, `potato`, `onion`, `pepper`, `tomato`, `beans`, `cured-meat`

For each family:

- Expand kind facets into subclass rows where needed.
- Reuse existing ids where they already exist.
- Move kind-specific aliases to child classes.
- Keep bare aliases on parent class.
- Drop kind facet from parent class.

## Data updates

- Migrate `PantryChef/Resources/seed_recipes.json` and `Recipe.samples`:
  - replace `catalogItemID + variant facet` with subclass `catalogItemID`
  - remove migrated kind facets from ingredient facet sets
- Delete `PantryChef/Resources/catalog_families.json`.

## Tests

- Replace canonical-identity tests with inheritance tests:
  - ancestor/descendant closure
  - multi-parent traversal
  - cycle handling
  - strict/loose matching behavior
  - additive facet inheritance
- Update matching/resolution tests to new ids.
- Keep existing performance baselines and verify no regressions.

## Execution checklist

1. Rewrite docs (`catalog-model.md`, this file).
2. Implement schema/runtime/matcher changes.
3. Rewrite validation/catalog-lib.
4. Add migration script.
5. Run nut migration + verify.
6. Run oil/cheese migration + verify.
7. Run remaining families + verify.
8. Migrate seeds/samples.
9. Remove obsolete files.
10. Run test suite and perf checks.
