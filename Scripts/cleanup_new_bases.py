#!/usr/bin/env python3
"""Clean up new_bases.json: remove dupes, facets, brand names, typos, niche items."""
import json, pathlib

OUT = pathlib.Path(__file__).resolve().parent / "triage_output"
new = json.loads((OUT / "new_bases.json").read_text())
existing = json.loads((OUT / "bases_by_aisle.json").read_text())

# Flatten existing bases for easy lookup
existing_flat = set()
for cat, bases in existing.items():
    for b in bases:
        existing_flat.add(b.lower())

# --- Items to REMOVE, grouped by reason ---

# Semantic duplicates / facets of existing bases
facets_of_existing = {
    # Dairy – forms of existing bases
    "egg whites", "egg yolks",         # facets of "egg"
    "half-and-half",                   # form of "cream"
    "powdered milk",                   # form of "milk"
    "condensed milk",                  # vs "sweetened condensed milk" (Canned)

    # Grains – processed forms
    "cream of wheat",                  # processed semolina/wheat
    "puffed rice",                     # puffed cereal form of rice
    "puffed wheat",                    # puffed cereal form of wheat
    "cracked wheat",                   # form of wheat
    "muesli",                          # cereal product

    # Protein – covered by existing species
    "albacore",                        # tuna variant
    "andouille",                       # sausage variant
    "bratwurst",                       # sausage variant
    "frankfurter",                     # = hot dog
    "salt pork",                       # form of pork
    "roast beef",                      # form of beef
    "sheep",                           # = lamb/mutton
    "squid",                           # = calamari (existing)

    # Baking – forms of existing bases
    "almond flour",                    # flour variant (facet)
    "coconut flour",                   # flour variant (facet)
    "brown sugar",                     # sugar variant
    "confectioners sugar",             # = powdered sugar = sugar
    "powdered sugar",                  # sugar variant
    "turbinado sugar",                 # sugar variant
    "graham cracker crumbs",           # processed product

    # Spices – forms/duplicates of existing
    "coriander seed",                  # = coriander
    "cumin seed",                      # = cumin
    "oregano leaf",                    # = oregano
    "sage leaf",                       # = sage
    "vanilla bean",                    # = vanilla
    "parsley flakes",                  # = parsley
    "mustard powder",                  # ground mustard seed
    "white pepper",                    # = black pepper form
    "peppercorn (white)",              # = black pepper form
    "chipotle powder",                 # chili powder variant
    "dried lemongrass",                # = lemongrass (Produce)
    "dried lime",                      # = lime form
    "kaffir lime powder",              # form of kaffir lime leaf
    "lemon peel",                      # facet of lemon
    "lime zest",                       # facet of lime
    "miso powder",                     # = miso (Condiments)
    "paprika (hot)",                   # = paprika variant
    "garlic salt",                     # seasoning blend

    # Produce – sub-types of existing bases
    "acorn squash",                    # squash variant
    "butternut squash",                # squash variant
    "delicata squash",                 # squash variant
    "red kuri squash",                 # squash variant
    "spaghetti squash",                # squash variant
    "alfalfa sprout",                  # = sprout
    "anaheim pepper",                  # pepper variant
    "bok choy (baby)",                 # = bok choy
    "cantaloupe (other varieties)",    # = cantaloupe
    "grapefruit (other varieties)",    # = grapefruit
    "nectarine (white)",               # = nectarine
    "persimmon (hachiya/fuyu)",        # = persimmon
    "pineapple (other varieties)",     # = pineapple
    "rutabaga (other varieties)",      # = rutabaga
    "radish (daikon/white icicle/french breakfast)", # = radish/daikon
    "romaine",                         # = lettuce variant
    "escarole",                        # = endive variant
    "hericium (lion's mane mushroom)", # mushroom variant
    "oyster mushroom",                 # mushroom variant
    "portabella mushroom",             # mushroom variant
    "shiitake mushroom",               # mushroom variant
    "porcini",                         # mushroom variant
    "morel",                           # mushroom variant
    "peas (snap)",                     # = pea
    "peas (snow)",                     # = pea
    "snap pea",                        # = pea (duplicate of above)
    "snow pea",                        # = pea (duplicate of above)
    "garbanzo bean (fresh/chickpea)",  # = chickpea (Legumes)
    "shiso",                           # = shiso leaf (Spices)
    "thai basil",                      # = basil (Spices)
    "turmeric root",                   # = turmeric (Spices)
    "wax bean",                        # = green bean variant

    # Condiments – dressings are facets of "dressing"
    "caesar dressing",                 # dressing variant
    "coleslaw dressing",               # dressing variant
    "french dressing",                 # dressing variant
    "green goddess dressing",          # dressing variant
    "ranch dressing",                  # dressing variant
    "thousand island dressing",        # dressing variant
    "mango chutney",                   # = chutney variant
    "salsa verde",                     # = salsa variant
    "nam pla",                         # = fish sauce (Thai name)
    "tamari",                          # = soy sauce variant
    "sambal oelek",                    # = chili paste variant
    "soybean paste",                   # = bean paste (existing)
    "yellow curry paste",              # = curry paste variant
    "tzatziki",                        # = tzatziki sauce (existing!)
    "cornichons",                      # = pickle variant

    # Frozen – just frozen forms of produce
    "frozen broccoli",                 # = broccoli
    "frozen corn",                     # = corn
    "frozen green beans",              # = green bean
    "frozen peas",                     # = pea
    "frozen spinach",                  # = spinach
    "frozen edamame",                  # = edamame/soybean
    "frozen potstickers",              # = frozen dumplings (keep dumplings)

    # Canned – just canned forms of existing bases
    "beans",                           # too generic / = bean (Legumes)
    "black beans",                     # = bean variant
    "capers",                          # = caper (Produce)
    "carrots",                         # = carrot (Produce)
    "chickpeas",                       # = chickpea (Legumes)
    "clams",                           # = clam (Protein)
    "fava beans",                      # = fava bean (→ Legumes)
    "green beans",                     # = green bean (Produce)
    "kidney beans",                    # = kidney bean (→ Legumes)
    "lima beans",                      # = lima bean (→ Legumes)
    "mandarin oranges",                # = orange (Produce)
    "mushrooms",                       # = mushroom (Produce)
    "peas",                            # = pea (Produce)
    "pinto beans",                     # = bean variant
    "sardines",                        # = sardine (Protein)
    "split peas",                      # = split pea (Legumes)
    "stewed tomatoes",                 # = tomato variant
    "tomatoes",                        # = tomato (Produce)

    # Pasta – shapes are facets of "pasta"
    "angel hair", "cavatelli", "farfalle", "fettuccine", "fusilli",
    "lasagna", "linguine", "macaroni", "orzo", "pappardelle",
    "penne", "shells",
    "rice vermicelli",                 # = rice noodle variant
    "glass noodle",                    # = cellophane noodle (in-list dupe)

    # Alcohol
    "armagnac",                        # = brandy variant
    "aperitif",                        # generic category, not a product

    # Breads – shapes/types of bread/flatbread
    "babka", "baguette", "breadstick", "brioche", "challah",
    "chapati",                         # = flatbread
    "ciabatta",                        # = bread variant
    "focaccia",                        # = flatbread/bread
    "lavash",                          # = flatbread
    "paratha",                         # = flatbread
    "roll",                            # = bread/bun

    # Nuts
    "acorn",                           # not commonly eaten
    "soy nut",                         # = roasted soybean

    # Snacks
    "cheese puff",                     # = chip variant
    "fruit snack",                     # too generic
    "nut",                             # = specific nuts exist already
    "puffed corn",                     # too generic
    "seaweed snack",                   # = seaweed (Produce)
    "trail mix",                       # = mixed nuts (existing)
    "yogurt-covered raisin",           # too specific

    # Beverages
    "plant milk",                      # = non-dairy milk (existing Dairy)
    "root beer",                       # = soda variant

    # Other
    "smoke essence",                   # = liquid smoke (Condiments)
    "smoked salt",                     # = salt variant
    "stock cube",                      # = stock (Canned)
    "vegemite",                        # = marmite (Condiments)
    "yeast extract",                   # = nutritional yeast / marmite
}

