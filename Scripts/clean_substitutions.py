#!/usr/bin/env python3
"""
Post-processing cleaner for substitutions.json.

Run after preprocess_miskg.py to apply targeted manual fixes:
  1.  Rename truncated / garbled key names  (stemming artifacts)
  2.  Fix the same typos inside substitute values
  3.  Remove non-food / kitchen-tool entries
  4.  Merge fragmented yeast variants into one canonical "yeast" key
  5.  Normalise a few remaining name inconsistencies
  6.  Patch missing common-ingredient holes

Usage:
    python3 Scripts/clean_substitutions.py
"""

import json
from pathlib import Path
from copy import deepcopy

ROOT = Path(__file__).parent.parent
INPUT  = ROOT / "PantryChef/Resources/substitutions.json"
OUTPUT = INPUT   # overwrite in place (preprocess_miskg.py is the canonical source)

# ─────────────────────────────────────────────────────────────────
# 1.  TRUNCATED KEY RENAMES
#     These are stemming artifacts where the last few characters
#     were stripped.  Value: (correct_name, merge_strategy)
#     merge_strategy:
#       "replace"  – drop the old key, insert under new name
#       "merge"    – combine both lists (deduped), keep enriched entries
# ─────────────────────────────────────────────────────────────────
KEY_RENAMES = {
    # stemming / chopping artifacts
    "asparagu":             "asparagus",
    "baby octopu":          "baby octopus",
    "octopu":               "octopus",
    "watercres":            "watercress",
    "beaujolai":            "beaujolais",
    "black sea bas":        "black sea bass",
    "sea bas":              "sea bass",
    "striped bas":          "striped bass",
    "cape capensi":         "cape capensis",
    "molass":               "molasses",
    "blackstrap molass":    "blackstrap molasses",
    "pomegranate molass":   "pomegranate molasses",
    "saccarin":             "saccharin",
    "dianthu":              "dianthus",
    "pickled asparagu":     "pickled asparagus",
    "white asparagu":       "white asparagus",
    "peppermint schnapp":   "peppermint schnapps",
    "egg roll wraper":      "egg roll wrapper",
    # minor name inconsistencies
    "basmati":              "basmati rice",   # if present without "rice"
    "couscou":              "couscous",
}

# ─────────────────────────────────────────────────────────────────
# 2.  SUBSTITUTE VALUE TYPO MAP
#     When a truncated / misspelled name appears as a *value*
#     inside another ingredient's entry, fix it here.
# ─────────────────────────────────────────────────────────────────
SUB_VALUE_FIXES = {
    "watercres":            "watercress",
    "asparagu":             "asparagus",
    "octopu":               "octopus",
    "beaujolai":            "beaujolais",
    "molass":               "molasses",
    "saccarin":             "saccharin",
    "blackstrap molass":    "blackstrap molasses",
    "pomegranate molass":   "pomegranate molasses",
    "baby octopu":          "baby octopus",
    "sea bas":              "sea bass",
    "striped bas":          "striped bass",
    "black sea bas":        "black sea bass",
    "cape capensi":         "cape capensis",
    "dianthu":              "dianthus",
    "white asparagu":       "white asparagus",
    "pickled asparagu":     "pickled asparagus",
    "peppermint schnapp":   "peppermint schnapps",
    "egg roll wraper":      "egg roll wrapper",
    "couscou":              "couscous",
}

# ─────────────────────────────────────────────────────────────────
# 3.  NON-FOOD / KITCHEN-EQUIPMENT KEYS TO REMOVE
#     These passed the bidirectionality gate because cooking sites
#     mention swapping one piece of equipment for another, but they
#     do not belong in an ingredient substitution database.
# ─────────────────────────────────────────────────────────────────
NON_FOOD_KEYS = {
    "aluminum foil",
    "basting brush",
    "blender",
    "bread knife",
    "broiler pan",
    "bulb baster",
    "casserole pot",
    "chef knife",
    "clay pot",         # too ambiguous; cuisines name this an ingredient vessel
    "food processor",
    "instant pot",
    "plastic wrap",
    "roasting pan",
    "wax paper",
}

