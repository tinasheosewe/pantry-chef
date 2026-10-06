# docs

Design documents, the backlog, and the inputs and outputs of the catalog and recipe data passes. Nothing here is needed to build the app.

## Documents

| File | What it is |
|---|---|
| `TODO.md` | Running backlog and decision log. |
| `input-system-proposal.md` | Proposal of 2 September 2026 for reworking ingredient entry, with a measurement of the current parser. Marked "for decision". |
| `redesign-spec.md` | Design spec for the June 2026 redesign. Records intent; the build differs in places. |
| `catalog-model.md` | The catalog model: entries with parent links, ten facet keys, derived fields. |
| `catalog-remodel-spec.md` | Spec for the remodel of 10 June 2026 that turned about 690 rows into facet values. |
| `catalog-inheritance-plan.md` | The May 2026 plan that introduced parent links. |
| `feature-inventory.md`, `feature-audit.md` | Snapshots from 10 and 11 June 2026: the feature list before the redesign, and the first redesign build measured against it. |

Documents that describe an earlier state carry a dated note at their top.

## Data-pass folders

Each catalog or recipe pass in June 2026 was run per category or per slice of recipes against a written brief, and produced JSON that a script then applied. The briefs, the JSON and the appliers are kept as the record of how the bundled data was edited. They are inputs that have already been applied; re-running an applier against the current files is not expected to work.

| Folder | Contents | Applied by |
|---|---|---|
| `catalog-audit/` | Per-category audit of the catalog: issues, redundancies, alias additions, new items, cleanups. | New items and aliases were merged into `catalog.json` on 18 June 2026 (that merge script was not kept); the rest became the operations in `catalog-tier32/`. |
| `catalog-enrich/` | Full definitions (facets, density, allergens, dietary tags, substitutions) for the items the audit added. | `tools/integrate_enrich.py`, then `tools/fix_invariants.py` |
| `catalog-tier32/` | Edit operations derived from the audit: structural fixes and data cleanups. Brief: `OPS_SPEC.md`. | `tools/apply_ops.py` |
| `catalog-review/` | A later review for names and aliases that resolved to the wrong item, in the same operation format. Brief: `SPEC.md`. | `tools/apply_ops.py`, pointed at this folder |
| `recipe-seed/` | The recipe drafts in four batches, and `all.json`, the merged set of 192 with catalog ids. | Became `PantryChef/Resources/seed_recipes.json`, where four near-duplicates were later removed |
| `recipe-pass/` | Per-step cook times and a validity flag for each recipe. Brief: `SPEC.md`. | Folded into `seed_recipes.json` (the script was not kept) |
| `recipe-essentiality/` | Which ingredient lines of each recipe are optional. Brief: `SPEC.md`. | `tools/apply_essentiality.py` |

The JSON in these folders refers to catalog ids and recipe names as they were on the day of each pass; later passes renamed, merged and removed some of them.
