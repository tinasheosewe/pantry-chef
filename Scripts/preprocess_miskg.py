#!/usr/bin/env python3
"""
Preprocess MISKG data into a compact, high-quality substitution JSON for PantryChef.

Strategy:
1. Normalise every raw MISKG name to a canonical form (canonical_name())
   — strips useless descriptors, collapses "or" combos, merges brand/format noise
2. Keep hand-curated entries as gold standard with full metadata
3. Use MISKG to expand coverage via bidirectionality gate
   (only pairs where A→B AND B→A exist in the dataset)
4. Remove self-links (exact-dup pairs after normalization)
5. Rank substitutes by nutrition similarity; cap at 5 per ingredient
6. Tag each entry as "enriched" (hand-curated) or not

Ingredient IDs from MISKG (original_id, processed_id) are intentionally ignored —
the app looks up substitutions by ingredient name string, not by ontology ID.
"""
import json
import csv
import re
from collections import defaultdict
from pathlib import Path

DATA_DIR = Path("Scripts/miskg_data/Competition-Dataset")
OUTPUT = Path("PantryChef/Resources/substitutions.json")

# ─────────────────────────────────────────────────────────────────
# CANONICAL NAME NORMALISATION
# Applied to EVERY raw MISKG name before the bidirectionality gate,
# so fragmented variants are treated as the same node.
# ─────────────────────────────────────────────────────────────────

# "X or Y" combos → single canonical name (None = drop the pair entirely)
OR_CANON = {
    "beer or ale":                              "beer",
    "bell pepper red or yellow":               "bell pepper",
    "black or red rice":                        None,          # too ambiguous
    "broth beef or chicken":                   "broth",
    "butter or margarine":                     "butter",
    "buttermilk or yogurt":                    None,
    "cake flour or pastry":                    "cake flour",
    "celery good raw or cooked":               "celery",
    "cheddar or vermont sage":                 None,
    "chicken breast or turkey breast":         None,
    "conch or other clam":                     "clam",
    "dark brown sugar or molass":              "dark brown sugar",
    "dill plant fresh or dried":               "dill",
    "extracts such ash lemon or peppermint":   None,
    "gelatin leaf or sheet":                   "gelatin sheets",
    "gelatin powdered plain or unflavored":    "unflavored gelatin",
    "grand marnier or orange flavored liqueur":"orange liqueur",
    "honey or maple syrup":                    None,
    "impatiens or other edible flower":        None,
    "lemon juice or vinegar":                  "lemon juice",
    "lemon juice or white vinegar":            "lemon juice",
    "lime juice or lemon juice":               "lime juice",
    "milk 35 or buttermilk":                   "milk",
    "milk 35 or soy milk":                     "milk",
    "milk buttermilk or sour":                 None,
    "milk evaporated whole or skim":           "evaporated milk",
    "nuts chopped ground or whole":            "mixed nuts",
    "parsley or chervil":                      None,
    "pinto bean bacon drippings or butter":    None,
    "port wine sweet sherry or fruit flavored liqueur": "port wine",
    "rum light or dark":                       "rum",
    "salt or soy":                             None,
    "sherry or bourbon":                       None,
    "soft or fresh bread":                     "bread",
    "sour cream or two":                       "sour cream",
    "sugar brown light or dark":               "brown sugar",
    "sugar or honey":                          None,
    "sugar or to taste":                       None,
    "tapioca instant or quick cooking":        "tapioca",
    "vinegar regular white or cider":          "white vinegar",
    "vodka light run or bandy":                "vodka",
    "water or milk":                           None,
    "white wine vinegar or champagne vinegar": "white wine vinegar",
}

