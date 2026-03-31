"""Audit misclassification between ingredient and prepared food catalogs."""
import json
import re
from collections import Counter

with open("recipe_ingredient_orchestrator/output/ingredient_catalog.json") as f:
    ingredients = json.load(f)
with open("recipe_ingredient_orchestrator/output/prepared_food_catalog.json") as f:
    prepared = json.load(f)
with open("recipe_ingredient_orchestrator/output/name_review.csv") as f:
    csv_lines = f.readlines()[1:]  # skip header

# Build a map from ingredient ID to USDA description
id_to_usda = {}
for line in csv_lines:
    # Parse CSV: "id","name","usda_description","category","base_ingredient"
    parts = line.strip().split('","')
    if len(parts) >= 3:
        entry_id = parts[0].strip('"')
        usda_desc = parts[2].strip('"')
        id_to_usda[entry_id] = usda_desc

# --- Prepared foods that look like raw ingredients ---
COOKED_TERMS = re.compile(
    r"\b(cooked|braised|roasted|grilled|fried|baked|steamed|boiled|"
    r"sauteed|sautéed|poached|broiled|stewed|smoked|scrambled|"
    r"pan-fried|deep-fried|stir-fried|microwaved|toasted|"
    r"casserole|sandwich|pot pie|dinner|soup|stew|pizza|burrito|taco|"
    r"from mix|prepared|with frosting|with icing|with filling|"
    r"and cheese|and gravy|on bun|in syrup)\b",
    re.IGNORECASE,
)

RAW_INGREDIENT_TERMS = re.compile(
    r"\b(raw|uncooked|unprepared|dried|dry|fresh|canned|frozen|"
    r"whole|ground|sliced|chopped|minced|diced|shredded|grated|"
    r"crushed|powdered|granulated|extract|juice|concentrate|"
    r"flour|sugar|salt|oil|vinegar|honey|syrup|butter|cream|milk|"
    r"spice|herb|seed|nut|bean|lentil|grain|rice|oat|wheat|corn meal)\b",
    re.IGNORECASE,
)

print("=" * 70)
print("PREPARED FOODS THAT LOOK LIKE RAW INGREDIENTS")
print("=" * 70)
raw_in_prepared = []
for item in prepared:
    desc = item.get("usda_description", item.get("name", ""))
    name = item.get("name", "")
    # Not cooked but has raw ingredient markers
    if not COOKED_TERMS.search(desc) and RAW_INGREDIENT_TERMS.search(desc):
        raw_in_prepared.append(item)

for item in raw_in_prepared[:40]:
    print(f"  {item['name'][:40]:<42s} | {item.get('usda_description', '')[:60]}")
print(f"\n  ... {len(raw_in_prepared)} total items that look like ingredients in prepared catalog")

print()
print("=" * 70)
print("INGREDIENTS THAT LOOK LIKE PREPARED/COOKED FOODS")
print("=" * 70)
cooked_in_ingredients = []
for item in ingredients:
    usda_desc = id_to_usda.get(item["id"], item["name"])
    if COOKED_TERMS.search(usda_desc):
        cooked_in_ingredients.append((item, usda_desc))

for item, desc in cooked_in_ingredients[:40]:
    print(f"  {item['name'][:40]:<42s} | {desc[:60]}")
print(f"\n  ... {len(cooked_in_ingredients)} total items that look like prepared food in ingredient catalog")

# --- Check specific problematic categories in prepared ---
print()
print("=" * 70)
print("PREPARED CATALOG USDA CATEGORIES BREAKDOWN")
print("=" * 70)
prep_cats = Counter(item.get("usda_category", "?") for item in prepared)
for cat, count in prep_cats.most_common():
    # Flag if this is NOT a prepared-food category
    is_prep_cat = cat in ("Fast Foods", "Baby Foods", "Meals, Entrees, and Side Dishes", "Restaurant Foods")
    flag = "" if is_prep_cat else " ← ingredient category!"
    print(f"  {cat:<45s} {count:>5}{flag}")

# --- Check Baked Products more carefully ---
print()
print("=" * 70)
print("SAMPLE: 'Baked Products' in PREPARED (are these ingredients?)")
print("=" * 70)
baked = [item for item in prepared if item.get("usda_category") == "Baked Products"]
for item in baked[:20]:
    print(f"  {item.get('usda_description', item['name'])[:80]}")

# --- Check what ingredient-category items ended up in prepared ---
print()
print("=" * 70)
print("SAMPLE: Vegetables in PREPARED")
print("=" * 70)
vegs = [item for item in prepared if item.get("usda_category") == "Vegetables and Vegetable Products"]
for item in vegs[:20]:
    print(f"  {item.get('usda_description', item['name'])[:80]}")

# --- Check what's in ingredient catalog that shouldn't be ---
print()
print("=" * 70)
print("SAMPLE: Suspicious ingredient names (contain 'prepared', 'mix', etc.)")
print("=" * 70)
suspicious_patterns = re.compile(
    r"\b(cake|cookie|pie|muffin|bread|biscuit|roll|croissant|"
    r"cereal|granola bar|candy|chocolate|ice cream|pudding|"
    r"soda|cola|energy drink|sport drink|lemonade)\b",
    re.IGNORECASE
)
suspicious = [(item, id_to_usda.get(item["id"], "")) for item in ingredients 
              if suspicious_patterns.search(id_to_usda.get(item["id"], item["name"]))]
for item, desc in suspicious[:30]:
    print(f"  {item['name'][:40]:<42s} | {desc[:60]}")
print(f"\n  ... {len(suspicious)} total suspicious items in ingredient catalog")
