# Catalog Remodel Spec — Entity vs. Attribute

> **Note (5 October 2026):** the spec for the remodel of 10 June 2026, with the counts of that day (2,966 → 2,278 items, validator at 0 errors).
> The catalog now holds 2,888 items after the passes of 18 June, which edited `catalog.json` directly; `validate_catalog.py` predates those passes and reports errors against the current file. See `Scripts/README.md`.

Status: **implemented**. The pipeline in [Scripts/remodel/](../Scripts/remodel/README.md)
applies this design: 2,966 → 2,278 items, 10-key governed facet taxonomy,
enrichment (density/allergens/dietary/swaps), validator green (0 errors). Supersedes
the coarse "Kind → subclass / State → facet" rule in [catalog-model.md](catalog-model.md).
Backwards-compatibility was intentionally dropped (nothing shipped), so the
redirect-table step in §5 was replaced by direct id/name repair.

## 1. Diagnosis (one paragraph)

The schema is sound. The problem is that the catalog has **two redundant ways to
express the same variation** — a child row (`parentIds`) or a facet value — and the
existing rule ("kinds become subclasses") is too coarse, so the data forced ~1,738
attribute-points into their own rows. Today: **550 roots, 2,419 leaves, of which
1,738 are "bare" leaves carrying nothing but `id`/`name`(/`aliases`)**. Those bare
leaves are facet values masquerading as entities. They cause the combinatorial
explosion ("never comprehensive"), the broken single-token names
(`carolina`, `thick`, `1%`, `00`), the namespace collisions (child `ginger` vs the
produce `ginger`), and the repetition you feel (the `form` facet has 265 distinct
values used 16,380 times; one identical 11-value `form` set is copy-pasted onto 42
items). The `variant` facet — the natural home for most of these — is defined and
wired into matching but has **zero** values in the data.

## 2. The sharpened rule: "Does it earn a row?"

Replace "Kind → subclass, State → facet" with this test. A variation becomes its own
catalog item (a child row) **only if it carries structure the parent cannot express
for it**. Otherwise it is a **facet value**.

A variation **earns a row** if *any* of these are true:

1. **It has its own distinct facet palette.** (Cheddar is sold sliced/shredded/block
   and graded mild→sharp; that palette is specific to cheddar, not all cheese.)
2. **It has its own defaults, storage, or freshness** that differ from the parent.
3. **Recipes name it specifically *and* further vary it** ("shredded cheddar",
   "crumbled feta") — i.e. it is itself a base for more facets.
4. **It is non-substitutable** for its siblings in a way recipes rely on (feta ≠
   cheddar; a recipe for feta is not satisfied by cheddar).

A variation is a **facet value** (no row) if it is a *terminal point on one attribute
axis* and carries none of the above:

- `2%` / `skim` / `whole` → a **fat** point on `milk`. No own palette.
- `mild` / `sharp` / `extra sharp` → a **grade** point on `cheddar`.
- `carolina` / `memphis` / `texas` → a **variant** of `barbecue-sauce`.
- `verte` / `blanche` / `bleue` → a **color/variant** of `absinthe`.

> Litmus: *"If I delete this row and add its distinguishing word as a value on the
> parent's facet, do I lose any information?"* If no → it never deserved a row.

Counts under this rule (measured): **1,738 leaves collapse to facet values; ~681
keep their row** (651 carry own facets, 30 carry own defaults/freshness). Target
catalog size drops from 2,966 to roughly **1,200 entities**, with the variation
carried by a small, shared, controlled facet vocabulary instead of enumerated rows.

## 3. Final facet taxonomy