# ─────────────────────────────────────────────────────────────────
# 4.  YEAST MERGE
#     "active dry yeast", "instant yeast", "fresh yeast",
#     "bread machine yeast", "baker s yeast"
#     → all collapse into canonical key "yeast"
#     "nutritional yeast" and "brewer s yeast" stay separate
#     (completely different culinary role).
# ─────────────────────────────────────────────────────────────────
YEAST_VARIANTS_TO_ABSORB = {
    "active dry yeast",
    "instant yeast",
    "fresh yeast",
    "bread machine yeast",
    "baker s yeast",
}

# The canonical substitutes for a generic "yeast" key.
# Ordered: most-useful first (baking perspective).
YEAST_CANONICAL_SUBS = [
    {"substitute": "instant yeast",       "nutritionImpact": "neutral",      "enriched": False,
     "notes": "Use 25% less than active dry; no blooming needed.", "ratio": "0.75:1"},
    {"substitute": "active dry yeast",    "nutritionImpact": "neutral",      "enriched": False,
     "notes": "Bloom in warm water (105–115 °F) before use.", "ratio": "1.25:1"},
    {"substitute": "fresh yeast",         "nutritionImpact": "neutral",      "enriched": False,
     "notes": "Use 2× the dry yeast amount; highly perishable.", "ratio": "2:1"},
    {"substitute": "bread machine yeast", "nutritionImpact": "neutral",      "enriched": False,
     "notes": "Fine granules; also called rapid-rise yeast.", "ratio": "1:1"},
    {"substitute": "baking powder",       "nutritionImpact": "lower protein", "enriched": False,
     "notes": "Emergency leavener only – no fermentation flavour."},
]

