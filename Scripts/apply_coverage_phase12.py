#!/usr/bin/env python3
"""Phase 1+2 corpus coverage improvements and generic oil base entry.

Run from repo root:
    python3 PantryChef/Scripts/apply_coverage_phase12.py
"""
from __future__ import annotations

import copy
import json
from pathlib import Path

CATALOG_PATH = Path("PantryChef/PantryChef/Resources/catalog.json")


def find_item(items: list[dict], item_id: str) -> dict | None:
    for item in items:
        if item["id"] == item_id:
            return item
    return None


def facet_options(item: dict, key: str) -> list[str]:
    for facet in item.get("facets", []):
        if facet.get("key") == key:
            return list(facet["options"])
    return []


def add_facet_options(item: dict, key: str, new_options: list[str]) -> None:
    for facet in item.get("facets", []):
        if facet.get("key") == key:
            existing = facet["options"]
            for opt in new_options:
                if opt not in existing:
                    existing.append(opt)
            return
    item.setdefault("facets", []).append({"key": key, "options": new_options})


def add_aliases(item: dict, aliases: list[str]) -> None:
    current = item.setdefault("aliases", [])
    for alias in aliases:
        if alias not in current and alias.lower() != item["name"].lower():
            current.append(alias)


def make_item(**kwargs) -> dict:
    base = {
        "id": kwargs.pop("id"),
        "name": kwargs.pop("name"),
        "category": kwargs.pop("category"),
        "defaultUnit": None,
        "defaultQuantity": None,
        "defaultStorage": "Pantry",
        "aliases": [],
        "facets": [],
        "defaultSelections": [],
        "freshnessByStorage": {"Pantry": [30, 365]},
    }
    base.update(kwargs)
    return base


