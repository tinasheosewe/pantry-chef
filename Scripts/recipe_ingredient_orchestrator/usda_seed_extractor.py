"""USDA FoodData Central → CatalogEntry seed extractor.

Downloads Foundation Foods + SR Legacy data, merges, classifies into
ingredient vs prepared-food catalogs, transforms to CatalogEntry format,
and writes output JSON files.

Usage:
    python -m recipe_ingredient_orchestrator.usda_seed_extractor [--skip-download]
"""

from __future__ import annotations

import argparse
import io
import json
import logging
import re
import zipfile
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional
from urllib.request import urlopen

from pydantic import ValidationError

from .catalog import InMemoryCatalog
from .models import CatalogEntry
from .schemas import FoodCategory, MeasurementUnit, PantryStorage

logger = logging.getLogger(__name__)

_SCRIPT_DIR = Path(__file__).resolve().parent
_DATA_DIR = _SCRIPT_DIR / "data" / "usda"
_OUTPUT_DIR = _SCRIPT_DIR / "output"

# ---------------------------------------------------------------------------
# USDA download URLs  (JSON zips from fdc.nal.usda.gov/download-datasets)
# ---------------------------------------------------------------------------

_DOWNLOADS = {
    "foundation": {
        "url": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_2024-10-31.zip",
        "inner_json": "foundationDownload.json",
        "key": "FoundationFoods",
    },
    "sr_legacy": {
        "url": "https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip",
        "inner_json": "FoodData_Central_sr_legacy_food_json_2018-04.json",
        "key": "SRLegacyFoods",
    },
}

# ---------------------------------------------------------------------------
# USDA category → FoodCategory mapping (by description, not code)
# ---------------------------------------------------------------------------

_PREPARED_FOOD_CATEGORIES = frozenset({
    "Baby Foods",
    "Fast Foods",
    "Meals, Entrees, and Side Dishes",
    "Restaurant Foods",
    "Baked Products",
    "Breakfast Cereals",
    "Sweets",
    "Snacks",
    "Soups, Sauces, and Gravies",
})

_USDA_DESC_TO_FOOD_CATEGORY: dict[str, FoodCategory] = {
    "Dairy and Egg Products": FoodCategory.DAIRY,
    "Spices and Herbs": FoodCategory.SPICES_HERBS,
    "Fats and Oils": FoodCategory.OILS_FATS,
    "Poultry Products": FoodCategory.PROTEIN,
    "Soups, Sauces, and Gravies": FoodCategory.CONDIMENTS_SAUCES,
    "Sausages and Luncheon Meats": FoodCategory.PROTEIN,
    "Beef Products": FoodCategory.PROTEIN,
    "Beverages": FoodCategory.BEVERAGES,
    "Fruits and Fruit Juices": FoodCategory.PRODUCE,
    "Pork Products": FoodCategory.PROTEIN,
    "Vegetables and Vegetable Products": FoodCategory.PRODUCE,
    "Nut and Seed Products": FoodCategory.NUTS_SEEDS,
    "Finfish and Shellfish Products": FoodCategory.PROTEIN,
    "Legumes and Legume Products": FoodCategory.PRODUCE,
    "Lamb, Veal, and Game Products": FoodCategory.PROTEIN,
    "Baked Products": FoodCategory.BAKING_SUPPLIES,
    "Sweets": FoodCategory.SNACKS,
    "Cereal Grains and Pasta": FoodCategory.GRAINS_CEREALS,
    "Breakfast Cereals": FoodCategory.GRAINS_CEREALS,
    "Snacks": FoodCategory.SNACKS,
    "American Indian/Alaska Native Foods": FoodCategory.OTHER,
}

# Egg detection — eggs in USDA category 0100 should be Protein, not Dairy
_EGG_PATTERNS = re.compile(r"\begg\b", re.IGNORECASE)

# Pasta detection within Cereal Grains (1700)
_PASTA_PATTERNS = re.compile(
    r"\b(pasta|noodle|spaghetti|macaroni|penne|fettuccin|linguine|"
    r"rigatoni|lasagna|ravioli|tortellini|orzo|vermicelli|ramen)\b",
    re.IGNORECASE,
)

# ---------------------------------------------------------------------------
# Cooked / composite routing patterns
# ---------------------------------------------------------------------------

_COOKED_TERMS = re.compile(
    r"\b(cooked|braised|roasted|grilled|fried|baked|steamed|boiled|"
    r"sauteed|sautéed|poached|broiled|stewed|smoked|scrambled|"
    r"pan-fried|deep-fried|stir-fried|microwaved|toasted)\b",
    re.IGNORECASE,
)

# Exceptions: cooking that fundamentally changes identity (keep as ingredient)
# Matches "dry roasted" or "dried" near common pantry-staple nouns (incl. plurals)
_IDENTITY_NOUNS = (
    r"beans?|nuts?|almonds?|cashews?|pecans?|pistachios?|walnuts?|peanuts?|"
    r"hazelnuts?|macadamias?|seeds?|lentils?|chickpeas?|peas?|herbs?|"
    r"tomato(?:es)?|peppers?|mushrooms?|fruits?|cranberr(?:ies|y)|"
    r"raisins?|apricots?|figs?|dates?|plums?|coconuts?"
)
_IDENTITY_VERBS = r"dried|dry[ -]?roasted|roasted"
_COOKED_IDENTITY_CHANGE = re.compile(
    rf"\b({_IDENTITY_VERBS})\b.*\b({_IDENTITY_NOUNS})\b"
    rf"|\b({_IDENTITY_NOUNS})\b.*\b({_IDENTITY_VERBS})\b",
    re.IGNORECASE,
)

