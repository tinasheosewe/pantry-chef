# Ingredient Catalog Pipeline

How to maintain and validate the PantryChef ingredient catalog.

## File Layout

```
Scripts/
  apply_catalog_audit.py          ← bulk catalog fixes / migrations
  apply_coverage_phase12.py       ← phase 1+2 coverage + generic oil/nut
  apply_generic_specific_model.py ← generic↔specific families, alias hygiene
  validate_catalog.py             ← reusable catalog integrity checks
  catalog_lib.py                  ← shared helpers for catalog scripts
  analyze_corpus_ingredients.py   ← corpus coverage analysis (RecipeNLG)
  triage_output/                  ← corpus analysis reports (generated)
PantryChef/
  Resources/
    catalog.json                  ← production catalog loaded by the app
    catalog_families.json         ← generic↔specific family definitions
  Models/
    PantryCatalog.swift           ← loads catalog.json + catalog_families.json
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
| `variant` | Types/varieties/species/cuts | beef: ground, sirloin, ribeye |
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

## Generic cooking oil

Recipes often list bare **"oil"**, **"neutral oil"**, or **"cooking oil"** without specifying a type. The catalog handles this with:

1. **`oil` catalog entry** — catches bare oil in corpus matching; default variant is `vegetable`.
2. **Specific `-oil` entries kept** — `olive-oil`, `vegetable-oil`, etc. for explicit mentions.
3. **Pantry matching** — a recipe requiring generic `oil` matches any specific cooking oil in the pantry (`PantryCatalog.satisfyingCookingOilCatalogItemIDs`). A recipe requiring `oil` + variant `olive` only matches `olive-oil`.

Do not treat oil like water (implicit/unlimited). Users track oil as a real pantry staple.

## Generic nuts

Same pattern as oil for bare **"nuts"**, **"nut"**, **"ground nuts"** in recipes:

1. **`nut` catalog entry** — default variant `mixed`; aliases catch corpus NER labels.
2. **Specific nut entries kept** — `walnut`, `peanut`, `almond`, etc.
3. **Pantry matching** — generic `nut` matches any edible nut in the pantry (`PantryCatalog.satisfyingEdibleNutCatalogItemIDs`). Typed variant (e.g. `walnut`) matches only that nut.

Seeds (`chia-seed`, `sesame-seed`, …) and products (`nut-butter`, `corn-nut`) are excluded from generic matching.

## Generic↔specific families

`catalog_families.json` defines substitution families (nut, oil) and generic-only facet bases (cheese, beef, …). Regenerate it with:

```bash
python3 PantryChef/Scripts/apply_generic_specific_model.py
```

This script:
- Syncs generic `variant` facets from specific members
- Keeps bare aliases on generic entries only (`nuts`, `cooking oil`, …)
- Enriches family-specific entries (nuts, `-oil` items) from `corpus_alias_candidates.json`
- Strips generic-only aliases from specific entries (e.g. `cooking oil` off `vegetable-oil`)

Use `--strip-only` to remove mistaken bulk corpus enrichment without re-enriching.

## Catalog validation

Run before committing catalog changes:

```bash
python3 PantryChef/Scripts/validate_catalog.py
python3 PantryChef/Scripts/validate_catalog.py --strict   # warnings → errors
python3 PantryChef/Scripts/validate_catalog.py --json       # machine-readable
```

Checks include:
- Duplicate alias keys across entries
- Generic aliases appearing on specific family members
- Facet options that duplicate standalone catalog entry names
- Orphan family IDs and unmapped generic variants
- Required fields and duplicate IDs

Pre-existing duplicate-alias pairs (e.g. `broth`/`bouillon`) are reported but may be intentional cross-entry synonyms to fix separately.

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
