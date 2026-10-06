# Catalog Inheritance Model

> **Note (5 October 2026):** the model described here (entries as classes with parent links, ten facet keys, derived enrichment) is the one the app uses.
> What has changed is the workflow around it: since 18 June 2026 `catalog.json` has been edited directly, so `catalog.source.json` is behind it, and the rules listed under `validate_catalog.py` are now held by the Swift `CatalogInvariantTests`. See `Scripts/README.md`.

## Core rules

- Catalog entries are **classes** in an inheritance graph (single-parent trees + rare multi-parent items).
- Any class can be selected directly by the user (no abstract-only classes).
- **Kind** information is modeled as subclasses (`children[]` in source, `parentIds` in compiled output).
- **State** information is modeled as facets (`form`, `processing`, `preservation`, etc.).
- Single-parent facet inheritance is **additive** (children may add facet options, not remove inherited ones).
- Multi-parent items own a **complete leaf definition**; their `parentIds` are for matching only (facets are not inherited).

Kind vs state rule (sharpened — see [catalog-remodel-spec.md](catalog-remodel-spec.md)):

- A variation keeps its own catalog row **only if it earns one**: it carries its own
  facet palette, its own defaults/freshness, is further sub-varied, or is
  non-substitutable for its siblings. `walnut` (a distinct kind) → subclass.
- Otherwise it is a **facet value**. `carolina` barbecue sauce, `2%` milk, `sharp`
  cheddar, `penne` pasta, `chopped` walnut → facets, not rows.

## Facet taxonomy

Ten governed facet keys (`PantryFacetKey`), split into *narrowing* facets (used to
pick a descendant during matching) and *state* facets (the same item's condition):

| Key | Kind | Meaning |
|-----|------|---------|
| `color` | narrowing | visible color |
| `variant` | narrowing | named style / cultivar / flavor / region (penne, carolina, verte) |
| `grade` | narrowing | intensity / strength / diet grade (mild, sharp, hot, reduced sodium) |
| `fat` | narrowing | dairy fat level (skim, 1%, 2%, whole) |
| `form` | state | physical / market form (ground, whole, powder, liquid, paste) |
| `preparation` | state | knife / prep state (sliced, diced, peeled, deveined) |
| `preservation` | state | how it is kept (fresh, frozen, dried, canned, pickled) |
| `processing` | state | treatment / cooking (raw, roasted, smoked, marinated) |
| `texture` | state | consistency (smooth, chunky, creamy, firm) |
| `medium` | state | packing / cooking liquid (in water, in oil, in brine) |

Rules enforced by `validate_catalog.py`: every value belongs to exactly one key
(orthogonality), facet keys are from the set above, and no item id is a bare
state/modifier word. The retired keys `concentration`/`base` were split into
`grade`/`fat`/`variant` and `medium`/`variant`.

## Enrichment

Compiled items also carry deterministically-derived fields (computed in
[`Scripts/remodel/enrich.py`](../Scripts/remodel/enrich.py), injected by
`compile_catalog.py`):

- `gramsPerCup`, `gramsPerPiece` — volume/count ↔ mass conversion.
- `allergens` — `Allergen` big-9 + sesame, from name/category rules.
- `dietaryTags` — `DietaryTag` (vegan/vegetarian/gluten-free/…), derived.
- `swaps` — `CatalogSwap` substitutions (curated + same-family siblings).

These are derived, not authored: they are NOT stored in `catalog.source.json` and
are regenerated on every compile.

## Source vs runtime format

| File | Role |
|------|------|
| [`catalog.source.json`](../PantryChef/Resources/catalog.source.json) | Authoritative authoring format |
| [`catalog.json`](../PantryChef/Resources/catalog.json) | Flat compiled output loaded by the app |

The app bundle loads **only** `catalog.json`. Edit `catalog.source.json`, then compile.

### Source schema (`catalog.source.json`)

Two sections:

```json
{
  "trees": [
    {
      "id": "nut",
      "name": "nut",
      "category": "Nuts & Seeds",
      "aliases": ["nuts"],
      "facets": [{ "key": "form", "options": ["whole", "chopped"] }],
      "children": [
        {
          "id": "walnut",
          "name": "walnut",
          "aliases": ["walnuts"]
        }
      ]
    }
  ],
  "multiInheritance": [
    {
      "group": "Sauces & condiments",
      "items": [
        {
          "id": "tomato-sauce",
          "parentIds": ["sauce", "tomato"],
          "name": "tomato sauce",
          "category": "Condiments & Sauces",
          "aliases": ["tomato sauces"],
          "facets": [{ "key": "texture", "options": ["smooth", "chunky"] }],
          "defaultSelections": [],
          "defaultStorage": "Pantry",
          "freshnessByStorage": { "Pantry": [180, 365] }
        }
      ]
    }
  ]
}
```

**Single inheritance (`trees`)**

- Parent owns `children[]`; each child has sparse overrides.
- One parent per node. Compiled output uses `parentIds: ["parent-id"]`.

**Multi inheritance (`multiInheritance`)**

- Item owns `parentIds` with **≥ 2** parents plus a **full standalone definition** (all required fields + facets).
- Used sparingly for true cross-taxonomy products (e.g. `tomato-sauce` → `sauce` + `tomato`).
- **Not** multi-inheritance: homonyms (`almond` vs `almond-oil`), shared cut names scoped per animal (`chicken-breast`, `beef-shank`).

### Compiled schema (`catalog.json`)

Each item is flat — no `children` or `parents` keys:

```json
{
  "id": "walnut",
  "name": "walnut",
  "parentIds": ["nut"],
  "aliases": ["walnuts"],
  "facets": [
    { "key": "form", "options": ["whole", "halved", "chopped"] },
    { "key": "processing", "options": ["raw", "roasted"] }
  ],
  "facetAliases": [
    {
      "text": "chopped walnuts",
      "facets": [{ "key": "form", "value": "chopped" }]
    }
  ]
}
```

Removed legacy fields: `isGenericBase`, `parentId`, `parentFacets`, `excludedFromGenericMatch`.

## Runtime semantics

`PantryCatalog` builds inheritance caches:

- `ancestors(of:)`
- `descendants(of:)`
- `inheritanceDistance(from:to:)`
- `effectiveFacets(for:)` — additive union for single-parent items; **leaf-only** for multi-parent items

Matching core:

- Pantry satisfies recipe iff pantry class is equal to or descendant of recipe class, and pantry facets satisfy required state facets.

Strict vs loose:

- Strict path uses structured class/facet matching only.
- Loose path is strict + text fallback + quantity fallback + substitutions.

## Authoring workflow

```bash
# Edit catalog.source.json, then compile
python3 Scripts/compile_catalog.py

# Or repair flat catalog + rebuild source + recompile
python3 Scripts/rebuild_catalog_source.py --write-source --write-catalog

# Validate compiled output (or source via compile)
python3 Scripts/validate_catalog.py
python3 Scripts/validate_catalog.py --source
```

## Validation

[`validate_catalog.py`](../Scripts/validate_catalog.py) enforces:

- required fields + unique IDs
- no deprecated legacy fields
- parent references exist
- no inheritance cycles
- additive facet inheritance (single-parent items only)
- multi-inheritance completeness (full leaf definition)
- facet alias key/value validity in effective hierarchy

## Migration notes

Legacy shared modifier nodes (`red`, `yellow`, `ground`, etc.) were split into scoped subclasses (`onion-red`, `beef-ground`, …). Kind facets (`variant`, `base`, …) were migrated to subclass rows where applicable. Seed recipes and tests use scoped catalog IDs (e.g. `chicken-breast`, `onion-yellow`).