_COMPOSITE_PATTERNS = re.compile(
    r"\b(with sauce|and gravy|dinner|casserole|sandwich|pot pie|"
    r"from mix|prepared.from.recipe|home.prepared|with frosting|"
    r"with icing|with filling|"
    r"and cheese|and beans|and rice|on bun|in syrup|"
    r"soup|stew|chili con|burrito|taco|pizza|potpie)\b",
    re.IGNORECASE,
)

# Items where _COMPOSITE_PATTERNS fires but the item is actually a standalone ingredient
_COMPOSITE_RESCUE = re.compile(
    r"^(sauce|sauces|gravy|gravies|mustard|horseradish|ketchup|catsup)\b",
    re.IGNORECASE,
)

# Commercial / branded product detection (catches processed items in any category)
_COMMERCIAL_PRODUCT = re.compile(
    r"commercially prepared|ready[- ]?to[- ]?eat|ready[- ]?to[- ]?heat|"
    r"ready[- ]?to[- ]?serve|ready[- ]?to[- ]?drink|frozen[,\s]+ready",
    re.IGNORECASE,
)

# Obviously-prepared food products that can appear in any USDA category
_OBVIOUS_PREPARED = re.compile(
    r"\b(ice creams?|frozen novelti|milk ?shakes?|"
    r"sherbet|sorbet|fudgesicle|popsicle|creamsicle|"
    r"energy drinks?)\b|"
    r"\byogurts?,\s*frozen\b|\bfrozen\s+yogurts?\b",
    re.IGNORECASE,
)


def _should_rescue_as_ingredient(desc: str, cat_code: str) -> bool:
    """Return True if an item in a prepared-default category is actually a cooking ingredient."""
    low = desc.lower()

    if cat_code == "Sweets":
        # Sugar
        if low.startswith(("sugars,", "sugar,")):
            return True
        # Honey (standalone, not candy with honey flavor)
        if low == "honey" or low.startswith("honey,"):
            return True
        if "molasses" in low:
            return True
        if re.search(r"\bcocoa\b", low):
            return True
        if "baking chocolate" in low:
            return True
        if "pectin" in low:
            return True
        # Jams, jellies, preserves, marmalade — genuine condiment-ingredients
        if low.startswith(("jams ", "jams,", "jam,", "jelly,", "jellies,")):
            return True
        if low.startswith(("preserves", "marmalade")):
            return True
        if low.startswith("jams and preserves"):
            return True
        if low.startswith(("jams, preserves",)):
            return True
        # Sweeteners (stevia, baking sweeteners, agave)
        if low.startswith("sweetener"):
            return True
        # Pure ingredient syrups: corn, maple, cane, malt, sorghum, agave
        if low.startswith(("syrups, corn", "syrups, maple", "syrups, malt",
                           "syrups, sorghum", "syrup, cane", "syrup, maple",
                           "syrup, maple, canadian")):
            return True
        if "agave" in low:
            return True
        return False

    if cat_code == "Baked Products":
        # Breadcrumbs — breading ingredient
        if "breadcrumb" in low or "bread crumb" in low:
            return True
        # Tortillas and tostada shells — used in cooking
        if "tortilla" in low:
            return True
        if "tostada shell" in low:
            return True
        # Phyllo/filo dough, puff pastry — baking ingredients
        if "phyllo" in low or "filo" in low:
            return True
        if "puff pastry" in low:
            return True
        # Coating mixes (Shake N Bake) — cooking ingredient
        if "coating" in low and ("dry" in low or "mix" in low):
            return True
        return False

    if cat_code == "Breakfast Cereals":
        # Hot cereals / cooking grains (dry forms)
        if "ready-to-eat" in low:
            return False
        if any(kw in low for kw in ("corn grits", "oats,", "oats ",
                                     "farina", "wheat germ",
                                     "cream of wheat", "cream of rice")):
            return True
        # Dry cereal mixes for cooking
        if low.startswith("cereals,") and "dry" in low:
            return True
        return False

    if cat_code == "Snacks":
        # Almost nothing — only unpopped popcorn
        if "popcorn" in low and ("unpopped" in low or "kernel" in low):
            return True
        return False

    if cat_code == "Soups, Sauces, and Gravies":
        # Standalone sauces / condiments are cooking ingredients
        sauce_prefixes = (
            "sauce,", "sauces,",
        )
        if low.startswith(sauce_prefixes):
            return True
        # Mustard (USDA puts "Mustard, prepared, yellow" here sometimes via cross-ref)
        if low.startswith(("mustard,", "mustard ")):
            return True
        # Ketchup / catsup
        if "ketchup" in low or "catsup" in low:
            return True
        # Standalone gravies — used as an ingredient/condiment
        if low.startswith(("gravy,", "gravies,")):
            return True
        # Broth, stock, bouillon — fundamental cooking liquids
        if any(kw in low for kw in ("broth", "stock", "bouillon", "consomme")):
            return True
        # Dips
        if low.startswith("dip,"):
            return True
        # Everything else (soups, chili, chowder, bisque) stays prepared
        return False

    return False

# ---------------------------------------------------------------------------
# Name cleaning
# ---------------------------------------------------------------------------

_NOISE_QUALIFIERS = frozenset({
    "raw", "uncooked", "unprepared", "mature seeds", "salad or cooking",
    "meat only", "separable lean and fat", "separable lean only",
    "meat and skin", "bone-in", "boneless", "skinless",
    "not further specified", "NFS", "USDA Commodity",
    "all commercial varieties", "all types", "all varieties",
    "flesh and skin", "skin only", "meat and fat",
    "includes USDA commodity", "year round average",
    "includes babyfood", "composite of cuts",
    "natural", "plain", "regular", "standard",
    "broilers or fryers", "roasting", "stewing",
    "light meat", "dark meat", "ground",
    "choice", "select", "prime",
    "trimmed to 0\" fat", "trimmed to 1/8\" fat",
})

