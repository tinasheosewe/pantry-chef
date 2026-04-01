#!/usr/bin/env python3
"""Find the correct USDA descriptions for mismatched golden cases."""

import sys
sys.path.insert(0, ".")

from ml_approaches.shared import load_usda_foods
from rapidfuzz import fuzz

foods = load_usda_foods()

# Golden case descriptions that returned [NOT FOUND]
targets = [
    "MARS SNACKFOOD US, M&M's Semisweet Chocolate Mini Baking Bits",
    "KRAFT, VELVEETA, Pasteurized Process Cheese Spread",
    "Flour, wheat, all-purpose, enriched, bleached",
    "Chicken, broilers or fryers, breast, skinless, boneless, meat only, raw",
    "Salmon, Atlantic, wild, raw",
    "Coconut oil",
    "Cream cheese, fat free",
    "Beef, ground, 85% lean / 15% fat, raw",
    "Turkey, all classes, breast, meat only, cooked, roasted",
    "Tea, brewed, prepared with tap water",
    "Coffee, brewed, prepared with tap water",
]

for t in targets:
    print(f"\n{'='*70}")
    print(f"GOLDEN: {t}")
    
    # Find top 3 fuzzy matches
    scored = []
    for food in foods:
        desc = food.get("description", "")
        score = fuzz.token_sort_ratio(t.lower(), desc.lower())
        scored.append((score, desc))
    scored.sort(key=lambda x: -x[0])
    
    for score, desc in scored[:3]:
        print(f"  [{score:5.1f}] {desc}")
