# Ingredient Catalog Pipeline

How to maintain and validate the PantryChef ingredient catalog.

## File Layout

```
Scripts/
  apply_catalog_audit.py          ← bulk catalog fixes / migrations
  apply_coverage_phase12.py       ← phase 1+2 coverage + generic oil/nut
  apply_inheritance_migration.py  ← kind facet -> subclass migration
  validate_catalog.py             ← reusable catalog integrity checks
  catalog_lib.py                  ← shared helpers for catalog scripts
  analyze_corpus_ingredients.py   ← corpus coverage analysis (RecipeNLG)
  triage_output/                  ← corpus analysis reports (generated)
PantryChef/
  Resources/
    catalog.json                  ← production catalog loaded by the app
  Models/
    PantryCatalog.swift           ← loads catalog.json + inheritance graph
    Enums.swift                ← FoodCategory, MeasurementUnit, etc.
```

## Production Catalog

`PantryChef/Resources/catalog.json` is the single source of truth. The app loads it at launch via `PantryCatalog.allItems`. Edit it directly, or use `apply_catalog_audit.py` for scripted bulk changes.

Each entry needs:

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Kebab-case, unique (e.g. `"my-new-ingredient"`) |
| `name` | string | Display name |
| `category` | string | Must match a `FoodCategory` rawValue |
| `defaultUnit` | string? | A `MeasurementUnit` rawValue |
| `defaultQuantity` | number? | Typical purchase quantity |
| `defaultStorage` | string | `"Pantry"`, `"Refrigerated"`, or `"Frozen"` |
| `aliases` | [string] | Alternative names, regional variants, plurals |
| `facets` | [object] | Facet dimensions — see below |
| `defaultSelections` | [object] | One `{ key, value }` per facet for the most common variant |
| `freshnessByStorage` | object | `{ "Pantry": [min, max], ... }` — shelf life in days |

**Valid categories** (18 total):
Alcohol & Spirits, Baking & Sweeteners, Beverages, Breads & Bakery, Canned & Jarred, Condiments & Sauces, Dairy & Eggs, Frozen Foods, Grains & Cereals, Legumes & Beans, Nuts & Seeds, Oils & Fats, Other, Pasta & Noodles, Produce, Protein, Snacks, Spices & Herbs

**Facet keys** (use only what applies — most items need 2–4):

| Key | Use for | Example |
|-----|---------|---------|
| `color` | Color (produce) | pepper: green, red, yellow |
| `variant` | Transitional kind facet during migration | moved to subclasses |
| `form` | Physical form | cheese: block, shredded, sliced |
| `preservation` | Storage method | fresh, frozen, dried, canned |
| `processing` | How it was processed | raw, roasted, smoked, cured |
| `preparation` | Pre-cooking prep | shelled, peeled, hulled |
| `texture` | Texture descriptor | creamy, chunky, smooth |
| `concentration` | Strength/dilution | regular, concentrated, lite |
| `base` | Base ingredient | cured-meat: pork, beef, turkey |

## Adding or Editing Items

1. Edit `PantryChef/Resources/catalog.json` directly (keep entries sorted by `id`).
2. Build and run the app — the catalog reloads from the bundle at launch.

For bulk migrations (merges, renames, facet consolidation), add a script like `apply_catalog_audit.py` or `apply_coverage_phase12.py` rather than hand-editing hundreds of entries.

## Inheritance migration

Run migration in dry-run mode first:

```bash
python3 PantryChef/Scripts/apply_inheritance_migration.py --families nut
python3 PantryChef/Scripts/apply_inheritance_migration.py --families nut --write
```

For full migration order:

```bash
python3 PantryChef/Scripts/apply_inheritance_migration.py --all --write
```

## Catalog validation

Run before committing catalog changes:

```bash
python3 PantryChef/Scripts/validate_catalog.py
python3 PantryChef/Scripts/validate_catalog.py --strict   # warnings → errors
python3 PantryChef/Scripts/validate_catalog.py --json       # machine-readable
```

Checks include:
- Parent links and inheritance cycles
- Additive facet inheritance constraints
- Facet-alias validity in effective hierarchy
- Required fields and duplicate IDs

## Corpus Coverage Analysis

Measure how well the catalog covers real recipe ingredients using the RecipeNLG dataset:

```bash
python3 Scripts/analyze_corpus_ingredients.py [--top N] [--min-count N]
```

Output files (in `Scripts/triage_output/`):

| File | Contents |
|------|----------|
| `corpus_frequency.json` | All normalized ingredients ranked by frequency |
| `corpus_gaps.json` | Frequent ingredients missing from catalog |
| `corpus_alias_candidates.json` | Potential new aliases for existing entries |
| `corpus_coverage_report.txt` | Summary statistics |
| `corpus_facet_covered.json` | Partial matches resolved via facets |
| `corpus_facet_gaps.json` | Partial matches with missing facet options |
| `corpus_true_gaps.json` | Ingredients with no catalog match |

## Bulk Enrichment (Historical)

The original staging pipeline (`bases_by_aisle.json` → `enriched_catalog.json` → `publish_catalog.py`) has been retired. The enriched catalog is now maintained directly in `catalog.json`. See git history (e.g. commit `ff18807`) for the original GPT batch enrichment script if needed.
