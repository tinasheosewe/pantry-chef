#!/usr/bin/env python3
"""
Analyze RecipeNLG corpus ingredients against the current catalog.

Reads the NER column (pre-extracted ingredient names) from RecipeNLG,
normalizes and counts them, then diffs against catalog.json to find:
  1. Coverage: what % of corpus ingredient occurrences resolve to catalog
  2. Gap list: ingredients that appear frequently but aren't in catalog
  3. Alias candidates: corpus names that map to existing catalog entries
  4. Modifier/facet evidence: qualifiers that appear with each ingredient

Usage:
    python analyze_corpus_ingredients.py [--top N] [--min-count N]

Output files (in Scripts/triage_output/):
    corpus_frequency.json        — all normalized ingredients ranked by frequency
    corpus_gaps.json             — frequent ingredients missing from catalog
    corpus_alias_candidates.json — potential new aliases for existing entries
    corpus_coverage_report.txt   — summary statistics
"""

import csv
import json
import re
import sys
import os
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
TRIAGE_DIR = SCRIPT_DIR / "triage_output"
CATALOG_PATH = SCRIPT_DIR.parent / "PantryChef" / "Resources" / "catalog.json"
DATASET_PATH = SCRIPT_DIR.parent / "RecipeNLG" / "RecipeNLG_dataset.csv"

# Minimum corpus occurrences to include in gap report
DEFAULT_MIN_COUNT = 50
# Top N gaps to display in console
DEFAULT_TOP_N = 200

# ---------------------------------------------------------------------------
# Normalization (mirrors IngredientLexicon logic)
# ---------------------------------------------------------------------------

# Modifiers to strip — these are qualifiers, not identity
STRIP_PHRASES = [
    # multi-word first (longest match)
    "low sodium", "low fat", "low calorie", "non fat", "fat free",
    "sugar free", "gluten free", "all purpose", "extra virgin",
    "light brown", "dark brown",
    "semi sweet", "semi-sweet",
    # compound modifiers (hyphens normalized to spaces before this runs)
    "bone in", "skin on", "store bought",
    "room temperature",
    "cream of",  # "cream of mushroom soup" → "mushroom soup" (still a true gap, but cleaner)
]

STRIP_WORDS = {
    # size/quality
    "large", "small", "medium", "big", "thin", "thick",
    # freshness/state — these become facet evidence, not identity
    "fresh", "frozen", "canned", "dried", "dry", "raw", "cooked",
    "roasted", "toasted", "smoked", "grilled", "baked", "fried",
    "steamed", "braised", "pickled", "marinated", "fermented",
    # processing
    "chopped", "diced", "minced", "sliced", "shredded", "grated",
    "crushed", "ground", "whole", "halved", "quartered", "cubed",
    "julienned", "mashed", "pureed", "sifted", "melted", "softened",
    # organic/quality
    "organic", "natural", "pure", "real", "homemade",
    "unsalted", "salted", "sweetened", "unsweetened",
    "blanched", "peeled", "seeded", "pitted", "cored", "trimmed",
    "boneless", "skinless",
    # adverbs (not identity-bearing)
    "freshly", "finely", "thinly", "roughly", "lightly", "coarsely",
    "loosely", "firmly", "newly", "very",
    # measurement words (not identity-bearing)
    "head", "stalk", "sprig", "bunch", "ear", "bulb",
    # temperature/state (not identity-bearing)
    "boiling", "cold", "warm", "lukewarm", "chilled", "cooled",
    "heated", "tepid",
    # filler
    "of", "for", "and", "or", "the", "a", "an", "to", "in",
}

# Modifiers we want to TRACK as facet evidence (not discard entirely)
FACET_EVIDENCE_WORDS = {
    # preservation
    "fresh", "frozen", "canned", "dried", "dry", "pickled", "fermented",
    "smoked", "cured",
    # form
    "ground", "whole", "chopped", "diced", "minced", "sliced", "shredded",
    "grated", "crushed", "cubed", "julienned", "mashed", "pureed",
    # preparation
    "cooked", "raw", "roasted", "toasted", "grilled", "baked", "fried",
    "steamed", "braised", "marinated",
    # processing
    "unsalted", "salted", "sweetened", "unsweetened",
    "boneless", "skinless", "bone-in", "skin-on",
    "bleached", "unbleached", "refined", "unrefined",
    # variant hints
    "extra virgin", "light", "dark", "white", "black", "red", "green",
    "yellow", "sweet", "hot", "mild", "spicy",
}

# Normalized compound forms that should map to a simpler name.
# Applied AFTER normalization to handle measurement-word artifacts.
COMPOUND_OVERRIDES = {
    "clove garlic": "garlic",       # "1 clove garlic" — clove is a unit
    "clove garlic clove": "garlic", # variant ordering
}

