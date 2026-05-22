# Ingredient Catalog Pipeline

How to maintain and validate the PantryChef ingredient catalog.

## File Layout

```
Scripts/
  compile_catalog.py              ← catalog.source.json → catalog.json
  rebuild_catalog_source.py       ← repair flat catalog + rebuild source + recompile
  catalog_source_lib.py           ← source schema, repair, compile helpers
  validate_catalog.py             ← catalog integrity checks (flat or --source)
  catalog_lib.py                  ← shared helpers for catalog scripts
  apply_inheritance_migration.py  ← legacy variant→subclass migration (historical)
  apply_catalog_audit.py          ← bulk catalog fixes / migrations
  analyze_corpus_ingredients.py   ← corpus coverage analysis (RecipeNLG)
  triage_output/                  ← corpus analysis reports (generated)
PantryChef/
  Resources/
    catalog.source.json           ← authoritative authoring format (trees + multiInheritance)
    catalog.json                  ← compiled flat catalog loaded by the app
  Models/
    PantryCatalog.swift           ← loads catalog.json + inheritance graph
```

## Production Catalog

**`catalog.source.json` is the source of truth.** The app loads the compiled `catalog.json` at launch via `PantryCatalog.allItems`.

### Workflow

```bash
# Normal edit cycle
# 1. Edit PantryChef/Resources/catalog.source.json
# 2. Compile
python3 Scripts/compile_catalog.py

# 3. Validate before commit
python3 Scripts/validate_catalog.py
python3 Scripts/validate_catalog.py --source   # validates via compile

# Repair pass (split bad shared nodes, fix homonyms, rebuild source)
python3 Scripts/rebuild_catalog_source.py --write-source --write-catalog
```

Each compiled entry needs:

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Kebab-case, unique (e.g. `"my-new-ingredient"`) |
| `name` | string | Display name |
| `category` | string | Must match a `FoodCategory` rawValue |
| `parentIds` | [string]? | Omitted for roots; one parent for tree items; ≥2 for multi-inheritance |
| `defaultUnit` | string? | A `MeasurementUnit` rawValue |
| `defaultQuantity` | number? | Typical purchase quantity |
| `defaultStorage` | string | `"Pantry"`, `"Refrigerated"`, or `"Frozen"` |
| `aliases` | [string] | Alternative names, regional variants, plurals |
| `facets` | [object] | Facet dimensions — see below |
| `defaultSelections` | [object] | One `{ key, value }` per facet for the most common variant |
| `freshnessByStorage` | object | `{ "Pantry": [min, max], ... }` — shelf life in days |

### Source format (authoring)

- **`trees[]`**: single-inheritance roots with nested `children[]` (sparse overrides).
- **`multiInheritance[]`**: rare cross-taxonomy items with `parentIds: [≥2]` and full leaf definitions.

See [`docs/catalog-model.md`](../docs/catalog-model.md) for schema details and examples.

**Valid categories** (18 total):
Alcohol & Spirits, Baking & Sweeteners, Beverages, Breads & Bakery, Canned & Jarred, Condiments & Sauces, Dairy & Eggs, Frozen Foods, Grains & Cereals, Legumes & Beans, Nuts & Seeds, Oils & Fats, Other, Pasta & Noodles, Produce, Protein, Snacks, Spices & Herbs

**Facet keys** (use only what applies — most items need 2–4):

| Key | Use for | Example |
|-----|---------|---------|
| `color` | Color (produce) | pepper: green, red, yellow |
| `variant` | Transitional kind facet during migration | prefer subclasses instead |
| `form` | Physical form | cheese: block, shredded, sliced |
| `preservation` | Storage method | fresh, frozen, dried, canned |
| `processing` | How it was processed | raw, roasted, smoked, cured |
| `preparation` | Pre-cooking prep | shelled, peeled, hulled |
| `texture` | Texture descriptor | creamy, chunky, smooth |
| `concentration` | Strength/dilution | regular, concentrated, lite |
| `base` | Base ingredient | cured-meat: pork, beef, turkey |

## Catalog validation

Run before committing catalog changes:

```bash
python3 Scripts/validate_catalog.py
python3 Scripts/validate_catalog.py --source
python3 Scripts/validate_catalog.py --strict   # warnings → errors
python3 Scripts/validate_catalog.py --json     # machine-readable
```

Checks include:
- Parent links and inheritance cycles
- Additive facet inheritance (single-parent items)
- Multi-inheritance completeness
- Facet-alias validity in effective hierarchy
- Required fields and duplicate IDs

## Corpus Coverage Analysis

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

## Historical migration

`apply_inheritance_migration.py` was used for the initial variant→subclass migration. Ongoing edits should use `catalog.source.json` + `compile_catalog.py`. See git history for retired staging pipelines.
