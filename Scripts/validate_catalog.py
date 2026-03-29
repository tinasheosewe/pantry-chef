#!/usr/bin/env python3
"""Validate all critical items are present in the catalog."""
import json
from collections import Counter

cat = json.load(open("recipe_ingredient_orchestrator/output/ingredient_catalog.json"))

must_have = [
    "filet mignon", "ny strip", "flank steak", "skirt steak", "brisket",
    "chuck roast", "tri-tip", "t-bone",
    "pork shoulder", "baby back", "spare rib", "chorizo", "bratwurst",
    "andouille", "kielbasa", "prosciutto", "pepperoni", "salami",
    "ground lamb", "lamb leg", "lamb shank", "chicken drumstick", "cornish hen",
    "halibut", "tilapia", "sea bass", "mahi", "swordfish", "trout",
    "snapper", "catfish", "smoked salmon", "sardine",
    "clam", "oyster", "calamari", "octopus", "crawfish",
    "pineapple", "watermelon", "cantaloupe", "grape", "raspberry",
    "blackberry", "peach", "cherry", "kiwi", "pomegranate", "cranberr",
    "fig", "apricot", "papaya", "coconut",
    "brussels sprout", "bok choy", "fennel", "leek", "radish",
    "turnip", "parsnip", "artichoke", "arugula", "swiss chard",
    "watercress", "endive", "okra",
    "serrano", "habanero", "poblano", "thai chili",
    "chives", "sage", "tarragon", "lemongrass", "plantain",
    "blue cheese", "gruyere", "provolone", "pepper jack", "monterey jack",
    "evaporated milk",
    "teriyaki", "gochujang", "harissa", "curry paste", "mirin",
    "sriracha", "balsamic glaze", "dijon",
    "smoked paprika", "white pepper", "star anise", "fennel seed",
    "mustard seed", "zaatar", "celery salt", "five spice",
    "ground coriander", "sumac",
]

found = []
missing = []
for term in must_have:
    matches = [
        e["id"] for e in cat
        if term.lower() in e["name"].lower()
        or term.lower() in e["id"].lower()
        or any(term.lower() in a.lower() for a in e.get("aliases", []))
    ]
    if matches:
        found.append((term, matches[0]))
    else:
        missing.append(term)

print(f"Found: {len(found)}/{len(must_have)}")
if missing:
    print(f"\nStill MISSING ({len(missing)}):")
    for m in missing:
        print(f"  - {m}")
else:
    print("All critical items present!")

dist = Counter(e["category"] for e in cat)
print(f"\nCategory distribution ({len(cat)} total):")
for cat_name, count in dist.most_common():
    print(f"  {cat_name}: {count}")
