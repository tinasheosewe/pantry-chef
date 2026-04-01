#!/usr/bin/env python3
"""Debug specific taxonomy cases to understand failures."""
import sys
sys.path.insert(0, ".")

from ml_approaches.parse_taxonomy import _parse_single

# Test cases
cases = [
    ("Cheese, cheddar", "Dairy and Egg Products", 1),
    ("Baking chocolate, MARS SNACKFOOD US, M&M's Semisweet Chocolate Mini Baking Bits", "Sweets", 2),
    ("Rice, white, long-grain, regular, raw, enriched", "Cereal Grains and Pasta", 3),
    ("Nuts, almonds, dry roasted, with salt added", "Nut and Seed Products", 4),
    ("Oil, coconut", "Fats and Oils", 5),
    ("Cheese, mozzarella, low moisture, part-skim", "Dairy and Egg Products", 6),
    ("Lettuce, iceberg (includes crisphead types), raw", "Vegetables and Vegetable Products", 7),
    ("Beverages, tea, black, brewed, prepared with tap water", "Beverages", 8),
    ("Beverages, coffee, brewed, prepared with tap water", "Beverages", 9),
    ("Oil, canola", "Fats and Oils", 10),
    ("Orange juice, frozen concentrate, unsweetened, undiluted", "Fruits and Fruit Juices", 11),
    ("Cheese, cream, fat free", "Dairy and Egg Products", 12),
    ("Beef, ground, 85% lean meat / 15% fat, raw", "Beef Products", 13),
    ("Turkey, retail parts, breast, meat only, cooked, roasted", "Poultry Products", 14),
    ("Wheat flour, white, all-purpose, enriched, bleached", "Cereal Grains and Pasta", 15),
]

for desc, cat, fdc_id in cases:
    result = _parse_single(desc, cat, fdc_id)
    print(f"\n{'='*60}")
    print(f"INPUT:  {desc}")
    print(f"OUTPUT: name={result.parsed_name!r}, base={result.parsed_base!r}")
    print(f"  quals={result.qualifiers}, form={result.form!r}")
    print(f"  brand={result.brand!r}, noise={result.noise_removed}")