# Known irregular plurals
IRREGULAR_PLURALS = {
    "cloves": "clove",
    "leaves": "leaf",
    "halves": "half",
    "loaves": "loaf",
    "knives": "knife",
    "calves": "calf",
    "shelves": "shelf",
    "olives": "olive",
    "chives": "chive",
    "endives": "endive",
    "potatoes": "potato",
    "tomatoes": "tomato",
    "mangoes": "mango",
    "avocados": "avocado",
    "anchovies": "anchovy",
    "chilies": "chili",
    "chilis": "chili",
}

# Pluralization rules
def depluralize(word: str) -> str:
    if len(word) <= 3:
        return word
    # Check irregulars first
    if word in IRREGULAR_PLURALS:
        return IRREGULAR_PLURALS[word]
    if word.endswith("ies") and len(word) > 4:
        return word[:-3] + "y"
    # Skip -ves → -f (too aggressive; handled by irregulars above)
    if word.endswith("oes") and len(word) > 4:
        return word[:-2]
    if word.endswith("ses") or word.endswith("zes") or word.endswith("xes"):
        return word[:-2]
    if word.endswith("ches") or word.endswith("shes"):
        return word[:-2]
    if word.endswith("s") and not word.endswith("ss") and not word.endswith("us"):
        return word[:-1]
    return word


def strip_accents(s: str) -> str:
    """Remove accent marks: jalapeño → jalapeno, gruyère → gruyere."""
    return "".join(
        c for c in unicodedata.normalize("NFD", s)
        if unicodedata.category(c) != "Mn"
    )


def normalize(name: str) -> tuple[str, list[str]]:
    """
    Normalize an ingredient name. Returns (normalized_name, facet_evidence).
    facet_evidence is a list of modifier words found before stripping.
    """
    text = name.lower().strip()
    # Strip accents: jalapeño → jalapeno
    text = strip_accents(text)
    # Remove parentheticals
    text = re.sub(r"\([^)]*\)", "", text)
    # Remove non-alpha except spaces and hyphens
    text = re.sub(r"[^a-z\s-]", " ", text)
    # Normalize hyphens to spaces (so "extra-virgin" matches "extra virgin")
    text = text.replace("-", " ")
    text = re.sub(r"\s+", " ", text).strip()

    # Strip multi-word phrases first
    for phrase in STRIP_PHRASES:
        text = text.replace(phrase, " ")

    tokens = text.split()

    # Collect facet evidence before any modification
    evidence = []
    for t in tokens:
        if t in FACET_EVIDENCE_WORDS:
            evidence.append(t)

    # Depluralize FIRST (so plurals of strip words get caught: "stalks" → "stalk")
    tokens = [depluralize(t) for t in tokens]

    # Strip modifier words (now checks depluralized forms)
    tokens = [t for t in tokens if t not in STRIP_WORDS]

    # Remove empty/short tokens
    tokens = [t for t in tokens if len(t) >= 2]

    normalized = " ".join(tokens)

    # Apply compound overrides
    if normalized in COMPOUND_OVERRIDES:
        normalized = COMPOUND_OVERRIDES[normalized]

    return normalized, evidence


# ---------------------------------------------------------------------------
# Catalog loading
# ---------------------------------------------------------------------------

def _build_facet_map(facets: list) -> dict:
    """Build {facet_key: set(normalized option values)} from catalog facet defs."""
    facet_map = {}
    for facet in facets:
        key = facet.get("key", "")
        options = facet.get("options", [])
        if not key or not options:
            continue
        norm_options = set()
        for opt in options:
            norm_opt = strip_accents(opt.lower().strip())
            norm_options.add(norm_opt)
            for word in norm_opt.split():
                norm_options.add(depluralize(word))
                norm_options.add(word)
        facet_map[key] = norm_options
    return facet_map


def _merge_facet_maps(existing: dict, new: dict) -> dict:
    """Union facet option sets when multiple catalog items share a lookup form."""
    if not existing:
        return new
    if not new:
        return existing
    merged = {}
    for key in set(existing) | set(new):
        merged[key] = set(existing.get(key, set())) | set(new.get(key, set()))
    return merged