# Explicit full-name → canonical remap (applied after prefix stripping)
NAME_REMAP = {
    # ── Broth/stock/bouillon consolidation ──────────────────────
    # base / reconstituted forms → stock
    "chicken base":                         "chicken stock",
    "chicken base reconstituted":           "chicken stock",
    "chicken soup base":                    "chicken stock",
    "chicken stock base instant":           "chicken stock",
    "beef base":                            "beef stock",
    "beef base reconstituted":              "beef stock",
    "ham soup base":                        "ham stock",
    "clam base":                            "clam broth",
    "lobster base":                         "lobster stock",
    # garlic-flavoured broth → plain broth
    "chicken broth with roasted garlic":    "chicken broth",
    # brand names → generic
    "swanson chicken broth":                "chicken broth",
    "knorr chicken bouillon":               "chicken bouillon",
    # bouillon cube/granule/powder forms → canonical bouillon
    "beef bouillon cube":                   "beef bouillon",
    "beef bouillon cubes reconstituted":    "beef bouillon",
    "beef bouillon granule":                "beef bouillon",
    "beef bouillon powder":                 "beef bouillon",
    "beef stock cube":                      "beef bouillon",
    "beef stock granule":                   "beef bouillon",
    "beef stock powder":                    "beef bouillon",
    "chicken bouillon cube":                "chicken bouillon",
    "chicken bouillon granule":             "chicken bouillon",
    "chicken bouillon powder":              "chicken bouillon",
    "chicken stock cube":                   "chicken bouillon",
    "chicken stock powder":                 "chicken bouillon",
    "chicken flavor instant bouillon":      "chicken bouillon",
    "instant bouillon granule":             "bouillon",
    "instant beef bouillon":                "beef bouillon",
    "instant chicken bouillon":             "chicken bouillon",
    "instant chicken bouillon granule":     "chicken bouillon",
    "instant dashi stock":                  "dashi stock",
    "low sodium beef bouillon cube":        "beef bouillon",
    "low sodium beef bouillon granule":     "beef bouillon",
    "low sodium instant chicken bouillon granule": "chicken bouillon",
    "stock cube":                           "bouillon",
    "vegetable bouillon cube":              "vegetable bouillon",
    "vegetable bouillon cubes reconstituted": "vegetable bouillon",
    "vegetable bouillon granule":           "vegetable bouillon",
    "vegetable stock cube":                 "vegetable bouillon",
    "vegetable stock powder":               "vegetable bouillon",

    # ── Canadian milk fat-percentage notation ───────────────────
    "milk 35":                              "heavy cream",
    "milk 35 hot":                          "heavy cream",
    "35 cream":                             "heavy cream",
    "10 cream":                             "light cream",
    "18 table cream":                       "table cream",
    "cream heavy 36 to 40 fat":             "heavy cream",
    "cream heavy36 to 40 fat":              "heavy cream",
    "cream light 18 to 20 fat":             "light cream",
    "cream light18 to 20 fat":              "light cream",
    "double cream 42 fat":                  "double cream",
    "2 milk":                               "2% milk",
    "milk 2 low fat":                       "2% milk",
    "2 low fat milk":                       "2% milk",
    "2 fat cottage cheese":                 "cottage cheese",
    "1 fat cottage cheese":                 "cottage cheese",
    "1 fat buttermilk":                     "buttermilk",
    "evaporated 2 milk":                    "evaporated milk",
    "milk 05 nonfat":                       "skim milk",

    # ── Lean-percentage ground beef ─────────────────────────────
    "90 lean ground beef":                  "ground beef",
    "93 lean ground beef":                  "ground beef",
    "95 lean ground beef":                  "ground beef",
    "96 lean ground beef":                  "ground beef",

    # ── Fat-free soup variants ───────────────────────────────────
    "98 fat free condensed cream of celery soup":   "cream of celery soup",
    "98 fat free cream of chicken soup":            "cream of chicken soup",
    "98 fat free cream of mushroom soup":           "cream of mushroom soup",
    "fat free half and half":               "half and half",
    "powdered milk low fat and reconstituted": "powdered milk",

    # ── Tortilla sizes → generic ────────────────────────────────
    "10 inch flour tortilla":               "flour tortilla",
    "6 inch flour tortilla":                "flour tortilla",
    "12 inch pizza crust":                  "pizza crust",

    # ── Brand names → generic ───────────────────────────────────
    "betty crocker fudge brownie mix":      "brownie mix",
    "bisquick baking mix":                  "baking mix",
    "bisquick reduced fat baking mix":      "baking mix",
    "eagle brand condensed milk":           "condensed milk",
    "kraft macaroni and cheese":            "macaroni and cheese",
    "mccormick s montreal brand steak seasoning": "steak seasoning",
    "kamut® brand berry":                   "kamut",
    "kamut® brand flake":                   "kamut",
    "kamut® brand wheat":                   "kamut",
    "heinz 57 steak sauce":                 "steak sauce",
    "diet 7 up":                            "diet soda",
    "v 8 juice":                            "vegetable juice",
    "licor 43":                             None,

    # ── Misc noise / junk ───────────────────────────────────────
    "bottled fresh":                        None,
    "ground turkey chicken broth greek yoghurt": None,
    "mayonnaise for use in salads and salad dressings": "mayonnaise",
    "celery good raw or cooked":            "celery",
    "kaffir lime leaf for 1 tablespoon zest": "kaffir lime leaves",
    "diced fresh tomatoes simmered 10 minute": "tomato",
    "long grain and wild rice blend":       "wild rice blend",
    "pork tenderloin 34 cube":             "pork tenderloin",
    "cuttlefish under 8":                   "cuttlefish",

    # ── Kitchen equipment ───────────────────────────────────────
    "apple peeler and corer":               None,
    "mortar and pestle":                    None,

    # ── Stemming/truncation artifacts in raw MISKG data ────────
    "asparagu":                             "asparagus",
    "baby octopu":                          "baby octopus",
    "octopu":                               "octopus",
    "watercres":                            "watercress",
    "beaujolai":                            "beaujolais",
    "black sea bas":                        "black sea bass",
    "sea bas":                              "sea bass",
    "striped bas":                          "striped bass",
    "cape capensi":                         "cape capensis",
    "molass":                               "molasses",
    "blackstrap molass":                    "blackstrap molasses",
    "pomegranate molass":                   "pomegranate molasses",
    "saccarin":                             "saccharin",
    "dianthu":                              "dianthus",
    "pickled asparagu":                     "pickled asparagus",
    "white asparagu":                       "white asparagus",
    "peppermint schnapp":                   "peppermint schnapps",
    "egg roll wraper":                      "egg roll wrapper",
    "basmati":                              "basmati rice",
    "couscou":                              "couscous",
}