# Per-category prefix stripping rules (keyed by USDA category description)
_CATEGORY_PREFIX_STRIP: dict[str, list[str]] = {
    "Spices and Herbs": ["Spices,", "Herbs,", "Spice,"],
    "Fats and Oils": ["Oil,", "Fat,", "Shortening,"],
    "Beverages": ["Beverages,", "Beverage,"],
    "Nut and Seed Products": ["Nuts,", "Seeds,", "Nut,", "Seed,"],
}

# Name overrides for items where rules fail
NAME_OVERRIDES: dict[int, str] = {
    # fdcId → display name (populated after first run review)
    # Example: 173410: "Unsalted Butter",
}

# Max meaningful qualifier tokens per category (keyed by USDA description)
_MAX_TOKENS: dict[str, int] = {
    "Dairy and Egg Products": 2,             # "Cheddar Cheese"
    "Spices and Herbs": 1,                   # "Paprika"
    "Fats and Oils": 2,                      # "Olive Oil"
    "Poultry Products": 2,                   # "Chicken Breast"
    "Beef Products": 2,                      # "Ground Beef"
    "Fruits and Fruit Juices": 2,            # "Red Apple"
    "Pork Products": 2,                      # "Pork Chop"
    "Vegetables and Vegetable Products": 2,  # "Red Onion"
    "Lamb, Veal, and Game Products": 2,      # "Lamb Chop"
    "Finfish and Shellfish Products": 2,     # "Atlantic Salmon"
    "Sausages and Luncheon Meats": 2,        # "Italian Sausage"
}
_DEFAULT_MAX_TOKENS = 3


def _clean_name(desc: str, cat_code: str, fdc_id: int) -> str:
    """Transform USDA description into a display name."""
    if fdc_id in NAME_OVERRIDES:
        return NAME_OVERRIDES[fdc_id]

    # Strip category prefix if applicable
    for prefix in _CATEGORY_PREFIX_STRIP.get(cat_code, []):
        if desc.startswith(prefix):
            desc = desc[len(prefix):].strip()
            break

    parts = [p.strip() for p in desc.split(",")]

    # Remove noise qualifiers
    cleaned: list[str] = []
    for part in parts:
        low = part.lower()
        if low in {q.lower() for q in _NOISE_QUALIFIERS}:
            continue
        # Skip parenthetical-only parts
        if low.startswith("(") and low.endswith(")"):
            continue
        cleaned.append(part)

    if not cleaned:
        cleaned = [parts[0]]

    # Category-aware restructuring
    max_tokens = _MAX_TOKENS.get(cat_code, _DEFAULT_MAX_TOKENS)

    if cat_code in ("Spices and Herbs",):
        # Spices: just take the meaningful parts, drop prefix was already done
        name = " ".join(cleaned[:max_tokens])
    elif cat_code in ("Fats and Oils",):
        # Oils/Fats: invert — "olive" → "Olive Oil"
        if len(cleaned) >= 1:
            qualifiers = cleaned[:max_tokens]
            name = " ".join(qualifiers) + " Oil"
            # Avoid "Oil Oil"
            if name.lower().endswith("oil oil"):
                name = " ".join(qualifiers)
        else:
            name = cleaned[0]
    elif cat_code in ("Poultry Products", "Beef Products", "Pork Products",
                       "Lamb, Veal, and Game Products",
                       "Finfish and Shellfish Products",
                       "Sausages and Luncheon Meats"):
        # Proteins: first token is the protein, rest are cuts/parts
        if len(cleaned) >= 2:
            name = f"{cleaned[0]} {cleaned[1]}"
        else:
            name = cleaned[0]
    elif cat_code in ("Dairy and Egg Products",):
        # Dairy: invert "Cheese, cheddar" → "Cheddar Cheese"
        if len(cleaned) >= 2:
            base = cleaned[0]  # e.g. "Cheese", "Milk", "Yogurt"
            qualifiers = cleaned[1:max_tokens]
            name = " ".join(qualifiers) + " " + base
        else:
            name = cleaned[0]
    elif cat_code in ("Nut and Seed Products",):
        # Nut/Seed: after prefix stripping, first part is the nut type
        # "almonds, dry roasted, with salt added" → "Dry Roasted Almonds"
        if len(cleaned) >= 2:
            nut_type = cleaned[0]  # e.g. "almonds"
            # Pick the most useful qualifier (skip "with salt added" etc)
            form = cleaned[1] if len(cleaned) > 1 else ""
            if form.lower().startswith("with "):
                name = nut_type
            else:
                name = f"{form} {nut_type}" if form else nut_type
        else:
            name = cleaned[0]
    else:
        # Default: invert first two tokens if more than one
        if len(cleaned) >= 2:
            # Take qualifiers, then base
            base = cleaned[0]
            qualifiers = cleaned[1:max_tokens]
            name = " ".join(qualifiers) + " " + base
        else:
            name = cleaned[0]

    # Title-case and strip extra whitespace
    name = " ".join(name.split())
    name = name.title()

    # Fix common title-case artifacts
    name = name.replace("'S", "'s").replace(" Or ", " or ").replace(" And ", " and ")
    name = name.replace(" Of ", " of ").replace(" With ", " with ").replace(" In ", " in ")

    return name


# ---------------------------------------------------------------------------
# ID generation
# ---------------------------------------------------------------------------

