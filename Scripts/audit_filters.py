#!/usr/bin/env python3
"""Audit what each filter actually removes from the bidirectional pair set."""
import json
from collections import defaultdict

DATA_DIR = "Scripts/miskg_data/Competition-Dataset"

MODIFIER_WORDS = {
    "fresh", "dried", "ground", "chopped", "minced", "whole", "large", "small",
    "medium", "raw", "cooked", "frozen", "canned", "organic", "sliced", "diced",
    "crushed", "powdered", "grated", "shredded", "toasted", "roasted",
    "blanched", "smoked", "pickled", "salted", "unsalted", "sweetened",
    "unsweetened", "low", "fat", "nonfat", "reduced", "light", "extra", "virgin",
    "unbleached", "enriched", "instant", "quick", "old", "fashioned",
}

def normalize(name):
    name = name.lower().strip()
    for prefix in ["fresh ", "dried ", "ground ", "chopped ", "minced ", "whole ",
                    "large ", "small ", "medium ", "raw ", "cooked ", "frozen "]:
        if name.startswith(prefix) and len(name) > len(prefix) + 2:
            name = name[len(prefix):]
    for suffix, replacement in [("ies", "y"), ("ves", "f")]:
        if name.endswith(suffix): name = name[:-len(suffix)] + replacement; break
    else:
        if name.endswith("es") and not name.endswith(("ses","ches","shes")): name = name[:-2]
        elif name.endswith("s") and not name.endswith(("ss","us","is")): name = name[:-1]
    return name.strip()

def is_same(a, b):
    na, nb = normalize(a), normalize(b)
    if na == nb: return True
    if len(na) > 3 and len(nb) > 3:
        if na in nb and len(nb) - len(na) < 8: return True
        if nb in na and len(na) - len(nb) < 8: return True
    return False

def is_modifier_variant(a, b):
    wa = set(a.lower().split()) - MODIFIER_WORDS
    wb = set(b.lower().split()) - MODIFIER_WORDS
    return wa == wb and len(wa) > 0

# Load
print("Loading...")
with open(f"{DATA_DIR}/substitution_pairs.json") as f:
    pairs = json.load(f)
with open(f"{DATA_DIR}/edamam.json") as f:
    edamam_raw = json.load(f)

nutrition = {}
for pid, data in edamam_raw.items():
    name = data.get("ingredient_name", "").lower().strip()
    if name and data.get("nutrients"):
        nutrition[name] = data["nutrients"]
known_foods = set(nutrition.keys())

# Build bidirectional set
forward = defaultdict(set)
for p in pairs:
    forward[p["ingredient"].lower().strip()].add(p["substitution"].lower().strip())

bidirectional = set()
for ingr, subs in forward.items():
    for sub in subs:
        if ingr in forward.get(sub, set()):
            bidirectional.add((min(ingr, sub), max(ingr, sub)))

print(f"\nBidirectional pairs: {len(bidirectional)}")

# Now audit each filter independently
self_link_dropped = [(a, b) for a, b in bidirectional if is_same(a, b)]
modifier_dropped  = [(a, b) for a, b in bidirectional if not is_same(a, b) and is_modifier_variant(a, b)]
edamam_dropped    = [(a, b) for a, b in bidirectional
                     if not is_same(a, b) and not is_modifier_variant(a, b)
                     and (a not in known_foods or b not in known_foods)]
surviving         = [(a, b) for a, b in bidirectional
                     if not is_same(a, b) and not is_modifier_variant(a, b)
                     and a in known_foods and b in known_foods]

print(f"\n{'Filter':<30} {'Dropped':>7}  Examples")
print("-" * 80)
print(f"{'is_same (self-links)':<30} {len(self_link_dropped):>7}  {self_link_dropped[:5]}")
print(f"{'is_modifier_variant':<30} {len(modifier_dropped):>7}  {modifier_dropped[:5]}")
print(f"{'Edamam unknown-food':<30} {len(edamam_dropped):>7}")
print(f"{'Surviving (kept)':<30} {len(surviving):>7}")

print(f"\n--- Self-link examples (first 20) ---")
for a, b in sorted(self_link_dropped)[:20]:
    print(f"  {a!r:35} <-> {b!r}")

print(f"\n--- Modifier-variant examples (first 20) ---")
for a, b in sorted(modifier_dropped)[:20]:
    print(f"  {a!r:35} <-> {b!r}")

print(f"\n--- Edamam-dropped examples (first 30) ---")
for a, b in sorted(edamam_dropped)[:30]:
    a_flag = "✓" if a in known_foods else "✗"
    b_flag = "✓" if b in known_foods else "✗"
    print(f"  {a_flag} {a!r:32} <-> {b_flag} {b!r}")
