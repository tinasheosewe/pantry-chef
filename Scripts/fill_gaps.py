#!/usr/bin/env python3
"""Targeted category generation to fill catalog gaps."""
import subprocess, sys, os

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
CATALOG = os.path.join(SCRIPTS, "recipe_ingredient_orchestrator/output/ingredient_catalog.json")

BATCHES = [
    {
        "prompt": (
            "Generate 40 Produce ingredients. MUST include: "
            "Onion (variant=yellow/white/red/sweet), Garlic, "
            "Tomato (variant=roma/beefsteak/cherry/grape/heirloom), "
            "Lemon, Lime, Avocado, "
            "Mushrooms (variant=button/cremini/shiitake/portobello/oyster), "
            "Bell Pepper (variant=red/green/yellow/orange), Celery, "
            "Lettuce (variant=romaine/iceberg/butter), Cucumber, "
            "Sweet Potato, Potato (variant=russet/yukon gold/red/fingerling), "
            "Banana, Mango, Strawberry, Blueberry, Spinach, Kale, "
            "Broccoli, Cauliflower, Carrots, Ginger, Zucchini, Corn, "
            "Cabbage, Asparagus, Green Beans, Green Onion, Jalapeno, "
            "Parsley, Cilantro, Basil, Mint, Rosemary, Thyme, Dill, "
            "Peas, Eggplant, Beets, Butternut Squash, Pear, "
            "Apple (variant=gala/fuji/granny smith/honeycrisp)."
        ),
        "count": 40,
    },
    {
        "prompt": (
            "Generate 15 Grains & Cereals ingredients. MUST include: "
            "Rice (variant=white/brown/basmati/jasmine/arborio/sushi), "
            "Flour (variant=all-purpose/bread/cake/self-rising/whole wheat), "
            "Bread (variant=white/whole wheat/sourdough/rye), "
            "Tortilla (variant=flour/corn/whole wheat), "
            "Quinoa, Oats (variant=rolled/steel-cut/instant), "
            "Couscous, Pasta (variant=spaghetti/penne/fettuccine/rigatoni/fusilli), "
            "Cornmeal, Bulgur Wheat, Pearl Barley, Farro, "
            "Naan, Pita Bread, Polenta."
        ),
        "count": 15,
    },
    {
        "prompt": (
            "Generate 10 Pasta & Noodles ingredients. MUST include: "
            "Egg Noodles, Rice Noodles, Ramen Noodles, Udon Noodles, "
            "Soba Noodles, Lasagna Sheets, Glass Noodles, "
            "Gnocchi, Wonton Wrappers, Dumpling Wrappers."
        ),
        "count": 10,
    },
    {
        "prompt": (
            "Generate 15 Oils & Fats ingredients. MUST include: "
            "Olive Oil (variant=extra virgin/virgin/light), "
            "Vegetable Oil, Canola Oil, Coconut Oil (variant=refined/unrefined), "
            "Sesame Oil (variant=regular/toasted), Avocado Oil, "
            "Butter (variant=salted/unsalted), Ghee, "
            "Peanut Oil, Grapeseed Oil, Sunflower Oil, "
            "Lard, Shortening, Cooking Spray, Truffle Oil."
        ),
        "count": 15,
    },
    {
        "prompt": (
            "Generate 20 Condiments & Sauces ingredients. Focus on essentials: "
            "Soy Sauce, Fish Sauce, Worcestershire Sauce, Hot Sauce (variant=tabasco/sriracha/frank's), "
            "Ketchup, Mustard (variant=yellow/dijon/whole grain/honey), "
            "Mayonnaise, BBQ Sauce, Honey, Maple Syrup, "
            "Vinegar (variant=white/apple cider/balsamic/red wine/rice), "
            "Tomato Paste, Salsa (variant=mild/medium/hot), "
            "Hoisin Sauce, Oyster Sauce, Tahini, "
            "Miso Paste (variant=white/red/yellow), "
            "Peanut Butter, Jam (variant=strawberry/raspberry/apricot), "
            "Coconut Milk (canned)."
        ),
        "count": 20,
    },
    {
        "prompt": (
            "Generate 25 Spices & Herbs ingredients. The essentials: "
            "Salt (variant=table/kosher/sea/himalayan), "
            "Black Pepper, Cumin (variant=ground/whole seeds), "
            "Paprika (variant=sweet/smoked/hot), Chili Powder, "
            "Cinnamon (variant=ground/sticks), Turmeric, "
            "Oregano (variant=dried/fresh), Thyme (variant=dried/fresh), "
            "Garlic Powder, Onion Powder, "
            "Red Pepper Flakes, Bay Leaves, "
            "Coriander (variant=ground/whole seeds), Nutmeg, "
            "Ginger (ground), Cloves, Allspice, "
            "Curry Powder, Garam Masala, Italian Seasoning, "
            "Cayenne Pepper, Saffron, Cardamom, Vanilla Extract."
        ),
        "count": 25,
    },
    {
        "prompt": (
            "Generate 15 Baking Supplies ingredients. MUST include: "
            "Baking Powder, Baking Soda, Sugar (variant=white/brown/powdered), "
            "Chocolate Chips (variant=semi-sweet/dark/milk/white), "
            "Cocoa Powder, Cornstarch, Yeast (variant=active dry/instant), "
            "Cream of Tartar, Gelatin, Food Coloring, "
            "Almond Extract, Coconut Flakes, Sprinkles, "
            "Graham Crackers, Condensed Milk."
        ),
        "count": 15,
    },
    {
        "prompt": (
            "Generate 15 Canned & Jarred ingredients. MUST include: "
            "Canned Tomatoes (variant=diced/crushed/whole/fire-roasted), "
            "Canned Beans (variant=black/kidney/pinto/cannellini/chickpeas), "
            "Chicken Broth, Beef Broth, Vegetable Broth, "
            "Canned Corn, Canned Coconut Milk, "
            "Olives (variant=black/kalamata/green), "
            "Capers, Artichoke Hearts, Roasted Red Peppers, "
            "Pickles (variant=dill/bread & butter), "
            "Sundried Tomatoes, Chipotle in Adobo, Anchovy Paste."
        ),
        "count": 15,
    },
    {
        "prompt": (
            "Generate 10 Nuts & Seeds. MUST include: "
            "Almonds, Walnuts, Pecans, Cashews, Peanuts, Pine Nuts, "
            "Sesame Seeds, Chia Seeds, Flaxseed, Sunflower Seeds."
        ),
        "count": 10,
    },
    {
        "prompt": (
            "Generate 10 miscellaneous essentials. Include: "
            "Tofu (variant=firm/extra-firm/silken/soft, category=Protein), "
            "Coconut Cream, Nutritional Yeast, "
            "Lentils (variant=green/brown/red/black, category=Protein), "
            "Dried Fruit (variant=raisins/cranberries/apricots/dates), "
            "Breadcrumbs (variant=plain/panko/seasoned), "
            "Seaweed (variant=nori/wakame/kombu), "
            "Coconut Sugar, Agave Nectar, Tempeh."
        ),
        "count": 10,
    },
]


def run_batch(batch, catalog_path):
    cmd = [
        sys.executable, "-m", "recipe_ingredient_orchestrator", "generate",
        "--prompt", batch["prompt"],
        "--count", str(batch["count"]),
        "--seed-catalog", catalog_path,
    ]
    result = subprocess.run(cmd, cwd=SCRIPTS, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  FAILED: {result.stderr[-500:]}")
        return False
    # Print last few lines
    for line in result.stderr.strip().split("\n")[-3:]:
        print(f"  {line}")
    return True


if __name__ == "__main__":
    for i, batch in enumerate(BATCHES, 1):
        label = batch["prompt"][:60]
        print(f"\n[{i}/{len(BATCHES)}] {label}...")
        ok = run_batch(batch, CATALOG)
        if not ok:
            print("Stopping due to error.")
            sys.exit(1)
    print("\nAll batches complete!")