# Brand names
brand_names = {
    "frank's redhot",
    "heinz 57",
    "kewpie mayonnaise",
    "maggi seasoning",
    "sriracha",
}

# Typos / nonsense
typos = {
    "emuw",                            # typo for emu (also too niche)
    "jerkfruit",                       # typo for jackfruit (already in Other)
}

# Too niche for a general-purpose pantry app
too_niche = {
    "job's tears",                     # obscure grain
    "triticale",                       # wheat-rye hybrid, very rare
    "einkorn",                         # ancient wheat, rarely stocked
    "scup",                            # very niche fish
    "sprat",                           # very niche fish
    "smelt",                           # niche fish
    "kangaroo",                        # exotic meat
    "turducken",                       # novelty dish, not ingredient
    "cinnamon leaf",                   # vs cinnamon bark
    "fennel pollen",                   # very niche
    "shallot powder",                  # niche
    "urfa biber",                      # niche Turkish pepper
    "alum",                            # pickling chemical
    "cactus pear",                     # rarely encountered
    "tindora",                         # niche gourd
    "fiddlehead fern",                 # seasonal specialty
    "beechnut",                        # very niche
    "candlenut",                       # niche
    "sacha inchi seed",                # niche
    "piccalilli",                      # niche relish
    "shacha sauce",                    # niche
    "scotch bonnet sauce",             # niche
    "nuoc cham",                       # recipe, not ingredient
    "wing sauce",                      # = hot sauce variant
    "yogurt sauce",                    # too generic
    "garlic sauce",                    # too generic
    "kvass",                           # very niche
    "shrubs",                          # niche drinking vinegan
    "horchata",                        # niche beverage
    "baking ammonia",                  # niche
}

# In-list duplicates (keep the first, remove these)
in_list_dupes = {
    "butter bean",                     # = lima bean (both in new list)
    "crushed red pepper",              # = chili flakes (both in new list)
}

# Combine all removals
all_removals = set()
for s in [facets_of_existing, brand_names, typos, too_niche, in_list_dupes]:
    all_removals |= {x.lower() for x in s}

# Apply cleanup
cleaned = {}
total_removed = 0
total_kept = 0

for cat, bases in new.items():
    kept = []
    for b in bases:
        if b.lower() in all_removals:
            total_removed += 1
        elif b.lower() in existing_flat:
            # Exact match with existing – shouldn't happen (broaden script deduped)
            # but just in case
            total_removed += 1
        else:
            kept.append(b)
            total_kept += 1
    if kept:
        cleaned[cat] = sorted(kept, key=str.lower)

# Write cleaned file
(OUT / "new_bases_cleaned.json").write_text(
    json.dumps(cleaned, indent=2, ensure_ascii=False) + "\n"
)

print(f"Removed: {total_removed}")
print(f"Kept:    {total_kept}")
print()
for cat, bases in cleaned.items():
    print(f"  {cat}: {len(bases)}")
    for b in bases:
        print(f"    - {b}")
