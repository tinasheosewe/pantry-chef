#!/usr/bin/env python3
"""
EDA on substitutions.json — surface quality issues and statistics.
"""
import json
from collections import defaultdict, Counter

with open("PantryChef/Resources/substitutions.json") as f:
    data = json.load(f)

meta = data.get("_meta", {})
subs = data["substitutions"]

print("=" * 70)
print("METADATA")
print("=" * 70)
for k, v in meta.items():
    print(f"  {k}: {v}")

print()
print("=" * 70)
print("BASIC STATS")
print("=" * 70)
all_entries = [(ingr, s) for ingr, elist in subs.items() for s in elist]
total_ingr = len(subs)
total_entries = len(all_entries)
enriched_ingr = sum(1 for elist in subs.values() if any(s.get("enriched") for s in elist))
unenriched_only = total_ingr - enriched_ingr
counts = Counter(len(v) for v in subs.values())
print(f"  Total ingredients: {total_ingr}")
print(f"  Total substitution entries: {total_entries}")
print(f"  Ingredients with hand-curated subs: {enriched_ingr}")
print(f"  Ingredients with MISKG-only subs: {unenriched_only}")
print(f"  Avg subs per ingredient: {total_entries / total_ingr:.1f}")
print(f"  Distribution: {dict(sorted(counts.items()))}")

# Ingredients with no substitutes (shouldn't exist by construction, but check)
empty = [k for k, v in subs.items() if not v]
if empty:
    print(f"\n  ⚠ Empty entries: {empty[:10]}")

print()
print("=" * 70)
print("SUSPICIOUS SUBSTITUTIONS (meat for vegetables / category mismatch)")
print("=" * 70)

MEATS = {"ham", "bacon", "chicken", "beef", "pork", "lamb", "turkey", "sausage",
          "meat", "salami", "pepperoni", "prosciutto", "anchovy", "anchovies",
          "tuna", "shrimp", "salmon", "lard", "ground beef", "ground pork"}
DAIRY = {"butter", "cream", "milk", "cheese", "yogurt", "sour cream", "whey"}
SWEET = {"sugar", "honey", "maple syrup", "agave", "molasse", "caramel",
         "chocolate", "candy", "syrup"}
VEGGIES = {"pepper", "chili", "chile", "carrot", "broccoli", "spinach",
           "tomato", "onion", "garlic", "celery", "mushroom", "zucchini",
           "asparagus", "cucumber", "lettuce", "kale", "leek", "fennel",
           "artichoke", "eggplant", "pea", "lentil", "bean"}

def tag(name):
    n = name.lower()
    if any(m in n for m in MEATS):
        return "meat"
    if any(d == n or n.startswith(d) for d in DAIRY):
        return "dairy"
    if any(s in n for s in SWEET):
        return "sweet"
    if any(v in n for v in VEGGIES):
        return "veggie"
    return "other"

suspicious = []
for ingr, elist in subs.items():
    ingr_tag = tag(ingr)
    if ingr_tag == "other":
        continue
    for s in elist:
        sub_name = s["substitute"]
        sub_tag = tag(sub_name)
        if ingr_tag != sub_tag and sub_tag != "other":
            suspicious.append((ingr, sub_name, ingr_tag, sub_tag))

print(f"  Found {len(suspicious)} cross-category pairings:\n")
for ingr, sub, it, st in sorted(suspicious, key=lambda x: x[0])[:40]:
    print(f"  ⚠  {ingr} ({it}) → {sub} ({st})")

print()
print("=" * 70)
print("HAM AS SUBSTITUTE — all cases")
print("=" * 70)
ham_cases = [(ingr, s) for ingr, elist in subs.items()
             for s in elist if "ham" in s["substitute"].lower()]
if ham_cases:
    for ingr, s in sorted(ham_cases, key=lambda x: x[0]):
        print(f"  {ingr} → {s['substitute']}")
else:
    print("  None found.")

print()
print("=" * 70)
print("MOST COMMON SUBSTITUTES (top 20 — high frequency = suspiciously generic)")
print("=" * 70)
sub_counter = Counter(s["substitute"] for _, s in all_entries)
for sub, count in sub_counter.most_common(20):
    print(f"  {count:4d}x  {sub}")

print()
print("=" * 70)
print("SELF-SUBSTITUTION CHECK")
print("=" * 70)
self_subs = [(ingr, s["substitute"]) for ingr, elist in subs.items()
             for s in elist if ingr.lower().strip() == s["substitute"].lower().strip()]
if self_subs:
    print(f"  ⚠ Found {len(self_subs)}: {self_subs[:10]}")
else:
    print("  None found ✓")

print()
print("=" * 70)
print("VERY SHORT / NONSENSE SUBSTITUTES")
print("=" * 70)
short = [(ingr, s["substitute"]) for ingr, elist in subs.items()
         for s in elist if len(s["substitute"].strip().split()) <= 1 and len(s["substitute"].strip()) < 4]
if short:
    for ingr, sub in short[:20]:
        print(f"  {ingr} → '{sub}'")
else:
    print("  None ✓")

print()
print("=" * 70)
print("SAMPLE: 10 RANDOM MISKG-ONLY INGREDIENTS")
print("=" * 70)
import random
random.seed(42)
miskg_only = [(k, v) for k, v in subs.items()
              if all(not s.get("enriched") for s in v)]
sample = random.sample(miskg_only, min(10, len(miskg_only)))
for ingr, elist in sorted(sample, key=lambda x: x[0]):
    sub_names = [s["substitute"] for s in elist]
    print(f"  {ingr}: {sub_names}")

print()
print("=" * 70)
print("NUTRITION IMPACT DISTRIBUTION")
print("=" * 70)
impacts = Counter(s.get("nutritionImpact", "N/A") for _, s in all_entries)
for impact, count in impacts.most_common(15):
    bar = "█" * (count // 20)
    print(f"  {count:5d}  {impact:<35} {bar}")
