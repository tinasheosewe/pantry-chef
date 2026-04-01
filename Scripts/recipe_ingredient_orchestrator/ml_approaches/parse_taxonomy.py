"""Taxonomy-based USDA food description parser.

Uses a curated food taxonomy (food terms, forms, qualifiers) plus
rapidfuzz fuzzy matching to map USDA descriptions to canonical names.

Strategy:
1. Split USDA desc into comma-separated fields
2. Match each field against taxonomy of known foods, forms, qualifiers
3. Detect and strip brands, USDA noise
4. Assemble canonical name from matched components
"""

from __future__ import annotations

import logging
import re
from typing import Any

from rapidfuzz import fuzz, process

from .shared import (
    BRAND_PATTERNS,
    COMMERCIAL_NOISE,
    USDA_NOISE_TERMS,
    ParsedItem,
    get_fdc_id,
    get_usda_category,
    get_usda_description,
    load_usda_foods,
    save_parse_results,
)

logger = logging.getLogger(__name__)

APPROACH_NAME = "taxonomy"

# ---------------------------------------------------------------------------
# Taxonomy: canonical food terms
# ---------------------------------------------------------------------------

# Map from USDA term → canonical consumer name
_FOOD_CANONICAL: dict[str, str] = {
    # Proteins
    "chicken": "Chicken", "beef": "Beef", "pork": "Pork",
    "turkey": "Turkey", "lamb": "Lamb", "veal": "Veal",
    "duck": "Duck", "goose": "Goose", "bison": "Bison",
    "venison": "Venison", "goat": "Goat",
    "salmon": "Salmon", "tuna": "Tuna", "cod": "Cod",
    "tilapia": "Tilapia", "shrimp": "Shrimp", "crab": "Crab",
    "lobster": "Lobster", "scallop": "Scallop", "clam": "Clam",
    "mussel": "Mussel", "oyster": "Oyster", "sardine": "Sardine",
    "trout": "Trout", "catfish": "Catfish", "halibut": "Halibut",
    "swordfish": "Swordfish", "anchovy": "Anchovy", "mackerel": "Mackerel",
    "herring": "Herring", "snapper": "Snapper", "bass": "Bass",
    "squid": "Squid", "octopus": "Octopus",
    "frankfurter": "Frankfurter", "sausage": "Sausage",
    "hot dog": "Hot Dog", "bacon": "Bacon", "ham": "Ham",

    # Dairy
    "cheese": "Cheese", "milk": "Milk", "cream": "Cream",
    "yogurt": "Yogurt", "yoghurt": "Yogurt", "butter": "Butter",
    "ghee": "Ghee", "kefir": "Kefir", "whey": "Whey",
    "egg": "Egg", "eggs": "Egg",
    "cream cheese": "Cream Cheese", "sour cream": "Sour Cream",
    "cottage cheese": "Cottage Cheese",
    "cheese spread": "Cheese Spread",

    # Produce
    "apple": "Apple", "apples": "Apple",
    "banana": "Banana", "bananas": "Banana",
    "orange": "Orange", "oranges": "Orange",
    "grape": "Grape", "grapes": "Grape",
    "tomato": "Tomato", "tomatoes": "Tomato",
    "potato": "Potato", "potatoes": "Potato",
    "onion": "Onion", "onions": "Onion",
    "garlic": "Garlic", "pepper": "Pepper", "peppers": "Pepper",
    "carrot": "Carrot", "carrots": "Carrot",
    "celery": "Celery", "broccoli": "Broccoli",
    "spinach": "Spinach", "kale": "Kale",
    "lettuce": "Lettuce", "cucumber": "Cucumber",
    "mushroom": "Mushroom", "mushrooms": "Mushroom",
    "corn": "Corn", "squash": "Squash", "avocado": "Avocado",
    "lemon": "Lemon", "lime": "Lime", "mango": "Mango",
    "pineapple": "Pineapple", "peach": "Peach", "pear": "Pear",
    "cherry": "Cherry", "cherries": "Cherry",
    "plum": "Plum", "melon": "Melon",
    "cabbage": "Cabbage", "cauliflower": "Cauliflower",
    "eggplant": "Eggplant", "zucchini": "Zucchini",
    "bean": "Bean", "beans": "Bean",
    "lentil": "Lentil", "lentils": "Lentil",
    "chickpea": "Chickpea", "chickpeas": "Chickpea",
    "pea": "Pea", "peas": "Pea",

    # Grains/staples
    "rice": "Rice", "pasta": "Pasta",
    "noodle": "Noodle", "noodles": "Noodle",
    "bread": "Bread", "flour": "Flour",
    "wheat flour": "Flour",
    "oat": "Oat", "oats": "Oat",
    "barley": "Barley", "quinoa": "Quinoa",
    "cornstarch": "Cornstarch",
    "tortilla": "Tortilla", "tortillas": "Tortilla",
    "baking chocolate": "Baking Chocolate",

    # Nuts/seeds (plural canonical — countable nouns)
    "almond": "Almonds", "almonds": "Almonds",
    "walnut": "Walnuts", "walnuts": "Walnuts",
    "pecan": "Pecans", "pecans": "Pecans",
    "cashew": "Cashews", "cashews": "Cashews",
    "peanut": "Peanuts", "peanuts": "Peanuts",
    "pistachio": "Pistachios", "pistachios": "Pistachios",
    "coconut": "Coconut", "hazelnut": "Hazelnuts",
    "macadamia": "Macadamia",

    # Pantry
    "oil": "Oil", "vinegar": "Vinegar",
    "sauce": "Sauce", "sauces": "Sauce",
    "mustard": "Mustard", "ketchup": "Ketchup",
    "salsa": "Salsa", "honey": "Honey",
    "sugar": "Sugar", "sugars": "Sugar",
    "salt": "Salt", "tea": "Tea", "coffee": "Coffee",
    "juice": "Juice", "water": "Water",
    "chocolate": "Chocolate", "cocoa": "Cocoa",
    "vanilla": "Vanilla", "lard": "Lard",
    "hummus": "Hummus", "tofu": "Tofu",
    "soy": "Soy", "syrup": "Syrup",
    "olive oil": "Olive Oil", "coconut oil": "Coconut Oil",
    "canola oil": "Canola Oil", "sesame oil": "Sesame Oil",
    "peanut butter": "Peanut Butter",
    "almond butter": "Almond Butter",
    "maple syrup": "Maple Syrup",
    "soy sauce": "Soy Sauce",
    "orange juice": "Orange Juice",
    "apple juice": "Apple Juice",
    "lemon juice": "Lemon Juice",
}