Each facet key gets a crisp definition, a governance policy, and an orthogonality
rule: **no value may appear under two keys.** Keys are split into *narrowing* facets
(used by `matchingCatalogItemIDs` kind-keys to pick a descendant) and *state* facets
(describe the same item's condition).

| Key | Kind | Means | Controlled vocabulary (governed) | Notes / fixes |
|---|---|---|---|---|
| `variant` | narrowing | Named style/cultivar/region that does **not** change the facet palette | open, per-family (carolina, memphis, verte, gala…) | **Currently empty — this absorbs most collapsed leaves.** |
| `color` | narrowing | Visible color | brown, green, orange, purple, red, white, yellow, black | keep as-is |
| `grade` | narrowing | Intensity/strength on the product's defining axis | mild, medium, sharp, extra-sharp, hot, extra-hot, light, dark | **New.** Splits the overloaded `concentration`. |
| `fat` | narrowing | Fat/richness level for dairy & similar | skim, 1%, 2%, whole, low-fat, full-fat, reduced-fat | **New.** Removes `1%`/`2%`/`skim` rows. |
| `form` | state | **Physical/market form only** | whole, ground, powder, liquid, paste, flakes, fillet, granulated | **Narrowed.** Remove cuts and packaging (below). |
| `preparation` | state | Knife/prep state | sliced, diced, chopped, minced, shredded, grated, cubed, peeled, seeded, trimmed | **Absorbs cut values currently mislabeled `form`.** |
| `preservation` | state | How it is kept / shelf state | fresh, frozen, dried, canned, pickled, cured, fermented, brined | `cured` lives here, not `processing`. |
| `processing` | state | How it has been treated/cooked | raw, cooked, roasted, smoked, toasted, blanched, marinated, seasoned | **`smoked` lives here only.** Resolve every preservation/processing collision. |
| `texture` | state | Mouthfeel/consistency | smooth, chunky, creamy, thick, thin, coarse, fine | keep |
| `medium` | state | Packing/cooking liquid | in water, in oil, in brine, in syrup, in tomato purée | **New.** Splits the liquid half out of `base`. |
| `base` | narrowing | Underlying ingredient of a derived product (stock/broth) | chicken, beef, vegetable, pork, fish, mushroom | **Reduced** to the protein-base meaning only. |

Retired / reassigned:

- **`concentration`** → split into `grade` (intensity) and `fat` (dairy); reassign
  sodium/sugar/dilution points to `grade` or to `medium` where they're really
  packing liquid.
- **Packaging** values (bottle, carton, tub, basket, can, jar) → **dropped from
  facets entirely.** Packaging is not a culinary attribute; if needed it belongs to
  the pantry item's `unit`/quantity, not the ingredient identity.

Governance: each facet's vocabulary lives in **one place** (a constants table in
`catalog_source_lib.py`), the compiler rejects out-of-vocabulary values, and a value
may belong to exactly one key.

## 4. Worked examples (before → after)

### Milk
**Before:** `milk` + children `milk-2` (2%), `milk-skim`, `raw-milk`, `whole-milk`.
**After:** one `milk` entity:
```
fat:          [skim, 1%, 2%, whole]      (narrowing)
form:         [liquid, powdered]
processing:   [pasteurized, ultra-pasteurized, homogenized, raw]
```
`raw-milk` collapses to `processing: raw`; the four fat rows collapse to `fat`.
A recipe for "milk" matches the entity; "2% milk" matches `milk` + `fat:2%`.

### Cheese (shows the rule's nuance)
**Before:** `cheese` + 28 children, mixing three different things.
**After:**
- **Keep as rows** (own palette + named in recipes + non-substitutable):
  `cheddar`, `mozzarella`, `feta`, `brie`, `gouda`, `parmesan`, `swiss`, … each
  carrying its own `form`/`preparation`.
- **Collapse to a `grade` facet on `cheddar`:** `mild`, `sharp`, `extra-sharp`
  (these are not cheeses — they are cheddar grades).
- **Fix id/name drift:** `romano` → `pecorino-romano`.

### Barbecue sauce
**Before:** `barbecue-sauce` + children `carolina`, `memphis`, `kansas-city`,
`texas`, `hickory`, `honey`, `original`…
**After:** `barbecue-sauce` with `variant: [carolina, memphis, kansas-city, texas,
hickory, honey, original]`. Recipe "memphis bbq sauce" → `barbecue-sauce` +
`variant:memphis`.

### Absinthe
**Before:** `absinthe` + children `blanche`, `bleue`, `verte`, `bohemian`, `french`,
`swiss-absinthe`.
**After:** `absinthe` with `color:[green, white, blue]` (verte/blanche/bleue) and
`variant:[bohemian, french, swiss]`.

## 5. Reference stability (do this before deleting any row)

Deleting 1,738 IDs breaks every reference to them. References live in:
`seed_recipes.json`, persisted user `PantryItem`/`Ingredient` (`catalogItemID`),
and tests. Required safeguards:

