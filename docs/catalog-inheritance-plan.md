# Catalog Inheritance Model — Locked Plan

> **Note (5 October 2026):** a plan from 22 May 2026, kept as the record of that decision.
> Two later changes: the June remodel turned about 690 subclass rows back into facet values (`docs/catalog-remodel-spec.md`), and the source file is no longer authoritative: `catalog.json` has been edited directly since 18 June 2026 (`Scripts/README.md`). The "Customize" disclosure and the catalog tree view listed below belonged to the earlier interface and were removed with it.

> Status: implemented. Source format is authoritative; `catalog.json` is compiled output.

## Locked decisions

- Catalog items are classes in an inheritance graph.
- **Single inheritance**: parent owns `children[]` in `catalog.source.json`; compiled as `parentIds: [one-parent]`.
- **Multi inheritance** (rare): item owns `parentIds: [≥2]` + complete leaf definition in `multiInheritance[]`; matching-only, no facet inheritance.
- Every class is instantiable (no `isAbstract`).
- Kind becomes subclass; state remains facets.
- Single-parent facet inheritance is additive.
- Multi-parent items use leaf-only facets at runtime.
- Matching core is ancestor containment + facet subsumption.
- Strict matching is a subset of loose matching.
- Search and pickers show abstract class + matching leaves.
- UI exposes state facets via progressive "Customize" disclosure.
- `catalog_families.json` is deleted.

## Kind vs state

Use one test: is this a **kind** of the ingredient, or a **state** of it?

- Kind → subclass (`walnut` is a kind of `nut`, `greek` is a kind of `yogurt`)
- State → facet (`chopped`, `roasted`, `dried`, `fresh`)

Default mapping:

- Move to subclass space: `variant`, `base`, `concentration`, and most taxonomy-like values currently represented as facets.
- Keep as facets: `form`, `processing`, `preservation`, `preparation`.

## What is NOT multi-inheritance

- Homonyms: `almond`, `almond-oil`, `almond-flour` are distinct products.
- Shared cut names scoped per animal: `chicken-breast`, `beef-shank`, `turkey-thigh` — not one `breast` node with multiple parents.
- Color/modifier pollution: `red`, `yellow`, `spicy` split into scoped subclasses (`onion-red`, `pepper-red`, …).

## True multi-inheritance examples

- `tomato-sauce` → `parentIds: ["sauce", "tomato"]`
- `soy-sauce` → `parentIds: ["sauce", "soy"]`
- `chicken-broth` → `parentIds: ["broth", "chicken"]`
- `coconut-milk` → `parentIds: ["coconut", "non-dairy-milk"]`

## Source format target

See [`catalog-model.md`](catalog-model.md) for full schema. Key files:

| File | Purpose |
|------|---------|
| `PantryChef/Resources/catalog.source.json` | Authoring (trees + multiInheritance) |
| `PantryChef/Resources/catalog.json` | Compiled flat catalog for app |
| `Scripts/catalog_source_lib.py` | Repair, flat↔source conversion, compile |
| `Scripts/compile_catalog.py` | Source → flat |
| `Scripts/rebuild_catalog_source.py` | Repair flat + rebuild source + recompile |
| `Scripts/validate_catalog.py` | Integrity checks (flat or `--source`) |

## Runtime target

### `PantryCatalog` APIs

- `ancestors(of:) -> Set<String>`
- `descendants(of:) -> Set<String>`
- `inheritanceDistance(from:to:) -> Int?`
- `effectiveFacets(for:) -> [PantryFacetDefinition]` — leaf-only for multi-parent items

### Matching model

1. Pantry item class must be same as, or descendant of, required class.
2. Pantry facets must satisfy required non-`none` facets.

## UI target (future)

- State facets hidden behind "Customize"; default is no preference.
- Search disambiguation: do not collapse matches when query hit different leaf classes.
- Surfaces: PantryView, PantryViewModel, ShoppingListView, IngredientCatalogSettingsView.

## Execution checklist

- [x] Rewrite docs (`catalog-model.md`, this file)
- [x] Implement schema/runtime/matcher changes
- [x] Rewrite validation/catalog-lib
- [x] Add source format + compile/rebuild scripts
- [x] Audit and repair multi-parent pollution (~384 → 20 true multi-inheritance items)
- [x] Split shared cut/modifier nodes
- [x] Migrate seeds/samples to scoped IDs
- [x] Remove `catalog_families.json`
- [x] Run inheritance + resolution tests
- [ ] UI: progressive Customize facets, search disambiguation, catalog tree settings view