def load_catalog():
    """
    Load the production catalog.json (array of item objects).
    Returns:
      - catalog_names: set of normalized catalog ingredient names (exact match, incl. aliases)
      - name_to_category: mapping of normalized name → category
      - raw_catalog: mapping of original item name → category (for inverse report)
      - facet_index: mapping of normalized catalog name → {facet_key: set of normalized option values}
    """
    with open(CATALOG_PATH) as f:
        items = json.load(f)

    catalog_names = set()
    name_to_category = {}
    raw_catalog = {}
    facet_index = {}  # normalized catalog name → {facet_key: {normalized option values}}

    for item in items:
        name = item.get("name", "")
        category = item.get("category", "Other")
        aliases = item.get("aliases", [])
        facets = item.get("facets", [])

        raw_catalog[name] = category
        facet_map = _build_facet_map(facets) if facets else {}

        # Collect every lookup form for this item (name + aliases).
        forms = set()
        norm, _ = normalize(name)
        raw = name.lower().strip()
        if norm:
            forms.add(norm)
        if raw:
            forms.add(raw)
        for alias in aliases:
            anorm, _ = normalize(alias)
            araw = alias.lower().strip()
            if anorm:
                forms.add(anorm)
            if araw:
                forms.add(araw)

        primary_norm, _ = normalize(name)

        for form in forms:
            catalog_names.add(form)
            if form not in name_to_category:
                name_to_category[form] = category
            elif form == primary_norm:
                # Prefer the category of the item whose primary name matches this form.
                name_to_category[form] = category
            if facet_map:
                if form in facet_index:
                    facet_index[form] = _merge_facet_maps(facet_index[form], facet_map)
                else:
                    facet_index[form] = facet_map

    return catalog_names, name_to_category, raw_catalog, facet_index


def build_reverse_facet_index() -> dict:
    """
    Build reverse index: full facet-option string → list of (base_catalog_name, facet_key).

    Reads catalog.json directly so we only index FULL option strings
    (e.g. 'parmesan', 'shallot', 'cayenne', 'goat cheese'), NOT individual
    word fragments from the split-and-depluralize expansion in facet_index.

    Stores ALL matching bases per option — caller picks the best by corpus frequency.
    """
    reverse = defaultdict(list)  # normalized_option → [(base_name, facet_key), ...]
    with open(CATALOG_PATH) as f:
        items = json.load(f)
    for item in items:
        name = item.get("name", "").lower().strip()
        norm_name, _ = normalize(name)
        if not norm_name:
            norm_name = name
        for facet in item.get("facets", []):
            key = facet.get("key", "")
            for opt in facet.get("options", []):
                norm_opt = strip_accents(opt.lower().strip())
                deplural_opt = " ".join(depluralize(w) for w in norm_opt.split())
                for form in {norm_opt, deplural_opt}:
                    if form:
                        reverse[form].append((norm_name, key))
    return dict(reverse)


# Minimum corpus mentions for a base ingredient to be accepted
# as a reverse-facet resolution target. Filters out obscure bases
# like "cress" (for "water") or "babka" (for "nut").
MIN_REVERSE_BASE_COUNT = 1000

# Single-token catalog bases that are too generic or wrong-domain for
# suffix matching without facet coverage (e.g. snack "chip" ≠ baking chips).
WEAK_SUFFIX_BASES = {
    "chip", "crumb", "cube", "mix", "meal", "roll", "ball", "bar", "shell",
    "sprout",  # "bean sprout" ≠ generic sprout
}

# Categories where a bare single-token base is usually the wrong domain
# for suffix compounds (qualifier + snack ≠ recipe ingredient).
WEAK_SUFFIX_CATEGORIES = {"Snacks"}

# Words too generic to resolve via reverse-facet lookup.
# These are standalone words that appear as facet options of specific
# products but whose common meaning is different.
REVERSE_FACET_BLOCKLIST = {
    # generic food categories
    "nut", "herb", "meat", "fish", "sauce", "oil", "water",
    "fruit", "berry", "seed", "vegetable", "grain", "juice",
    # generic forms/shapes/parts
    "filling", "topping", "crust", "shell", "cube", "mix", "meal",
    "roll", "heart", "leaf", "wedge", "strip", "slice", "ring",
    # ambiguous words with primary meanings different from matched variant
    "hamburger", "taco", "regular", "maple", "italian", "liquid",
    "concentrate", "round", "brown",
}


# ---------------------------------------------------------------------------
# Corpus processing
# ---------------------------------------------------------------------------

