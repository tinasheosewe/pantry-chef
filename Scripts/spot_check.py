#!/usr/bin/env python3
"""Deep spot-check of enriched catalog — focus on items with known rich variant sets."""
import json

with open("Scripts/triage_output/enriched_catalog.json") as f:
    data = json.load(f)

def show(name):
    item = data.get(name)
    if not item:
        print(f"\n❌ {name}: NOT FOUND")
        return
    facets = item.get("facets", [])
    aliases = item.get("aliases", [])
    print(f"\n{'='*60}")
    print(f"{name} [{item['category']}]")
    print(f"  unit={item['defaultUnit']}, qty={item['defaultQuantity']}, storage={item['defaultStorage']}")
    print(f"  aliases: {aliases}")
    fbs = item.get("freshnessByStorage", {})
    print(f"  freshness: p={fbs.get('pantry')} r={fbs.get('refrigerated')} f={fbs.get('frozen')}")
    print(f"  defaults: {item.get('defaultSelections', [])}")
    for f in facets:
        print(f"  {f['key']} ({len(f['options'])}): {f['options']}")

print("=" * 60)
print("PROTEIN — cuts, species, preparation")
print("=" * 60)
for name in ["beef", "pork", "lamb", "turkey", "duck", "veal",
             "white fish", "oily fish", "shrimp", "crab", "lobster",
             "sausage", "bacon", "ham", "salami", "prosciutto"]:
    show(name)

print("\n\n" + "=" * 60)
print("PRODUCE — varieties that matter for cooking")
print("=" * 60)
for name in ["pepper", "mushroom", "squash", "lettuce", "apple",
             "onion", "potato", "tomato", "berry", "cabbage",
             "kale", "corn", "garlic", "ginger", "avocado", "banana"]:
    show(name)

print("\n\n" + "=" * 60)
print("DAIRY — fat levels, types, forms")
print("=" * 60)
for name in ["cheese", "milk", "yogurt", "cream", "butter", "egg",
             "cream cheese", "sour cream", "cottage cheese"]:
    show(name)

print("\n\n" + "=" * 60)
print("CONDIMENTS — types/flavors")
print("=" * 60)
for name in ["vinegar", "mustard", "hot sauce", "jam", "syrup",
             "soy sauce", "dressing", "salsa", "curry paste", "miso"]:
    show(name)

print("\n\n" + "=" * 60)
print("BAKING — types matter a lot")
print("=" * 60)
for name in ["flour", "sugar", "chocolate", "extract", "honey", "yeast"]:
    show(name)

print("\n\n" + "=" * 60)
print("GRAINS/PASTA/BREAD — key structural items")
print("=" * 60)
for name in ["rice", "pasta", "bread", "oats", "cereal", "tortilla",
             "flatbread", "noodle"]:
    show(name)

print("\n\n" + "=" * 60)
print("NUTS/OILS — processing matters")
print("=" * 60)
for name in ["olive oil", "sesame oil", "coconut oil", "almond", "peanut", "nut butter"]:
    show(name)
