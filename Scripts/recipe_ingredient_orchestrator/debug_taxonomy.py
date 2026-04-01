"""Debug specific taxonomy parser failures."""
from ml_approaches.parse_taxonomy import _parse_single

tests = [
    ("Frankfurter, beef", "Sausages and Luncheon Meats", 1),
    ("Flour, wheat, all-purpose, enriched, bleached", "Cereal Grains and Pasta", 2),
    ("Oil, olive, salad or cooking", "Fats and Oils", 3),
    ("Butter, salted", "Dairy and Egg Products", 4),
    ("KRAFT, VELVEETA, Pasteurized Process Cheese Spread, original", "Dairy and Egg Products", 5),
    ("MARS SNACKFOOD US, M&M's Semisweet Chocolate Mini Baking Bits", "Sweets", 6),
    ("Yogurt, Greek, strawberry, nonfat", "Dairy and Egg Products", 7),
    ("Potatoes, au gratin, dry mix, prepared with water, whole milk and butter", "Vegetables and Vegetable Products", 8),
    ("Mustard, prepared, yellow", "Legumes and Legume Products", 9),
    ("Egg, whole, raw, fresh", "Dairy and Egg Products", 10),
    ("Milk, whole, 3.25% milkfat, with added vitamin D", "Dairy and Egg Products", 11),
    ("Sauce, salsa, ready-to-serve", "Soups, Sauces, and Gravies", 12),
]

for desc, cat, fdc in tests:
    r = _parse_single(desc, cat, fdc)
    print(f"{desc[:60]:60s} -> name={r.parsed_name!r:30s} base={r.parsed_base!r:12s} quals={r.qualifiers} form={r.form!r} noise={r.noise_removed}")