# Base ingredient mapping (food term → base)
_BASE_MAP: dict[str, str] = {
    "chicken": "chicken", "beef": "beef", "pork": "pork",
    "turkey": "turkey", "lamb": "lamb", "salmon": "salmon",
    "tuna": "tuna", "cod": "cod", "shrimp": "shrimp",
    "cheese": "cheese", "milk": "milk", "cream": "cream",
    "yogurt": "yogurt", "butter": "butter", "egg": "egg",
    "rice": "rice", "pasta": "pasta", "bread": "bread",
    "flour": "flour", "oat": "oat",
    "bean": "bean", "lentil": "lentil", "chickpea": "chickpea",
    "pea": "pea", "tofu": "soy", "hummus": "chickpea",
    "apple": "apple", "banana": "banana", "orange": "orange",
    "tomato": "tomato", "potato": "potato", "onion": "onion",
    "garlic": "garlic", "pepper": "pepper", "carrot": "carrot",
    "broccoli": "broccoli", "spinach": "spinach", "lettuce": "lettuce",
    "mushroom": "mushroom", "corn": "corn", "avocado": "avocado",
    "lemon": "lemon", "lime": "lime",
    "almond": "almond", "walnut": "walnut", "peanut": "peanut",
    "coconut": "coconut",
    "oil": "oil", "vinegar": "vinegar", "sauce": "sauce",
    "mustard": "mustard", "salsa": "salsa", "honey": "honey",
    "sugar": "sugar", "salt": "salt", "chocolate": "chocolate",
    "cocoa": "cocoa", "vanilla": "vanilla", "lard": "lard",
    "tea": "tea", "coffee": "coffee", "juice": "juice",
    "olive oil": "olive oil", "coconut oil": "coconut oil",
    "canola oil": "canola oil", "soy sauce": "soy sauce",
    "orange juice": "orange juice", "apple juice": "apple juice",
    "cream cheese": "cheese", "sour cream": "cream",
    "cottage cheese": "cheese", "cheese spread": "cheese",
    "peanut butter": "peanut",
    "maple syrup": "maple syrup", "frankfurter": "frankfurter",
    "sausage": "sausage", "bacon": "pork", "ham": "pork",
    "tortilla": "tortilla", "cornstarch": "corn",
    "syrup": "syrup",
    "marinara sauce": "sauce", "marinara": "sauce",
    "salsa": "salsa", "teriyaki sauce": "sauce",
    "baking chocolate": "chocolate",
    "wheat flour": "flour",
}