# Descriptor prefixes to unconditionally strip
# Order matters — longer prefixes first to avoid partial matches
_STRIP_PREFIXES = [
    "homemade ",
    "bottled ",
    "canned ",
    "frozen ",
]

# Qualifier prefixes to strip ONLY from broth/stock/bouillon names
_BROTH_QUALIFIERS = [
    "fat free low sodium ",
    "fat free ",
    "low fat ",
    "nonfat ",
    "reduced fat ",
    "low sodium ",
    "reduced sodium ",
    "no salt added ",
    "hot ",
    "rich ",
    "gluten free ",
    "vegetarian ",
    "unsalted ",
    "condensed ",
    "instant ",
]

_BROTH_WORDS = {"broth", "stock", "bouillon"}


def canonical_name(raw: str):
    """Return canonical ingredient name, or None to drop this pair entirely."""
    name = raw.lower().strip()

    # 1. Explicit OR-combo table (before anything else)
    if name in OR_CANON:
        return OR_CANON[name]

    # 2. Explicit full-name remap
    if name in NAME_REMAP:
        return NAME_REMAP[name]

    # 3. Strip generic descriptor prefixes
    for prefix in _STRIP_PREFIXES:
        if name.startswith(prefix) and len(name) > len(prefix) + 2:
            name = name[len(prefix):]
            break  # only one prefix per name

    # 4. Re-check explicit remap after prefix stripping
    if name in NAME_REMAP:
        return NAME_REMAP[name]

    # 5. Strip qualifiers from broth/stock/bouillon names
    words = set(name.split())
    if words & _BROTH_WORDS:
        for qp in _BROTH_QUALIFIERS:
            if name.startswith(qp):
                name = name[len(qp):]
                break

    return name if name else None


def normalize(name):
    name = name.lower().strip()
    for prefix in ["fresh ", "dried ", "ground ", "chopped ", "minced ", "whole ",
                    "large ", "small ", "medium ", "raw ", "cooked ", "frozen "]:
        if name.startswith(prefix) and len(name) > len(prefix) + 2:
            name = name[len(prefix):]
    if name.endswith("ies"):
        name = name[:-3] + "y"
    elif name.endswith("ves"):
        name = name[:-3] + "f"
    elif name.endswith("es") and not name.endswith(("ses", "ches", "shes")):
        name = name[:-2]
    elif name.endswith("s") and not name.endswith(("ss", "us", "is")):
        name = name[:-1]
    return name.strip()