# ─────────────────────────────────────────────────────────────────
# 5.  HOLES TO PATCH  (common ingredients with no entry yet)
#     Value is a minimal list of substitute entries.
# ─────────────────────────────────────────────────────────────────
PATCHES = {
    "couscous": [
        {"substitute": "quinoa",           "nutritionImpact": "higher protein, gluten-free", "enriched": False},
        {"substitute": "bulgur",           "nutritionImpact": "similar calories",             "enriched": False},
        {"substitute": "rice",             "nutritionImpact": "similar calories",             "enriched": False},
        {"substitute": "orzo",             "nutritionImpact": "similar calories",             "enriched": False},
        {"substitute": "millet",           "nutritionImpact": "similar, gluten-free",         "enriched": False},
    ],
    "hummus": [
        {"substitute": "baba ganoush",     "nutritionImpact": "lower protein",  "enriched": False},
        {"substitute": "white bean dip",   "nutritionImpact": "similar protein", "enriched": False},
        {"substitute": "tzatziki",         "nutritionImpact": "lower calories",  "enriched": False},
        {"substitute": "guacamole",        "nutritionImpact": "higher fat",      "enriched": False},
    ],
    "broccolini": [
        {"substitute": "broccoli",         "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "chinese broccoli", "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "asparagus",        "nutritionImpact": "similar",         "enriched": False},
    ],
    "cauliflower rice": [
        {"substitute": "riced broccoli",   "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "quinoa",           "nutritionImpact": "higher protein",  "enriched": False},
        {"substitute": "rice",             "nutritionImpact": "higher carbs",    "enriched": False},
    ],
    "zucchini noodles": [
        {"substitute": "spaghetti squash", "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "shirataki",        "nutritionImpact": "lower calories",  "enriched": False},
        {"substitute": "pasta",            "nutritionImpact": "higher carbs",    "enriched": False},
    ],
    "coconut aminos": [
        {"substitute": "soy sauce",        "nutritionImpact": "higher sodium",   "enriched": False},
        {"substitute": "tamari",           "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "liquid aminos",    "nutritionImpact": "similar",         "enriched": False},
    ],
    "flax egg": [
        {"substitute": "chia egg",         "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "egg",              "nutritionImpact": "higher protein",  "enriched": False},
        {"substitute": "aquafaba",         "nutritionImpact": "lower fat",       "enriched": False},
    ],
    "chia egg": [
        {"substitute": "flax egg",         "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "egg",              "nutritionImpact": "higher protein",  "enriched": False},
        {"substitute": "aquafaba",         "nutritionImpact": "lower fat",       "enriched": False},
    ],
    "mushroom broth": [
        {"substitute": "vegetable broth",  "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "beef broth",       "nutritionImpact": "higher protein",  "enriched": False},
        {"substitute": "water",            "nutritionImpact": "lower sodium",    "enriched": False},
    ],
    "monterey jack": [
        {"substitute": "colby jack",       "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "cheddar",          "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "muenster",         "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "havarti",          "nutritionImpact": "similar",         "enriched": False},
    ],
    "colby jack": [
        {"substitute": "monterey jack",    "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "cheddar",          "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "colby",            "nutritionImpact": "similar",         "enriched": False},
    ],
    "ricotta": [
        {"substitute": "cottage cheese",   "nutritionImpact": "higher protein",  "enriched": False},
        {"substitute": "cream cheese",     "nutritionImpact": "higher fat",      "enriched": False},
        {"substitute": "tofu",             "nutritionImpact": "lower fat",       "enriched": False},
        {"substitute": "mascarpone",       "nutritionImpact": "higher fat",      "enriched": False},
    ],
    "pecorino romano": [
        {"substitute": "parmesan",         "nutritionImpact": "milder flavour",  "enriched": False},
        {"substitute": "asiago aged",      "nutritionImpact": "similar",         "enriched": False},
        {"substitute": "grana padano",     "nutritionImpact": "milder flavour",  "enriched": False},
    ],
}

# ─────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────

def dedup_entries(entries):
    """Deduplicate entries by substitute name, preserving enriched ones first."""
    seen = {}
    for e in entries:
        s = e["substitute"]
        if s not in seen or (e.get("enriched") and not seen[s].get("enriched")):
            seen[s] = e
    return list(seen.values())

def apply_sub_value_fixes(entries, fix_map):
    """Fix typos in the substitute field of a list of entries."""
    fixed = []
    for e in entries:
        e2 = dict(e)
        if e2["substitute"] in fix_map:
            e2["substitute"] = fix_map[e2["substitute"]]
        fixed.append(e2)
    return fixed

# ─────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────

def clean(data):
    subs = data["substitutions"]
    report = {
        "renamed_keys": [],
        "sub_value_fixes": [],
        "removed_non_food": [],
        "yeast_merge": [],
        "patches_added": [],
        "enriched_protected": [],
    }

    # ── STEP 1: rename truncated keys ──────────────────────────
    for old_key, new_key in KEY_RENAMES.items():
        if old_key not in subs:
            continue
        entries = subs.pop(old_key)
        if new_key in subs:
            # Merge: combine, keep enriched entries, dedup
            combined = subs[new_key] + entries
            subs[new_key] = dedup_entries(combined)
            report["renamed_keys"].append(f"MERGE  {old_key!r} -> {new_key!r}")
        else:
            subs[new_key] = entries
            report["renamed_keys"].append(f"RENAME {old_key!r} -> {new_key!r}")

    # ── STEP 2: fix substitute values everywhere ────────────────
    for key in list(subs.keys()):
        original = [e["substitute"] for e in subs[key]]
        fixed = apply_sub_value_fixes(subs[key], SUB_VALUE_FIXES)
        subs[key] = fixed
        changed = [
            f"{o!r} -> {n['substitute']!r}"
            for o, n in zip(original, fixed)
            if o != n["substitute"]
        ]
        if changed:
            report["sub_value_fixes"].append(f"{key}: {changed}")

    # ── STEP 3: remove non-food keys ────────────────────────────
    for key in NON_FOOD_KEYS:
        if key in subs:
            entries = subs.pop(key)
            # Protect enriched entries — they were hand-curated
            enriched = [e for e in entries if e.get("enriched")]
            if enriched:
                report["enriched_protected"].append(
                    f"NON_FOOD key {key!r} had enriched entries – KEPT"
                )
                subs[key] = entries  # put back
            else:
                report["removed_non_food"].append(key)

    # Also remove these keys from substitute values
    # (e.g. "butter": [..., "blend in blender"] type noise — not present here,
    # but good practice to scrub tools from value lists too)
    for key in list(subs.keys()):
        before = len(subs[key])
        subs[key] = [e for e in subs[key] if e["substitute"] not in NON_FOOD_KEYS]
        if len(subs[key]) < before:
            report["removed_non_food"].append(
                f"  → removed tool ref from {key!r} values"
            )

    # ── STEP 4: yeast merge ──────────────────────────────────────
    # Collect any useful extra subs from the variant keys
    extra_yeast_subs = []
    for variant_key in YEAST_VARIANTS_TO_ABSORB:
        if variant_key in subs:
            for e in subs[variant_key]:
                # Only carry forward subs that aren't themselves yeast variants
                if e["substitute"] not in YEAST_VARIANTS_TO_ABSORB and e["substitute"] != "yeast":
                    extra_yeast_subs.append(e)
            del subs[variant_key]
            report["yeast_merge"].append(f"absorbed {variant_key!r}")

    # Build the canonical yeast entry
    base = YEAST_CANONICAL_SUBS[:]
    if "yeast" in subs:
        # Merge: keep existing enriched entries, add canonical, then extras
        existing = subs["yeast"]
        enriched_existing = [e for e in existing if e.get("enriched")]
        if enriched_existing:
            base = enriched_existing + base
    subs["yeast"] = dedup_entries(base + extra_yeast_subs)
    report["yeast_merge"].append("wrote canonical 'yeast' entry")

    # Also remove yeast-variant references from all substitute value lists
    for key in list(subs.keys()):
        if key == "yeast":
            continue
        before = len(subs[key])
        # Keep a ref if the entry maps a variant to the canonical yeast
        # Logic: only strip if the substitute IS a yeast variant key we absorbed
        subs[key] = [
            e for e in subs[key]
            if e["substitute"] not in YEAST_VARIANTS_TO_ABSORB
            or e["substitute"] == "yeast"
        ]
        if len(subs[key]) < before:
            report["yeast_merge"].append(
                f"  → stripped variant yeast subs from {key!r}"
            )
        # Replace stripped yeast-variant sub values with canonical "yeast"
        # But only if the key itself isn't a yeast concept
        # (avoids adding "yeast" as a sub of "brewer s yeast" nonsensically)

    # ── STEP 5: patches for missing holes ───────────────────────
    for key, entries in PATCHES.items():
        if key not in subs:
            subs[key] = entries
            report["patches_added"].append(key)
        else:
            # Key exists; only add subs that are missing
            existing_subs = {e["substitute"] for e in subs[key]}
            new_entries = [e for e in entries if e["substitute"] not in existing_subs]
            if new_entries:
                subs[key].extend(new_entries)
                report["patches_added"].append(f"{key} (extended)")

    # ── STEP 6: drop empty entries ───────────────────────────────
    empty = [k for k, v in subs.items() if len(v) == 0]
    for k in empty:
        del subs[k]

    # ── UPDATE META ──────────────────────────────────────────────
    # Replace meta counts in place (preprocess_miskg.py uses camelCase keys)
    meta = data["_meta"]
    meta["totalIngredients"] = len(subs)
    meta["totalSubstitutions"] = sum(len(v) for v in subs.values())
    # Remove any duplicate keys added by previous runs of this script
    for k in ["total_ingredients", "total_entries", "notes"]:
        meta.pop(k, None)

    return data, report


if __name__ == "__main__":
    print(f"Loading {INPUT} …")
    with open(INPUT) as f:
        data = json.load(f)

    before_keys  = len(data["substitutions"])
    before_total = sum(len(v) for v in data["substitutions"].values())

    data, report = clean(data)

    after_keys  = len(data["substitutions"])
    after_total = sum(len(v) for v in data["substitutions"].values())

    print(f"\n── REPORT ────────────────────────────────────────────")
    print(f"\n[1] Key renames ({len(report['renamed_keys'])}):")
    for r in report["renamed_keys"]:
        print(f"    {r}")

    print(f"\n[2] Substitute value fixes ({len(report['sub_value_fixes'])}):")
    for r in report["sub_value_fixes"]:
        print(f"    {r}")

    print(f"\n[3] Non-food keys removed ({len(report['removed_non_food'])}):")
    for r in report["removed_non_food"]:
        print(f"    {r}")

    if report["enriched_protected"]:
        print(f"\n[!] Enriched entries protected:")
        for r in report["enriched_protected"]:
            print(f"    {r}")

    print(f"\n[4] Yeast merge:")
    for r in report["yeast_merge"]:
        print(f"    {r}")

    print(f"\n[5] Patches added ({len(report['patches_added'])}):")
    for r in report["patches_added"]:
        print(f"    {r}")

    print(f"\n── SUMMARY ───────────────────────────────────────────")
    print(f"  Keys  : {before_keys:,} → {after_keys:,}  (Δ {after_keys - before_keys:+d})")
    print(f"  Entries: {before_total:,} → {after_total:,}  (Δ {after_total - before_total:+d})")

    # Write compact JSON to match preprocess_miskg.py's output format
    with open(OUTPUT, "w") as f:
        json.dump(data, f, ensure_ascii=False)
    print(f"\nSaved to {OUTPUT}")
