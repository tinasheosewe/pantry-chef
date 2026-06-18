#!/usr/bin/env python3
"""Fold the recipe-essentiality classification (docs/recipe-essentiality/chunk-*.json)
into PantryChef/Resources/seed_recipes.json.

Sets an explicit `optional` bool on EVERY seed ingredient (true for the lines the agents
flagged droppable, false otherwise) so the data — not RecipeLine.isLikelyOptional — governs
essentiality for seed dishes. RecipeSeed reads `optional` first and only falls back to the
heuristic when it's absent.

Guard: a recipe must keep a core — if a chunk somehow marks ALL of a recipe's ingredients
optional, we ignore that recipe's marks (leave everything essential) and flag it.
"""
import json, glob, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = os.path.join(ROOT, "PantryChef/Resources/seed_recipes.json")
CHUNKS = os.path.join(ROOT, "docs/recipe-essentiality")

def main():
    data = json.load(open(SEED))
    recipes = data["recipes"]
    by_name = {}
    for idx, r in enumerate(recipes):
        by_name.setdefault(r["name"].lower(), idx)

    # recipe index -> set of optional ingredient indices
    optional_by_recipe = {}
    warn, matched_recipes = [], set()
    for f in sorted(glob.glob(os.path.join(CHUNKS, "chunk-*.json"))):
        chunk = json.load(open(f))
        for entry in chunk.get("recipes", []):
            idx = entry.get("index")
            name = entry.get("name", "")
            # resolve the recipe: trust index if name matches, else fall back to name
            if not (isinstance(idx, int) and 0 <= idx < len(recipes) and
                    recipes[idx]["name"].lower() == name.lower()):
                idx = by_name.get(name.lower())
                if idx is None:
                    warn.append(f"{os.path.basename(f)}: recipe '{name}' not found"); continue
            matched_recipes.add(idx)
            opt = set()
            for o in entry.get("optional", []):
                i = o.get("i"); nm = o.get("name", "")
                ings = recipes[idx]["ingredients"]
                if isinstance(i, int) and 0 <= i < len(ings) and ings[i]["name"].lower() == nm.lower():
                    opt.add(i)
                else:
                    # index drifted — match the optional line by name within the recipe
                    hit = next((j for j, g in enumerate(ings) if g["name"].lower() == nm.lower()), None)
                    if hit is not None: opt.add(hit)
                    else: warn.append(f"{recipes[idx]['name']}: optional '{nm}' (i={i}) not found")
            optional_by_recipe[idx] = opt

    # apply: explicit optional bool on every ingredient of every covered recipe
    total_opt = 0; all_opt_recipes = []; zero_opt = 0
    for idx, r in enumerate(recipes):
        ings = r["ingredients"]
        opt = optional_by_recipe.get(idx, set())
        if opt and len(opt) >= len(ings):
            all_opt_recipes.append(r["name"]); opt = set()      # guard: keep the core
        if not opt: zero_opt += 1
        for j, g in enumerate(ings):
            g["optional"] = (j in opt)
            if j in opt: total_opt += 1

    missing = [recipes[i]["name"] for i in range(len(recipes)) if i not in matched_recipes]

    json.dump(data, open(SEED, "w"), indent=1, ensure_ascii=False)
    open(SEED, "a").write("\n")

    print(f"recipes: {len(recipes)} | classified: {len(matched_recipes)} | optional marks: {total_opt}")
    print(f"recipes with 0 optional: {zero_opt}")
    if all_opt_recipes:
        print(f"!! ALL-optional (guarded → kept essential): {all_opt_recipes}")
    if missing:
        print(f"!! recipes not covered by any chunk ({len(missing)}): {missing[:10]}")
    if warn:
        print(f"\nWARN ({len(warn)}):")
        for w in warn[:40]: print("  ", w)

if __name__ == "__main__":
    main()