# Qualifier terms (variant descriptors meaningful to consumers)
_QUALIFIER_TERMS: dict[str, str] = {
    "cheddar": "cheddar", "mozzarella": "mozzarella",
    "parmesan": "parmesan", "swiss": "swiss", "brie": "brie",
    "gouda": "gouda", "feta": "feta", "provolone": "provolone",
    "colby": "colby", "monterey": "monterey", "american": "American",
    "cottage": "cottage", "ricotta": "ricotta", "mascarpone": "mascarpone",
    "muenster": "muenster", "havarti": "havarti", "gruyere": "gruyere",
    "neufchatel": "neufchatel",
    "atlantic": "Atlantic", "pacific": "Pacific", "wild": "wild",
    "sweet": "sweet", "hot": "hot", "mild": "mild",
    "red": "red", "green": "green", "yellow": "yellow",
    "white": "white", "black": "black", "brown": "brown",
    "iceberg": "iceberg", "romaine": "romaine",
    "italian": "Italian", "greek": "Greek", "french": "French",
    "long-grain": "long-grain", "short-grain": "short-grain",
    "basmati": "basmati", "jasmine": "jasmine",
    "all-purpose": "all-purpose", "self-rising": "self-rising",
    "whole-wheat": "whole-wheat", "whole wheat": "whole-wheat",
    "extra-virgin": "extra-virgin", "virgin": "virgin",
    "nonfat": "nonfat", "low-fat": "low-fat", "lowfat": "low-fat",
    "reduced-fat": "reduced-fat", "reduced fat": "reduced-fat",
    "fat-free": "fat-free", "fat free": "fat-free",
    "part-skim": "part-skim",
    "snap": "snap", "kidney": "kidney", "pinto": "pinto",
    "navy": "navy", "lima": "lima",
    "bell": "bell", "jalapeño": "jalapeño",
    "teriyaki": "teriyaki", "marinara": "marinara",
    "alfredo": "alfredo", "spaghetti": "spaghetti",
    "granulated": "granulated", "powdered": "powdered",
    "confectioners": "confectioners",
    "breast": "breast", "thigh": "thigh", "wing": "wing",
    "drumstick": "drumstick", "loin": "loin", "chop": "chop",
    "tenderloin": "tenderloin", "rib": "rib", "sirloin": "sirloin",
    "filet": "filet", "fillet": "fillet", "steak": "steak",
    "roast": "roast",
    "whole": "whole", "firm": "firm", "soft": "soft",
    "plain": "plain", "vanilla": "vanilla", "strawberry": "strawberry",
    "blueberry": "blueberry", "raspberry": "raspberry",
    "cider": "cider",
    "semisweet": "semisweet", "bittersweet": "bittersweet",
    "wheat": "wheat", "rye": "rye", "buckwheat": "buckwheat",
    "prepared": "prepared",
    # salted/unsalted meaningful as qualifiers for butter/nuts
    "salted": "salted", "unsalted": "unsalted",
    "sweetened": "sweetened", "unsweetened": "unsweetened",
}

