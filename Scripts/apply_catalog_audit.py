#!/usr/bin/env python3
"""Apply catalog audit fixes to production catalog.json.

Run from repo root:
    python3 PantryChef/Scripts/apply_catalog_audit.py
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


def set_facet_options(item: dict, key: str, options: list[str]) -> None:
    for facet in item.get("facets", []):
        if facet.get("key") == key:
            facet["options"] = options
            return
    item.setdefault("facets", []).append({"key": key, "options": options})


def add_facet_options(item: dict, key: str, new_options: list[str]) -> None:
    existing = facet_options(item, key)
    merged = existing[:]
    for opt in new_options:
        if opt not in merged:
            merged.append(opt)
    set_facet_options(item, key, merged)


def add_aliases(item: dict, aliases: list[str]) -> None:
    current = item.setdefault("aliases", [])
    for alias in aliases:
        if alias not in current and alias.lower() != item["name"].lower():
            current.append(alias)


def ensure_facet(item: dict, key: str, options: list[str]) -> None:
    if facet_options(item, key):
        add_facet_options(item, key, options)
    else:
        set_facet_options(item, key, options)


def ensure_preservation_frozen(item: dict) -> None:
    add_facet_options(item, "preservation", ["frozen"])


def remove_items(items: list[dict], remove_ids: set[str]) -> list[dict]:
    return [item for item in items if item["id"] not in remove_ids]


def merge_aliases_from(items: list[dict], target_id: str, source_ids: set[str], extra: list[str] | None = None) -> None:
    target = find_item(items, target_id)
    if not target:
        raise SystemExit(f"Missing target item: {target_id}")
    aliases = list(extra or [])
    for source_id in source_ids:
        source = find_item(items, source_id)
        if not source:
            continue
        aliases.append(source["name"])
        aliases.extend(source.get("aliases", []))
    add_aliases(target, aliases)


def rename_item(item: dict, new_id: str, new_name: str) -> None:
    item["id"] = new_id
    item["name"] = new_name


def make_item(**kwargs) -> dict:
    base = {
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
    report: dict = {"removed": [], "merged": [], "renamed": [], "added": [], "updated": []}

    # ------------------------------------------------------------------ #
    # 1. Rename black-pepper → peppercorn
    # ------------------------------------------------------------------ #
    peppercorn = find_item(items, "black-pepper")
    if peppercorn:
        rename_item(peppercorn, "peppercorn", "peppercorn")
        peppercorn["aliases"] = [
            a for a in peppercorn.get("aliases", [])
            if a.lower() not in {"pepper", "peppers", "peppercorns"}
        ]
        add_aliases(peppercorn, [
            "black pepper", "black peppercorn", "peppercorns", "black peppers",
            "whole peppercorn", "ground peppercorn",
        ])
        add_facet_options(peppercorn, "variant", ["black", "white", "green", "pink"])
        peppercorn["defaultSelections"] = [
            {"key": "variant", "value": "black"},
            {"key": "form", "value": "ground"},
        ]
        report["renamed"].append("black-pepper → peppercorn")

    # ------------------------------------------------------------------ #
    # 2. Merge duplicate protein / legume / fish bases
    # ------------------------------------------------------------------ #
    merge_plan = {
        "beef": {
            "sources": {"brisket", "oxtail", "roast-beef"},
            "aliases": [
                "hamburger", "hamburg", "ground hamburger", "lean hamburger",
                "beef brisket", "beef oxtail", "meaty oxtail",
            ],
        },
        "oily-fish": {
            "sources": {"anchovy", "tuna", "smoked-salmon", "canned-salmon", "canned-sardine"},
            "aliases": [
                "salmon", "smoked salmon", "canned salmon", "canned tuna", "canned sardine",
                "sardine", "sardines", "anchovies", "tunas",
            ],
        },
        "white-fish": {
            "sources": {"bass"},
            "aliases": ["sea bass", "striped bass"],
        },
        "beans": {
            "sources": {"fava-bean", "soybean"},
            "aliases": ["fava bean", "fava beans", "soy bean", "soy beans"],
        },
        "broth": {
            "sources": {"stock"},
            "aliases": ["stock", "stocks", "cooking stock", "chicken stock", "beef stock", "vegetable stock"],
        },
        "turkey": {
            "sources": {"deli-turkey"},
            "aliases": ["deli turkey", "deli turkey breast", "sliced turkey"],
        },
    }

    for target_id, spec in merge_plan.items():
        sources = spec["sources"]
        merge_aliases_from(items, target_id, sources, spec.get("aliases"))
        target = find_item(items, target_id)
        if target:
            ensure_preservation_frozen(target)
            if target_id == "oily-fish":
                add_facet_options(target, "preservation", ["canned"])
                add_facet_options(target, "processing", ["smoked", "cured", "salted"])
            if target_id == "white-fish":
                add_facet_options(target, "variant", ["bass", "bream"])
            if target_id == "beef":
                add_facet_options(target, "preservation", ["frozen"])
        items = remove_items(items, sources)
        report["merged"].append(f"{sorted(sources)} → {target_id}")

    # Remove generic liver (replaced by per-meat liver entries)
    items = remove_items(items, {"liver"})
    report["removed"].append("liver (generic)")

    chicken = find_item(items, "pork")
    if chicken:
        pass
    chicken_item = find_item(items, "chicken")
    if chicken_item:
        set_facet_options(
            chicken_item,
            "variant",
            [v for v in facet_options(chicken_item, "variant") if v != "liver"],
        )

    pork = find_item(items, "pork")
    if pork:
        set_facet_options(
            pork,
            "variant",
            [v for v in facet_options(pork, "variant") if v not in {"ham", "sausage"}],
        )

    # Merge canned tuna entry into tuna (already removed via oily-fish - check canned-tuna)
    canned_tuna = find_item(items, "canned-tuna")
    if canned_tuna:
        merge_aliases_from(items, "oily-fish", {"canned-tuna"}, ["canned tuna", "tuna in water", "tuna in oil"])
        items = remove_items(items, {"canned-tuna"})
        report["merged"].append("canned-tuna → oily-fish")

    # ------------------------------------------------------------------ #
    # 3. Cured meats → single cured-meat entry
    # ------------------------------------------------------------------ #
    cured_sources = {
        "ham", "bacon", "sausage", "pepperoni", "salami", "prosciutto", "pastrami",
        "bologna", "mortadella", "bratwurst", "kielbasa", "chorizo", "hot-dog",
        "jerky", "beef-jerky", "luncheon-meat", "spam", "corn-dog",
    }
    cured_aliases: list[str] = []
    for cid in cured_sources:
        source = find_item(items, cid)
        if source:
            cured_aliases.append(source["name"])
            cured_aliases.extend(source.get("aliases", []))
    items = remove_items(items, cured_sources)

    cured_meat = make_item(
        id="cured-meat",
        name="cured meat",
        category="Protein",
        defaultUnit="lb",
        defaultQuantity=1.0,
        defaultStorage="Refrigerated",
        aliases=sorted(set(cured_aliases + [
            "deli meat", "lunch meat", "lunchmeat", "cold cuts", "cold cut",
            "cured meats", "smoked meat", "hot dog", "hot dogs", "corn dog",
            "beef jerky", "meat stick", "luncheon meat",
        ])),
        facets=[
            {
                "key": "base",
                "options": ["pork", "beef", "turkey", "lamb", "chicken", "venison"],
            },
            {
                "key": "variant",
                "options": [
                    "ham", "bacon", "sausage", "salami", "pepperoni", "prosciutto",
                    "pastrami", "bologna", "mortadella", "bratwurst", "kielbasa",
                    "chorizo", "hot dog", "jerky", "spam", "luncheon meat", "andouille",
                    "capicola", "guanciale", "canadian bacon", "pancetta", "speck",
                    "landjäger", "summer sausage", "breakfast sausage", "italian sausage",
                ],
            },
            {
                "key": "form",
                "options": ["whole", "sliced", "diced", "ground", "link", "stick", "patty"],
            },
            {
                "key": "preservation",
                "options": ["cured", "smoked", "dried", "cooked", "semi-dry"],
            },
        ],
        defaultSelections=[
            {"key": "base", "value": "pork"},
            {"key": "variant", "value": "ham"},
            {"key": "form", "value": "sliced"},
        ],
        freshnessByStorage={
            "Pantry": [14, 60],
            "Refrigerated": [7, 21],
            "Frozen": [60, 180],
        },
    )
    items.append(cured_meat)
    report["added"].append("cured-meat")
    report["merged"].append(f"{sorted(cured_sources)} → cured-meat")

    # ------------------------------------------------------------------ #
    # 4. Per-meat liver entries
    # ------------------------------------------------------------------ #
    liver_template = {
        "category": "Protein",
        "defaultUnit": "lb",
        "defaultQuantity": 0.5,
        "defaultStorage": "Refrigerated",
        "facets": [
            {"key": "form", "options": ["whole", "sliced", "diced"]},
            {"key": "preservation", "options": ["fresh", "frozen"]},
        ],
        "defaultSelections": [{"key": "form", "value": "whole"}],
        "freshnessByStorage": {"Refrigerated": [1, 3], "Frozen": [90, 180]},
    }
    for lid, lname, aliases in [
        ("chicken-liver", "chicken liver", ["chicken livers", "livers chicken"]),
        ("beef-liver", "beef liver", ["beef livers", "calf liver", "calves liver"]),
        ("pork-liver", "pork liver", ["pork livers"]),
        ("lamb-liver", "lamb liver", ["lamb livers"]),
        ("turkey-liver", "turkey liver", ["turkey livers"]),
        ("veal-liver", "veal liver", ["veal livers"]),
    ]:
        entry = make_item(id=lid, name=lname, aliases=aliases, **liver_template)
        items.append(entry)
        report["added"].append(lid)

    # ------------------------------------------------------------------ #
    # 5. Produce pepper — add color facet
    # ------------------------------------------------------------------ #
    pepper = find_item(items, "pepper")
    if pepper:
        ensure_facet(pepper, "color", ["green", "red", "yellow", "orange", "white", "purple", "brown"])
        add_aliases(pepper, [
            "bell pepper", "bell peppers", "sweet pepper", "green pepper", "red pepper",
            "yellow pepper", "orange pepper", "green bell pepper", "red bell pepper",
            "yellow bell pepper", "orange bell pepper", "green chili pepper",
        ])
        report["updated"].append("pepper: color facet + aliases")

    # ------------------------------------------------------------------ #
    # 6. Facet / alias enrichment from corpus gaps
    # ------------------------------------------------------------------ #
    onion = find_item(items, "onion")
    if onion:
        add_aliases(onion, ["shallot", "shallots", "purple onion", "spanish onion", "sweet onion"])

    sugar = find_item(items, "sugar")
    if sugar:
        add_aliases(sugar, [
            "confectioners sugar", "confectioner sugar", "confectioners' sugar",
            "icing sugar", "powdered sugar", "superfine sugar", "caster sugar",
            "golden sugar", "cinnamon sugar",
        ])
        add_facet_options(sugar, "variant", ["powdered", "confectioners", "icing"])

    cheese = find_item(items, "cheese")
    if cheese:
        add_facet_options(cheese, "variant", ["romano", "sharp", "extra sharp", "mild"])

    salt = find_item(items, "salt")
    if salt:
        add_facet_options(salt, "variant", ["garlic", "celery", "onion", "seasoned", "popcorn"])

    cream = find_item(items, "cream")
    if cream:
        add_facet_options(cream, "variant", ["condensed", "evaporated"])
        add_aliases(cream, ["heavy whipping cream", "whipping cream"])

    potato = find_item(items, "potato")
    if potato:
        add_facet_options(potato, "variant", ["baking", "russet"])
        add_aliases(potato, ["baking potato", "hash brown potato", "hash browns"])

    coconut = find_item(items, "coconut")
    if coconut:
        add_facet_options(coconut, "form", ["flaked", "shredded"])

    flour = find_item(items, "flour")
    if flour:
        add_aliases(flour, ["white flour", "all purpose flour", "ap flour"])

    milk = find_item(items, "milk")
    if milk:
        add_aliases(milk, ["whole milk", "sweet milk", "sour milk", "pet milk", "2% milk", "skim milk"])

    cream_cheese = find_item(items, "cream-cheese")
    if cream_cheese:
        add_facet_options(cream_cheese, "variant", ["philadelphia"])

    lemon = find_item(items, "lemon")
    if lemon:
        add_facet_options(lemon, "form", ["zest"])
        add_aliases(lemon, ["lemon zest", "fresh lemon zest", "grated lemon zest"])

    cream_soup = find_item(items, "cream-soup")
    if cream_soup:
        add_aliases(cream_soup, [
            "cream of mushroom soup", "mushroom soup", "cream of chicken soup",
            "chicken soup", "cream of celery soup", "celery soup",
            "cream of potato soup", "onion soup", "cream of onion soup",
        ])

    # ------------------------------------------------------------------ #
    # 7. New gap entries
    # ------------------------------------------------------------------ #
    new_entries = [
        make_item(
            id="tomato-soup",
            name="tomato soup",
            category="Canned & Jarred",
            defaultUnit="can",
            defaultQuantity=1.0,
            aliases=["cream of tomato soup", "tomatoes soup", "condensed tomato soup"],
            facets=[
                {"key": "concentration", "options": ["regular", "reduced sodium", "condensed"]},
            ],
            defaultSelections=[{"key": "concentration", "value": "regular"}],
            freshnessByStorage={"Pantry": [365, 1095]},
        ),
        make_item(
            id="pimento",
            name="pimento",
            category="Produce",
            defaultUnit="oz",
            defaultQuantity= 4.0,
            defaultStorage="Refrigerated",
            aliases=["pimentos", "pimiento", "pimiento pepper", "cherry pepper"],
            facets=[
                {"key": "form", "options": ["whole", "diced", "sliced", "roasted"]},
                {"key": "preservation", "options": ["fresh", "jarred", "roasted"]},
            ],
            defaultSelections=[{"key": "preservation", "value": "jarred"}],
            freshnessByStorage={"Pantry": [365, 730], "Refrigerated": [7, 14]},
        ),
        make_item(
            id="graham-cracker-crumb",
            name="graham cracker crumb",
            category="Baking & Sweeteners",
            defaultUnit="cup",
            defaultQuantity=1.0,
            aliases=[
                "graham cracker crumbs", "graham cracker crust", "graham cracker pie crust",
                "graham crumbs", "graham cracker crumb crust",
            ],
            facets=[{"key": "form", "options": ["fine", "coarse"]}],
            defaultSelections=[{"key": "form", "value": "fine"}],
            freshnessByStorage={"Pantry": [90, 180]},
        ),
        make_item(
            id="graham-cracker",
            name="graham cracker",
            category="Baking & Sweeteners",
            defaultUnit="piece",
            defaultQuantity=12.0,
            aliases=["graham crackers", "graham cracker square", "graham cracker squares"],
            facets=[{"key": "form", "options": ["whole", "crushed", "square"]}],
            defaultSelections=[{"key": "form", "value": "whole"}],
            freshnessByStorage={"Pantry": [90, 180]},
        ),
        make_item(
            id="bisquick",
            name="bisquick",
            category="Baking & Sweeteners",
            defaultUnit="cup",
            defaultQuantity=2.0,
            aliases=["bisquick mix", "baking mix", "pancake mix"],
            facets=[{"key": "variant", "options": ["original", "heart smart", "gluten free"]}],
            defaultSelections=[{"key": "variant", "value": "original"}],
            freshnessByStorage={"Pantry": [180, 365]},
        ),
    ]
    items.extend(new_entries)
    report["added"].extend([e["id"] for e in new_entries])

    # ------------------------------------------------------------------ #
    # 8. Frozen duplicates → aliases + preservation; remove Frozen Foods
    # ------------------------------------------------------------------ #
    frozen_remap = {
        "frozen-broccoli": "broccoli",
        "frozen-corn": "corn",
        "frozen-spinach": "spinach",
        "frozen-shrimp": "shrimp",
        "frozen-scallop": "scallop",
        "frozen-calamari": "calamari",
        "frozen-peas": "pea",
        "frozen-rice": "rice",
        "frozen-meatball": "meatball",
        "frozen-pancake": "pancake",
        "frozen-pie": "pie",
        "frozen-ravioli": "ravioli",
        "frozen-garlic-bread": "garlic-bread",
        "frozen-lasagna": "lasagna",
        "frozen-fruit-bar": "fruit-bar",
        "frozen-waffles": "waffle",
        "frozen-edamame": "edamame",
        "frozen-berries": "berry",
        "frozen-mixed-vegetables": "mixed-vegetables",
        "frozen-hash-brown": "potato",
        "frozen-french-fries": "potato",
    }
    frozen_remove: set[str] = set()
    for frozen_id, base_id in frozen_remap.items():
        frozen = find_item(items, frozen_id)
        base = find_item(items, base_id)
        if frozen and base:
            add_aliases(base, [frozen["name"]] + frozen.get("aliases", []))
            ensure_preservation_frozen(base)
            frozen_remove.add(frozen_id)
    # Remove all remaining Frozen Foods category entries
    for item in items:
        if item["category"] == "Frozen Foods":
            frozen_remove.add(item["id"])
    items = remove_items(items, frozen_remove)
    report["removed"].extend(sorted(frozen_remove))

    # Ensure preservation frozen on common produce/protein
    for bid in ["broccoli", "corn", "spinach", "shrimp", "rice", "pea", "berry", "edamame", "calamari", "scallop"]:
        base = find_item(items, bid)
        if base:
            ensure_preservation_frozen(base)

    # ------------------------------------------------------------------ #
    # 9. Remove Snacks + unused niche entries
    # ------------------------------------------------------------------ #
    remove_niche = {
        "baba-ganoush", "breakfast-bar", "cheese-puff", "energy-bar",
        "everything-bagel-seasoning", "herbes-de-provence", "meat-stick",
        "nut-bar", "peri-peri-seasoning", "pilinut", "protein-bar", "rugelach",
        "sacha-inchi-seed", "seaweed-snack", "sports-drink", "tamarind-drink", "tiger-nut",
        "old-bay-seasoning",
    }
    snack_remove = {item["id"] for item in items if item["category"] == "Snacks"}
    snack_remove |= remove_niche
    # Keep string-cheese as dairy — move if present in snacks
    string_cheese = find_item(items, "string-cheese")
    if string_cheese and string_cheese["category"] == "Snacks":
        string_cheese["category"] = "Dairy & Eggs"
        snack_remove.discard("string-cheese")
    items = remove_items(items, snack_remove)
    report["removed"].extend(sorted(snack_remove))

    # ------------------------------------------------------------------ #
    # 10. Sort and dedupe aliases
    # ------------------------------------------------------------------ #
    seen_ids: set[str] = set()
    deduped: list[dict] = []
    for item in sorted(items, key=lambda x: x["id"]):
        if item["id"] in seen_ids:
            continue
        seen_ids.add(item["id"])
        item["aliases"] = sorted(set(item.get("aliases", [])), key=str.lower)
        deduped.append(item)

    return deduped, report


def main() -> None:
    with open(CATALOG_PATH) as f:
        original = json.load(f)

    updated, report = apply_migration(original)

    with open(CATALOG_PATH, "w") as f:
        json.dump(updated, f, indent=2)
        f.write("\n")

    print(f"Catalog migration complete: {len(original)} → {len(updated)} entries")
    print(f"  Removed: {len(report['removed'])}")
    print(f"  Added:   {len(report['added'])}")
    print(f"  Merged:  {len(report['merged'])}")
    print(f"  Renamed: {report['renamed']}")


if __name__ == "__main__":
    main()
