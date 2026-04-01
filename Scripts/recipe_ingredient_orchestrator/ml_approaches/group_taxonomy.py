"""Taxonomy-guided grouping for food entries.

Groups food entries deterministically by base_ingredient + category,
then uses fuzzy matching to catch items that should belong to a group
but have a different base.
"""

from __future__ import annotations

import logging
from collections import Counter, defaultdict
from typing import Any

from rapidfuzz import fuzz, process

from .shared import (
    FoodGroup,
    GroupMember,
    ParsedItem,
    load_parse_results,
    save_group_results,
)

logger = logging.getLogger(__name__)

APPROACH_NAME = "taxonomy_guided"

# ---------------------------------------------------------------------------
# Canonical group definitions
# ---------------------------------------------------------------------------

# base_ingredient → canonical group name
_CANONICAL_GROUPS: dict[str, str] = {
    # Proteins
    "chicken": "Chicken", "beef": "Beef", "pork": "Pork",
    "turkey": "Turkey", "lamb": "Lamb", "veal": "Veal",
    "duck": "Duck", "bison": "Bison", "venison": "Venison",
    "salmon": "Salmon", "tuna": "Tuna", "cod": "Cod",
    "tilapia": "Tilapia", "shrimp": "Shrimp", "crab": "Crab",
    "lobster": "Lobster", "scallop": "Scallop", "trout": "Trout",
    "catfish": "Catfish", "halibut": "Halibut", "sardine": "Sardine",
    "clam": "Clam", "mussel": "Mussel", "oyster": "Oyster",
    "sausage": "Sausage", "frankfurter": "Frankfurter",
    # Dairy
    "cheese": "Cheese", "milk": "Milk", "cream": "Cream",
    "yogurt": "Yogurt", "butter": "Butter", "egg": "Egg",
    "ghee": "Ghee",
    # Produce
    "apple": "Apple", "banana": "Banana", "orange": "Orange",
    "tomato": "Tomato", "potato": "Potato", "onion": "Onion",
    "garlic": "Garlic", "pepper": "Pepper", "carrot": "Carrot",
    "broccoli": "Broccoli", "spinach": "Spinach", "kale": "Kale",
    "lettuce": "Lettuce", "mushroom": "Mushroom", "corn": "Corn",
    "avocado": "Avocado", "lemon": "Lemon", "lime": "Lime",
    "celery": "Celery", "cucumber": "Cucumber",
    "bean": "Bean", "lentil": "Lentil", "chickpea": "Chickpea",
    "pea": "Pea",
    # Grains
    "rice": "Rice", "pasta": "Pasta", "bread": "Bread",
    "flour": "Flour", "oat": "Oat", "tortilla": "Tortilla",
    # Nuts/seeds
    "almond": "Almond", "almonds": "Almond",
    "walnut": "Walnut", "walnuts": "Walnut",
    "pecan": "Pecan", "pecans": "Pecan",
    "cashew": "Cashew", "cashews": "Cashew",
    "peanut": "Peanut", "peanuts": "Peanut",
    "coconut": "Coconut",
    "pistachio": "Pistachio", "pistachios": "Pistachio",
    "hazelnut": "Hazelnut", "hazelnuts": "Hazelnut",
    "macadamia": "Macadamia",
    # Pantry
    "oil": "Cooking Oil", "olive oil": "Olive Oil",
    "coconut oil": "Coconut Oil", "canola oil": "Canola Oil",
    "vinegar": "Vinegar", "sauce": "Sauce", "mustard": "Mustard",
    "salsa": "Salsa", "honey": "Honey", "sugar": "Sugar",
    "salt": "Salt", "chocolate": "Chocolate", "cocoa": "Cocoa",
    "vanilla": "Vanilla", "tea": "Tea", "coffee": "Coffee",
    "maple syrup": "Maple Syrup", "soy sauce": "Soy Sauce",
    "soy": "Soy", "tofu": "Tofu",
    # Other
    "lard": "Lard",
    "orange juice": "Orange Juice", "apple juice": "Apple Juice",
}

# Groups that should merge (e.g., "sour cream" → cream group)
_GROUP_MERGES: dict[str, str] = {
    "sour cream": "cream",
    "cream cheese": "cheese",
    "cottage cheese": "cheese",
    "peanut butter": "peanut",
    "almond butter": "almond",
}

# Culinary distinction rules: when to keep items SEPARATE within a group
# (items that differ in cooking/nutrition/storage should stay separate)
_FORCE_SEPARATE = {
    "cheese": {"cottage", "cream cheese", "ricotta"},  # Very different from hard cheeses
    "milk": {"condensed", "evaporated", "buttermilk"},  # Different cooking use
}


def _normalize_base(base: str) -> str:
    """Normalize base ingredient for grouping."""
    base = base.lower().strip()

    # Apply merges
    if base in _GROUP_MERGES:
        base = _GROUP_MERGES[base]

    # Singularize simple cases
    if base.endswith("s") and base not in ("bass", "peas", "oats", "lens"):
        singular = base[:-1]
        if singular in _CANONICAL_GROUPS:
            return singular

    return base


def _assign_group(item: ParsedItem,
                  all_group_names: list[str]) -> str | None:
    """Assign an item to a canonical group. Returns group key or None."""
    base = _normalize_base(item.parsed_base)

    # Direct match
    if base in _CANONICAL_GROUPS:
        return base

    # Try fuzzy match against group names
    if all_group_names:
        match = process.extractOne(
            base,
            all_group_names,
            scorer=fuzz.ratio,
            score_cutoff=80,
        )
        if match:
            return match[0]

    # Try matching parsed_name words against group keys
    name_words = item.parsed_name.lower().split()
    for word in name_words:
        if word in _CANONICAL_GROUPS:
            return word

    # Fallback: use the base as its own group key if there's a base
    if base and len(base) > 1:
        return f"_auto:{base}"

    return None