# Form/preservation terms
_FORM_TERMS: dict[str, str] = {
    "raw": "raw", "cooked": "cooked", "dried": "dried", "dry": "dry",
    "dry roasted": "dry roasted", "dry-roasted": "dry roasted",
    "roasted": "roasted", "smoked": "smoked",
    "canned": "canned", "frozen": "frozen", "fresh": "fresh",
    "pickled": "pickled", "fermented": "fermented", "cured": "cured",
    "ground": "ground", "sliced": "sliced", "diced": "diced",
    "chopped": "chopped", "minced": "minced",
    "shredded": "shredded", "grated": "grated",
    "crushed": "crushed", "powdered": "powdered",
    "blanched": "blanched", "peeled": "peeled",
    "dehydrated": "dehydrated", "freeze-dried": "freeze-dried",
    "concentrated": "concentrated", "condensed": "condensed",
    "evaporated": "evaporated", "concentrate": "concentrate",
    "brewed": "brewed", "instant": "instant",
    "frozen concentrate": "frozen concentrate",
    # Cooking methods as forms
    "braised": "braised", "grilled": "grilled", "fried": "fried",
    "baked": "baked", "steamed": "steamed", "boiled": "boiled",
    "sauteed": "sauteed", "poached": "poached", "broiled": "broiled",
    "stewed": "stewed", "pan-fried": "pan-fried",
    "deep-fried": "deep-fried", "stir-fried": "stir-fried",
    "microwaved": "microwaved", "toasted": "toasted",
    "scrambled": "scrambled",
    # Fat content is handled as qualifiers (in _QUALIFIER_TERMS)
    "pasteurized": "pasteurized", "homogenized": "homogenized",
    "processed": "processed",
}

# Noise phrases to detect and strip
_NOISE_PHRASES: list[str] = [
    "not further specified", "nfs", "usda commodity",
    "includes usda commodity", "all commercial varieties",
    "all types", "all varieties", "composite of cuts",
    "year round average", "commercially prepared",
    "ready-to-serve", "ready-to-eat", "ready-to-heat",
    "ready-to-drink", "ready-to-bake or -fry",
    "enriched", "fortified", "bleached", "unbleached",
    "regular pack", "drained solids",
    "separable lean and fat", "separable lean only",
    "meat only", "meat and skin", "bone-in", "boneless", "skinless",
    "flesh and skin", "skin only", "meat and fat",
    "broilers or fryers", "broiler or fryers", "all classes",
    "retail parts",
    "regular",
    "commercial", "commercially prepared",
    "fluid",
    "includes foods for usda's food distribution program",
    "with added vitamin d", "with added vitamin a",
    "with added vitamin a and vitamin d",
    "salad or cooking",
    "includes crisphead types",
    "prepared with tap water",
    "prepared with water, whole milk and butter",
    "whole milk and butter",
    "prepared with calcium sulfate",
    "low moisture",
    "ripe",
    # Preparation/dilution states
    "undiluted", "diluted",
    "diluted with 3 volume water", "diluted with 3 volumes water",
    "unheated", "heated",
    # Fat content noise
    "milkfat",
    # USDA process descriptors
    "pasteurized process",
    "imitation", "substitute",
    "mini baking bits",
    # Brand sub-names that leak through brand detection
    "m&m's",
    # Shelf-stable process
    "shelf stable", "shelf-stable",
]

# Category → prefix to strip before parsing
_CAT_PREFIXES: dict[str, list[str]] = {
    "Spices and Herbs": ["spices,", "herbs,", "spice,"],
    "Fats and Oils": ["oil,", "fat,", "shortening,"],
    "Beverages": ["beverages,", "beverage,"],
    "Nut and Seed Products": ["nuts,", "seeds,", "nut,", "seed,"],
    "Soups, Sauces, and Gravies": ["sauce,", "sauces,"],
    "Sweets": ["sugars,", "sugar,", "syrups,", "syrup,",
               "baking chocolate,"],
    "Finfish and Shellfish Products": ["fish,"],
}