def _to_kebab(name: str) -> str:
    """Convert display name to kebab-case ID."""
    s = name.lower().strip()
    s = re.sub(r"[^a-z0-9\s-]", "", s)
    s = re.sub(r"\s+", "-", s)
    s = re.sub(r"-+", "-", s)
    s = s.strip("-")
    return s


# ---------------------------------------------------------------------------
# base_ingredient derivation
# ---------------------------------------------------------------------------

_PROTEIN_FAMILIES: dict[str, str] = {
    "chicken": "chicken", "turkey": "turkey", "duck": "duck",
    "beef": "beef", "veal": "veal", "bison": "bison",
    "pork": "pork", "ham": "pork", "bacon": "pork",
    "lamb": "lamb", "goat": "goat", "venison": "venison",
    "salmon": "salmon", "tuna": "tuna", "cod": "cod",
    "tilapia": "tilapia", "shrimp": "shrimp", "crab": "crab",
    "lobster": "lobster", "scallop": "scallop", "clam": "clam",
    "mussel": "mussel", "oyster": "oyster", "sardine": "sardine",
    "trout": "trout", "catfish": "catfish", "halibut": "halibut",
    "swordfish": "swordfish", "anchovy": "anchovy", "mackerel": "mackerel",
    "herring": "herring", "snapper": "snapper", "bass": "bass",
    "squid": "squid", "octopus": "octopus",
}

_DAIRY_FAMILIES: dict[str, str] = {
    "cheese": "cheese", "milk": "milk", "cream": "cream",
    "yogurt": "yogurt", "yoghurt": "yogurt", "butter": "butter",
    "kefir": "kefir", "ghee": "ghee", "whey": "whey",
    "ricotta": "cheese", "mozzarella": "cheese", "cheddar": "cheese",
    "parmesan": "cheese", "brie": "cheese", "gouda": "cheese",
    "feta": "cheese", "gruyere": "cheese", "provolone": "cheese",
    "swiss": "cheese", "colby": "cheese", "monterey": "cheese",
    "camembert": "cheese", "muenster": "cheese", "havarti": "cheese",
    "mascarpone": "cheese", "cottage": "cheese", "neufchatel": "cheese",
}

_PRODUCE_FAMILIES: dict[str, str] = {
    "bean": "bean", "beans": "bean",
    "pepper": "pepper", "peppers": "pepper",
    "lettuce": "lettuce", "apple": "apple", "apples": "apple",
    "berry": "berry", "berries": "berry",
    "orange": "orange", "oranges": "orange",
    "tomato": "tomato", "tomatoes": "tomato",
    "potato": "potato", "potatoes": "potato",
    "onion": "onion", "onions": "onion",
    "squash": "squash", "melon": "melon",
    "grape": "grape", "grapes": "grape",
    "pear": "pear", "peach": "peach",
    "plum": "plum", "cherry": "cherry", "cherries": "cherry",
    "banana": "banana", "mango": "mango",
    "pineapple": "pineapple", "lemon": "lemon", "lime": "lime",
    "cabbage": "cabbage", "broccoli": "broccoli",
    "cauliflower": "cauliflower", "carrot": "carrot", "carrots": "carrot",
    "celery": "celery", "spinach": "spinach", "kale": "kale",
    "corn": "corn", "pea": "pea", "peas": "pea",
    "lentil": "lentil", "lentils": "lentil",
    "chickpea": "chickpea", "mushroom": "mushroom", "mushrooms": "mushroom",
    "garlic": "garlic", "ginger": "ginger",
    "avocado": "avocado", "cucumber": "cucumber",
    "eggplant": "eggplant", "zucchini": "zucchini",
    "asparagus": "asparagus", "artichoke": "artichoke",
    "beet": "beet", "turnip": "turnip", "radish": "radish",
    "parsnip": "parsnip", "rutabaga": "rutabaga",
    "fig": "fig", "date": "date",
    "coconut": "coconut", "olive": "olive",
}


_NUT_SEED_TYPES: set[str] = {
    "almond", "almonds", "cashew", "cashews", "pecan", "pecans",
    "walnut", "walnuts", "peanut", "peanuts", "pistachio", "pistachios",
    "hazelnut", "hazelnuts", "macadamia", "macadamias",
    "chestnut", "chestnuts", "pine", "brazil",
    "sunflower", "pumpkin", "sesame", "flax", "flaxseed", "chia",
    "hemp", "poppy", "caraway", "fennel", "cumin",
    "coconut", "acorn", "breadfruit", "lotus",
}


def _derive_base_ingredient(name: str, category: FoodCategory) -> Optional[str]:
    """Derive base_ingredient from cleaned name and category."""
    low = name.lower()
    words = low.split()

    if category == FoodCategory.PROTEIN:
        for word in words:
            if word in _PROTEIN_FAMILIES:
                return _PROTEIN_FAMILIES[word]
        return None

    if category == FoodCategory.DAIRY:
        for word in words:
            if word in _DAIRY_FAMILIES:
                return _DAIRY_FAMILIES[word]
        return None

    if category == FoodCategory.PRODUCE:
        # Iterate reversed — noun (tomato, pepper) is usually last in English names
        for word in reversed(words):
            if word in _PRODUCE_FAMILIES:
                return _PRODUCE_FAMILIES[word]
        return None

    if category == FoodCategory.NUTS_SEEDS:
        # Find the actual nut/seed type, skipping qualifiers like "dry", "roasted"
        for word in words:
            if word in _NUT_SEED_TYPES:
                # Normalize plurals
                return word.rstrip("s") if word.endswith("s") and word not in ("flax", "lotus") else word
        # Fallback to first word if it looks like a nut type
        if words:
            return words[0]
        return None

    return None