def process_corpus(dataset_path: Path, progress_interval: int = 250_000):
    """
    Read NER column from RecipeNLG, normalize, count.
    Returns:
      - ingredient_counts: Counter of normalized ingredient names
      - facet_evidence: dict of ingredient → Counter of modifier words
      - raw_variants: dict of normalized name → Counter of raw NER strings
      - total_recipes: int
      - total_ingredient_mentions: int
    """
    import time
    ingredient_counts = Counter()
    facet_evidence = defaultdict(Counter)
    raw_variants = defaultdict(Counter)
    total_recipes = 0
    total_mentions = 0

    # Cache normalize() results — "salt" appears 500K+ times,
    # no need to re-run regex/depluralize each time.
    norm_cache: dict[str, tuple[str, list[str]]] = {}

    def cached_normalize(raw: str) -> tuple[str, list[str]]:
        result = norm_cache.get(raw)
        if result is None:
            result = normalize(raw)
            norm_cache[raw] = result
        return result

    csv.field_size_limit(sys.maxsize)
    t0 = time.time()

    with open(dataset_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader)
        # Find NER column index once
        try:
            ner_idx = header.index("NER")
        except ValueError:
            print("Error: No NER column in CSV header", file=sys.stderr)
            sys.exit(1)

        for i, row in enumerate(reader):
            total_recipes += 1
            if (i + 1) % progress_interval == 0:
                elapsed = time.time() - t0
                rate = (i + 1) / elapsed
                print(f"  {i + 1:>10,} recipes  ({elapsed:.0f}s, {rate:,.0f} rows/s, cache: {len(norm_cache):,})", file=sys.stderr)

            if ner_idx >= len(row):
                continue
            ner_raw = row[ner_idx]
            try:
                ner_items = json.loads(ner_raw)
            except (json.JSONDecodeError, ValueError):
                continue

            for raw_name in ner_items:
                if not raw_name or not isinstance(raw_name, str):
                    continue
                raw_name = raw_name.strip()
                if not raw_name:
                    continue

                total_mentions += 1
                norm, evidence = cached_normalize(raw_name)
                if not norm:
                    continue

                ingredient_counts[norm] += 1
                raw_variants[norm][raw_name.lower()] += 1

                for ev in evidence:
                    facet_evidence[norm][ev] += 1

    elapsed = time.time() - t0
    print(f"  Corpus read complete in {elapsed:.1f}s (cache: {len(norm_cache):,} unique raw names)", file=sys.stderr)
    return ingredient_counts, facet_evidence, raw_variants, total_recipes, total_mentions


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------

def _qualifier_in_facet_options(qualifier: str, facet_options: set[str]) -> bool:
    """Check if a qualifier token matches a facet option (incl. depluralized forms)."""
    q = qualifier.lower()
    q_forms = {q, depluralize(q)}
    if q.endswith("s"):
        q_forms.add(q[:-1])
    return any(form in facet_options for form in q_forms)


def _check_facet_coverage(base_name: str, qualifier_tokens: list[str], facet_index: dict) -> bool:
    """Check if ALL qualifier tokens are covered by facet options for the base."""
    facets = facet_index.get(base_name, {})
    if not facets:
        return False
    all_options = set()
    for opts in facets.values():
        all_options.update(opts)
    for qt in qualifier_tokens:
        if not _qualifier_in_facet_options(qt, all_options):
            return False
    return True


def _suffix_match_allowed(base_name: str, qualifier_tokens: list[str], facet_index: dict,
                          name_to_category: dict) -> bool:
    """Reject suffix matches to weak/generic bases unless facets fully cover qualifiers."""
    base_tokens = base_name.split()
    if len(base_tokens) != 1:
        return True
    facet_covered = _check_facet_coverage(base_name, qualifier_tokens, facet_index)
    if facet_covered:
        return True
    category = name_to_category.get(base_name, "")
    if base_name in WEAK_SUFFIX_BASES or category in WEAK_SUFFIX_CATEGORIES:
        return False
    return True


def _try_partial_match(name: str, catalog_names: set[str], facet_index: dict,
                       name_to_category: dict):
    """
    Try to match a corpus ingredient to a catalog base + qualifier.
    Returns (base_name, qualifier_tokens, facet_covered) or None.

    Strategy:
      - SUFFIX match (base at end): "cheddar cheese" → base="cheese".
        Accept unconditionally — qualifiers before the noun usually
        describe the variant/type.
      - PREFIX match (base at start): "garlic powder" → base="garlic".
        Accept ONLY if all qualifiers are known facet options.
        This avoids false matches like chicken→chicken broth.
      - Prefer the match with the longest base (most tokens).
    """
    name_tokens = name.split()
    if len(name_tokens) < 2:
        return None

    candidates = []  # (base, extra_tokens, match_kind)

    # --- Suffix matching: base is the last N tokens ---
    for i in range(1, len(name_tokens)):
        candidate_base = " ".join(name_tokens[i:])
        if candidate_base not in catalog_names:
            continue
        extra = name_tokens[:i]
        if not extra:
            continue
        if not _suffix_match_allowed(candidate_base, extra, facet_index, name_to_category):
            continue
        candidates.append((candidate_base, extra, "suffix"))
        break  # first hit is the longest suffix base

    # --- Prefix matching: base is the first N tokens ---
    # Accept if qualifiers are ALL covered by facets (strict).
    for i in range(len(name_tokens) - 1, 0, -1):
        candidate_base = " ".join(name_tokens[:i])
        if candidate_base not in catalog_names:
            continue
        extra = name_tokens[i:]
        if extra and _check_facet_coverage(candidate_base, extra, facet_index):
            candidates.append((candidate_base, extra, "prefix"))
            break  # longest prefix that is facet-covered

    # Also accept suffix matches where facets fully cover qualifiers.
    for i in range(1, len(name_tokens)):
        candidate_base = " ".join(name_tokens[i:])
        if candidate_base not in catalog_names:
            continue
        extra = name_tokens[:i]
        if extra and _check_facet_coverage(candidate_base, extra, facet_index):
            if not any(c[0] == candidate_base and c[1] == extra for c in candidates):
                candidates.append((candidate_base, extra, "suffix_covered"))

    if not candidates:
        return None

    def _rank(candidate):
        base, extra, kind = candidate
        base_len = len(base.split())
        facet_covered = _check_facet_coverage(base, extra, facet_index)
        kind_score = {"prefix": 3, "suffix_covered": 2, "suffix": 1}[kind]
        return (facet_covered, base_len, kind_score)

    best_base, best_extra, _ = max(candidates, key=_rank)
    facet_covered = _check_facet_coverage(best_base, best_extra, facet_index)
    return (best_base, best_extra, facet_covered)


