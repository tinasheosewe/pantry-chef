# Catalog Inheritance Model

## Core rules

- Catalog entries are classes in an inheritance DAG.
- Any class can be selected directly by the user (no abstract-only classes).
- `parentIds: [String]` defines inheritance; multi-inheritance is allowed.
- Kind information is modeled as subclasses.
- State information is modeled as facets.
- Facet inheritance is additive.

Kind vs state rule:

- Kind example: `walnut` is a kind of `nut` -> subclass.
- State example: `chopped` is a state of `walnut` -> facet.

## Schema

Each item in [`catalog.json`](../PantryChef/Resources/catalog.json) may include:

- `parentIds: [String]`
- `facetAliases: [{ text, facets }]`

Removed fields:

- `isGenericBase`
- `parentId`
- `parentFacets`
- `excludedFromGenericMatch`

Example:

```json
{
  "id": "walnut",
  "name": "walnut",
  "parentIds": ["nut"],
  "aliases": ["walnuts", "english walnut"],
  "facets": [
    { "key": "form", "options": ["whole", "halved", "chopped"] },
    { "key": "processing", "options": ["raw", "roasted", "toasted"] }
  ],
  "facetAliases": [
    {
      "text": "chopped walnuts",
      "facets": [{ "key": "form", "value": "chopped" }]
    }
  ]
}
```

## Runtime semantics

`PantryCatalog` builds inheritance caches:

- `ancestors(of:)`
- `descendants(of:)`
- `inheritanceDistance(from:to:)`
- `effectiveFacets(for:)`

Matching core:

- Pantry satisfies recipe iff pantry class is equal to or descendant of recipe class, and pantry facets satisfy required state facets.

Strict vs loose:

- Strict path uses structured class/facet matching only.
- Loose path is strict + text fallback + quantity fallback + substitutions.

## Search and UI behavior

- Search should surface abstract class plus matching leaves.
- State facets are progressive disclosure via Customize.
- State facets appear in display names only when explicitly selected.

## Validation

[`validate_catalog.py`](../Scripts/validate_catalog.py) enforces:

- required fields + unique IDs
- no deprecated legacy fields
- parent references exist
- no inheritance cycles
- additive facet inheritance
- facet alias key/value validity in effective hierarchy

## Migration workflow

- Use [`apply_inheritance_migration.py`](../Scripts/apply_inheritance_migration.py) with dry-run first.
- Migrate family-by-family in this order:
  - `nut`, `oil`, `cheese`, `beef`, `rice`, `flour`, `broth`, `pasta`, `bread`, `sugar`, `cream`, `yogurt`, `milk`, `pork`, `lamb`, `turkey`, `fish`, `shrimp`, `mushroom`, `potato`, `onion`, `pepper`, `tomato`, `beans`, `cured-meat`
- After each family: run validation and spot-check matching paths.