# Specific sauce/condiment types that should override generic "Sauce"
_SAUCE_SPECIFICS: dict[str, str] = {
    "salsa": "Salsa", "marinara": "Marinara Sauce", "alfredo": "Alfredo Sauce",
    "teriyaki": "Teriyaki Sauce", "soy": "Soy Sauce", "hot": "Hot Sauce",
    "barbecue": "Barbecue Sauce", "bbq": "BBQ Sauce",
    "worcestershire": "Worcestershire Sauce",
    "pesto": "Pesto", "hoisin": "Hoisin Sauce",
    "sriracha": "Sriracha", "tabasco": "Tabasco Sauce",
    "cocktail": "Cocktail Sauce", "tartar": "Tartar Sauce",
    "enchilada": "Enchilada Sauce", "pizza": "Pizza Sauce",
}

# Context-dependent qualifiers: should be dropped for certain foods
# (USDA uses "whole" for eggs to distinguish whole vs whites vs yolks,
#  but consumers just say "egg"; "prepared" is default for condiments)
_DROP_QUALIFIERS: dict[str, set[str]] = {
    "egg": {"whole"},
    "milk": set(),  # "whole" is meaningful for milk
    "mustard": {"prepared"},  # all consumer mustard is prepared
    "ketchup": {"prepared"},
    "salsa": {"prepared"},
    "flour": {"wheat", "white"},  # all-purpose flour is wheat flour by definition
    "tortilla": {"shelf stable", "shelf-stable"},
    "rice": {"regular", "long-grain", "short-grain"},
    "milk": {"fluid"},
    "orange juice": {"unsweetened"},
    "juice": {"unsweetened"},
    "yogurt": {"plain", "nonfat"},  # "plain" is default; nonfat is form info
}

# Consumer-friendly translations for qualifiers
_QUALIFIER_TRANSLATE: dict[str, str] = {
    "sweet": "bell",  # sweet pepper → bell pepper in consumer language
}


def _strip_category_prefix(desc: str, cat: str) -> tuple[str, str | None]:
    """Strip category prefix and return (remaining, stripped_prefix)."""
    low = desc.lower()
    for prefix in _CAT_PREFIXES.get(cat, []):
        if low.startswith(prefix):
            return desc[len(prefix):].strip(), prefix.rstrip(",")
    return desc, None


def _detect_brand(desc: str) -> tuple[str, str]:
    """Detect and strip brand name. Returns (cleaned_desc, brand)."""
    # Always strip ALL leading all-caps comma-separated parts first
    parts = desc.split(",")
    brands = []
    remaining_parts = []
    brand_done = False
    for part in parts:
        stripped = part.strip()
        if not brand_done and stripped == stripped.upper() and len(stripped) > 2 and stripped.lower() not in _FOOD_CANONICAL:
            brands.append(stripped)
        else:
            brand_done = True
            remaining_parts.append(part)

    if brands:
        brand = brands[0]  # primary brand
        cleaned = ", ".join(remaining_parts).strip()
        if cleaned:
            return cleaned, brand

    # Fallback: regex-based brand detection
    m = BRAND_PATTERNS.match(desc)
    if m:
        brand = m.group(1).strip()
        return desc[m.end():].strip(" ,"), brand

    return desc, ""


