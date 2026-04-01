#!/usr/bin/env python3
"""Debug why golden cases return [NOT FOUND] in evaluation."""

import json
import sys
sys.path.insert(0, ".")

from ml_approaches.shared import load_usda_foods

foods = load_usda_foods()
print(f"Total USDA foods loaded: {len(foods)}")

# Golden case descriptions to find
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

print("\n=== Checking golden case descriptions against USDA data ===\n")

for t in targets:
    found = False
    t_low = t.lower()
    for food in foods:
        desc = food.get("description", "")
        desc_low = desc.lower()
        if desc_low == t_low or desc_low.startswith(t_low):
            print(f"EXACT MATCH: {t!r}")
            print(f"  USDA desc: {desc!r}")
            found = True
            break
    if not found:
        # Try substring match
        for food in foods:
            desc = food.get("description", "")
            if t_low[:30] in desc.lower():
                print(f"PARTIAL MATCH for: {t!r}")
                print(f"  USDA desc: {desc!r}")
                found = True
                break
    if not found:
        print(f"NOT IN USDA DATA: {t!r}")

# Now check what the taxonomy parser actually produces for items that ARE in the data
print("\n\n=== Checking taxonomy parse output ===\n")

from ml_approaches.shared import ParsedItem
import pathlib, json as j

output_file = pathlib.Path("ml_outputs/parse_taxonomy.json")
if output_file.exists():
    parsed_items = [ParsedItem(**d) for d in j.loads(output_file.read_text())]
    print(f"Total parsed items: {len(parsed_items)}")
    
    for t in targets:
        t_low = t.lower()
        match = None
        for item in parsed_items:
            if item.original_desc.lower() == t_low:
                match = item
                break
            if item.original_desc.lower().startswith(t_low):
                match = item
                break
        if match:
            print(f"FOUND in parse output: {t[:60]}")
            print(f"  parsed_name={match.parsed_name}, base={match.parsed_base}")
        else:
            # Try substring
            for item in parsed_items:
                if t_low[:30] in item.original_desc.lower():
                    print(f"PARTIAL in parse output: {t[:60]}")
                    print(f"  original_desc={item.original_desc[:80]}")
                    print(f"  parsed_name={match.parsed_name if match else item.parsed_name}")
                    match = item
                    break
            if not match:
                print(f"NOT IN PARSE OUTPUT: {t[:60]}")
else:
    print("No parse output file found. Run the pipeline first.")
