# ML Ingredient Parsing & Grouping — Findings Summary

## Executive Summary

We evaluated **3 parsing approaches** and **3 grouping approaches** on 7,924 USDA food items (Foundation + SR Legacy) to determine the best pipeline for transforming raw USDA descriptions into a structured, faceted ingredient catalog for PantryChef.

**Winner:** Taxonomy parser (composite 99.1) + TF-IDF agglomerative grouping (94.1% facet coverage) → **614 groups** with rich facets.

Pipeline runtime: **~20 seconds** on Apple M4 Pro.

---

## 1. Data Source

| Dataset | Items | Source |
|---------|-------|--------|
| USDA Foundation Foods | 316 | FoodData Central API |
| USDA SR Legacy | 7,793 | FoodData Central API |
| **Merged (deduplicated)** | **7,924** | Foundation preferred on overlap |

Each item is a comma-separated USDA description like:
```
"Cheese, cheddar (Includes foods for USDA's Food Distribution Program)"
```

---

## 2. Parse Approach Comparison

Each parser extracts: **name**, **base**, **category**, **form**, **qualifiers**, **noise**.

Evaluated against 50 golden test cases derived from manual audit of real USDA descriptions, plus 8 regression-fix cases and 16 non-regression-hold cases.

| Rank | Approach | Composite | Golden Acc | Reg-Fix | Non-Reg | Architecture |
|------|----------|-----------|-----------|---------|---------|-------------|
| **1** | **Taxonomy** | **99.1** | 97.7% | 100% | 100% | Curated rules + canonical maps |
| 2 | CRF | 61.3 | 82.9% | 50.0% | 43.8% | CRF sequence labeling (sklearn-crfsuite) |
| 3 | spaCy NER | 48.9 | 70.5% | 37.5% | 31.3% | EntityRuler + NER patterns |

### Score Progression (Taxonomy Parser)

```
Round 0 (baseline):   47.1
Round 1 (fixes):      61.6  (+14.5)
Round 2 (fixes):      82.9  (+21.3)
Round 3 (fixes):      91.7  (+8.8)
Round 4 (final):      99.1  (+7.4)
```

### Why Taxonomy Won

1. **Domain is closed:** USDA descriptions follow a well-defined comma-separated grammar. Rules can capture 99%+ of patterns.
2. **Canonical maps are precise:** Curated `_FOOD_CANONICAL`, `_FORM_TERMS`, `_QUALIFIER_TERMS`, `_NOISE_PATTERNS` eliminate ambiguity.
3. **Iterative refinement is surgical:** Each failure can be traced to a specific rule and fixed without regression.
4. **No training data needed:** Self-supervised CRF/spaCy approaches bootstrap silver labels from heuristics—but those heuristics are effectively the taxonomy parser itself.

### Why CRF / spaCy Underperformed

- **Silver label quality ceiling:** Both approaches generate training labels from rules. If the rules are good enough to label data well, they're good enough to parse directly.
- **Token-level ambiguity:** Words like "plain", "white", "light" are context-dependent (qualifier vs. form vs. noise). Rules handle this with lookup tables; CRF/spaCy struggle with limited context windows.
- **Regression fragility:** Fixing one pattern in CRF often breaks others (composite 61.3 despite 82.9% golden accuracy).

---

## 3. Group Approach Comparison

Each grouper clusters parsed items into ingredient groups and extracts facets (variant, form, color).

| Rank | Approach | Singletons | Facet Coverage | Groups | Architecture |
|------|----------|-----------|---------------|--------|-------------|
| **1** | **TF-IDF Agglomerative** | **5.5%** | **94.1%** | **614** | TF-IDF on names → agglomerative clustering |
| 2 | Taxonomy Guided | 54.7% | 60.9% | 869 | Rules: base + category → canonical groups |
| 3 | Embeddings HDBSCAN | 38.6% | 45.7% | 3,615 | SentenceTransformer → HDBSCAN density clustering |

