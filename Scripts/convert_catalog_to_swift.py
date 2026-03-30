#!/usr/bin/env python3
"""Convert ingredient_catalog.json to Swift code for PantryCatalog.swift."""

import json
from pathlib import Path

# Mapping from JSON values to Swift enum cases
# Swift FoodCategory: dairy, produce, protein, grains, spices, condiments, 
# bakingSupplies, frozenFoods, canned, beverages, snacks, oils, pasta, nuts, other
# JSON categories from ingredient_catalog.json:
# Baking Supplies, Canned & Jarred, Condiments & Sauces, Dairy, Grains & Cereals,
# Nuts & Seeds, Oils & Fats, Other, Pasta & Noodles, Produce, Protein, Spices & Herbs
CATEGORY_MAP = {
    "Protein": ".protein",
    "Produce": ".produce",
    "Dairy": ".dairy",
    "Grains & Cereals": ".grains",
    "Pasta & Noodles": ".pasta",
    "Oils & Fats": ".oils",
    "Condiments & Sauces": ".condiments",
    "Spices & Herbs": ".spices",
    "Baking Supplies": ".bakingSupplies",
    "Nuts & Seeds": ".nuts",
    "Canned & Jarred": ".canned",
    "Other": ".other",
}

UNIT_MAP = {
    "g": ".gram",
    "gram": ".gram",
    "kg": ".kilogram",
    "ml": ".milliliter",
    "l": ".liter",
    "liter": ".liter",
    "cup": ".cup",
    "tbsp": ".tablespoon",
    "tablespoon": ".tablespoon",
    "tsp": ".teaspoon",
    "teaspoon": ".teaspoon",
    "oz": ".ounce",
    "ounce": ".ounce",
    "lb": ".pound",
    "pound": ".pound",
    "piece": ".piece",
    "clove": ".clove",
    "bunch": ".bunch",
    "head": ".head",
    "stalk": ".stalk",
    "sprig": ".sprig",
    "leaf": ".leaf",
    "slice": ".slice",
    "can": ".can",
    "bottle": ".bottle",
    "jar": ".jar",
    "package": ".package",
    "pinch": ".pinch",
    "dash": ".dash",
    "whole": ".whole",
    None: "nil",
}

STORAGE_MAP = {
    "Pantry": ".pantry",
    "Refrigerated": ".refrigerated",
    "Frozen": ".frozen",
}

FACET_KEY_MAP = {
    "variant": ".variant",
    "form": ".form",
    "preservation": ".preservation",
    "processing": ".processing",
    "preparation": ".preparation",
    "texture": ".texture",
    "concentration": ".concentration",
    "base": ".base",
}

IMPACT_MAP = {
    "None": ".none",
    "Slight": ".slight",
    "Moderate": ".moderate",
    "Significant": ".significant",
}

COOKING_IMPACT_MAP = {
    "None": ".none",
    "Slight Adjustment": ".slightAdjustment",
    "Moderate Adjustment": ".moderateAdjustment",
    "Significant Adjustment": ".significantAdjustment",
}


def escape_string(s: str) -> str:
    """Escape a string for Swift."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


def convert_item(item: dict) -> str:
    """Convert a single catalog item to Swift code."""
    lines = []
    
    item_id = item["id"]
    name = escape_string(item["name"])
    category = CATEGORY_MAP.get(item["category"], ".miscellaneous")
    
    default_unit = UNIT_MAP.get(item.get("default_unit"), "nil")
    default_quantity = item.get("default_quantity")
    default_storage = STORAGE_MAP.get(item.get("default_storage", "Pantry"), ".pantry")
    
    # Aliases
    aliases = item.get("aliases", [])
    aliases_str = ", ".join(f'"{escape_string(a)}"' for a in aliases)
    
    # Facets
    facets = item.get("facets", [])
    facet_strs = []
    for f in facets:
        key = FACET_KEY_MAP.get(f["key"])
        if key:
            options = ", ".join(f'"{escape_string(o)}"' for o in f["options"])
            facet_strs.append(f'{key}([{options}])')
    facets_str = ", ".join(facet_strs)
    
    # Default selections
    default_selections = item.get("default_selections", [])
    selections_strs = []
    for s in default_selections:
        key = FACET_KEY_MAP.get(s["key"])
        value = escape_string(s["value"])
        if key:
            selections_strs.append(f'.init(key: {key}, value: "{value}")')
    selections_str = ", ".join(selections_strs)
    
    # Freshness by storage
    freshness = item.get("freshness_by_storage", [])
    freshness_strs = []
    for f in freshness:
        storage = STORAGE_MAP.get(f["storage"])
        min_days = f["min_days"]
        max_days = f["max_days"]
        if storage:
            freshness_strs.append(f'{storage}: {min_days}...{max_days}')
    freshness_str = ", ".join(freshness_strs)
    
    # Build the item call
    lines.append(f'        item(')
    lines.append(f'            id: "{item_id}",')
    lines.append(f'            name: "{name}",')
    lines.append(f'            category: {category},')
    lines.append(f'            defaultUnit: {default_unit},')
    if default_quantity is not None:
        lines.append(f'            defaultQuantity: {default_quantity},')
    else:
        lines.append(f'            defaultQuantity: nil,')
    lines.append(f'            defaultStorage: {default_storage},')
    lines.append(f'            aliases: [{aliases_str}],')
    lines.append(f'            facets: [{facets_str}],')
    lines.append(f'            defaultSelections: [{selections_str}],')
    lines.append(f'            freshnessByStorage: [{freshness_str}]')
    lines.append(f'        )')
    
    return "\n".join(lines)


def main():
    script_dir = Path(__file__).parent
    catalog_path = script_dir / "recipe_ingredient_orchestrator" / "output" / "ingredient_catalog.json"
    output_path = script_dir / "generated_catalog_items.swift"
    
    with open(catalog_path) as f:
        catalog = json.load(f)
    
    items = []
    for item in catalog:
        try:
            swift_code = convert_item(item)
            items.append(swift_code)
        except Exception as e:
            print(f"Warning: Failed to convert {item.get('id', 'unknown')}: {e}")
    
    output = ",\n".join(items)
    
    with open(output_path, "w") as f:
        f.write("// Generated catalog items - paste into PantryCatalog.swift\n")
        f.write("// Total items: " + str(len(items)) + "\n\n")
        f.write(output)
    
    print(f"Generated {len(items)} items to {output_path}")


if __name__ == "__main__":
    main()
