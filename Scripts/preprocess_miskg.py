#!/usr/bin/env python3
"""
Preprocess MISKG data into a compact, high-quality substitution JSON for PantryChef.

Strategy:
1. Keep hand-curated entries (45 ingredients) as gold standard with full metadata
2. Use MISKG to expand coverage — but only for ingredients where BOTH the
   ingredient AND substitute are recognized food items in Edamam nutrition DB
3. Filter aggressively: remove self-links, same-category noise, modifier variants
4. Rank substitutes by nutrition similarity
5. Cap at 5 substitutes per ingredient
6. Tag each entry as "enriched" (hand-curated) or not
"""
import json
import csv
import re
from collections import defaultdict, Counter
from pathlib import Path

DATA_DIR = Path("Scripts/miskg_data/Competition-Dataset")
OUTPUT = Path("PantryChef/Resources/substitutions.json")


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
    na, nb = normalize(a), normalize(b)
    if na == nb:
        return True
    if len(na) > 3 and len(nb) > 3:
        if na in nb and len(nb) - len(na) < 8:
            return True
        if nb in na and len(na) - len(nb) < 8:
            return True
    return False


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


MODIFIER_WORDS = {
    "fresh", "dried", "ground", "chopped", "minced", "whole", "large", "small",
    "medium", "raw", "cooked", "frozen", "canned", "organic", "sliced", "diced",
    "crushed", "powdered", "grated", "shredded", "toasted", "roasted",
    "blanched", "smoked", "pickled", "salted", "unsalted", "sweetened",
    "unsweetened", "low", "fat", "nonfat", "reduced", "light", "extra", "virgin",
    "unbleached", "enriched", "instant", "quick", "old", "fashioned",
}

# Things that appear so frequently in MISKG they're meaningless as substitutes.
# They flood results and create nonsense pairings (green chili → ham, etc.)
BLOCKLIST_SUBSTITUTES = {
    # Generic proteins that co-occur in recipes but aren't substitutes for veggies/spices
    "chicken", "beef", "meat", "pork", "ham", "turkey", "lamb",
    "chicken breast", "ground beef", "ground pork", "ground turkey",
    # Generic catch-alls
    "spice", "seasoning", "sauce", "broth", "stock",
    # Over-generic vegetables that appear for everything
    "broccoli", "spinach", "zucchini", "carrot",
}

# Cap how many times the same substitute can appear globally.
# If "ham" or "chicken" appears as a substitute for 50 different things, it's noise.
MAX_GLOBAL_FREQUENCY = 15


def is_modifier_variant(a, b):
    wa = set(a.lower().split()) - MODIFIER_WORDS
    wb = set(b.lower().split()) - MODIFIER_WORDS
    return wa == wb and len(wa) > 0


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
    curated = old.get("substitutions", old)
    print("  {} hand-curated ingredients".format(len(curated)))

    # Phase 1: Build filtered MISKG index
    print("\nPhase 1: Filtering MISKG pairs...")
    known_foods = set(nutrition.keys())
    miskg = defaultdict(set)
    kept = 0
    blocked_generic = 0
    for p in pairs:
        ingr = p["ingredient"].lower().strip()
        sub = p["substitution"].lower().strip()
        if is_same(ingr, sub):
            continue
        if is_modifier_variant(ingr, sub):
            continue
        if ingr not in known_foods or sub not in known_foods:
            continue
        if sub in BLOCKLIST_SUBSTITUTES:
            blocked_generic += 1
            continue
        miskg[ingr].add(sub)
        kept += 1
    print("  Kept {} pairs across {} ingredients".format(kept, len(miskg)))
    print("  Blocked {} generic/noisy substitutes".format(blocked_generic))

    # Apply global frequency cap: if a substitute appears for >MAX_GLOBAL_FREQUENCY
    # different ingredients, it's too generic to be useful (recipe co-occurrence noise)
    sub_freq = Counter(sub for subs in miskg.values() for sub in subs)
    too_common = {sub for sub, freq in sub_freq.items() if freq > MAX_GLOBAL_FREQUENCY}
    if too_common:
        print("  Removing {} over-common substitutes (>{} uses): {}".format(
            len(too_common), MAX_GLOBAL_FREQUENCY, sorted(too_common)[:10]))
        before = sum(len(v) for v in miskg.values())
        miskg = {ingr: {s for s in subs if s not in too_common}
                 for ingr, subs in miskg.items()}
        miskg = {k: v for k, v in miskg.items() if v}  # drop empty
        after = sum(len(v) for v in miskg.values())
        print("  Pairs after freq-cap: {} -> {}".format(before, after))

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
