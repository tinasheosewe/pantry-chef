"""Shared infrastructure for ML parsing and grouping approaches.

Provides:
- USDA data loading (from cached JSON)
- Dataclasses for parsed items and food groups
- Golden-50 test cases derived from manual parser audit
- Convenience helpers
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

_SCRIPT_DIR = Path(__file__).resolve().parent.parent
_DATA_DIR = _SCRIPT_DIR / "data" / "usda"
_OUTPUT_DIR = _SCRIPT_DIR / "output"
_ML_OUTPUT_DIR = _SCRIPT_DIR / "ml_outputs"

# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

def load_usda_foods() -> list[dict[str, Any]]:
    """Load and merge Foundation + SR Legacy from cached JSON files.

    Returns raw USDA food dicts with keys: fdcId, description,
    foodCategory.description, foodNutrients, _source.
    """
    foundation_path = _DATA_DIR / "foundation.json"
    sr_legacy_path = _DATA_DIR / "sr_legacy.json"

    foods: list[dict[str, Any]] = []

    for path, key in [(foundation_path, "FoundationFoods"), (sr_legacy_path, "SRLegacyFoods")]:
        if not path.exists():
            logger.warning("Cache file %s not found — run usda_seed_extractor first", path)
            continue
        with open(path) as f:
            data = json.load(f)
        items = data.get(key, data) if isinstance(data, dict) else data
        logger.info("Loaded %d items from %s", len(items), path.name)
        foods.extend(items)

    # Deduplicate by ndbNumber (Foundation priority)
    merged: dict[str, dict[str, Any]] = {}
    foundation_ndb: set[str] = set()
    for food in foods:
        src = food.get("_source", "")
        ndb = str(food.get("ndbNumber", ""))
        fdc = str(food.get("fdcId", ""))
        key = ndb if ndb else fdc
        if src == "foundation" or key not in merged:
            merged[key] = food
            if src == "foundation" and ndb:
                foundation_ndb.add(ndb)
        elif ndb and ndb in foundation_ndb:
            continue  # SR Legacy duplicate
        else:
            merged[key] = food

    result = list(merged.values())
    logger.info("Merged USDA foods: %d total", len(result))
    return result


def load_ingredient_catalog() -> list[dict[str, Any]]:
    """Load the current ingredient_catalog.json (output of usda_seed_extractor)."""
    path = _OUTPUT_DIR / "ingredient_catalog.json"
    if not path.exists():
        logger.warning("ingredient_catalog.json not found — run usda_seed_extractor first")
        return []
    with open(path) as f:
        return json.load(f)


def get_usda_description(food: dict[str, Any]) -> str:
    """Extract the raw USDA description string."""
    return food.get("description", "")


def get_usda_category(food: dict[str, Any]) -> str:
    """Extract the USDA category description."""
    cat = food.get("foodCategory", {})
    if isinstance(cat, dict):
        return cat.get("description", "") or ""
    return ""


def get_fdc_id(food: dict[str, Any]) -> int:
    """Extract the FDC ID."""
    return int(food.get("fdcId", 0))


def ensure_output_dir() -> Path:
    """Create and return the ml_outputs directory."""
    _ML_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    return _ML_OUTPUT_DIR


# ---------------------------------------------------------------------------
# Output dataclasses
# ---------------------------------------------------------------------------

@dataclass
class ParsedItem:
    """Result of parsing a single USDA food description."""
    fdc_id: int
    original_desc: str
    usda_category: str
    parsed_name: str
    parsed_base: str = ""
    qualifiers: list[str] = field(default_factory=list)
    form: str = ""
    brand: str = ""
    noise_removed: list[str] = field(default_factory=list)
    confidence: float = 1.0

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class GroupMember:
    """A member of a food group with its distinguishing attributes."""
    fdc_id: int
    parsed_name: str
    distinguishing_attrs: dict[str, str] = field(default_factory=dict)


@dataclass
class FoodGroup:
    """Result of grouping related food entries."""
    group_id: str
    group_name: str
    base_ingredient: str
    category: str = ""
    members: list[GroupMember] = field(default_factory=list)
    suggested_facets: dict[str, list[str]] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

def save_parse_results(results: list[ParsedItem], approach_name: str) -> Path:
    """Save parse results to ml_outputs/<approach_name>_parse.json."""
    out_dir = ensure_output_dir()
    path = out_dir / f"{approach_name}_parse.json"
    with open(path, "w") as f:
        json.dump([r.to_dict() for r in results], f, indent=2, ensure_ascii=False)
    logger.info("Saved %d parsed items to %s", len(results), path)
    return path


def save_group_results(groups: list[FoodGroup], approach_name: str) -> Path:
    """Save group results to ml_outputs/<approach_name>_groups.json."""
    out_dir = ensure_output_dir()
    path = out_dir / f"{approach_name}_groups.json"
    with open(path, "w") as f:
        json.dump([g.to_dict() for g in groups], f, indent=2, ensure_ascii=False)
    logger.info("Saved %d groups to %s", len(groups), path)
    return path


def load_parse_results(approach_name: str) -> list[ParsedItem]:
    """Load previously saved parse results."""
    path = _ML_OUTPUT_DIR / f"{approach_name}_parse.json"
    if not path.exists():
        return []
    with open(path) as f:
        data = json.load(f)
    return [ParsedItem(**d) for d in data]


def load_group_results(approach_name: str) -> list[FoodGroup]:
    """Load previously saved group results."""
    path = _ML_OUTPUT_DIR / f"{approach_name}_groups.json"
    if not path.exists():
        return []
    with open(path) as f:
        data = json.load(f)
    groups = []
    for d in data:
        members = [GroupMember(**m) for m in d.pop("members", [])]
        groups.append(FoodGroup(**d, members=members))
    return groups


# ---------------------------------------------------------------------------
# USDA noise / brand patterns (shared across approaches)
# ---------------------------------------------------------------------------

USDA_NOISE_TERMS = re.compile(
    r"\b(NFS|USDA Commodity|not further specified|"
    r"includes foods for|includes USDA commodity|"
    r"year round average|all commercial varieties|"
    r"all types|all varieties|composite of cuts|"
    r"separable lean and fat|separable lean only|"
    r"meat and skin|meat only|bone-in|boneless|skinless|"
    r"flesh and skin|skin only|meat and fat|"
    r"trimmed to \d[/\"]+ fat)\b",
    re.IGNORECASE,
)

COMMERCIAL_NOISE = re.compile(
    r"\b(commercially prepared|ready[- ]?to[- ]?eat|"
    r"ready[- ]?to[- ]?heat|ready[- ]?to[- ]?serve|"
    r"ready[- ]?to[- ]?drink|frozen[,\s]+ready)\b",
    re.IGNORECASE,
)

# Known USDA brand prefixes (ALL CAPS or known mixed-case brands)
BRAND_PATTERNS = re.compile(
    r"^(KRAFT|NESTLE|MARS SNACKFOOD US|MARS INC\.|"
    r"GENERAL MILLS|KELLOGG|PILLSBURY|"
    r"OSCAR MAYER|PEPPERIDGE FARM|"
    r"NABISCO|HERSHEY|BETTY CROCKER|"
    r"CAMPBELL'?S?|HORMEL|TYSON|"
    r"HEINZ|DEL MONTE|DOLE|STOUFFER'?S?|"
    r"MCDONALD'?S?|BURGER KING|WENDY'?S?|"
    r"SUBWAY|TACO BELL|KFC|PIZZA HUT|DOMINO'?S?|"
    r"CHICK-FIL-A|ARBY'?S?|JACK IN THE BOX)\b[,\s]*",
    re.IGNORECASE,
)

# Form/preservation qualifiers that should become facets
FORM_QUALIFIERS = re.compile(
    r"\b(raw|cooked|dried|dry[- ]roasted|roasted|smoked|"
    r"canned|frozen|fresh|pickled|fermented|cured|"
    r"ground|whole|sliced|diced|chopped|minced|"
    r"shredded|grated|crushed|powdered|granulated|"
    r"blanched|peeled|dehydrated|freeze[- ]dried|"
    r"concentrated|condensed|evaporated|"
    r"salted|unsalted|sweetened|unsweetened|"
    r"enriched|fortified|bleached|unbleached|"
    r"pasteurized|unpasteurized|homogenized|"
    r"fat[- ]free|low[- ]fat|reduced[- ]fat|nonfat|whole[- ]milk|"
    r"organic|conventional)\b",
    re.IGNORECASE,
)

# Cooking method terms
COOKING_METHODS = re.compile(
    r"\b(braised|grilled|fried|baked|steamed|boiled|"
    r"sauteed|sautéed|poached|broiled|stewed|"
    r"pan-fried|deep-fried|stir-fried|microwaved|toasted|"
    r"scrambled|roasted)\b",
    re.IGNORECASE,
)