def analyze(
    ingredient_counts: Counter,
    facet_evidence: dict,
    raw_variants: dict,
    catalog_names: set[str],
    name_to_category: dict[str, str],
    raw_catalog: dict[str, str],
    facet_index: dict,
    reverse_facet: dict,
    total_recipes: int,
    total_mentions: int,
    min_count: int,
    top_n: int,
):
    """Compute three-bucket coverage, gaps, and inverse analysis.
    
    Buckets:
      1. EXACT MATCH: corpus name matches catalog entry directly
      2. PARTIAL MATCH (facet gap): base ingredient exists, but qualifier
         is missing from facets → enrichment needed
      3. TRUE GAP: no base ingredient match → new entry needed
    """

    # --- Three-bucket coverage ---
    exact_mentions = 0
    exact_unique = 0
    partial_facet_covered_mentions = 0  # base matches AND facet exists
    partial_facet_covered_unique = 0
    partial_facet_gap_mentions = 0      # base matches but facet MISSING
    partial_facet_gap_unique = 0
    true_gap_list = []                  # no base match at all
    facet_gap_list = []                 # base matches, facet missing
    facet_covered_list = []             # base matches, facet exists

    for name, count in ingredient_counts.most_common():
        if name in catalog_names:
            exact_mentions += count
            exact_unique += 1
        else:
            partial = _try_partial_match(name, catalog_names, facet_index, name_to_category)
            if partial is not None:
                base_name, qualifiers, facet_covered = partial
                if facet_covered:
                    # Base exists AND qualifier is a known facet → fully covered
                    partial_facet_covered_mentions += count
                    partial_facet_covered_unique += 1
                    facet_covered_list.append((name, count, base_name, qualifiers))
                else:
                    # Base exists but qualifier NOT in facets → facet gap
                    partial_facet_gap_mentions += count
                    partial_facet_gap_unique += 1
                    facet_gap_list.append((name, count, base_name, qualifiers))
            else:
                # No partial match — try reverse facet lookup for standalone
                # variant names (e.g. "parmesan" → cheese:parmesan)
                skip_rf = name in FACET_EVIDENCE_WORDS or name in REVERSE_FACET_BLOCKLIST
                rfhits = reverse_facet.get(name, []) if not skip_rf else []
                best_rf = None
                best_rf_count = 0
                for rf_base, rf_key in rfhits:
                    base_count = ingredient_counts.get(rf_base, 0)
                    if base_count > best_rf_count:
                        best_rf = (rf_base, rf_key)
                        best_rf_count = base_count
                # Base must be common AND significantly more common than the option
                if best_rf and best_rf_count >= MIN_REVERSE_BASE_COUNT and best_rf_count > count * 2:
                    base_name, facet_key = best_rf
                    partial_facet_covered_mentions += count
                    partial_facet_covered_unique += 1
                    facet_covered_list.append((name, count, base_name, [f"{facet_key}:{name}"]))
                else:
                    true_gap_list.append((name, count))

    total_unique = len(ingredient_counts)

    # Effective coverage = exact matches + partial with facets covered
    covered_mentions = exact_mentions + partial_facet_covered_mentions
    covered_unique = exact_unique + partial_facet_covered_unique
    coverage_by_mention = covered_mentions / total_mentions * 100 if total_mentions else 0
    coverage_by_unique = covered_unique / total_unique * 100 if total_unique else 0

    # Exact-only coverage (stricter)
    exact_coverage_by_mention = exact_mentions / total_mentions * 100 if total_mentions else 0

    # --- True gaps (frequent, no base match at all) ---
    true_gaps = [(name, count) for name, count in true_gap_list if count >= min_count]
    true_gaps.sort(key=lambda x: -x[1])

    # --- Facet gaps (base matches, qualifier missing from facets) ---
    facet_gaps = [(name, count, base, quals) for name, count, base, quals in facet_gap_list if count >= min_count]
    facet_gaps.sort(key=lambda x: -x[1])

    # --- Build output structures ---
    frequency_list = [
        {"name": name, "count": count, "in_catalog": name in catalog_names}
        for name, count in ingredient_counts.most_common()
    ]

    true_gap_output = []
    for name, count in true_gaps[:top_n * 5]:
        top_raw = raw_variants[name].most_common(5)
        top_facets = facet_evidence[name].most_common(10) if name in facet_evidence else []
        true_gap_output.append({
            "name": name,
            "count": count,
            "pct_of_recipes": round(count / total_recipes * 100, 2),
            "raw_variants": [{"text": t, "count": c} for t, c in top_raw],
            "facet_evidence": [{"modifier": m, "count": c} for m, c in top_facets],
        })

    facet_gap_output = []
    for name, count, base, quals in facet_gaps[:top_n * 5]:
        top_raw = raw_variants[name].most_common(5)
        facet_gap_output.append({
            "name": name,
            "count": count,
            "pct_of_recipes": round(count / total_recipes * 100, 2),
            "base_entry": base,
            "missing_qualifiers": quals,
            "base_category": name_to_category.get(base, "unknown"),
            "raw_variants": [{"text": t, "count": c} for t, c in top_raw],
        })

    facet_covered_output = []
    for name, count, base, quals in sorted(facet_covered_list, key=lambda x: -x[1])[:top_n * 5]:
        facet_covered_output.append({
            "name": name,
            "count": count,
            "base_entry": base,
            "matched_qualifiers": quals,
        })

    # --- Inverse: catalog entries NOT found in corpus ---
    # Build a token→corpus_names index for fast containment checks
    # (replaces O(N*M) linear scan with O(N*T) indexed lookup)
    _corpus_token_index: dict[str, set[str]] = defaultdict(set)
    for corpus_name in ingredient_counts:
        for tok in corpus_name.split():
            _corpus_token_index[tok].add(corpus_name)

    unused_catalog = []
    used_catalog = []
    for raw_name, category in sorted(raw_catalog.items()):
        norm, _ = normalize(raw_name)
        raw_lower = raw_name.lower().strip()
        corpus_count = ingredient_counts.get(norm, 0) + ingredient_counts.get(raw_lower, 0)
        if corpus_count == 0 and norm:
            norm_tokens = norm.split()
            if norm_tokens:
                # Intersect token sets to find corpus names containing ALL tokens
                candidates = None
                for tok in norm_tokens:
                    tok_set = _corpus_token_index.get(tok, set())
                    candidates = tok_set if candidates is None else candidates & tok_set
                if candidates:
                    for corpus_name in candidates:
                        corpus_count = ingredient_counts.get(corpus_name, 0)
                        if corpus_count > 0:
                            break
        entry = {
            "name": raw_name,
            "normalized": norm,
            "category": category,
            "corpus_count": corpus_count,
        }
        if corpus_count == 0:
            unused_catalog.append(entry)
        else:
            used_catalog.append(entry)

    used_catalog.sort(key=lambda x: -x["corpus_count"])

    return {
        "coverage": {
            "total_recipes": total_recipes,
            "total_ingredient_mentions": total_mentions,
            "unique_ingredients_in_corpus": total_unique,
            "catalog_size": len(raw_catalog),
            "exact_match_mentions": exact_mentions,
            "exact_match_unique": exact_unique,
            "partial_facet_covered_mentions": partial_facet_covered_mentions,
            "partial_facet_covered_unique": partial_facet_covered_unique,
            "partial_facet_gap_mentions": partial_facet_gap_mentions,
            "partial_facet_gap_unique": partial_facet_gap_unique,
            "true_gap_mentions": sum(c for _, c in true_gap_list),
            "true_gap_unique": len(true_gap_list),
            "covered_mentions_pct": round(coverage_by_mention, 2),
            "covered_unique_pct": round(coverage_by_unique, 2),
            "exact_only_mentions_pct": round(exact_coverage_by_mention, 2),
        },
        "frequency_list": frequency_list,
        "true_gaps": true_gap_output,
        "facet_gaps": facet_gap_output,
        "facet_covered": facet_covered_output,
        "unused_catalog": unused_catalog,
        "used_catalog": used_catalog,
    }


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def write_outputs(results: dict, top_n: int):
    os.makedirs(TRIAGE_DIR, exist_ok=True)
    cov = results["coverage"]

    # 1. Full frequency list
    freq_path = TRIAGE_DIR / "corpus_frequency.json"
    with open(freq_path, "w") as f:
        json.dump(results["frequency_list"], f, indent=2)
    print(f"Wrote {freq_path} ({len(results['frequency_list']):,} entries)")

    # 2. True gaps
    true_gap_path = TRIAGE_DIR / "corpus_true_gaps.json"
    with open(true_gap_path, "w") as f:
        json.dump(results["true_gaps"], f, indent=2)
    print(f"Wrote {true_gap_path} ({len(results['true_gaps']):,} entries)")

    # 3. Facet gaps
    facet_gap_path = TRIAGE_DIR / "corpus_facet_gaps.json"
    with open(facet_gap_path, "w") as f:
        json.dump(results["facet_gaps"], f, indent=2)
    print(f"Wrote {facet_gap_path} ({len(results['facet_gaps']):,} entries)")

    # 4. Facet covered (resolved via base + existing facet)
    facet_covered_path = TRIAGE_DIR / "corpus_facet_covered.json"
    with open(facet_covered_path, "w") as f:
        json.dump(results["facet_covered"], f, indent=2)
    print(f"Wrote {facet_covered_path} ({len(results['facet_covered']):,} entries)")

    # 5. Unused catalog
    unused_path = TRIAGE_DIR / "corpus_unused_catalog.json"
    with open(unused_path, "w") as f:
        json.dump(results["unused_catalog"], f, indent=2)
    print(f"Wrote {unused_path} ({len(results['unused_catalog']):,} unused entries)")

    # 6. Used catalog
    used_path = TRIAGE_DIR / "corpus_used_catalog.json"
    with open(used_path, "w") as f:
        json.dump(results["used_catalog"], f, indent=2)
    print(f"Wrote {used_path} ({len(results['used_catalog']):,} used entries)")

    # --- Build report ---
    total_mentions = cov["total_ingredient_mentions"]
    exact_pct = cov["exact_only_mentions_pct"]
    covered_pct = cov["covered_mentions_pct"]
    facet_covered_pct = round(cov["partial_facet_covered_mentions"] / total_mentions * 100, 1) if total_mentions else 0
    facet_gap_pct = round(cov["partial_facet_gap_mentions"] / total_mentions * 100, 1) if total_mentions else 0
    true_gap_pct = round(cov["true_gap_mentions"] / total_mentions * 100, 1) if total_mentions else 0

    lines = [
        "=" * 70,
        "CORPUS COVERAGE REPORT (THREE-BUCKET ANALYSIS)",
        "=" * 70,
        "",
        f"Recipes analyzed:             {cov['total_recipes']:>12,}",
        f"Ingredient mentions:          {total_mentions:>12,}",
        f"Unique ingredients (corpus):   {cov['unique_ingredients_in_corpus']:>11,}",
        f"Catalog entries:              {cov['catalog_size']:>12,}",
        "",
        "--- COVERAGE BREAKDOWN (by mention) ---",
        "",
        f"  1. EXACT MATCH:             {exact_pct:>6.1f}%  ({cov['exact_match_mentions']:>10,} mentions, {cov['exact_match_unique']:,} unique)",
        f"     Corpus name matches catalog entry directly.",
        "",
        f"  2. PARTIAL + FACET EXISTS:  {facet_covered_pct:>6.1f}%  ({cov['partial_facet_covered_mentions']:>10,} mentions, {cov['partial_facet_covered_unique']:,} unique)",
        f"     Base ingredient in catalog AND qualifier is a known facet option.",
        f"     e.g. 'cheddar cheese' → cheese + variant:cheddar ✓",
        "",
        f"  3. PARTIAL + FACET GAP:     {facet_gap_pct:>6.1f}%  ({cov['partial_facet_gap_mentions']:>10,} mentions, {cov['partial_facet_gap_unique']:,} unique)",
        f"     Base ingredient in catalog BUT qualifier is NOT a facet option.",
        f"     → Enrichment needed on existing catalog entry.",
        "",
        f"  4. TRUE GAP:                {true_gap_pct:>6.1f}%  ({cov['true_gap_mentions']:>10,} mentions, {cov['true_gap_unique']:,} unique)",
        f"     No base ingredient match at all.",
        f"     → New catalog entry needed.",
        "",
        f"  EFFECTIVE COVERAGE (1+2):   {covered_pct:>6.1f}%",
        f"  STRICT COVERAGE (1 only):   {exact_pct:>6.1f}%",
        "",
        "=" * 70,
        f"TOP TRUE GAPS (new catalog entries needed, min {DEFAULT_MIN_COUNT}+ occurrences)",
        "=" * 70,
        "",
    ]

    for i, gap in enumerate(results["true_gaps"][:top_n]):
        raw_examples = ", ".join(f'"{v["text"]}"' for v in gap["raw_variants"][:3])
        lines.append(
            f"  {i+1:>4}. {gap['name']:<35} "
            f"{gap['count']:>8,}x  ({gap['pct_of_recipes']:>5.1f}% of recipes)  "
            f"e.g. {raw_examples}"
        )

    lines.extend([
        "",
        "=" * 70,
        f"TOP FACET GAPS (base exists, qualifier missing, min {DEFAULT_MIN_COUNT}+ occurrences)",
        "=" * 70,
        "",
    ])

    for i, gap in enumerate(results["facet_gaps"][:top_n]):
        raw_examples = ", ".join(f'"{v["text"]}"' for v in gap["raw_variants"][:3])
        lines.append(
            f"  {i+1:>4}. {gap['name']:<35} → base: {gap['base_entry']:<15} "
            f"missing: {gap['missing_qualifiers']}  "
            f"({gap['count']:>7,}x)"
        )

    lines.extend([
        "",
        "=" * 70,
        "UNUSED CATALOG ENTRIES (not found in corpus)",
        "=" * 70,
        "",
        f"  {len(results['unused_catalog'])} of {cov['catalog_size']} catalog entries "
        f"({len(results['unused_catalog'])/cov['catalog_size']*100:.1f}%) "
        f"have NO match in {cov['total_recipes']:,} recipes",
        "",
    ])

    unused_by_cat = defaultdict(list)
    for entry in results["unused_catalog"]:
        unused_by_cat[entry["category"]].append(entry["name"])
    for cat in sorted(unused_by_cat.keys()):
        items = unused_by_cat[cat]
        lines.append(f"  {cat} ({len(items)}):")
        for item in sorted(items):
            lines.append(f"    - {item}")
        lines.append("")

    report = "\n".join(lines) + "\n"
    report_path = TRIAGE_DIR / "corpus_coverage_report.txt"
    with open(report_path, "w") as f:
        f.write(report)
    print(f"Wrote {report_path}")

    # --- Console summary ---
    print()
    # Print header + coverage breakdown
    for line in lines[:30]:
        print(line)
    print()
    # Top 20 true gaps
    true_gap_start = next(i for i, l in enumerate(lines) if "TOP TRUE GAPS" in l)
    for line in lines[true_gap_start:true_gap_start + 23]:
        print(line)
    print(f"  ... ({len(results['true_gaps'])} total true gaps in {true_gap_path})")
    print()
    # Top 20 facet gaps
    facet_gap_start = next(i for i, l in enumerate(lines) if "TOP FACET GAPS" in l)
    for line in lines[facet_gap_start:facet_gap_start + 23]:
        print(line)
    print(f"  ... ({len(results['facet_gaps'])} total facet gaps in {facet_gap_path})")
    print()
    # Unused summary
    unused_start = next(i for i, l in enumerate(lines) if "UNUSED CATALOG" in l)
    for line in lines[unused_start:unused_start + 8]:
        print(line)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    import argparse
    import time
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--top", type=int, default=DEFAULT_TOP_N, help="Top N gaps to display")
    parser.add_argument("--min-count", type=int, default=DEFAULT_MIN_COUNT, help="Minimum corpus count for gap report")
    parser.add_argument("--dataset", type=str, default=str(DATASET_PATH), help="Path to RecipeNLG CSV")
    args = parser.parse_args()

    dataset_path = Path(args.dataset)
    if not dataset_path.exists():
        print(f"Error: Dataset not found at {dataset_path}", file=sys.stderr)
        sys.exit(1)

    if not CATALOG_PATH.exists():
        print(f"Error: Catalog not found at {CATALOG_PATH}", file=sys.stderr)
        sys.exit(1)

    t_start = time.time()

    print(f"Loading catalog from {CATALOG_PATH}...")
    catalog_names, name_to_category, raw_catalog, facet_index = load_catalog()
    reverse_facet = build_reverse_facet_index()
    print(f"  {len(catalog_names)} normalized catalog entries ({len(raw_catalog)} raw, {len(facet_index)} with facet data, {len(reverse_facet)} reverse facet entries)")
    print(f"  Catalog loaded in {time.time() - t_start:.1f}s")

    t_corpus = time.time()
    print(f"\nProcessing corpus from {dataset_path}...")
    print(f"  (2.2M recipes — expect ~2-4 minutes)")
    counts, facets, raw_vars, total_recipes, total_mentions = process_corpus(dataset_path)
    print(f"  Done: {total_recipes:,} recipes, {total_mentions:,} mentions, {len(counts):,} unique")
    print(f"  Corpus processed in {time.time() - t_corpus:.1f}s")

    t_analyze = time.time()
    print(f"\nAnalyzing coverage (min_count={args.min_count})...")
    results = analyze(
        counts, facets, raw_vars,
        catalog_names, name_to_category, raw_catalog, facet_index, reverse_facet,
        total_recipes, total_mentions,
        min_count=args.min_count,
        top_n=args.top,
    )
    print(f"  Analysis complete in {time.time() - t_analyze:.1f}s")

    t_write = time.time()
    print(f"\nWriting outputs...")
    write_outputs(results, top_n=args.top)
    print(f"  Outputs written in {time.time() - t_write:.1f}s")
    print(f"\nTotal elapsed: {time.time() - t_start:.1f}s")


if __name__ == "__main__":
    main()
