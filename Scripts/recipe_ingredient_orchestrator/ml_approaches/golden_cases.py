"""Golden test cases derived from manual parser audit.

Each case specifies a USDA description and the expected parse output.
ML approaches are scored against these to ensure they fix known failures
and don't regress on items the regex parser handled correctly.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class GoldenCase:
    """A single golden test case for parse evaluation."""
    usda_desc: str
    usda_category: str
    expected_name: str
    expected_base: str = ""
    expected_qualifiers: list[str] = field(default_factory=list)
    expected_form: str = ""
    expected_brand: str = ""
    expected_noise: list[str] = field(default_factory=list)
    # If True, this is a case the regex parser got WRONG (ML must fix)
    is_regression: bool = True
    notes: str = ""


# ---------------------------------------------------------------------------
# PARSE golden cases (50 items)
# ---------------------------------------------------------------------------

GOLDEN_PARSE_CASES: list[GoldenCase] = [
    # --- Category 1: USDA noise leaking into names ---
    GoldenCase(
        usda_desc="Sauce, salsa, ready-to-serve",
        usda_category="Soups, Sauces, and Gravies",
        expected_name="Salsa",
        expected_base="salsa",
        expected_qualifiers=[],
        expected_noise=["ready-to-serve"],
        is_regression=True,
        notes="Ready-To-Serve noise not stripped",
    ),
    GoldenCase(
        usda_desc="Sauce, teriyaki, ready-to-serve",
        usda_category="Soups, Sauces, and Gravies",
        expected_name="Teriyaki Sauce",
        expected_base="sauce",
        expected_qualifiers=["teriyaki"],
        expected_noise=["ready-to-serve"],
        is_regression=True,
    ),
    GoldenCase(
        usda_desc="Sauce, pasta, spaghetti/marinara, ready-to-serve",
        usda_category="Soups, Sauces, and Gravies",
        expected_name="Marinara Sauce",
        expected_base="sauce",
        expected_qualifiers=["marinara"],
        expected_noise=["ready-to-serve"],
        is_regression=True,
        notes="Slash compound not resolved",
    ),
    GoldenCase(
        usda_desc="Cheese, pasteurized process, American",
        usda_category="Dairy and Egg Products",
        expected_name="American Cheese",
        expected_base="cheese",
        expected_qualifiers=["American"],
        expected_form="processed",
        expected_noise=["pasteurized process"],
        is_regression=True,
        notes="Ugly non-consumer name",
    ),
    GoldenCase(
        usda_desc="Orange juice, frozen concentrate, unsweetened, undiluted",
        usda_category="Fruits and Fruit Juices",
        expected_name="Orange Juice",
        expected_base="orange juice",
        expected_qualifiers=["unsweetened"],
        expected_form="frozen concentrate",
        expected_noise=[],
        is_regression=True,
        notes="Frozen concentrate is form, not part of name",
    ),
    GoldenCase(
        usda_desc="Orange juice, frozen concentrate, unsweetened, diluted with 3 volume water",
        usda_category="Fruits and Fruit Juices",
        expected_name="Orange Juice",
        expected_base="orange juice",
        expected_qualifiers=["unsweetened"],
        expected_form="frozen concentrate",
        expected_noise=["diluted with 3 volume water"],
        is_regression=True,
        notes="Near-duplicate of undiluted version",
    ),

    # --- Category 2: Ugly comma inversions ---
    GoldenCase(
        usda_desc="Frankfurter, beef",
        usda_category="Sausages and Luncheon Meats",
        expected_name="Beef Frankfurter",
        expected_base="frankfurter",
        expected_qualifiers=["beef"],
        is_regression=False,
        notes="Regex gets this right via inversion",
    ),
    GoldenCase(
        usda_desc="Cheese, cheddar (Includes foods for USDA's Food Distribution Program)",
        usda_category="Dairy and Egg Products",
        expected_name="Cheddar Cheese",
        expected_base="cheese",
        expected_qualifiers=["cheddar"],
        is_regression=False,
        notes="Regex gets this right",
    ),

    # --- Category 3: Information loss ---
    GoldenCase(
        usda_desc="Beans, snap, green, canned, regular pack, drained solids",
        usda_category="Vegetables and Vegetable Products",
        expected_name="Green Snap Beans",
        expected_base="bean",
        expected_qualifiers=["green", "snap"],
        expected_form="canned",
        expected_noise=["regular pack", "drained solids"],
        is_regression=True,
        notes="Lost green+canned qualifiers",
    ),
    GoldenCase(
        usda_desc="Yogurt, Greek, plain, nonfat",
        usda_category="Dairy and Egg Products",
        expected_name="Greek Yogurt",
        expected_base="yogurt",
        expected_qualifiers=["Greek", "plain", "nonfat"],
        is_regression=True,
        notes="Nonfat qualifier lost, dedup collision with strawberry",
    ),
    GoldenCase(
        usda_desc="Yogurt, Greek, strawberry, nonfat",
        usda_category="Dairy and Egg Products",
        expected_name="Strawberry Greek Yogurt",
        expected_base="yogurt",
        expected_qualifiers=["Greek", "strawberry", "nonfat"],
        is_regression=True,
        notes="Must be distinct from plain Greek yogurt",
    ),
    GoldenCase(
        usda_desc="Egg, whole, raw, fresh",
        usda_category="Dairy and Egg Products",
        expected_name="Egg",
        expected_base="egg",
        expected_qualifiers=["whole"],
        expected_form="raw",
        expected_noise=["fresh"],
        is_regression=True,
        notes="Dedup collision with dried variant",
    ),
    GoldenCase(
        usda_desc="Egg, whole, dried",
        usda_category="Dairy and Egg Products",
        expected_name="Egg",
        expected_base="egg",
        expected_qualifiers=["whole"],
        expected_form="dried",
        is_regression=True,
        notes="Should collapse with raw egg via form facet",
    ),

    # --- Category 4: Brand names in display names ---
    GoldenCase(
        usda_desc="Baking chocolate, MARS SNACKFOOD US, M&M's Semisweet Chocolate Mini Baking Bits",
        usda_category="Sweets",
        expected_name="Chocolate",
        expected_base="chocolate",
        expected_qualifiers=[],
        expected_brand="MARS SNACKFOOD US",
        expected_noise=["M&M's", "mini baking bits"],
        is_regression=True,
        notes="Brand name leaking into display name",
    ),
    GoldenCase(
        usda_desc="KRAFT VELVEETA Pasteurized Process Cheese Spread",
        usda_category="Dairy and Egg Products",
        expected_name="Cheese Spread",
        expected_base="cheese",
        expected_qualifiers=["processed"],
        expected_brand="KRAFT",
        is_regression=True,
    ),

    # --- Category 5: Slash/special characters ---
    GoldenCase(
        usda_desc="Pasta, dry, enriched",
        usda_category="Cereal Grains and Pasta",
        expected_name="Pasta",
        expected_base="pasta",
        expected_form="dry",
        expected_noise=["enriched"],
        is_regression=True,
        notes="Enriched is noise, dry is form",
    ),

    # --- Category 6: USDA jargon kept ---
    GoldenCase(
        usda_desc="Milk, whole, 3.25% milkfat, with added vitamin D",
        usda_category="Dairy and Egg Products",
        expected_name="Whole Milk",
        expected_base="milk",
        expected_qualifiers=["whole"],
        expected_noise=["3.25% milkfat", "with added vitamin D"],
        is_regression=True,
        notes="Milkfat percentage and vitamin D are noise for consumer",
    ),
    GoldenCase(
        usda_desc="Wheat flour, white, all-purpose, enriched, bleached",
        usda_category="Cereal Grains and Pasta",
        expected_name="All-Purpose Flour",
        expected_base="flour",
        expected_qualifiers=["all-purpose"],
        expected_noise=["enriched", "bleached"],
        is_regression=True,
        notes="Enriched and bleached are USDA detail noise",
    ),

    # --- Category 7: Classification boundary items ---
    GoldenCase(
        usda_desc="Potatoes, au gratin, dry mix, prepared with water, whole milk and butter",
        usda_category="Vegetables and Vegetable Products",
        expected_name="Au Gratin Potatoes",
        expected_base="potato",
        expected_qualifiers=["au gratin"],
        expected_noise=["dry mix", "prepared with water, whole milk and butter"],
        is_regression=True,
        notes="This is a prepared dish that leaked into ingredients",
    ),
    GoldenCase(
        usda_desc="Mustard, prepared, yellow",
        usda_category="Soups, Sauces, and Gravies",
        expected_name="Yellow Mustard",
        expected_base="mustard",
        expected_qualifiers=["yellow"],
        expected_noise=["prepared"],
        is_regression=True,
        notes="'prepared' means condiment form, not cooked dish",
    ),

    # --- Category 8: Items regex gets RIGHT (regression checks) ---
    GoldenCase(
        usda_desc="Butter, salted",
        usda_category="Dairy and Egg Products",
        expected_name="Salted Butter",
        expected_base="butter",
        expected_qualifiers=["salted"],
        is_regression=False,
    ),
    GoldenCase(
        usda_desc="Oil, olive, salad or cooking",
        usda_category="Fats and Oils",
        expected_name="Olive Oil",
        expected_base="olive oil",
        expected_qualifiers=[],
        expected_noise=["salad or cooking"],
        is_regression=False,
    ),
    GoldenCase(
        usda_desc="Spices, paprika",
        usda_category="Spices and Herbs",
        expected_name="Paprika",
        expected_base="paprika",
        is_regression=False,
    ),
    GoldenCase(
        usda_desc="Chicken, broiler or fryers, breast, skinless, boneless, meat only, raw",
        usda_category="Poultry Products",
        expected_name="Chicken Breast",
        expected_base="chicken",
        expected_qualifiers=["breast"],
        expected_form="raw",
        expected_noise=["broilers or fryers", "skinless", "boneless", "meat only"],
        is_regression=False,
    ),
    GoldenCase(
        usda_desc="Rice, white, long-grain, regular, raw, enriched",
        usda_category="Cereal Grains and Pasta",
        expected_name="White Rice",
        expected_base="rice",
        expected_qualifiers=["white", "long-grain"],
        expected_form="raw",
        expected_noise=["regular", "enriched"],
        is_regression=False,
    ),
    GoldenCase(
        usda_desc="Fish, salmon, Atlantic, wild, raw",
        usda_category="Finfish and Shellfish Products",
        expected_name="Atlantic Salmon",
        expected_base="salmon",
        expected_qualifiers=["Atlantic", "wild"],
        expected_form="raw",
        is_regression=False,
    ),
    GoldenCase(
        usda_desc="Nuts, almonds, dry roasted, with salt added",
        usda_category="Nut and Seed Products",
        expected_name="Dry Roasted Almonds",
        expected_base="almonds",
        expected_qualifiers=[],
        expected_noise=["with salt added"],
        is_regression=False,
    ),

    # --- Category 9: Missing base_ingredient cases ---
    GoldenCase(
        usda_desc="Hummus, commercial",
        usda_category="Legumes and Legume Products",
        expected_name="Hummus",
        expected_base="chickpea",
        expected_noise=["commercial"],
        is_regression=True,
        notes="base_ingredient should be chickpea",
    ),
    GoldenCase(
        usda_desc="Tofu, firm, prepared with calcium sulfate",
        usda_category="Legumes and Legume Products",
        expected_name="Firm Tofu",
        expected_base="soy",
        expected_qualifiers=["firm"],
        expected_noise=["prepared with calcium sulfate"],
        is_regression=True,
        notes="base_ingredient should be soy",
    ),
    GoldenCase(
        usda_desc="Oil, coconut",
        usda_category="Fats and Oils",
        expected_name="Coconut Oil",
        expected_base="coconut oil",
        is_regression=True,
        notes="base_ingredient was empty",
    ),
    GoldenCase(
        usda_desc="Vinegar, cider",
        usda_category="Soups, Sauces, and Gravies",
        expected_name="Cider Vinegar",
        expected_base="vinegar",
        expected_qualifiers=["cider"],
        is_regression=False,
    ),

    # --- Category 10: Complex multi-qualifier items ---
    GoldenCase(
        usda_desc="Cheese, mozzarella, low moisture, part-skim",
        usda_category="Dairy and Egg Products",
        expected_name="Part-Skim Mozzarella",
        expected_base="cheese",
        expected_qualifiers=["mozzarella", "part-skim"],
        expected_noise=["low moisture"],
        is_regression=True,
        notes="Low moisture is technical detail for consumer",
    ),
    GoldenCase(
        usda_desc="Cheese, cream, fat free",
        usda_category="Dairy and Egg Products",
        expected_name="Fat-Free Cream Cheese",
        expected_base="cheese",
        expected_qualifiers=["cream", "fat-free"],
        is_regression=True,
    ),
    GoldenCase(
        usda_desc="Milk, reduced fat, fluid, 2% milkfat, with added vitamin A and vitamin D",
        usda_category="Dairy and Egg Products",
        expected_name="Reduced-Fat Milk",
        expected_base="milk",
        expected_qualifiers=["reduced fat"],
        expected_noise=["fluid", "2% milkfat", "with added vitamin A and vitamin D"],
        is_regression=True,
        notes="Reduced-fat is the consumer-meaningful qualifier; milkfat percentage is noise",
    ),
    GoldenCase(
        usda_desc="Sour cream, reduced fat",
        usda_category="Dairy and Egg Products",
        expected_name="Reduced-Fat Sour Cream",
        expected_base="cream",
        expected_qualifiers=["sour", "reduced-fat"],
        is_regression=True,
    ),
    GoldenCase(
        usda_desc="Beef, ground, 85% lean meat / 15% fat, raw",
        usda_category="Beef Products",
        expected_name="Ground Beef",
        expected_base="beef",
        expected_qualifiers=["ground", "85% lean"],
        expected_form="raw",
        expected_noise=["15% fat"],
        is_regression=True,
        notes="Lean percentage is a useful qualifier, fat percentage is noise",
    ),
    GoldenCase(
        usda_desc="Turkey, retail parts, breast, meat only, cooked, roasted",
        usda_category="Poultry Products",
        expected_name="Turkey Breast",
        expected_base="turkey",
        expected_qualifiers=["breast"],
        expected_form="roasted",
        expected_noise=["retail parts", "meat only"],
        is_regression=True,
    ),
    GoldenCase(
        usda_desc="Pork, fresh, loin, whole, separable lean and fat, raw",
        usda_category="Pork Products",
        expected_name="Pork Loin",
        expected_base="pork",
        expected_qualifiers=["loin", "whole"],
        expected_form="raw",
        expected_noise=["fresh", "separable lean and fat"],
        is_regression=False,
    ),

    # --- Category 11: Produce with multiple descriptors ---
    GoldenCase(
        usda_desc="Peppers, sweet, red, raw",
        usda_category="Vegetables and Vegetable Products",
        expected_name="Red Bell Pepper",
        expected_base="pepper",
        expected_qualifiers=["sweet", "red"],
        expected_form="raw",
        is_regression=True,
        notes="'sweet' should map to 'bell' in consumer language",
    ),
    GoldenCase(
        usda_desc="Lettuce, iceberg (includes crisphead types), raw",
        usda_category="Vegetables and Vegetable Products",
        expected_name="Iceberg Lettuce",
        expected_base="lettuce",
        expected_qualifiers=["iceberg"],
        expected_form="raw",
        expected_noise=["includes crisphead types"],
        is_regression=True,
        notes="Parenthetical USDA clarification is noise",
    ),
    GoldenCase(
        usda_desc="Tomatoes, red, ripe, raw, year round average",
        usda_category="Vegetables and Vegetable Products",
        expected_name="Tomato",
        expected_base="tomato",
        expected_qualifiers=["red"],
        expected_form="raw",
        expected_noise=["ripe", "year round average"],
        is_regression=True,
    ),
    GoldenCase(
        usda_desc="Broccoli, raw",
        usda_category="Vegetables and Vegetable Products",
        expected_name="Broccoli",
        expected_base="broccoli",
        expected_form="raw",
        is_regression=False,
    ),

    # --- Category 12: Grains and baking ---
    GoldenCase(
        usda_desc="Bread, whole-wheat, commercially prepared",
        usda_category="Baked Products",
        expected_name="Whole-Wheat Bread",
        expected_base="bread",
        expected_qualifiers=["whole-wheat"],
        expected_noise=["commercially prepared"],
        is_regression=True,
        notes="Commercially prepared is noise",
    ),
    GoldenCase(
        usda_desc="Tortillas, ready-to-bake or -fry, flour",
        usda_category="Baked Products",
        expected_name="Flour Tortilla",
        expected_base="tortilla",
        expected_qualifiers=["flour"],
        expected_noise=["ready-to-bake or -fry"],
        is_regression=True,
    ),
    GoldenCase(
        usda_desc="Cornstarch",
        usda_category="Cereal Grains and Pasta",
        expected_name="Cornstarch",
        expected_base="corn",
        is_regression=False,
    ),
    GoldenCase(
        usda_desc="Sugars, granulated",
        usda_category="Sweets",
        expected_name="Granulated Sugar",
        expected_base="sugar",
        expected_qualifiers=["granulated"],
        is_regression=False,
    ),

    # --- Category 13: Beverages ---
    GoldenCase(
        usda_desc="Beverages, tea, black, brewed, prepared with tap water",
        usda_category="Beverages",
        expected_name="Black Tea",
        expected_base="tea",
        expected_qualifiers=["black"],
        expected_form="brewed",
        expected_noise=["prepared with tap water"],
        is_regression=True,
    ),
    GoldenCase(
        usda_desc="Beverages, coffee, brewed, prepared with tap water",
        usda_category="Beverages",
        expected_name="Coffee",
        expected_base="coffee",
        expected_form="brewed",
        expected_noise=["prepared with tap water"],
        is_regression=True,
    ),

    # --- Category 14: Oils and fats ---
    GoldenCase(
        usda_desc="Oil, canola",
        usda_category="Fats and Oils",
        expected_name="Canola Oil",
        expected_base="canola oil",
        is_regression=False,
    ),
    GoldenCase(
        usda_desc="Lard",
        usda_category="Fats and Oils",
        expected_name="Lard",
        expected_base="lard",
        is_regression=False,
    ),
]


def get_golden_parse_cases() -> list[GoldenCase]:
    """Return all golden parse test cases."""
    return GOLDEN_PARSE_CASES


def get_regression_cases() -> list[GoldenCase]:
    """Return only cases the regex parser got WRONG — ML must fix these."""
    return [c for c in GOLDEN_PARSE_CASES if c.is_regression]


def get_non_regression_cases() -> list[GoldenCase]:
    """Return cases the regex parser got RIGHT — ML must not break these."""
    return [c for c in GOLDEN_PARSE_CASES if not c.is_regression]