def _match_field(field: str) -> tuple[str, str]:
    """Match a single comma-field against taxonomy.

    Returns (matched_term, category) where category is one of:
    'food', 'qualifier', 'form', 'noise', 'unknown'.
    """
    field = field.strip()
    low = field.lower()

    # Check noise first (longer phrases)
    for noise in _NOISE_PHRASES:
        if noise in low:
            # If the field contains BOTH noise and a food/qualifier term, strip noise and re-evaluate
            remaining = low.replace(noise, "").strip(" ,")
            if remaining:
                for term, canonical in sorted(_FOOD_CANONICAL.items(),
                                              key=lambda x: -len(x[0])):
                    if len(term.split()) > 1 and term in remaining:
                        return canonical, "food"
                for word in remaining.split():
                    wc = word.strip(".,;:()")
                    if wc in _FOOD_CANONICAL:
                        return _FOOD_CANONICAL[wc], "food"
                # Also check if remaining is a qualifier
                for word in remaining.split():
                    wc = word.strip(".,;:()")
                    if wc in _QUALIFIER_TERMS:
                        return _QUALIFIER_TERMS[wc], "qualifier"
            return field, "noise"

    # Percentage pattern (e.g., "3.25% milkfat", "85% lean")
    if re.match(r"\d+\.?\d*%", low):
        return field, "noise"

    # "with added ..." pattern
    if low.startswith("with "):
        return field, "noise"

    # "prepared with ..." pattern
    if low.startswith("prepared with "):
        return field, "noise"

    # "dry mix" pattern
    if "dry mix" in low:
        return field, "noise"

    # Check multi-word food matches first (e.g., "cream cheese")
    for term, canonical in sorted(_FOOD_CANONICAL.items(),
                                  key=lambda x: -len(x[0])):
        if len(term.split()) > 1 and term in low:
            return canonical, "food"

    # Check single-word food matches
    words = low.split()
    for word in words:
        word_clean = word.strip(".,;:()")
        if word_clean in _FOOD_CANONICAL:
            return _FOOD_CANONICAL[word_clean], "food"

    # Check form terms — multi-word first, then single-word with WORD BOUNDARY matching
    for term in sorted(_FORM_TERMS, key=len, reverse=True):
        if " " in term and term in low:
            return _FORM_TERMS[term], "form"
    for word in words:
        word_clean = word.strip(".,;:()")
        if word_clean in _FORM_TERMS:
            return _FORM_TERMS[word_clean], "form"

    # Check qualifier terms — multi-word first, then single-word
    for term in sorted(_QUALIFIER_TERMS, key=len, reverse=True):
        if " " in term and term in low:
            return _QUALIFIER_TERMS[term], "qualifier"
    for word in words:
        word_clean = word.strip(".,;:()")
        if word_clean in _QUALIFIER_TERMS:
            return _QUALIFIER_TERMS[word_clean], "qualifier"

    # Fuzzy match against food terms (threshold 85)
    for word in words:
        word_clean = word.strip(".,;:()")
        if len(word_clean) < 3:
            continue
        match = process.extractOne(
            word_clean,
            list(_FOOD_CANONICAL.keys()),
            scorer=fuzz.ratio,
            score_cutoff=85,
        )
        if match:
            return _FOOD_CANONICAL[match[0]], "food"

    return field, "unknown"


# ---------------------------------------------------------------------------
# Main parsing logic
# ---------------------------------------------------------------------------