def _should_keep_separate(item: ParsedItem, group_key: str) -> bool:
    """Check if an item should be a separate sub-group per culinary-distinction rules."""
    if group_key not in _FORCE_SEPARATE:
        return False

    separate_markers = _FORCE_SEPARATE[group_key]
    item_text = f"{item.parsed_name} {' '.join(item.qualifiers)}".lower()

    for marker in separate_markers:
        if marker in item_text:
            return True

    return False


def _extract_facets(members: list[ParsedItem]) -> dict[str, list[str]]:
    """Derive facets from within-group variation."""
    facets: dict[str, set[str]] = defaultdict(set)

    for m in members:
        for q in m.qualifiers:
            if q:
                facets["variant"].add(q)
        if m.form:
            for form_part in m.form.split():
                if form_part:
                    facets["form"].add(form_part)

    # Color variants → separate key
    colors = {"red", "green", "yellow", "white", "black", "brown"}
    color_variants = set()
    non_color_variants = set()
    for v in facets.get("variant", set()):
        if v.lower() in colors:
            color_variants.add(v)
        else:
            non_color_variants.add(v)

    result: dict[str, list[str]] = {}

    if color_variants:
        result["color"] = sorted(color_variants)
    if non_color_variants:
        result["variant"] = sorted(non_color_variants)
    if "form" in facets and len(facets["form"]) > 1:
        result["form"] = sorted(facets["form"])

    return result


# ---------------------------------------------------------------------------
# Main grouping
# ---------------------------------------------------------------------------

def _group_items(items: list[ParsedItem]) -> list[FoodGroup]:
    """Group items using taxonomy-guided approach."""
    canonical_keys = list(_CANONICAL_GROUPS.keys())

    # Phase 1: assign items to canonical groups
    assigned: dict[str, list[ParsedItem]] = defaultdict(list)
    unassigned: list[ParsedItem] = []

    for item in items:
        group_key = _assign_group(item, canonical_keys)
        if group_key:
            # Check culinary distinction
            if _should_keep_separate(item, group_key):
                # Create a more specific group key
                specific_key = f"{group_key}:{item.parsed_name.lower()}"
                assigned[specific_key].append(item)
            else:
                assigned[group_key].append(item)
        else:
            unassigned.append(item)

    logger.info("Assigned %d items to %d groups, %d unassigned",
                sum(len(v) for v in assigned.values()),
                len(assigned), len(unassigned))

    # Phase 2: try to assign unassigned items via fuzzy name matching
    remaining: list[ParsedItem] = []
    for item in unassigned:
        # Try fuzzy matching the parsed name against existing group names
        existing_names = {
            k: _CANONICAL_GROUPS.get(k.split(":")[0], k.split(":")[0].title())
            for k in assigned
        }
        name_match = process.extractOne(
            item.parsed_name.lower(),
            list(existing_names.values()),
            scorer=fuzz.token_sort_ratio,
            score_cutoff=70,
        )
        if name_match:
            # Find the key
            for k, v in existing_names.items():
                if v == name_match[0]:
                    assigned[k].append(item)
                    break
        else:
            remaining.append(item)

    logger.info("After fuzzy assignment: %d still unassigned", len(remaining))

    # Phase 3: build FoodGroup objects
    groups: list[FoodGroup] = []
    group_idx = 0

    for key, members in sorted(assigned.items()):
        if key.startswith("_auto:"):
            base_key = key[6:]  # strip "_auto:"
            group_name = base_key.title()
        else:
            base_key = key.split(":")[0]
            group_name = _CANONICAL_GROUPS.get(base_key, base_key.title())

        # Use most common category
        cat_counts = Counter(m.usda_category for m in members if m.usda_category)
        group_cat = cat_counts.most_common(1)[0][0] if cat_counts else ""

        facets = _extract_facets(members)

        group_members = []
        for m in members:
            attrs: dict[str, str] = {}
            if m.qualifiers:
                attrs["qualifiers"] = ", ".join(m.qualifiers)
            if m.form:
                attrs["form"] = m.form
            group_members.append(GroupMember(
                fdc_id=m.fdc_id,
                parsed_name=m.parsed_name,
                distinguishing_attrs=attrs,
            ))

        groups.append(FoodGroup(
            group_id=f"tax-{group_idx}",
            group_name=group_name,
            base_ingredient=base_key,
            category=group_cat,
            members=group_members,
            suggested_facets=facets,
        ))
        group_idx += 1

    # Remaining items become singleton groups
    for m in remaining:
        groups.append(FoodGroup(
            group_id=f"tax-singleton-{m.fdc_id}",
            group_name=m.parsed_name,
            base_ingredient=m.parsed_base,
            category=m.usda_category,
            members=[GroupMember(
                fdc_id=m.fdc_id,
                parsed_name=m.parsed_name,
                distinguishing_attrs={},
            )],
            suggested_facets={},
        ))

    return groups


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def run(parsed_items: list[ParsedItem] | None = None,
        parse_approach: str = "taxonomy") -> list[FoodGroup]:
    """Group items using taxonomy-guided approach."""
    if parsed_items is None:
        parsed_items = load_parse_results(parse_approach)
        if not parsed_items:
            raise RuntimeError(
                f"No parse results found for '{parse_approach}'. "
                "Run a parse approach first."
            )

    logger.info("Grouping %d items with taxonomy-guided approach...", len(parsed_items))
    groups = _group_items(parsed_items)

    save_group_results(groups, APPROACH_NAME)
    logger.info("Taxonomy-guided grouping complete: %d groups from %d items",
                len(groups), len(parsed_items))
    return groups