### Why TF-IDF Agglomerative Won

1. **Word overlap captures ingredient similarity:** "Pork Loin Tenderloin" and "Pork Loin Chop" share enough TF-IDF tokens to cluster naturally.
2. **Distance threshold is tunable:** Agglomerative clustering with a distance threshold creates the right granularity (614 groups for 7,924 items = avg 12.9 per group).
3. **No density requirement:** Unlike HDBSCAN, agglomerative clustering doesn't require dense neighborhoods—it assigns every item to a cluster.

### Why Embeddings HDBSCAN Underperformed

- **HDBSCAN is conservative:** Designed to find natural dense clusters, producing 38.6% singletons even after tuning (min_cluster_size=2, min_samples=1, leaf selection).
- **Semantic embeddings over-generalize:** "Chicken breast" and "Chicken thigh" are semantically close but should probably be in the same group—embeddings do this. But "Chicken soup" and "Chicken breast" are also close, causing noisy merges.
- **3,615 groups** is far too many for a useful catalog (many are singletons or pairs).

### Why Taxonomy Guided Underperformed

- **Rigid matching:** Only groups items that match curated canonical group patterns. Items with unknown bases become singletons.
- **Auto-group fallback helped** (96.5% → 54.7% singletons) but still can't match TF-IDF's organic clustering.

---

## 4. Hybrid Pipeline Architecture

```
USDA Data (7,924 items)
    │
    ▼
┌─────────────────┐
│ Taxonomy Parser  │  composite=99.1
│ (parse_taxonomy) │
└────────┬────────┘
         │ Parsed items: name, base, category, form, qualifiers, noise
         ▼
┌──────────────────────┐
│ TF-IDF Agglomerative │  614 groups, 94.1% faceted
│  (group_tfidf)       │
└────────┬─────────────┘
         │ Groups with variant/form/color facets
         ▼
┌─────────────────┐
│  PantryChef     │
│  Catalog        │
└─────────────────┘
```

---

## 5. Representative Hybrid Output

### Group Statistics

| Metric | Value |
|--------|-------|
| Total groups | 614 |
| Total items | 7,924 |
| Avg group size | 12.9 |
| Singletons | 34 (0.4%) |
| Groups with 2+ items | 580 |
| Groups with 5+ items | 277 |
| Groups with 10+ items | 157 |

### Largest Groups

| Group | Size | Example Members |
|-------|------|----------------|
| Beef Steak | 603 | Trimmed To 0" Fat Select Beef Loin Tenderloin, etc. |
| Pork Loin | 212 | Pork, Pork Loin, Pork Loin Tenderloin |
| Chicken | 192 | Chicken Breast, Chicken |
| Bean | 165 | Red Bean, Flour Bean |
| Lamb | 155 | Foreshank Lamb, Shoulder Lamb |

### Example: Faceted Medium Group

**Seaweed** (10 members):
- Facets: `variant=[agar, kelp, laver, wakame, spirulina, irishmoss, ...]`, `form=[dried, dry, raw]`
- Members: "Canadian Cultivated Emi-Tsunomata Seaweed", "Kelp Seaweed", "Laver Seaweed", etc.

**Bagels** (10 members):
- Facets: `variant=[wheat, multigrain, cinnamon-raisin, plain, sesame, ...]`, `form=[boiled, toasted, frozen, ...]`
- Members: "Wheat Bagels", "Multigrain Bagels", "Cinnamon-Raisin Bagels", etc.

---

## 6. Known Limitations & Quality Issues

### Parsing

- **Brand/program noise bleeds into names:** Some USDA descriptions include "(Includes foods for USDA's Food Distribution Program)" — handled as noise but occasionally leaks.
- **Compound names:** "Olive oil" vs "Peanut oil" correctly identified, but "Cream cheese" sometimes splits.
- **Cut/form ambiguity in meats:** "Trimmed to 0" fat" is a qualifier but creates awkward display names.

### Grouping

