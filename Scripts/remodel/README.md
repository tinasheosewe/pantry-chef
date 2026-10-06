# Catalog remodel pipeline

> **Note (5 October 2026):** this describes the one-time remodel of 10 June 2026 and the workflow as it stood that day.
> The transform cannot be re-run from this repository: its input, `baseline_catalog.json`, is not tracked. And the last line below no longer holds: later passes edited `catalog.json` directly, so `catalog.source.json` is behind it and `compile_catalog.py` stops rather than overwrite the larger file. See `Scripts/README.md` for the current state.

One-time structural remodel + repeatable enrichment that turned the legacy
"every variation is its own row" catalog into a governed entity + facet model.
See [docs/catalog-remodel-spec.md](../../docs/catalog-remodel-spec.md) for the design.

## What it does

- **Collapses** ~690 "adds-nothing" leaf rows (carolina BBQ, 2% milk, penne pasta,
  sharp cheddar…) into facet values on their parents, while **keeping** genuine
  kinds (basmati rice, brazil nut, cheddar) as rows — the "earns a row" rule.
- **Remaps** the facet vocabulary to the 10-key taxonomy (adds `grade`/`fat`/`medium`,
  retires `concentration`/`base`, splits cuts out of `form`, drops packaging,
  de-overlaps preservation/processing, enforces one canonical key per value).
- **Repairs** names/ids/aliases (garbled doubled names, misleading bare-word ids
  like `fresh`→`fresh-goji-berry`, alias pollution, canonical staples whose id was
  occupied by a derived product e.g. `olive-oil`→"olive oil cooking spray").
- **Enriches** every item with density (`gramsPerCup`/`gramsPerPiece`), `allergens`,
  `dietaryTags`, and `swaps`.

## Files

| File | Role |
|------|------|
| `vocab.py` | controlled facet vocabularies + token/value classifier (the one-time decisions) |
| `build.py` | structural transform: collapse leaves → facets, remap vocabulary, materialize |
| `coverage.py` | canonical-staple fixes + missing-staple additions |
| `hygiene.py` | name repair, id repair, alias de-pollution |
| `enrich.py` | deterministic density / allergens / dietary / swaps (also the final alias clean) |
| `baseline_catalog.json` | snapshot of the pre-remodel catalog (transform input) |
| `redirects.json` | map of each collapsed id → its parent + facet (audit trail) |

## Regenerating from scratch

The structural transform reads `baseline_catalog.json` and writes both
`catalog.json` and `catalog.source.json`:

```bash
cd Scripts
python3 remodel/build.py    --apply   # collapse + remap (baseline -> catalog + source)
python3 remodel/coverage.py --apply   # canonical fixes + new staples
python3 remodel/hygiene.py  --apply   # names / ids / aliases
python3 compile_catalog.py            # source -> materialized catalog.json + enrich()
python3 validate_catalog.py           # expect 0 errors
```

After this, `catalog.source.json` is authoritative structure and
`catalog.json == compile(source) + enrich(...)`. Day-to-day, edit
`catalog.source.json` and just run `python3 Scripts/compile_catalog.py`
(enrichment is baked into the compiler).