def is_same(a, b):
    """Return True only for genuinely identical ingredients (after normalization).
    Deliberately narrow — we don't want to drop valid subs like basil/thai basil
    or blood orange/orange. Just catches exact duplicates and trivial plurals.
    """
    return normalize(a) == normalize(b)


def nutrition_similarity(a_nutr, b_nutr):
    if not a_nutr or not b_nutr:
        return 0.5
    keys = ["ENERC_KCAL", "PROCNT", "FAT", "CHOCDF", "FIBTG"]
    diffs = []
    for k in keys:
        va = a_nutr.get(k, 0) or 0
        vb = b_nutr.get(k, 0) or 0
        if va == 0 and vb == 0:
            continue
        maxv = max(va, vb, 0.01)
        diffs.append(abs(va - vb) / maxv)
    if not diffs:
        return 0.5
    return max(0, 1 - sum(diffs) / len(diffs))


def nutrition_impact_str(orig, sub):
    if not orig or not sub:
        return "Similar"
    labels = {"ENERC_KCAL": "calories", "PROCNT": "protein", "FAT": "fat",
              "CHOCDF": "carbs", "FIBTG": "fiber"}
    diffs = []
    for key, label in labels.items():
        ov = orig.get(key, 0) or 0
        sv = sub.get(key, 0) or 0
        if ov == 0:
            if sv > 5:
                diffs.append("Higher " + label)
            continue
        ratio = sv / ov
        if ratio > 1.3:
            diffs.append("Higher " + label)
        elif ratio < 0.7:
            diffs.append("Lower " + label)
    return ", ".join(diffs[:3]) if diffs else "Similar"


# (is_modifier_variant removed — pairs like old-fashioned oat↔quick oat and
#  fresh yeast↔instant yeast are valid substitutions, not noise to drop)