def apply_migration(items: list[dict]) -> tuple[list[dict], dict]:
    items = copy.deepcopy(items)
    report: dict = {"updated": [], "added": []}

    # ------------------------------------------------------------------ #
    # Generic oil base — bare "oil", "neutral oil", "cooking oil"
    # ------------------------------------------------------------------ #
    if not find_item(items, "oil"):
        items.append(make_item(
            id="oil",
            name="oil",
            category="Oils & Fats",
            defaultUnit="tbsp",
            defaultQuantity=2.0,
            defaultStorage="Pantry",
            aliases=[
                "oils",
                "neutral oil",
                "cooking oil",
                "salad oil",
                "liquid oil",
                "frying oil",
            ],
            facets=[{
                "key": "variant",
                "options": [
                    "vegetable", "neutral", "olive", "canola", "coconut", "sesame",
                    "peanut", "sunflower", "safflower", "corn", "avocado", "walnut",
                    "grapeseed", "soybean", "palm", "truffle", "mustard", "rice bran",
                    "hazelnut", "flaxseed", "hemp", "almond", "macadamia", "pecan",
                ],
            }],
            defaultSelections=[{"key": "variant", "value": "vegetable"}],
            freshnessByStorage={"Pantry": [180, 365]},
        ))
        report["added"].append("oil (generic cooking oil base)")

    # ------------------------------------------------------------------ #
    # Generic nut base — bare "nuts", "nut", "ground nuts"
    # ------------------------------------------------------------------ #
    if not find_item(items, "nut"):
        items.append(make_item(
            id="nut",
            name="nut",
            category="Nuts & Seeds",
            defaultUnit="cup",
            defaultQuantity=0.5,
            defaultStorage="Pantry",
            aliases=[
                "nuts",
                "ground nuts",
                "ground nut",
                "chopped nuts",
                "unsalted nuts",
            ],
            facets=[{
                "key": "variant",
                "options": [
                    "mixed", "walnut", "pecan", "almond", "cashew", "peanut",
                    "hazelnut", "pistachio", "macadamia", "pine", "brazil",
                    "chestnut", "black walnut",
                ],
            }, {
                "key": "form",
                "options": ["whole", "halved", "chopped", "ground", "sliced"],
            }, {
                "key": "processing",
                "options": ["raw", "roasted", "toasted", "salted", "unsalted", "blanched"],
            }],
            defaultSelections=[
                {"key": "variant", "value": "mixed"},
                {"key": "form", "value": "whole"},
            ],
            freshnessByStorage={"Pantry": [90, 365]},
        ))
        report["added"].append("nut (generic nut base)")

    # ------------------------------------------------------------------ #
    # Phase 1 — aliases and facet enrichment
    # ------------------------------------------------------------------ #
    phase1: list[tuple[str, list[str], dict[str, list[str]]]] = [
        ("lemon", [
            "lemon rind", "lemon peel", "grated lemon rind", "freshly grated lemon rind",
        ], {"form": ["rind", "peel"]}),
        ("orange", [
            "orange rind", "orange peel", "grated orange rind", "freshly grated orange rind",
        ], {"form": ["rind", "peel"]}),
        ("lime", [
            "lime zest", "fresh lime zest", "grated lime zest",
        ], {"form": ["zest", "rind", "peel"]}),
        ("ginger", ["gingerroot", "fresh gingerroot", "peeled gingerroot"], {}),
        ("pimento", ["pimiento", "pimientos", "ground pimiento"], {}),
        ("tomato", [
            "tomato puree", "tomato purée", "tomatoes puree", "ro-tel", "ro tel",
        ], {}),
        ("beans", [
            "bean sprout", "bean sprouts", "fresh bean sprouts", "white bean",
            "red kidney bean", "red kidney beans", "kidney bean",
        ], {"variant": ["white"]}),
        ("cheese", ["velveeta cheese", "velveeta"], {"variant": ["velveeta", "gorgonzola"]}),
        ("beef", ["lean beef", "extra lean beef"], {"processing": ["lean"]}),
        ("corn", [
            "cream style corn", "cream-style corn", "creamed corn",
        ], {"variant": ["cream-style"], "form": ["cream-style"]}),
        ("syrup", ["simple syrup"], {"variant": ["simple"]}),
        ("yogurt", ["vanilla yogurt"], {"variant": ["vanilla"]}),
        ("banana", ["ripe banana"], {"preparation": ["ripe"]}),
        ("cream-soup", [
            "vegetable soup", "cream of vegetable soup", "cheddar cheese soup",
            "cream of cheddar cheese soup", "potato soup", "cream of potato soup",
        ], {"variant": ["vegetable", "cheddar"]}),
        ("pasta-sauce", ["pizza sauce"], {"variant": ["pizza", "marinara"]}),
        ("curry-powder", ["curry", "ground curry", "curry ground"], {}),
        ("mustard", ["mustard powder", "dry mustard powder", "ground mustard powder"], {"form": ["powder"]}),
        ("gelatin", [
            "jello", "jell-o", "gelatin dessert",
            "strawberry jello", "lemon jello", "orange jello", "lime jello",
            "cherry jello", "raspberry jello",
        ], {
            "variant": ["strawberry", "lemon", "orange", "lime", "cherry", "raspberry"],
            "processing": ["flavored"],
        }),
        ("brussels-sprout", ["brussel", "brussels"], {}),
        ("graham-cracker-crumb", [
            "graham cracker", "graham crackers", "graham cracker crushed",
            "graham cracker crust", "graham cracker pie crust",
        ], {}),
    ]

    for item_id, aliases, facets in phase1:
        item = find_item(items, item_id)
        if not item:
            continue
        add_aliases(item, aliases)
        for key, opts in facets.items():
            add_facet_options(item, key, opts)
        report["updated"].append(item_id)

    # ------------------------------------------------------------------ #
    # Phase 2 — high-value new entries
    # ------------------------------------------------------------------ #
    new_entries = [
        make_item(
            id="raisin",
            name="raisin",
            category="Baking & Sweeteners",
            defaultUnit="cup",
            defaultQuantity=0.5,
            aliases=["raisins", "seeded raisins", "sultana", "sultanas"],
            facets=[{
                "key": "variant",
                "options": ["dark", "golden", "sultana", "currants", "monukka"],
            }],
            defaultSelections=[{"key": "variant", "value": "dark"}],
        ),
        make_item(
            id="cracker",
            name="cracker",
            category="Snacks",
            defaultUnit="oz",
            defaultQuantity=8.0,
            aliases=["crackers", "saltine", "saltines", "ritz cracker", "ritz crackers"],
            facets=[{
                "key": "variant",
                "options": ["saltine", "ritz", "graham", "wheat", "butter", "oyster"],
            }, {
                "key": "form",
                "options": ["whole", "crushed", "crumb"],
            }],
            defaultSelections=[
                {"key": "variant", "value": "saltine"},
                {"key": "form", "value": "whole"},
            ],
        ),
        make_item(
            id="herb",
            name="herb",
            category="Spices & Herbs",
            defaultUnit="bunch",
            defaultQuantity=1.0,
            defaultStorage="Refrigerated",
            aliases=["herbs", "fresh herbs", "fresh herb", "mixed herbs"],
            facets=[{
                "key": "variant",
                "options": [
                    "basil", "parsley", "cilantro", "thyme", "rosemary", "oregano",
                    "dill", "mint", "sage", "chive", "tarragon", "mixed",
                ],
            }],
            defaultSelections=[{"key": "variant", "value": "mixed"}],
            freshnessByStorage={"Refrigerated": [3, 7], "Pantry": [1, 3]},
        ),
        make_item(
            id="prune",
            name="prune",
            category="Produce",
            defaultUnit="cup",
            defaultQuantity=0.5,
            aliases=["prunes", "dried prune", "dried prunes"],
            facets=[{
                "key": "preservation",
                "options": ["dried", "pitted", "whole"],
            }],
            defaultSelections=[{"key": "preservation", "value": "dried"}],
        ),
        make_item(
            id="taco-shell",
            name="taco shell",
            category="Breads & Bakery",
            defaultUnit="piece",
            defaultQuantity=8,
            aliases=["taco", "tacos", "hard taco shell", "taco shells", "corn taco shell"],
            facets=[{
                "key": "variant",
                "options": ["corn", "flour", "hard", "soft"],
            }],
            defaultSelections=[{"key": "variant", "value": "corn"}],
        ),
        make_item(
            id="ice-cream",
            name="ice cream",
            category="Frozen Foods",
            defaultUnit="cup",
            defaultQuantity=1.0,
            defaultStorage="Frozen",
            aliases=["ice creams", "vanilla ice cream", "frozen ice cream"],
            facets=[{
                "key": "variant",
                "options": ["vanilla", "chocolate", "strawberry", "neapolitan", "coffee"],
            }],
            defaultSelections=[{"key": "variant", "value": "vanilla"}],
            freshnessByStorage={"Frozen": [60, 180]},
        ),
        make_item(
            id="cake-mix",
            name="cake mix",
            category="Baking & Sweeteners",
            defaultUnit="box",
            defaultQuantity=1.0,
            aliases=[
                "cake mixes", "yellow cake mix", "white cake mix", "chocolate cake mix",
                "lemon cake mix", "dry cake mix",
            ],
            facets=[{
                "key": "variant",
                "options": ["yellow", "white", "chocolate", "lemon", "spice", "devil's food"],
            }],
            defaultSelections=[{"key": "variant", "value": "yellow"}],
        ),
        make_item(
            id="crescent-roll",
            name="crescent roll",
            category="Breads & Bakery",
            defaultUnit="can",
            defaultQuantity=1.0,
            defaultStorage="Refrigerated",
            aliases=["crescent rolls", "crescent-roll", "refrigerated crescent rolls"],
            facets=[{
                "key": "preservation",
                "options": ["refrigerated", "frozen", "baked"],
            }],
            defaultSelections=[{"key": "preservation", "value": "refrigerated"}],
            freshnessByStorage={"Refrigerated": [7, 14], "Frozen": [90, 180]},
        ),
        make_item(
            id="vanilla-wafer",
            name="vanilla wafer",
            category="Snacks",
            defaultUnit="oz",
            defaultQuantity=11.0,
            aliases=["vanilla wafers", "nilla wafer", "nilla wafers", "ground vanilla wafers"],
            facets=[{
                "key": "form",
                "options": ["whole", "crushed", "crumb"],
            }],
            defaultSelections=[{"key": "form", "value": "whole"}],
        ),
        make_item(
            id="tortilla-chip",
            name="tortilla chip",
            category="Snacks",
            defaultUnit="oz",
            defaultQuantity=10.0,
            aliases=["tortilla chips", "tortillas chips", "corn tortilla chips", "nacho chips"],
            facets=[{
                "key": "variant",
                "options": ["corn", "flour", "blue corn"],
            }],
            defaultSelections=[{"key": "variant", "value": "corn"}],
        ),
        make_item(
            id="graham-cracker",
            name="graham cracker",
            category="Snacks",
            defaultUnit="oz",
            defaultQuantity=14.0,
            aliases=["graham crackers", "graham cracker square", "graham cracker squares"],
            facets=[{
                "key": "form",
                "options": ["whole", "crushed", "crumb"],
            }],
            defaultSelections=[{"key": "form", "value": "whole"}],
        ),
        make_item(
            id="pumpkin-pie-spice",
            name="pumpkin pie spice",
            category="Spices & Herbs",
            defaultUnit="tsp",
            defaultQuantity=1.0,
            aliases=["pumpkin-pie spice", "pumpkin pie spices", "pumpkin spice blend"],
        ),
        make_item(
            id="pie-shell",
            name="pie shell",
            category="Breads & Bakery",
            defaultUnit="piece",
            defaultQuantity=1.0,
            aliases=[
                "pie shells", "unbaked pie shell", "pie crust shell", "graham cracker pie shell",
            ],
            facets=[{
                "key": "variant",
                "options": ["plain", "graham", "phyllo"],
            }, {
                "key": "preservation",
                "options": ["fresh", "frozen", "refrigerated"],
            }],
            defaultSelections=[
                {"key": "variant", "value": "plain"},
                {"key": "preservation", "value": "refrigerated"},
            ],
            freshnessByStorage={"Refrigerated": [7, 14], "Frozen": [90, 180]},
        ),
        make_item(
            id="canned-green-chile",
            name="canned green chile",
            category="Canned & Jarred",
            defaultUnit="can",
            defaultQuantity=1.0,
            aliases=[
                "green chile", "green chiles", "green chili", "green chilies",
                "canned green chiles", "diced green chiles",
            ],
            facets=[{
                "key": "form",
                "options": ["whole", "diced", "chopped"],
            }, {
                "key": "concentration",
                "options": ["mild", "hot"],
            }],
            defaultSelections=[
                {"key": "form", "value": "diced"},
                {"key": "concentration", "value": "mild"},
            ],
        ),
    ]

    existing_ids = {item["id"] for item in items}
    for entry in new_entries:
        if entry["id"] not in existing_ids:
            items.append(entry)
            report["added"].append(entry["id"])
            existing_ids.add(entry["id"])

    items.sort(key=lambda x: x["id"])
    return items, report


def main() -> None:
    with open(CATALOG_PATH) as f:
        items = json.load(f)

    updated, report = apply_migration(items)

    with open(CATALOG_PATH, "w") as f:
        json.dump(updated, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Updated {len(set(report['updated']))} existing entries")
    print(f"Added {len(report['added'])} entries:")
    for entry in report["added"]:
        print(f"  + {entry}")
    print(f"Total catalog entries: {len(updated)}")


if __name__ == "__main__":
    main()
