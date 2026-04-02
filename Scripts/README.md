# Ingredient Catalog Pipeline

This documents how to add, enrich, and publish ingredients for the PantryChef catalog.

## File Layout

```
Scripts/
  triage_output/
    bases_by_aisle.json        ← raw ingredient list grouped by aisle (staging)
    enriched_catalog.json      ← fully enriched catalog with all fields (staging)
  publish_catalog.py           ← converts staging → production
PantryChef/
  Resources/
    catalog.json               ← production catalog loaded by the app
  Models/
    PantryCatalog.swift        ← loads catalog.json at launch
    Enums.swift                ← FoodCategory, MeasurementUnit, etc.
```

## The Three Files

| File | Role | Format |
|------|------|--------|
| `bases_by_aisle.json` | Source of truth for **which ingredients exist** | `{ "Aisle Name": ["item", ...], ... }` |
| `enriched_catalog.json` | Staging catalog with full metadata for every base | `{ "item": { id, name, category, ... }, ... }` |
| `catalog.json` | Production copy the app reads from the bundle | `[ { id, name, category, ... }, ... ]` (array, Swift-compatible values) |

## Adding New Ingredients

### 1. Add to `bases_by_aisle.json`

Add the ingredient name (lowercase) to the appropriate aisle category, keeping alphabetical order:

```json
{
  "Pasta & Noodles": [
    "cellophane noodle",
    "egg noodle",
    "my new ingredient",
    "pasta"
  ]
}
```

**Rules:**
- One base per concept (e.g. "beef" not "beef sirloin" — cuts are facet variants)
- Lowercase, no leading articles
- Frozen items get the "frozen" prefix (e.g. "frozen french fries")
- Keep items alphabetically sorted within each aisle

### 2. Enrich the new item in `enriched_catalog.json`

Add a new entry keyed by the ingredient name. Every item needs these fields:

```json
{
  "my new ingredient": {
    "id": "my-new-ingredient",
    "name": "my new ingredient",
    "category": "Pasta & Noodles",
    "defaultUnit": "oz",
    "defaultQuantity": 12,
    "defaultStorage": "pantry",
    "aliases": ["alternative name", "regional name"],
    "facets": [
      { "key": "variant", "options": ["type1", "type2"] },
      { "key": "form", "options": ["dry", "fresh"] }
    ],
    "defaultSelections": [
      { "key": "variant", "value": "type1" },
      { "key": "form", "value": "dry" }
    ],
    "freshnessByStorage": {
      "pantry": [180, 365],
      "refrigerated": [7, 14],
      "frozen": [180, 365]
    }
  }
}
```

**Field reference:**

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Kebab-case, unique (e.g. `"my-new-ingredient"`) |
| `name` | string | Matches the key in `bases_by_aisle.json` |
| `category` | string | Must match a `FoodCategory` rawValue (see below) |
| `defaultUnit` | string? | A `MeasurementUnit` rawValue: tsp, tbsp, cup, fl oz, ml, L, g, kg, oz, lb, piece, whole, loaf, slice, clove, bunch, can, pkg, pinch, splash, to taste |
| `defaultQuantity` | number? | Typical purchase quantity |
| `defaultStorage` | string | `"pantry"`, `"refrigerated"`, or `"frozen"` (lowercase in staging) |
| `aliases` | [string] | Alternative names, regional variants, plurals |
| `facets` | [object] | Facet dimensions — see below |
| `defaultSelections` | [object] | One `{ key, value }` per facet for the most common variant |
| `freshnessByStorage` | object | `{ "pantry": [min, max], ... }` — shelf life in days |

**Valid categories** (18 total):
Alcohol & Spirits, Baking & Sweeteners, Beverages, Breads & Bakery, Canned & Jarred, Condiments & Sauces, Dairy & Eggs, Frozen Foods, Grains & Cereals, Legumes & Beans, Nuts & Seeds, Oils & Fats, Other, Pasta & Noodles, Produce, Protein, Snacks, Spices & Herbs

**Facet keys** (use only what applies — most items need 2-4):

| Key | Use for | Example |
|-----|---------|---------|
| `variant` | Types/varieties/species/cuts | beef: ground, sirloin, ribeye |
| `form` | Physical form | cheese: block, shredded, sliced |
| `preservation` | Storage method | fresh, frozen, dried, canned |
| `processing` | How it was processed | raw, roasted, smoked, cured |
| `preparation` | Pre-cooking prep | shelled, peeled, hulled |
| `texture` | Texture descriptor | creamy, chunky, smooth |
| `concentration` | Strength/dilution | regular, concentrated, lite |
| `base` | Base ingredient | broth: chicken, beef, vegetable |

### 3. Publish to production

```bash
python3 Scripts/publish_catalog.py
```

This converts `enriched_catalog.json` → `PantryChef/Resources/catalog.json` by:
- Mapping `category` strings to `FoodCategory` rawValues
- Capitalizing `defaultStorage` keys (`"pantry"` → `"Pantry"`)
- Capitalizing `freshnessByStorage` keys
- Converting from dict → sorted array

### 4. Verify

Build and run the app. The catalog loads from `catalog.json` at launch via `PantryCatalog.allItems`.

## Bulk Enrichment

For adding many items at once, the enrichment was originally done with a GPT-4.1 batch script (`enrich_catalog.py`, preserved in git at `ff18807`). It uses schema-enforced structured output with gold examples and deterministic validation. See that commit for the full script if you need to re-enrich or bulk-add.

## Spot-Checking

`Scripts/spot_check.py` inspects complex items across key categories (Protein, Produce, Dairy, Condiments, Baking, Grains, Nuts) and prints facet counts and option lists for review.

```bash
python3 Scripts/spot_check.py
```
