"""Controlled vocabularies mirroring PantryChef's Swift enums.

These are the single source of truth for the orchestrator.
Prompt builders and Pydantic models reference these directly so generated
data always uses valid enum values the app can consume.
"""

from enum import Enum


class FoodCategory(str, Enum):
    DAIRY = "Dairy"
    PRODUCE = "Produce"
    PROTEIN = "Protein"
    GRAINS_CEREALS = "Grains & Cereals"
    SPICES_HERBS = "Spices & Herbs"
    CONDIMENTS_SAUCES = "Condiments & Sauces"
    BAKING_SUPPLIES = "Baking Supplies"
    FROZEN_FOODS = "Frozen Foods"
    CANNED_JARRED = "Canned & Jarred"
    BEVERAGES = "Beverages"
    SNACKS = "Snacks"
    OILS_FATS = "Oils & Fats"
    PASTA_NOODLES = "Pasta & Noodles"
    NUTS_SEEDS = "Nuts & Seeds"
    OTHER = "Other"


class MeasurementUnit(str, Enum):
    TSP = "tsp"
    TBSP = "tbsp"
    CUP = "cup"
    FL_OZ = "fl oz"
    ML = "ml"
    L = "L"
    G = "g"
    KG = "kg"
    OZ = "oz"
    LB = "lb"
    PIECE = "piece"
    WHOLE = "whole"
    LOAF = "loaf"
    SLICE = "slice"
    CLOVE = "clove"
    BUNCH = "bunch"
    CAN = "can"
    PKG = "pkg"
    PINCH = "pinch"
    SPLASH = "splash"
    TO_TASTE = "to taste"


class DietaryTag(str, Enum):
    VEGETARIAN = "Vegetarian"
    VEGAN = "Vegan"
    GLUTEN_FREE = "Gluten-Free"
    DAIRY_FREE = "Dairy-Free"
    NUT_FREE = "Nut-Free"
    LOW_CARB = "Low Carb"
    HIGH_PROTEIN = "High Protein"
    KETO = "Keto"
    PALEO = "Paleo"
    HALAL = "Halal"
    KOSHER = "Kosher"


class DifficultyLevel(int, Enum):
    BEGINNER = 1
    EASY = 2
    MEDIUM = 3
    HARD = 4
    EXPERT = 5


class MealType(str, Enum):
    BREAKFAST = "Breakfast"
    LUNCH = "Lunch"
    DINNER = "Dinner"
    SNACK = "Snack"
    DESSERT = "Dessert"


class CuisineType(str, Enum):
    """Reference vocabulary for common cuisines.
    
    NOTE: Models accept any cuisine string — this enum is for documentation
    and prompt hints only. Normalization is a manual QA step, not automated.
    """
    ITALIAN = "Italian"
    MEXICAN = "Mexican"
    CHINESE = "Chinese"
    JAPANESE = "Japanese"
    INDIAN = "Indian"
    THAI = "Thai"
    FRENCH = "French"
    MEDITERRANEAN = "Mediterranean"
    AMERICAN = "American"
    KOREAN = "Korean"
    VIETNAMESE = "Vietnamese"
    GREEK = "Greek"
    MIDDLE_EASTERN = "Middle Eastern"
    ETHIOPIAN = "Ethiopian"
    CARIBBEAN = "Caribbean"
    PERUVIAN = "Peruvian"
    BRAZILIAN = "Brazilian"
    TURKISH = "Turkish"
    MOROCCAN = "Moroccan"
    FILIPINO = "Filipino"
    MALAYSIAN = "Malaysian"
    OTHER = "Other"


class PantryStorage(str, Enum):
    PANTRY = "Pantry"
    REFRIGERATED = "Refrigerated"
    FROZEN = "Frozen"


# FacetKey: Open string type with common constants.
# The LLM can use ANY facet key (e.g. "grade", "age", "region") — these are conventions only.
class FacetKey:
    """Common facet key constants. Any string value is valid."""
    VARIANT = "variant"
    FORM = "form"
    PRESERVATION = "preservation"
    PROCESSING = "processing"
    PREPARATION = "preparation"
    TEXTURE = "texture"
    CONCENTRATION = "concentration"
    BASE = "base"

    # Helper to list common keys for prompts
    @classmethod
    def common_keys(cls) -> list[str]:
        return [cls.VARIANT, cls.FORM, cls.PRESERVATION, cls.PROCESSING,
                cls.PREPARATION, cls.TEXTURE, cls.CONCENTRATION, cls.BASE]


class SubstitutionImpact(str, Enum):
    NONE = "None"
    SLIGHT = "Slight"
    MODERATE = "Moderate"
    SIGNIFICANT = "Significant"


class CookingImpact(str, Enum):
    NONE = "None"
    SLIGHT = "Slight Adjustment"
    MODERATE = "Moderate Adjustment"
    MAJOR = "Major Adjustment"


class GenerationMode(str, Enum):
    INGREDIENTS = "ingredients"
    RECIPES = "recipes"
    BOTH = "both"


class ReviewStatus(str, Enum):
    ACCEPTED = "accepted"
    REVISE = "revise"
    REJECTED = "rejected"


def enum_values(enum_cls: type[Enum]) -> list[str]:
    """Return all raw values from an enum as a list of strings."""
    return [str(m.value) for m in enum_cls]