- **Beef group is too large** (603 items): All beef cuts cluster together. A second-level grouping by cut type would improve usability.
- **Group names need polish:** Some group labels inherit awkward substrings ("Trimmed To 0" Fat All Grades Beef Steak" as a group name).
- **Cross-category leakage:** "From Kid's Menu" items (chicken nuggets + cheese pizza) cluster by source rather than food type.

---

## 7. Recommendations for Production

### Immediate

1. **Use taxonomy parse + TF-IDF agglomerative** as the catalog generation pipeline.
2. **Post-process group names:** Strip trim/fat descriptors, use the most common base name in each group as the display name.
3. **Split oversized groups:** Apply a second agglomerative pass to groups >100 items using tighter distance thresholds.
4. **Add manual overrides:** Maintain a `_GROUP_OVERRIDES` map for known misclassifications (e.g., kid's menu items).

### Future

5. **User-facing catalog UI:** Present groups as browsable categories with facet filters (form, variant, color).
6. **Recipe ingredient matching:** Map recipe ingredient strings to catalog groups using fuzzy matching on parsed names.
7. **Incremental updates:** When USDA adds new items, re-run parse (instant) and update grouping (incremental merge vs. full re-cluster).
8. **Consider CRF as validation:** Run CRF parser in parallel to taxonomy; flag items where outputs diverge for manual review.

---

## 8. File Inventory

### Parse Approaches
| File | Lines | Description |
|------|-------|-------------|
| `ml_approaches/parse_taxonomy.py` | ~680 | Curated taxonomy parser (BEST) |
| `ml_approaches/parse_crf.py` | ~330 | CRF sequence labeling parser |
| `ml_approaches/parse_spacy_ner.py` | ~380 | spaCy EntityRuler + NER parser |

### Group Approaches
| File | Lines | Description |
|------|-------|-------------|
| `ml_approaches/group_tfidf.py` | ~170 | TF-IDF + agglomerative clustering (BEST) |
| `ml_approaches/group_taxonomy.py` | ~240 | Taxonomy-guided grouping |
| `ml_approaches/group_embeddings.py` | ~180 | Sentence embeddings + HDBSCAN |

### Evaluation & Orchestration
| File | Lines | Description |
|------|-------|-------------|
| `ml_approaches/golden_cases.py` | ~350 | 50 golden test cases |
| `ml_approaches/evaluate.py` | ~300 | Evaluation framework |
| `ml_approaches/build_hybrid.py` | ~60 | Best-parse + best-group combiner |
| `ml_approaches/run_all.py` | ~80 | Full pipeline runner |

### Outputs
| File | Description |
|------|-------------|
| `ml_outputs/taxonomy_parse.json` | Taxonomy parse results (7,924 items) |
| `ml_outputs/hybrid_parse.json` | Best parse output |
| `ml_outputs/hybrid_groups.json` | Final grouped catalog (614 groups) |
| `ml_outputs/evaluation_report.json` | All scores and metrics |

---

## 9. Appendix: Taxonomy Parser Key Design Decisions

1. **Comma-split grammar:** First field = category, subsequent fields = food/form/qualifier tokens.
2. **Multi-word matching:** Form and qualifier terms matched longest-first to handle "low-fat", "cream cheese", etc.
3. **Canonical maps:** 100+ food items mapped to canonical display names (e.g., "cheddar" → "Cheddar").
4. **Cheese variety promotion:** When a cheese has variety + other qualifiers, variety promoted to name component.
5. **Meat cut postfix:** Cut terms appended to name ("Beef Loin Tenderloin" not just "Beef").
6. **Noise extraction:** Brand names, program references, USDA metadata stripped from display name.
7. **Drop qualifiers:** Category-specific defaults dropped from name (yogurt → drop "plain", "nonfat").
8. **Compound base derivation:** "Olive oil" kept as single base rather than split into "olive" + "oil".
9. **Plural canonical names:** Countable foods use plural ("Almonds" not "Almond").