def main():
    print("Loading data...")

    with open(DATA_DIR / "substitution_pairs.json") as f:
        pairs = json.load(f)
    print("  {} MISKG pairs".format(len(pairs)))

    with open(DATA_DIR / "edamam.json") as f:
        edamam_raw = json.load(f)
    nutrition = {}
    for pid, data in edamam_raw.items():
        name = data.get("ingredient_name", "").lower().strip()
        if name and data.get("nutrients"):
            nutrition[name] = data["nutrients"]
    print("  {} Edamam nutrition entries".format(len(nutrition)))

    with open("PantryChef/Resources/substitutions.json") as f:
        old = json.load(f)
    # Load ONLY hand-curated (enriched=True) entries as the gold standard.
    # Filtering by the enriched flag means this script is idempotent — re-running
    # it won't accidentally promote MISKG entries to curated status.
    all_subs = old.get("substitutions", old)
    curated = {
        k: [e for e in v if e.get("enriched")]
        for k, v in all_subs.items()
    }
    curated = {k: v for k, v in curated.items() if v}
    print("  {} hand-curated ingredients".format(len(curated)))

    # Phase 1: Normalise names and build bidirectionality index
    print("\nPhase 1: Normalising names + building bidirectionality index...")
    # canonical_name() strips descriptor noise (frozen/canned/homemade/bottled),
    # collapses "X or Y" combos, merges brand/format variants, and maps specific
    # problem names to clean canonical forms — all BEFORE the bidirectionality
    # gate so that e.g. "low sodium chicken broth" and "canned chicken broth" and
    # "chicken broth" are treated as the same graph node.
    # Note: ingredient IDs in the raw file (original_id, processed_id) are ignored
    # — the app looks up substitutions by ingredient name string, not by ID.
    forward = defaultdict(set)
    dropped_norm = 0
    for p in pairs:
        a = canonical_name(p["ingredient"])
        b = canonical_name(p["substitution"])
        if a is None or b is None:
            dropped_norm += 1
            continue
        forward[a].add(b)
    print(f"  Dropped {dropped_norm} pairs (non-food / OR-combo drop / junk)")

    bidirectional = set()
    for ingr, subs in forward.items():
        for sub in subs:
            if ingr in forward.get(sub, set()):
                bidirectional.add((min(ingr, sub), max(ingr, sub)))
    print(f"  {len(bidirectional)} bidirectional pairs from {len(forward)} canonical ingredients")

    print("\nPhase 1b: Filtering self-links...")
    # Only filter exact duplicates (after normalization). Edamam is used for
    # ranking only — not as a gate — since its 11K coverage would silently drop
    # thousands of valid bidirectional pairs.
    miskg = defaultdict(set)
    kept = 0
    dropped_same = 0
    for a, b in bidirectional:
        if is_same(a, b):
            dropped_same += 1
            continue
        miskg[a].add(b)
        miskg[b].add(a)
        kept += 1
    print(f"  Kept {kept} pairs -> {len(miskg)} ingredients")
    print(f"  Dropped {dropped_same} exact-duplicate pairs")

    # Phase 2: Rank MISKG substitutes by nutrition similarity
    print("\nPhase 2: Ranking...")
    miskg_ranked = {}
    for ingr, subs in miskg.items():
        ingr_nutr = nutrition.get(ingr, {})
        scored = []
        for sub in subs:
            sim = nutrition_similarity(ingr_nutr, nutrition.get(sub, {}))
            scored.append((sub, sim))
        scored.sort(key=lambda x: -x[1])
        miskg_ranked[ingr] = scored[:5]

    # Phase 3: Merge hand-curated + MISKG
    print("\nPhase 3: Merging...")
    output = {}

    for ingredient, entries in curated.items():
        key = ingredient.lower().strip()
        subs = []
        for e in entries:
            subs.append({
                "substitute": e["substitute"],
                "ratio": e.get("ratio", "1:1"),
                "tasteImpact": e.get("tasteImpact", "none"),
                "textureImpact": e.get("textureImpact", "none"),
                "nutritionImpact": nutrition_impact_str(
                    nutrition.get(key, {}), nutrition.get(e["substitute"].lower(), {})),
                "notes": e.get("notes", ""),
                "dietary": e.get("dietary", []),
                "enriched": True,
            })
        output[key] = subs

    miskg_added = 0
    for ingredient, scored_subs in miskg_ranked.items():
        if ingredient in output:
            existing = {normalize(s["substitute"]) for s in output[ingredient]}
            for sub_name, _ in scored_subs:
                if normalize(sub_name) not in existing and len(output[ingredient]) < 5:
                    output[ingredient].append({
                        "substitute": sub_name,
                        "nutritionImpact": nutrition_impact_str(
                            nutrition.get(ingredient, {}), nutrition.get(sub_name, {})),
                        "enriched": False,
                    })
                    existing.add(normalize(sub_name))
        else:
            subs = []
            for sub_name, _ in scored_subs:
                subs.append({
                    "substitute": sub_name,
                    "nutritionImpact": nutrition_impact_str(
                        nutrition.get(ingredient, {}), nutrition.get(sub_name, {})),
                    "enriched": False,
                })
            if subs:
                output[ingredient] = subs
                miskg_added += 1

    total = sum(len(v) for v in output.values())
    print("  Hand-curated: {}".format(len(curated)))
    print("  MISKG added: {}".format(miskg_added))
    print("  Total: {} ingredients, {} entries".format(len(output), total))

    # Phase 4: Write output
    result = {
        "_meta": {
            "source": "MISKG + hand-curated",
            "license": "CC BY-NC 4.0 (MISKG data)",
            "url": "https://www.kaggle.com/datasets/kanakraj/multimodal-ingredient-substitution",
            "generated": "2026-03-08",
            "note": "TODO: Replace MISKG data with commercially-licensed data before monetization",
            "totalIngredients": len(output),
            "totalSubstitutions": total,
            "enrichedIngredients": len(curated),
            "miskgIngredients": miskg_added,
        },
        "substitutions": dict(sorted(output.items()))
    }

    with open(OUTPUT, "w") as f:
        json.dump(result, f, ensure_ascii=False)

    size_kb = OUTPUT.stat().st_size / 1024
    print("\nWrote {} ({:.0f} KB)".format(OUTPUT, size_kb))

    print("\nSample entries:")
    for name in ["butter", "egg", "garlic", "tofu", "fish sauce", "quinoa",
                  "coconut milk", "sriracha", "tempeh", "tahini"]:
        if name in output:
            subs = output[name]
            enriched = sum(1 for s in subs if s.get("enriched"))
            names = [s["substitute"] for s in subs]
            print("  {}: {} subs ({} enriched) -> {}".format(name, len(subs), enriched, names))


if __name__ == "__main__":
    main()
