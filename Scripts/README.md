# Ingredient Catalog Scripts

Python scripts that built and reshaped the ingredient catalog. Read this before running any of them: several write `catalog.json` in place.

## Current state

- `PantryChef/Resources/catalog.json` is the catalog the app loads, and it is the file that is edited. It holds 2,888 items.
- `PantryChef/Resources/catalog.source.json` is the tree-shaped authoring format the catalog was compiled from until June 2026. It is behind `catalog.json`: it compiles to 2,277 items. The passes of 18 June 2026 (new items, enrichment, structural fixes and cleanups) were applied to `catalog.json` directly by `tools/integrate_enrich.py`, `tools/fix_invariants.py` and `tools/apply_ops.py`, with their inputs under `docs/catalog-*`.
- The checks that hold for the current catalog are the Swift tests `CatalogInvariantTests` and `SeedDishCatalogTests`, which run against the file the app loads.

## File layout

```
Scripts/
  validate_catalog.py             ← catalog integrity checks (read-only)
  find_duplicate_facets.py        ← lists facet values that sit under two keys of one item (read-only)
  analyze_facet_duplicates.py     ← groups those duplicates by category (read-only)
  analyze_corpus_ingredients.py   ← corpus coverage analysis against a local RecipeNLG copy
  catalog_lib.py                  ← shared helpers
  catalog_source_lib.py           ← source schema, repair, compile helpers
  compile_catalog.py              ← catalog.source.json → catalog.json (refuses to shrink it)
  rebuild_catalog_source.py       ← repairs catalog.json in place, rebuilds the source, recompiles
  catalog_llm_validator.py        ← name/alias/semantic review of the source, optionally with an LLM
  deduplicate_facets.py           ← removes duplicate facet values; writes catalog.json
  apply_inheritance_migration.py  ← variant→subclass migration from May 2026 (dry run unless --write)
  remodel/                        ← the one-time June 2026 remodel (see remodel/README.md)
  ci/                             ← test runner and coverage gate used by CI
```

## Read-only checks

```bash
python3 Scripts/validate_catalog.py            # the bundled catalog.json
python3 Scripts/validate_catalog.py --source   # catalog.source.json, via compile
python3 Scripts/validate_catalog.py --strict   # warnings → errors
python3 Scripts/validate_catalog.py --json     # machine-readable
python3 Scripts/find_duplicate_facets.py
```

`validate_catalog.py` checks parent links and inheritance cycles, additive facet inheritance, multi-inheritance completeness, facet aliases, facet keys and orthogonality, required fields, duplicate and self aliases, bare modifier ids and a shelf-life range for each item's default storage.

Its rules were written for the compiled output and predate the June passes. Against the bundled `catalog.json` it reports 686 errors and 1,341 warnings: 655 `non_additive_facet_override` (it compares the facet lists as written, where the app computes inherited facets when it loads the file) and 31 `missing_freshness_for_default_storage`.

## Scripts that write the catalog

- `compile_catalog.py` recompiles `catalog.json` from the source and re-derives density, allergens, dietary tags and substitutions. Because the source is behind, it stops when the result would have fewer items than the existing file; `--force` overrides that and discards the direct edits.
- `rebuild_catalog_source.py` runs a repair pass over `catalog.json` and saves it, even with no flags. `--write-source` regenerates the source from the flat file and `--write-catalog` recompiles, without the enrichment step.
- `catalog_llm_validator.py --apply` edits the source and then runs `compile_catalog.py`.
- `deduplicate_facets.py` rewrites `catalog.json` on every run.
- `apply_inheritance_migration.py --write` and the `remodel/` scripts with `--apply` are migrations that have already been applied.

To bring the source back in step with the catalog, the source format would first have to carry what the June passes changed (edited allergens, dietary tags and substitutions are re-derived by `compile_catalog.py`, not read from the source).

## Catalog entry fields

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Kebab-case, unique (e.g. `"my-new-ingredient"`) |
| `name` | string | Display name |
| `category` | string | Must match a `FoodCategory` rawValue |
| `parentIds` | [string] | Empty for roots; one parent for tree items; two or more for multi-inheritance |
| `defaultUnit` | string? | A `MeasurementUnit` rawValue |
| `defaultQuantity` | number? | Typical purchase quantity |
| `defaultStorage` | string | `"Pantry"`, `"Refrigerated"`, or `"Frozen"` |
| `aliases` | [string] | Alternative names, regional variants, plurals |
| `facets` | [object] | Facet dimensions, see below |
| `defaultSelections` | [object] | One `{ key, value }` per facet for the most common variant |
| `facetAliases` | [object] | Phrases that select facet values (`"skim milk"` → `fat: skim`) |
| `freshnessByStorage` | object | `{ "Pantry": [min, max], ... }`, shelf life in days |
| `gramsPerCup`, `gramsPerPiece` | number? | Density and piece weight for unit conversion |
| `allergens`, `dietaryTags` | [string] | From the `Allergen` and `DietaryTag` enums |
| `swaps` | [object] | Curated substitutions: `{ substituteItemID, ratio, notes }` |

**Valid categories** (18 total):
Alcohol & Spirits, Baking & Sweeteners, Beverages, Breads & Bakery, Canned & Jarred, Condiments & Sauces, Dairy & Eggs, Frozen Foods, Grains & Cereals, Legumes & Beans, Nuts & Seeds, Oils & Fats, Other, Pasta & Noodles, Produce, Protein, Snacks, Spices & Herbs

**Facet keys** (ten, from `PantryFacetKey`; most items use two to four):

| Key | Use for | Example |
|-----|---------|---------|
| `color` | Visible color | pepper: green, red, yellow |
| `variant` | Named style, cultivar, flavor or region | pasta: penne |
| `grade` | Intensity, strength or diet grade | cheddar: mild, sharp |
| `fat` | Dairy fat level | milk: skim |
| `form` | Physical or market form | cumin: ground, whole |
| `preparation` | Knife or prep state | sliced, diced, peeled |
| `preservation` | How it is kept | fresh, frozen, dried, canned |
| `processing` | Treatment or cooking | raw, roasted, smoked |
| `texture` | Consistency | creamy, chunky, smooth |
| `medium` | Packing or cooking liquid | in water, in oil, in brine |

See [`docs/catalog-model.md`](../docs/catalog-model.md) for the model and [`docs/catalog-remodel-spec.md`](../docs/catalog-remodel-spec.md) for the reasoning behind it.

## Corpus coverage analysis

```bash
python3 Scripts/analyze_corpus_ingredients.py [--top N] [--min-count N] [--dataset PATH]
```

Counts the ingredient names in a local copy of the RecipeNLG dataset (default path `RecipeNLG/RecipeNLG_dataset.csv` at the repository root) and compares them with the catalog: coverage by mention, frequent names the catalog lacks, alias candidates. RecipeNLG is distributed by Poznań University of Technology for non-commercial research and educational use and has to be requested from them; neither the dataset nor the output of this script is kept in the repository. The script writes to `Scripts/triage_output/`, which is git-ignored.