# ---------------------------------------------------------------------------
# Unit and storage mapping
# ---------------------------------------------------------------------------

_USDA_UNIT_MAP: dict[str, MeasurementUnit] = {
    "tsp": MeasurementUnit.TSP,
    "tbsp": MeasurementUnit.TBSP,
    "cup": MeasurementUnit.CUP,
    "fl oz": MeasurementUnit.FL_OZ,
    "ml": MeasurementUnit.ML,
    "l": MeasurementUnit.L,
    "g": MeasurementUnit.G,
    "kg": MeasurementUnit.KG,
    "oz": MeasurementUnit.OZ,
    "lb": MeasurementUnit.LB,
    "piece": MeasurementUnit.PIECE,
    "slice": MeasurementUnit.SLICE,
    "can": MeasurementUnit.CAN,
    "pkg": MeasurementUnit.PKG,
    "clove": MeasurementUnit.CLOVE,
    "bunch": MeasurementUnit.BUNCH,
    "whole": MeasurementUnit.WHOLE,
}

_CATEGORY_DEFAULT_UNITS: dict[FoodCategory, tuple[MeasurementUnit, float]] = {
    FoodCategory.SPICES_HERBS: (MeasurementUnit.TSP, 1.0),
    FoodCategory.PROTEIN: (MeasurementUnit.LB, 1.0),
    FoodCategory.DAIRY: (MeasurementUnit.CUP, 1.0),
    FoodCategory.PRODUCE: (MeasurementUnit.PIECE, 1.0),
    FoodCategory.OILS_FATS: (MeasurementUnit.TBSP, 1.0),
    FoodCategory.GRAINS_CEREALS: (MeasurementUnit.CUP, 1.0),
    FoodCategory.PASTA_NOODLES: (MeasurementUnit.OZ, 8.0),
    FoodCategory.NUTS_SEEDS: (MeasurementUnit.CUP, 1.0),
    FoodCategory.BEVERAGES: (MeasurementUnit.CUP, 1.0),
    FoodCategory.BAKING_SUPPLIES: (MeasurementUnit.CUP, 1.0),
    FoodCategory.SNACKS: (MeasurementUnit.OZ, 1.0),
    FoodCategory.CANNED_JARRED: (MeasurementUnit.CAN, 1.0),
    FoodCategory.CONDIMENTS_SAUCES: (MeasurementUnit.TBSP, 1.0),
}

_STORAGE_BY_CATEGORY: dict[FoodCategory, PantryStorage] = {
    FoodCategory.PROTEIN: PantryStorage.REFRIGERATED,
    FoodCategory.DAIRY: PantryStorage.REFRIGERATED,
    FoodCategory.PRODUCE: PantryStorage.REFRIGERATED,
    FoodCategory.FROZEN_FOODS: PantryStorage.FROZEN,
}

# ---------------------------------------------------------------------------
# Nutrition extraction
# ---------------------------------------------------------------------------

_NUTRIENT_MAP = {
    "calories": [2047, 2048, 1008],  # Atwater General, Atwater Specific, Energy
    "protein": [1003],
    "fat": [1004],
    "carbohydrates": [1005],
    "fiber": [1079],
    "sugar": [2000],
    "sodium": [1093],
}


def _extract_nutrition(food: dict[str, Any]) -> dict[str, Optional[float]]:
    """Extract nutrition per 100g from USDA food object."""
    nutrients_by_id: dict[int, float] = {}
    for fn in food.get("foodNutrients", []):
        nid = fn.get("nutrient", {}).get("id") or fn.get("nutrientId")
        amount = fn.get("amount")
        if nid and amount is not None:
            nutrients_by_id[int(nid)] = float(amount)

    result: dict[str, Optional[float]] = {}
    for key, ids in _NUTRIENT_MAP.items():
        val = None
        for nid in ids:
            if nid in nutrients_by_id:
                val = nutrients_by_id[nid]
                break
        result[key] = val
    return result


# ---------------------------------------------------------------------------
# Portion extraction
# ---------------------------------------------------------------------------

def _extract_portion(
    food: dict[str, Any], category: FoodCategory,
) -> tuple[Optional[MeasurementUnit], Optional[float]]:
    """Extract default unit and quantity from USDA portion data."""
    portions = food.get("foodPortions", [])
    if not portions:
        default = _CATEGORY_DEFAULT_UNITS.get(category)
        if default:
            return default
        return MeasurementUnit.G, 100.0

    # Prefer the first portion with a recognized unit
    for portion in portions:
        measure = portion.get("measureUnit", {})
        abbr = (measure.get("abbreviation") or "").lower().strip()
        # Also check portionDescription for unit hints
        desc = (portion.get("portionDescription") or "").lower()
        amount = portion.get("amount", 1.0)

        if abbr in _USDA_UNIT_MAP:
            return _USDA_UNIT_MAP[abbr], float(amount)

        # Parse common descriptions
        for unit_str, unit_enum in _USDA_UNIT_MAP.items():
            if unit_str in desc:
                return unit_enum, float(amount)

    # Fallback to category defaults
    default = _CATEGORY_DEFAULT_UNITS.get(category)
    if default:
        return default
    return MeasurementUnit.G, 100.0


# ---------------------------------------------------------------------------
# Download & parse
# ---------------------------------------------------------------------------