1. **Redirect table.** The compiler emits a `redirects: { "milk-2": { "to":
   "milk", "facets": [{"key":"fat","value":"2%"}] } }` map. Loaders resolve a stale
   `catalogItemID` through it on read, rewriting to parent + facets. This makes the
   collapse non-breaking for existing data and recipes.
2. **Stable IDs going forward.** New IDs are slugs of the canonical full name, never
   numeric/fragmentary (`milk-2` was named `2%`). IDs never change once shipped; a
   rename adds an alias, it does not mutate the id.
3. **Decouple display from render-time parent lookup.** Today `catalogBaseName`
   ([PantryCatalog.swift:347](../PantryChef/Models/PantryCatalog.swift#L347))
   reconstructs the display name from the parent at render time — a crutch for the
   broken child names. After collapse, store the real display name; delete that path.

## 6. Dead-field decisions

- `substitutions`, `unitOverrides` — **not in `CodingKeys`**
  ([PantryCatalog.swift:176](../PantryChef/Models/PantryCatalog.swift#L176)),
  hardcoded empty on decode, 0 rows populated. **Decision:** remove from the struct
  now; reintroduce deliberately if/when a feature needs them.
- `facetAliases` — decodable but **0 rows populate it**, so the matcher branch at
  [PantryCatalog.swift:1117](../PantryChef/Models/PantryCatalog.swift#L1117) is
  dormant. **Decision:** keep, and have the **compiler auto-generate** them from
  facet options (e.g. `form:chopped` on `walnut` → alias `"chopped walnuts"`). This
  lights up the dormant matching path for free and is the mechanism that lets a
  collapsed value like "memphis barbecue sauce" still resolve exactly.
- `parentIds` dual semantics (1 = inherit facets; ≥2 = matching-only). Keep, but
  document loudly and keep `multiInheritance` rare (currently 20 items / 5 groups).

## 7. Migration plan (phased, each phase ships & validates green)

1. **Taxonomy first (no row changes).** Land the new facet keys (`grade`, `fat`,
   `medium`), split `form`→`form`+`preparation`, de-overlap
   `preservation`/`processing`, drop packaging. Update the vocab constants +
   `validate_catalog.py`. Recompile; fix fallout. *Now the targets exist.*
2. **Mechanical collapse of bare leaves.** A script walks each parent; for every
   bare/alias-only leaf, extract the distinguishing token (most names already embed
   the parent, so the token is the leading word), append it to the right facet,
   fold safe aliases up, emit a redirect entry, delete the child node. Run per
   family, smallest first; commit per family.
3. **Triage the ~681 "keep" leaves.** Manually confirm each genuinely earns a row by
   §2; demote the false positives (e.g. grade-only children that happen to carry a
   redundant inherited facet block).
4. **Wire redirects + auto facetAliases into the compiler**, add the loader
   redirect-resolution, update `seed_recipes.json` to canonical ids+facets.
5. **Re-point the LLM validator.** It currently grades names/aliases of the wrong
   structure. Give it the new job: *"should this child be a facet value of its
   parent?"* and *"is this facet value in the right key / a duplicate?"*

## 8. New validation gates (extend `validate_catalog.py`)

- **No bare leaf.** A leaf with no own facets/defaults/freshness and a single-token
  name is an error → must be a facet value.
- **Facet vocabulary closed.** Every facet value ∈ its key's controlled vocabulary.
- **Orthogonality.** No value string appears under two different keys across the
  catalog (catches `smoked` in both preservation and processing).
- **No facet duplication across siblings.** If N children declare an identical facet
  option set, it must be hoisted to the common ancestor (kills the 42×-copied set).
- **ID stability.** ID is a slug of the canonical name; no numeric-only / fragment
  ids; redirect entries cover every removed id.

## 9. Expected outcome

- Entities: ~2,966 → ~1,200. Variation carried by a **shared, governed** facet
  vocabulary, so "comprehensive" becomes "enumerate the axes once," not "enumerate
  the cross-product."
- Naming/collision/semantic report issues largely vanish at the source (they are
  symptoms of bare leaves).
- Adding coverage becomes: add a facet *value* (one word) far more often than a new
  row — directly serving "users rarely have to add new ingredients."
