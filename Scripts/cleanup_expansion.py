#!/usr/bin/env python3
"""
Phase 3/4 cleanup of expansion_candidates.json:
- Remove facets of existing collapsed bases (bean→kidney bean, pasta→spaghetti, flatbread→naan)
- Remove semantic duplicates (squid=calamari, crayfish=crawfish)
- Remove too-niche items
- Remove non-ingredients (smoothie, milkshake)
- Remove redundant duplicates within (milk powder vs powdered milk)
- Bring combined total to ~800-900
"""

import json
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
BASES_PATH = SCRIPT_DIR / "triage_output" / "bases_by_aisle.json"
EXPANSION_PATH = SCRIPT_DIR / "triage_output" / "expansion_candidates.json"

with open(BASES_PATH) as f:
    catalog = json.load(f)
with open(EXPANSION_PATH) as f:
    expansion = json.load(f)

# ── Items to REMOVE (facets of collapsed bases, dupes, niche, non-ingredients) ──

REMOVALS: dict[str, set[str]] = {
    "Legumes & Beans": {
        # All collapsed into "bean" previously
        "adzuki bean", "cannellini bean", "kidney bean", "lima bean",
        "navy bean", "mung bean", "great northern bean",
        # Other facets of "bean"
        "borlotti bean", "butter bean", "cranberry bean", "flageolet bean",
        "haricot bean", "roman bean", "runner bean", "scarlet runner bean",
        "red bean", "white bean", "french bean", "black bean",
        # "broad bean" = fava bean (already exists)
        "broad bean",
        # "garbanzo bean" = chickpea (already exists)
        "garbanzo bean",
        # Obscure
        "bambara groundnut", "navy pea",
        # "yellow split pea" is facet of "split pea"
        "yellow split pea",
        # "yellow pea" overlaps "split pea"
        "yellow pea",
        # green gram = mung bean
        "green gram",
        # marrowfat pea is niche
        "marrowfat pea",
        # field pea overlaps existing pea types
        "field pea",
    },
    "Pasta & Noodles": {
        # All are facets/shapes of "pasta" (previously collapsed)
        "angel hair", "bucatini", "campanelle", "cannelloni", "capellini",
        "cavatappi", "cavatelli", "ditalini", "elbow macaroni", "fettuccine",
        "fusilli", "gemelli", "lasagne sheet", "linguine", "macaroni",
        "maccheroni", "manicotti", "mostaccioli", "orecchiette",
        "pappardelle", "pastina", "penne", "radiatori", "rigatoni",
        "rotini", "spaghetti", "tagliatelle", "vermicelli", "ziti",
        # "noodle" is too generic — we have specific noodle types
        "noodle",
    },
    "Breads & Bakery": {
        # These are facets of "flatbread" (previously collapsed)
        "chapati", "naan", "pita", "roti", "lavash",
        # Facets of "bread"
        "rye bread", "sourdough bread", "raisin bread", "sandwich bread",
        "vienna bread", "english toasting bread", "sweet bread", "soda bread",
        "tea bread", "quick bread",
        # "frozen bread dough" = facet of "dough"
        "frozen bread dough",
        # "frozen dinner roll" too specific
        "frozen dinner roll",
        # "frozen puff pastry" = facet of "pastry"
        "frozen puff pastry",
        # "puff pastry" = facet of "pastry"
        "puff pastry",
        # "crescent roll dough" = facet of "dough"
        "crescent roll dough",
        # "hot dog bun" = facet of "bun"
        "hot dog bun",
        # "sub roll" = facet of "bun"/"bread"
        "sub roll",
        # "kaiser roll" = facet of "bun"
        "kaiser roll",
    },
    "Beverages": {
        # Non-ingredients / prepared drinks
        "smoothie", "vegetable smoothie", "protein shake", "milkshake",
        "bubble tea", "turmeric latte", "sweet lassi", "iced tea",
        "milk tea",
        # Facets of "non-dairy milk" (already exists)
        "almond milk", "oat milk", "soy milk", "rice milk",
        # Just water
        "spring water",
        # "isotonic drink" = sports drink (already exists)
        "isotonic drink",
        # "buttermilk drink" — we have buttermilk already
        "buttermilk drink",
        # Too niche
        "squash drink", "sarsaparilla", "whey drink",
        # barley tea — niche
        "barley tea",
        # frozen juice concentrate = juice concentrate (in Canned)
        "frozen juice concentrate",
    },
    "Dairy & Eggs": {
        # Duplicates
        "milk powder",  # = powdered milk
        # Facets of existing
        "egg white",  # facet of egg
        "egg yolk",  # facet of egg
        "duck egg", "quail egg", "pasteurized egg", "liquid egg",  # facets of egg
        "egg replacer",  # = egg substitute (already exists)
        "smoked cheese",  # facet of cheese
        "processed cheese",  # facet of cheese
        "cheese spread",  # facet of cheese
        "cheese curd",  # facet of cheese
        # Overlaps with existing
        "condensed milk",  # = sweetened condensed milk in Canned
        "evaporated goat milk",  # niche
        "sheep milk",  # niche
        "milk substitute",  # = non-dairy milk (in Produce context)
        # Non-ingredients
        "milkshake",
        "ice milk",  # = ice cream variant
        "frozen yogurt",  # = ice cream variant
        "dairy dessert",  # too vague
        "custard dessert",  # = custard (already exists)
        "dairy creamer",  # = coffee creamer (keeping that one)
    },
    "Frozen Foods": {
        # Facets of existing frozen items or fresh items
        "frozen bagel",  # facet of bagel
        "frozen biscuit",  # facet of biscuit
        "frozen cake",  # facet of cake
        "frozen cheesecake",  # facet of cake
        "frozen gnocchi",  # facet of gnocchi
        "frozen pasta",  # facet of pasta
        "frozen paneer",  # facet of paneer
        "frozen tofu",  # facet of tofu
        "frozen turkey breast",  # facet of turkey
        "frozen pork chop",  # facet of pork
        "frozen chicken breast",  # facet of chicken
        "frozen sausage",  # facet of sausage
        "frozen yogurt bar",  # snack
    },
    "Protein": {
        # Semantic dupes of existing
        "squid",  # = calamari (already exists)
        "crayfish",  # = crawfish (already exists)
        # Individual fish species (we collapsed to white fish/oily fish)
        "catfish", "cod", "grouper", "haddock", "halibut", "pollock", "tilapia",  # white fish facets
        "mackerel",  # oily fish facet
        # Too niche
        "turducken", "squirrel", "emu", "frog", "conch", "snail", "milkfish",
        "soft shell crab",  # facet of crab
        "scampi",  # = shrimp/prawn variant
        # "herbed tofu" = facet of tofu
        "herbed tofu",
        # morcia — not a standard item
        "morcia",
    },
    "Nuts & Seeds": {
        # Too niche / not commonly available
        "argan nut", "baruka nut", "beechnut", "breadnut", "candlenut",
        "johnnycake nut", "karuka nut", "kukui nut", "ogbono seed",
        # Non-nut items
        "peanut brittle",  # snack, not a nut
        # "filbert" = hazelnut
        "filbert",
        # "butternut" — ambiguous (squash or nut?)
        "butternut",
        # "acorn" — not commonly eaten
        "acorn",
    },
    "Oils & Fats": {
        # "crisco" is brand of shortening (already exists)
        "crisco",
        # "butter oil" = ghee (already exists)
        "butter oil",
        # "chicken fat" = schmaltz (already exists)
        "chicken fat",
        # "pork fat" = lard (already exists)
        "pork fat",
        # "salmon oil" — supplement, not cooking oil
        "salmon oil",
    },
    "Grains & Cereals": {
        # Too niche
        "triticale", "job's tears", "einkorn",
        # Brand names that are facets
        "rice krispies",  # brand of cereal
        # "instant" variants are facets
        "instant couscous", "instant grits", "instant oatmeal", "instant polenta",
        "minute rice", "ready rice",
        # "puffed" variants are facets
        "puffed millet", "puffed rice", "puffed wheat",
        # "rice pudding" — prepared dish, not grain
        "rice pudding",
        # "bran flakes" — facet of bran/cereal
        "bran flakes",
    },
    "Snacks": {
        # Too specific / facets
        "cracker stick",  # facet of cracker
        "yogurt-covered pretzel",  # facet of pretzel
        "gelatin snack",  # too vague
        "jerky stick",  # = beef jerky variant
        "pop chip",  # brand
    },
    "Spices & Herbs": {
        # Flavored salts are facets of "salt"
        "celery salt", "chili salt", "garlic salt", "herb salt",
        "himalayan pink salt", "lemon salt", "lime salt", "onion salt",
        "smoked salt",
        # Too niche
        "bamboo leaf", "beau monde seasoning", "chili sugar", "chili thread",
        "dried rose petal", "katsu curry powder", "lime leaf powder",
        "makrut lime powder", "oregano oil",
        # Overlap/facets
        "parsley flakes",  # = dried parsley = parsley
        "italian herb blend",  # = italian seasoning (already exists)
        "green curry powder",  # = curry powder facet
        "dried seaweed",  # = seaweed in Produce
        "dried lemongrass",  # = lemongrass in Produce
    },
    "Condiments & Sauces": set(),  # All manual additions are good
    "Produce": set(),  # All manual additions are good
}

# Apply removals
removed_count = 0
for cat, to_remove in REMOVALS.items():
    if cat in expansion:
        before = len(expansion[cat])
        expansion[cat] = [x for x in expansion[cat] if x not in to_remove]
        removed_count += before - len(expansion[cat])

# Remove empty categories
expansion = {k: sorted(v) for k, v in expansion.items() if v}

# Final counts
expansion_total = sum(len(v) for v in expansion.values())
original_total = sum(len(v) for v in catalog.values())
combined = original_total + expansion_total

print(f"Removed {removed_count} items in cleanup")
print(f"\nOriginal: {original_total}")
print(f"Expansion: {expansion_total}")
print(f"Combined: {combined}")
print(f"\nBy category:")
for cat in sorted(expansion.keys()):
    orig = len(catalog.get(cat, []))
    new = len(expansion[cat])
    print(f"  {cat}: +{new} (was {orig}, would be {orig + new})")
    for item in expansion[cat]:
        print(f"    • {item}")

# Overwrite
with open(EXPANSION_PATH, 'w') as f:
    json.dump(expansion, f, indent=2, ensure_ascii=False)
print(f"\n✅ Cleaned expansion written to {EXPANSION_PATH.name}")