def _download_and_extract(name: str, info: dict[str, str]) -> list[dict[str, Any]]:
    """Download a USDA zip, extract JSON, return food list."""
    cache_path = _DATA_DIR / f"{name}.json"
    if cache_path.exists():
        logger.info("Using cached %s from %s", name, cache_path)
        with open(cache_path) as f:
            data = json.load(f)
        return data.get(info["key"], data) if isinstance(data, dict) else data

    _DATA_DIR.mkdir(parents=True, exist_ok=True)
    logger.info("Downloading %s from %s ...", name, info["url"])
    with urlopen(info["url"]) as resp:  # noqa: S310 — trusted USDA URL
        zip_bytes = resp.read()

    logger.info("Extracting %s (%d KB) ...", name, len(zip_bytes) // 1024)
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        # Find the JSON file inside the zip
        json_name = info["inner_json"]
        candidates = [n for n in zf.namelist() if n.endswith(".json")]
        target = json_name if json_name in zf.namelist() else candidates[0] if candidates else None
        if not target:
            raise FileNotFoundError(f"No JSON found in {name} zip: {zf.namelist()}")

        logger.info("Parsing %s ...", target)
        with zf.open(target) as jf:
            data = json.load(jf)

    # Cache for future runs
    cache_path.write_text(json.dumps(data, ensure_ascii=False))
    logger.info("Cached %s to %s", name, cache_path)

    return data.get(info["key"], data) if isinstance(data, dict) else data


# ---------------------------------------------------------------------------
# Merge logic
# ---------------------------------------------------------------------------

def _merge_datasets(
    foundation: list[dict[str, Any]],
    sr_legacy: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Merge Foundation + SR Legacy, Foundation takes priority on overlap."""
    merged: dict[str, dict[str, Any]] = {}

    # Index foundation by ndbNumber
    foundation_ndb: set[str] = set()
    for food in foundation:
        ndb = str(food.get("ndbNumber", ""))
        fdc = str(food.get("fdcId", ""))
        key = ndb if ndb else fdc
        food["_source"] = "foundation"
        merged[key] = food
        if ndb:
            foundation_ndb.add(ndb)

    # Add SR Legacy items not in Foundation
    sr_added = 0
    sr_skipped = 0
    for food in sr_legacy:
        ndb = str(food.get("ndbNumber", ""))
        fdc = str(food.get("fdcId", ""))
        key = ndb if ndb else fdc
        if ndb and ndb in foundation_ndb:
            sr_skipped += 1
            continue
        food["_source"] = "sr_legacy"
        merged[key] = food
        sr_added += 1

    logger.info(
        "Merge: %d foundation + %d sr_legacy added (%d sr overlaps skipped) = %d total",
        len(foundation), sr_added, sr_skipped, len(merged),
    )
    return list(merged.values())


# ---------------------------------------------------------------------------
# Classification: ingredient vs prepared
# ---------------------------------------------------------------------------

def _get_category_code(food: dict[str, Any]) -> str:
    """Extract USDA category description from food object (used as key)."""
    cat = food.get("foodCategory", {})
    if isinstance(cat, dict):
        return cat.get("description", "") or ""
    return ""


def _get_category_desc(food: dict[str, Any]) -> str:
    """Extract USDA category description (alias for consistency)."""
    return _get_category_code(food)


def _is_prepared(food: dict[str, Any]) -> bool:
    """Return True if item should go to prepared food catalog."""
    cat_code = _get_category_code(food)
    desc = food.get("description", "")

    # 1. Categories that are predominantly prepared food
    if cat_code in _PREPARED_FOOD_CATEGORIES:
        # Rescue genuine cooking ingredients from these categories
        if _should_rescue_as_ingredient(desc, cat_code):
            # Still send to prepared if it's a cooked/ready-to-eat form
            if _COOKED_TERMS.search(desc) and not _COOKED_IDENTITY_CHANGE.search(desc):
                return True
            return False  # Keep as ingredient
        return True

    # 2. Commercially prepared items in any category
    if _COMMERCIAL_PRODUCT.search(desc):
        return True

    # 2a. Obviously prepared food products (ice cream, milkshakes, etc.)
    if _OBVIOUS_PREPARED.search(desc):
        return True

    # 3. Composite dishes from ingredient categories
    if _COMPOSITE_PATTERNS.search(desc):
        # Don't route standalone sauces/condiments to prepared
        if not _COMPOSITE_RESCUE.search(desc):
            return True

    # 4. Cooked items (unless cooking changes identity)
    if _COOKED_TERMS.search(desc):
        if _COOKED_IDENTITY_CHANGE.search(desc):
            return False  # Keep as ingredient (dried beans, roasted nuts, etc.)
        return True

    return False


# ---------------------------------------------------------------------------
# Prepared food model (lighter than CatalogEntry)
# ---------------------------------------------------------------------------

def _build_prepared_food(food: dict[str, Any]) -> dict[str, Any]:
    """Build a prepared food entry from a USDA food object."""
    desc = food.get("description", "Unknown")
    cat_code = _get_category_code(food)
    cat_desc = _get_category_desc(food)
    fdc_id = food.get("fdcId", 0)

    name = _clean_name(desc, cat_code, fdc_id)
    entry_id = _to_kebab(name)

    # Map to closest FoodCategory
    category = _USDA_DESC_TO_FOOD_CATEGORY.get(cat_code, FoodCategory.OTHER)

    nutrition = _extract_nutrition(food)
    unit, qty = _extract_portion(food, category)

    return {
        "id": entry_id,
        "name": name,
        "usda_description": desc,
        "fdc_id": fdc_id,
        "category": category.value,
        "usda_category": cat_desc,
        "source": food.get("_source", "unknown"),
        "serving_unit": unit.value if unit else None,
        "serving_quantity": qty,
        "nutrition_per_100g": nutrition,
    }


# ---------------------------------------------------------------------------
# CatalogEntry builder
# ---------------------------------------------------------------------------

def _build_catalog_entry(
    food: dict[str, Any],
) -> Optional[CatalogEntry]:
    """Transform a USDA food object into a CatalogEntry skeleton."""
    desc = food.get("description", "Unknown")
    cat_code = _get_category_code(food)
    fdc_id = food.get("fdcId", 0)

    name = _clean_name(desc, cat_code, fdc_id)
    entry_id = _to_kebab(name)

    if not entry_id:
        logger.warning("Empty ID for '%s' (fdc=%s), skipping", desc, fdc_id)
        return None

    # Map category
    category = _USDA_DESC_TO_FOOD_CATEGORY.get(cat_code, FoodCategory.OTHER)

    # Egg exception: route to Protein
    if category == FoodCategory.DAIRY and _EGG_PATTERNS.search(desc):
        category = FoodCategory.PROTEIN

    # Pasta detection within Grains
    if category == FoodCategory.GRAINS_CEREALS and _PASTA_PATTERNS.search(desc):
        category = FoodCategory.PASTA_NOODLES

    # base_ingredient
    base = _derive_base_ingredient(name, category)

    # Unit/quantity
    unit, qty = _extract_portion(food, category)

    # Storage
    storage = _STORAGE_BY_CATEGORY.get(category, PantryStorage.PANTRY)

    try:
        return CatalogEntry(
            id=entry_id,
            name=name,
            category=category,
            base_ingredient=base,
            default_unit=unit,
            default_quantity=qty,
            default_storage=storage,
        )
    except ValidationError as e:
        logger.warning("Validation failed for '%s' (fdc=%s): %s", desc, fdc_id, e)
        return None


# ---------------------------------------------------------------------------
# Deduplication
# ---------------------------------------------------------------------------

def _deduplicate_entries(
    entries: list[CatalogEntry],
    sources: list[dict[str, Any]],
) -> tuple[list[CatalogEntry], list[dict[str, Any]]]:
    """Remove duplicate IDs, keeping first occurrence. Returns deduped entries + their sources."""
    seen_ids: dict[str, int] = {}
    unique: list[CatalogEntry] = []
    unique_sources: list[dict[str, Any]] = []

    for entry, source in zip(entries, sources):
        if entry.id in seen_ids:
            # Append category suffix to disambiguate
            suffix = entry.category.value.lower().replace(" ", "-").replace("&", "and")
            new_id = f"{entry.id}-{suffix}"
            new_id = re.sub(r"[^a-z0-9-]", "", new_id)
            if new_id in seen_ids:
                logger.debug("Dropping duplicate: %s (%s)", entry.name, entry.id)
                continue
            entry = entry.model_copy(update={"id": new_id})

        seen_ids[entry.id] = len(unique)
        unique.append(entry)
        unique_sources.append(source)

    return unique, unique_sources


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------

def run(*, skip_download: bool = False) -> dict[str, Any]:
    """Execute the full USDA seed extraction pipeline."""
    stats: dict[str, Any] = {
        "started_at": datetime.now(timezone.utc).isoformat(),
        "foundation_count": 0,
        "sr_legacy_count": 0,
        "merged_count": 0,
        "ingredient_candidates": 0,
        "prepared_candidates": 0,
        "ingredient_after_dedup": 0,
        "prepared_final": 0,
        "ingredient_final": 0,
        "validation_failures": 0,
        "category_distribution": {},
        "base_ingredient_families": {},
    }

    # Phase A: Download
    if skip_download:
        # Load from cache
        foundation_cache = _DATA_DIR / "foundation.json"
        sr_cache = _DATA_DIR / "sr_legacy.json"
        if not foundation_cache.exists() or not sr_cache.exists():
            raise FileNotFoundError(
                "Cached data not found. Run without --skip-download first."
            )
        with open(foundation_cache) as f:
            fdata = json.load(f)
        foundation = fdata.get("FoundationFoods", fdata) if isinstance(fdata, dict) else fdata
        with open(sr_cache) as f:
            sdata = json.load(f)
        sr_legacy = sdata.get("SRLegacyFoods", sdata) if isinstance(sdata, dict) else sdata
    else:
        foundation = _download_and_extract("foundation", _DOWNLOADS["foundation"])
        sr_legacy = _download_and_extract("sr_legacy", _DOWNLOADS["sr_legacy"])

    stats["foundation_count"] = len(foundation)
    stats["sr_legacy_count"] = len(sr_legacy)
    logger.info("Foundation Foods: %d items", len(foundation))
    logger.info("SR Legacy: %d items", len(sr_legacy))

    # Phase B: Merge
    merged = _merge_datasets(foundation, sr_legacy)
    stats["merged_count"] = len(merged)

    # Phase C: Classify
    ingredient_foods: list[dict[str, Any]] = []
    prepared_foods: list[dict[str, Any]] = []

    for food in merged:
        if _is_prepared(food):
            prepared_foods.append(food)
        else:
            ingredient_foods.append(food)

    stats["ingredient_candidates"] = len(ingredient_foods)
    stats["prepared_candidates"] = len(prepared_foods)
    logger.info(
        "Classification: %d ingredients, %d prepared foods",
        len(ingredient_foods), len(prepared_foods),
    )

    # Phase D: Transform ingredients
    entries: list[CatalogEntry] = []
    entry_sources: list[dict[str, Any]] = []  # parallel list: source food for each entry
    nutrition_cache: dict[str, dict[str, Optional[float]]] = {}

    for food in ingredient_foods:
        entry = _build_catalog_entry(food)
        if entry:
            entries.append(entry)
            entry_sources.append(food)
            nutrition_cache[entry.id] = _extract_nutrition(food)
        else:
            stats["validation_failures"] = stats.get("validation_failures", 0) + 1

    # Transform prepared foods
    prepared_entries: list[dict[str, Any]] = []
    for food in prepared_foods:
        pf = _build_prepared_food(food)
        prepared_entries.append(pf)
        nutrition_cache[pf["id"]] = pf["nutrition_per_100g"]

    # Phase E: Deduplicate ingredients
    entries, entry_sources = _deduplicate_entries(entries, entry_sources)
    stats["ingredient_after_dedup"] = len(entries)

    # Deduplicate prepared foods by ID
    seen_prep: set[str] = set()
    unique_prepared: list[dict[str, Any]] = []
    for pf in prepared_entries:
        if pf["id"] not in seen_prep:
            seen_prep.add(pf["id"])
            unique_prepared.append(pf)
    prepared_entries = unique_prepared

    stats["ingredient_final"] = len(entries)
    stats["prepared_final"] = len(prepared_entries)

    # Compute category distribution
    cat_counts: Counter[str] = Counter()
    for e in entries:
        cat_counts[e.category.value] += 1
    stats["category_distribution"] = dict(cat_counts.most_common())

    # Compute base_ingredient families
    families: defaultdict[str, int] = defaultdict(int)
    standalone = 0
    for e in entries:
        if e.base_ingredient:
            families[e.base_ingredient] += 1
        else:
            standalone += 1
    stats["base_ingredient_families"] = dict(
        sorted(families.items(), key=lambda x: x[1], reverse=True)
    )
    stats["standalone_count"] = standalone

    # Prepared food category breakdown
    prep_cat_counts: Counter[str] = Counter()
    for pf in prepared_entries:
        prep_cat_counts[pf.get("usda_category", "Unknown")] += 1
    stats["prepared_category_distribution"] = dict(prep_cat_counts.most_common())

    # Write outputs
    _OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Ingredient catalog
    catalog_data = [
        e.model_dump(mode="json", exclude_none=True) for e in entries
    ]
    catalog_path = _OUTPUT_DIR / "ingredient_catalog.json"
    catalog_path.write_text(json.dumps(catalog_data, indent=2, ensure_ascii=False))
    logger.info("Wrote %d ingredient entries to %s", len(entries), catalog_path)

    # Prepared food catalog
    prep_path = _OUTPUT_DIR / "prepared_food_catalog.json"
    prep_path.write_text(json.dumps(prepared_entries, indent=2, ensure_ascii=False))
    logger.info("Wrote %d prepared food entries to %s", len(prepared_entries), prep_path)

    # Nutrition cache
    nutrition_path = _OUTPUT_DIR / "usda_nutrition_cache.json"
    nutrition_path.write_text(json.dumps(nutrition_cache, indent=2, ensure_ascii=False))
    logger.info("Wrote nutrition cache to %s", nutrition_path)

    # Report
    stats["completed_at"] = datetime.now(timezone.utc).isoformat()
    report_path = _OUTPUT_DIR / "usda_seed_report.json"
    report_path.write_text(json.dumps(stats, indent=2))
    logger.info("Wrote report to %s", report_path)

    # Name review CSV
    review_path = _OUTPUT_DIR / "name_review.csv"
    with open(review_path, "w") as f:
        f.write("id,name,usda_description,category,base_ingredient\n")
        for entry, food in zip(entries, entry_sources):
            usda_desc = food.get("description", "").replace('"', '""')
            base = entry.base_ingredient or ""
            f.write(
                f'"{entry.id}","{entry.name}","{usda_desc}","{entry.category.value}","{base}"\n'
            )
    logger.info("Wrote name review CSV to %s", review_path)

    # Print summary
    _print_summary(stats)

    return stats


def _print_summary(stats: dict[str, Any]) -> None:
    """Print a human-readable summary to console."""
    print("\n" + "=" * 60)
    print("USDA SEED EXTRACTION REPORT")
    print("=" * 60)
    print(f"Foundation Foods:        {stats['foundation_count']:>6}")
    print(f"SR Legacy:               {stats['sr_legacy_count']:>6}")
    print(f"Merged total:            {stats['merged_count']:>6}")
    print(f"─ Ingredient candidates: {stats['ingredient_candidates']:>6}")
    print(f"─ Prepared candidates:   {stats['prepared_candidates']:>6}")
    print(f"After dedup:             {stats['ingredient_after_dedup']:>6}")
    print(f"Validation failures:     {stats['validation_failures']:>6}")
    print()
    print(f"FINAL: {stats['ingredient_final']} ingredient entries, "
          f"{stats['prepared_final']} prepared food entries")

    print("\n── Ingredient Category Distribution ──")
    for cat, count in sorted(
        stats.get("category_distribution", {}).items(),
        key=lambda x: x[1], reverse=True,
    ):
        pct = count / max(stats["ingredient_final"], 1) * 100
        bar = "█" * int(pct / 2)
        print(f"  {cat:<25} {count:>5} ({pct:5.1f}%) {bar}")

    print(f"\n── Top Base Ingredient Families (of {stats.get('standalone_count', 0)} standalone) ──")
    for family, count in list(stats.get("base_ingredient_families", {}).items())[:20]:
        print(f"  {family:<20} {count:>4} items")

    print("\n── Prepared Food Breakdown ──")
    for cat, count in sorted(
        stats.get("prepared_category_distribution", {}).items(),
        key=lambda x: x[1], reverse=True,
    )[:15]:
        print(f"  {cat:<40} {count:>5}")

    print("=" * 60)


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="USDA seed extractor")
    parser.add_argument(
        "--skip-download", action="store_true",
        help="Use cached USDA data (must have been downloaded previously)",
    )
    parser.add_argument(
        "--log-level", default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    run(skip_download=args.skip_download)


if __name__ == "__main__":
    main()