def _parse_single(desc: str, cat: str, fdc_id: int) -> ParsedItem:
    """Parse a single USDA description using taxonomy matching."""
    original = desc

    # Step 1: strip category prefix (before brand detection, so prefix doesn't
    # block the all-caps brand check)
    desc, stripped_prefix = _strip_category_prefix(desc, cat)

    # Step 2: detect and strip brand
    desc, brand = _detect_brand(desc)

    # Step 3: split into comma fields
    fields = [f.strip() for f in desc.split(",") if f.strip()]

    # Step 4: classify each field
    food_parts: list[str] = []
    qualifiers: list[str] = []
    forms: list[str] = []
    noise: list[str] = []
    sauce_specific: str | None = None  # for sauce sub-type detection

    # If we stripped a prefix, that tells us the food category
    prefix_food = None
    if stripped_prefix:
        low_prefix = stripped_prefix.lower()
        if low_prefix in _FOOD_CANONICAL:
            prefix_food = _FOOD_CANONICAL[low_prefix]

    for i, field_str in enumerate(fields):
        matched, match_type = _match_field(field_str)
        low_field = field_str.strip().lower()

        # Sauce specificity: if prefix is sauce-like, check for specific sauce type
        if prefix_food in ("Sauce",) and not sauce_specific:
            for key, sname in _SAUCE_SPECIFICS.items():
                if key in low_field:
                    sauce_specific = sname
                    # Don't add to food_parts; it'll be handled in name assembly
                    match_type = "sauce_specific"  # skip normal handling
                    break

        if match_type == "sauce_specific":
            continue  # already captured

        if match_type == "food":
            food_parts.append(matched)
        elif match_type == "qualifier":
            qualifiers.append(matched)
        elif match_type == "form":
            forms.append(matched)
        elif match_type == "noise":
            noise.append(field_str)
        else:
            # Unknown: if it's the first field, treat as food
            if i == 0 and not food_parts:
                food_parts.append(field_str.strip().title())
            else:
                # Check if it's a parenthetical
                if field_str.startswith("(") and field_str.endswith(")"):
                    noise.append(field_str)
                else:
                    qualifiers.append(field_str.strip().lower())

    # Step 5: context-dependent qualifier filtering for name assembly
    # Keep ALL qualifiers in the ParsedItem, but create name_qualifiers
    # that excludes context-specific ones from the display name
    primary_food_low = food_parts[0].lower() if food_parts else ""
    drop_set: set[str] = set()
    # Check multi-word food terms (e.g., "orange juice")
    if prefix_food:
        compound_key = prefix_food.lower()
        if compound_key in _DROP_QUALIFIERS:
            drop_set |= _DROP_QUALIFIERS[compound_key]
    if primary_food_low in _DROP_QUALIFIERS:
        drop_set |= _DROP_QUALIFIERS[primary_food_low]
    name_qualifiers = [q for q in qualifiers if q not in drop_set]

    # Step 5b: translate qualifiers for consumer-friendly names
    name_qualifiers = [_QUALIFIER_TRANSLATE.get(q, q) for q in name_qualifiers]
    qualifiers = [_QUALIFIER_TRANSLATE.get(q, q) for q in qualifiers]

    # Step 5c: for certain foods, include meaningful forms in the name
    # e.g., "dry roasted" almonds, "ground" beef
    _NAME_FORMS = {"almond", "almonds", "walnut", "walnuts", "pecan", "pecans",
                   "cashew", "cashews", "peanut", "peanuts", "pistachio", "pistachios",
                   "hazelnut", "hazelnuts", "macadamia", "beef"}
    name_form_parts: list[str] = []
    if primary_food_low in _NAME_FORMS:
        for f in forms:
            if f in ("dry roasted", "ground"):
                name_form_parts.append(f)
        # Remove name forms from forms list so they aren't double-counted
        forms = [f for f in forms if f not in name_form_parts]

    # Step 6: assemble name
    # If sauce-specific was detected, use that directly
    if sauce_specific:
        name = sauce_specific
        # For sauce-specific, the food IS the sauce type, override food_parts for base derivation
        food_parts = [sauce_specific]
    elif prefix_food:
        if prefix_food in ("Sauce", "Oil", "Sugar", "Syrup"):
            if name_qualifiers and not food_parts:
                # "teriyaki" → "Teriyaki Sauce"
                name = " ".join(q.title() for q in name_qualifiers) + " " + prefix_food
                food_parts = [prefix_food]
            elif food_parts:
                # Already found a food — qualifier + food + prefix
                # e.g., "olive" + "Oil" → "Olive Oil"
                qual_str = " ".join(q.title() for q in name_qualifiers)
                name = f"{qual_str} {food_parts[0]} {prefix_food}" if qual_str else f"{food_parts[0]} {prefix_food}"
            else:
                name = prefix_food
        else:
            # Generic: qualifiers before food
            if food_parts:
                name = " ".join(q.title() for q in name_qualifiers)
                if name:
                    name += " " + food_parts[0]
                else:
                    name = food_parts[0]
            else:
                name = " ".join(q.title() for q in name_qualifiers)
                if name:
                    name += " " + prefix_food
                else:
                    name = prefix_food
    else:
        if food_parts:
            primary_food = food_parts[0]
            extra_foods = food_parts[1:]
            all_quals = list(name_qualifiers) + [f.lower() for f in extra_foods]

            # Cheese variety special case: when primary is "Cheese" and there's a
            # variety qualifier (mozzarella, cheddar, etc.), promote variety to primary
            # Only promote when there are other qualifiers (e.g., "Part-Skim Mozzarella"
            # not "Cheddar" alone — keep as "Cheddar Cheese")
            _CHEESE_VARIETIES = {"mozzarella", "cheddar", "parmesan", "swiss", "brie",
                                 "gouda", "feta", "provolone", "colby", "gruyere",
                                 "havarti", "muenster", "neufchatel", "ricotta",
                                 "mascarpone", "monterey"}
            if primary_food.lower() == "cheese":
                variety = None
                for q in all_quals:
                    if q.lower() in _CHEESE_VARIETIES:
                        variety = q
                        break
                other_quals = [q for q in all_quals if q.lower() != (variety or "").lower()]
                if variety and other_quals:
                    primary_food = variety.title()
                    all_quals = other_quals

            # Include name-worthy forms (e.g., "dry roasted" for nuts, "ground" for beef)
            all_parts_pre = [f.title() for f in name_form_parts]

            # Meat cuts go AFTER animal name ("Turkey Breast" not "Breast Turkey")
            _POSTFIX_QUALS = {"breast", "thigh", "wing", "drumstick", "loin",
                              "chop", "tenderloin", "rib", "sirloin", "filet",
                              "fillet", "steak", "roast", "leg", "shank"}
            pre_quals = [q.title() for q in all_quals if q.lower() not in _POSTFIX_QUALS]
            post_quals = [q.title() for q in all_quals if q.lower() in _POSTFIX_QUALS]

            pre_str = " ".join(all_parts_pre + pre_quals)
            post_str = " ".join(post_quals)
            if pre_str and post_str:
                name = f"{pre_str} {primary_food} {post_str}"
            elif pre_str:
                name = f"{pre_str} {primary_food}"
            elif post_str:
                name = f"{primary_food} {post_str}"
            else:
                name = primary_food
        elif name_qualifiers:
            name = " ".join(q.title() for q in name_qualifiers)
        else:
            name = fields[0].strip().title() if fields else original.split(",")[0].title()

    # Clean up name
    name = " ".join(name.split())
    name = name.title()
    for old, new in [("'S", "'s"), (" Or ", " or "), (" And ", " and "),
                     (" Of ", " of "), (" With ", " with ")]:
        name = name.replace(old, new)

    # Step 7: derive base ingredient
    base = ""
    # For compound items (prefix + food), try compound base first (e.g., "coconut oil")
    if prefix_food and food_parts:
        compound = f"{food_parts[0].lower()} {prefix_food.lower()}"
        if compound in _BASE_MAP:
            base = _BASE_MAP[compound]
    if not base:
        for food in food_parts:
            low_food = food.lower()
            if low_food in _BASE_MAP:
                base = _BASE_MAP[low_food]
                break
    if not base and prefix_food:
        low_pf = prefix_food.lower()
        if low_pf in _BASE_MAP:
            base = _BASE_MAP[low_pf]
    if not base and food_parts:
        base = food_parts[0].lower()

    return ParsedItem(
        fdc_id=fdc_id,
        original_desc=original,
        usda_category=cat,
        parsed_name=name,
        parsed_base=base,
        qualifiers=qualifiers,
        form=" ".join(forms),
        brand=brand,
        noise_removed=noise,
    )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def run(foods: list[dict[str, Any]] | None = None) -> list[ParsedItem]:
    """Parse all USDA foods using taxonomy matching."""
    if foods is None:
        foods = load_usda_foods()

    logger.info("Parsing %d foods with taxonomy matching...", len(foods))
    results = [
        _parse_single(
            get_usda_description(food),
            get_usda_category(food),
            get_fdc_id(food),
        )
        for food in foods
        if get_usda_description(food)
    ]

    save_parse_results(results, APPROACH_NAME)
    logger.info("Taxonomy parse complete: %d items", len(results))
    return results
