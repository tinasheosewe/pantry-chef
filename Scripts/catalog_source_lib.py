"""Shared helpers for catalog.source.json authoring and compilation."""
from __future__ import annotations

import copy
import json
from collections import defaultdict
from pathlib import Path
from typing import Any

from catalog_lib import CATALOG_PATH, items_by_id, normalize_lookup_key, parent_ids

SCRIPT_DIR = Path(__file__).resolve().parent
CATALOG_SOURCE_PATH = SCRIPT_DIR.parent / "PantryChef" / "Resources" / "catalog.source.json"

MERGE_KEYS = (
    "name",
    "category",
    "defaultUnit",
    "defaultQuantity",
    "defaultStorage",
    "aliases",
    "facets",
    "defaultSelections",
    "facetAliases",
    "freshnessByStorage",
)

NON_SHAREABLE_MULTI_PARENT_IDS = {
    "breast",
    "thigh",
    "wing",
    "drumstick",
    "leg",
    "loin",
    "shoulder",
    "shank",
    "chop",
    "rib",
    "tenderloin",
    "fillet",
    "neck",
    "belly",
    "ground",
    "whole",
    "roast",
    "steak",
    "brisket",
}

MODIFIER_MULTI_PARENT_IDS = {
    "2",
    "berry",
    "black",
    "chinese",
    "classic",
    "cultured",
    "dark",
    "diet",
    "double",
    "flavored",
    "gluten-free",
    "golden",
    "green",
    "herbal",
    "hot",
    "instant",
    "japanese",
    "light",
    "medium",
    "orange",
    "organic",
    "original",
    "plain",
    "purple",
    "red",
    "refined",
    "regular",
    "skim",
    "smoky",
    "sour",
    "sourdough",
    "spicy",
    "standard",
    "sweet",
    "unrefined",
    "unsweetened",
    "vegan",
    "white",
    "wild",
    "yellow",
    "zero",
}

PRIMARY_PARENT_PREFERENCE: dict[str, str] = {
    "almond": "nut",
    "almond-flour": "flour",
    "almond-oil": "oil",
    "almond-non-dairy-milk": "non-dairy-milk",
    "beef-broth": "broth",
    "turkey-broth": "broth",
    "mushroom-broth": "broth",
    "grapeseed-oil": "oil",
    "baguette": "bread",
    "blue-cheese": "cheese",
    "all-purpose": "flour",
    "cake-flour": "flour",
    "rice-flour": "flour",
    "rye-flour": "flour",
    "spelt-flour": "flour",
    "american": "cheese",
    "alfredo": "pasta-sauce",
    "banana": "plantain",
}

TRUE_MULTI_INHERITANCE: dict[str, list[str]] = {
    "tomato-sauce": ["sauce", "tomato"],
    "tomato-paste": ["paste", "tomato"],
    "ketchup": ["sauce", "tomato"],
    "pasta-sauce": ["sauce", "tomato"],
    "pizza-sauce": ["sauce", "tomato"],
    "marinara": ["sauce", "tomato"],
    "soy-sauce": ["sauce", "soy"],
    "fish-sauce": ["sauce", "fish"],
    "oyster-sauce": ["sauce", "oyster"],
    "hoisin-sauce": ["sauce", "hoisin"],
    "worcestershire-sauce": ["sauce", "worcestershire"],
    "barbecue-sauce": ["sauce", "barbecue"],
    "hot-sauce": ["sauce", "chili-pepper"],
    "enchilada-sauce": ["sauce", "enchilada"],
    "teriyaki-sauce": ["sauce", "soy"],
    "chili-sauce": ["sauce", "chili-pepper"],
    "black-bean-sauce": ["sauce", "black-bean"],
    "peanut-sauce": ["sauce", "peanut"],
    "duck-sauce": ["sauce", "plum"],
    "plum-sauce": ["sauce", "plum"],
    "sweet-and-sour-sauce": ["sauce", "vinegar"],
    "cocktail-sauce": ["ketchup", "sauce"],
    "tartar-sauce": ["mayonnaise", "sauce"],
    "applesauce": ["apple", "sauce"],
    "chicken-broth": ["broth", "chicken"],
    "beef-stock": ["broth", "beef"],
    "vegetable-broth": ["broth", "vegetable"],
    "coconut-milk": ["coconut", "non-dairy-milk"],
    "oat-milk": ["non-dairy-milk", "oats"],
    "soy-milk": ["non-dairy-milk", "soy"],
}

# Correct metadata for items corrupted by shared-node splitting.
POST_REPAIR_FIXES: dict[str, dict[str, Any]] = {
    "sweet-potato": {
        "parentIds": ["potato"],
        "name": "sweet potato",
        "category": "Produce",
        "defaultUnit": "lb",
        "defaultQuantity": 1.0,
        "defaultStorage": "Pantry",
        "aliases": ["sweet potatoes", "sweet potato", "yam", "yams"],
        "defaultSelections": [],
        "freshnessByStorage": {"Pantry": [7, 14], "Refrigerated": [14, 21]},
    },
    "onion-red": {
        "name": "red onion",
        "aliases": ["red onion", "red onions", "onion red"],
    },
    "onion-yellow": {
        "name": "yellow onion",
        "aliases": ["yellow onion", "yellow onions", "onion yellow"],
    },
    "beef-ground": {
        "name": "ground beef",
        "aliases": ["ground beef", "ground hamburger", "minced beef", "beef ground"],
    },
    "greek": {
        "name": "Greek yogurt",
        "aliases": ["greek yogurt", "greek yoghurt"],
    },
    "all-purpose": {
        "name": "all-purpose flour",
        "aliases": ["all purpose flour", "all-purpose flour", "ap flour", "plain flour"],
    },
    "whole-wheat": {
        "name": "whole wheat flour",
        "aliases": ["whole wheat flour", "whole-wheat flour"],
    },
    "flour": {
        "aliases": ["flours"],
    },
    "beef": {
        "aliases": ["beef"],
    },
    "beef-bouillon": {
        "name": "beef bouillon",
        "aliases": [
            "beef bouillon",
            "beef bouillon cube",
            "beef bouillon granule",
            "beef bouillon powder",
            "beef demi-glace",
            "bouillon cubes",
            "bouillon granules",
            "broth cube",
            "broth cubes",
            "stock cube",
            "stock cubes",
        ],
    },
    "beef-protein-powder": {
        "name": "beef protein powder",
        "aliases": ["beef protein powder", "beef protein"],
    },
    "beef-meatball": {
        "name": "beef meatball",
        "aliases": ["beef meatball", "beef meatballs", "frozen beef meatball", "frozen beef meatballs"],
    },
    "velveeta": {
        "aliases": ["velveeta cheese", "velveeta"],
    },
    "romano": {
        "name": "pecorino romano",
        "aliases": ["pecorino", "pecorino cheese", "pecorino romano", "romano", "romano cheese"],
    },
    "jasmine": {
        "name": "jasmine rice",
        "aliases": ["jasmine rice"],
    },
    "stew-meat": {
        "name": "stew meat",
        "aliases": ["beef stew meat", "stew meat", "stewing beef"],
    },
    "beef-shank": {
        "name": "beef shank",
        "aliases": ["beef shank", "beef shanks"],
    },
}

MISSING_ROOTS: dict[str, dict[str, Any]] = {
    "sauce": {
        "id": "sauce",
        "name": "sauce",
        "category": "Condiments & Sauces",
        "defaultUnit": "cup",
        "defaultQuantity": 1.0,
        "defaultStorage": "Pantry",
        "aliases": ["sauces"],
        "facets": [
            {"key": "texture", "options": ["smooth", "chunky", "thick", "thin"]},
            {"key": "preservation", "options": ["fresh", "canned", "jarred", "refrigerated"]},
        ],
        "defaultSelections": [],
        "freshnessByStorage": {"Pantry": [180, 365], "Refrigerated": [7, 14]},
    },
    "paste": {
        "id": "paste",
        "name": "paste",
        "category": "Condiments & Sauces",
        "defaultUnit": "tbsp",
        "defaultQuantity": 1.0,
        "defaultStorage": "Pantry",
        "aliases": ["pastes"],
        "facets": [{"key": "form", "options": ["tube", "jar", "can"]}],
        "defaultSelections": [],
        "freshnessByStorage": {"Pantry": [180, 365], "Refrigerated": [30, 60]},
    },
    "puree": {
        "id": "puree",
        "name": "purée",
        "category": "Canned & Jarred",
        "defaultUnit": "cup",
        "defaultQuantity": 1.0,
        "defaultStorage": "Pantry",
        "aliases": ["puree", "purée"],
        "facets": [{"key": "texture", "options": ["smooth", "chunky"]}],
        "defaultSelections": [],
        "freshnessByStorage": {"Pantry": [365, 730], "Refrigerated": [5, 7]},
    },
}


def load_source() -> dict[str, Any]:
    with open(CATALOG_SOURCE_PATH, encoding="utf-8") as f:
        return json.load(f)


def save_source(source: dict[str, Any]) -> None:
    with open(CATALOG_SOURCE_PATH, "w", encoding="utf-8") as f:
        json.dump(source, f, indent=2, ensure_ascii=False)
        f.write("\n")


def _facet_map(facets: list[dict] | None) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for facet in facets or []:
        key = facet.get("key")
        if key:
            result[key] = list(facet.get("options", []))
    return result


def _merge_facets(parent: list[dict] | None, child: list[dict] | None) -> list[dict]:
    merged = _facet_map(parent)
    for key, options in _facet_map(child).items():
        existing = set(merged.get(key, []))
        merged[key] = list(existing.union(options))
    return [{"key": key, "options": sorted(values)} for key, values in sorted(merged.items())]


def merge_nodes(parent: dict[str, Any], child: dict[str, Any]) -> dict[str, Any]:
    merged = copy.deepcopy(parent)
    merged.pop("children", None)
    merged.pop("parentIds", None)
    for key in MERGE_KEYS:
        if key == "facets":
            merged["facets"] = _merge_facets(parent.get("facets"), child.get("facets"))
        elif key == "aliases":
            merged["aliases"] = sorted(
                set(parent.get("aliases", [])).union(child.get("aliases", []))
            )
        elif key in child:
            merged[key] = copy.deepcopy(child[key])
    merged["id"] = child["id"]
    if "name" in child:
        merged["name"] = child["name"]
    return merged


def sparse_child(parent: dict[str, Any], full_child: dict[str, Any]) -> dict[str, Any]:
    sparse: dict[str, Any] = {"id": full_child["id"]}
    parent_merged = merge_nodes(parent, {"id": parent["id"], "name": parent.get("name", parent["id"])})
    for key in MERGE_KEYS:
        if key not in full_child:
            continue
        if key == "facets":
            if _facet_map(full_child.get("facets")) != _facet_map(parent_merged.get("facets")):
                sparse["facets"] = copy.deepcopy(full_child["facets"])
        elif key == "aliases":
            child_aliases = [a for a in full_child.get("aliases", []) if a]
            parent_aliases = set(parent_merged.get("aliases", []))
            extra = [a for a in child_aliases if a not in parent_aliases]
            if extra:
                sparse["aliases"] = extra
        elif full_child.get(key) != parent_merged.get(key):
            sparse[key] = copy.deepcopy(full_child[key])
    if full_child.get("name") and full_child["name"] != parent_merged.get("name"):
        sparse["name"] = full_child["name"]
    if full_child.get("children"):
        sparse["children"] = full_child["children"]
    return sparse


def _emit_tree_node(
    node: dict[str, Any],
    parent_id: str | None,
    emitted: dict[str, dict[str, Any]],
    parent_full: dict[str, Any] | None,
) -> None:
    if parent_full:
        full = merge_nodes(parent_full, node)
    else:
        full = copy.deepcopy(node)
    full.pop("children", None)
    if parent_id:
        full["parentIds"] = [parent_id]
    else:
        full.pop("parentIds", None)
    item_id = full["id"]
    if item_id in emitted:
        raise ValueError(f"Duplicate catalog id while compiling trees: {item_id!r}")
    emitted[item_id] = full
    for child in node.get("children", []):
        _emit_tree_node(child, item_id, emitted, full)


def _emit_multi_item(
    node: dict[str, Any],
    emitted: dict[str, dict[str, Any]],
    inherited_parent: dict[str, Any] | None = None,
) -> None:
    item = copy.deepcopy(node)
    item.pop("children", None)
    if inherited_parent is None:
        parents = item.get("parentIds", [])
        if len(parents) < 2:
            raise ValueError(f"multiInheritance item {item['id']!r} requires parentIds length >= 2")
    else:
        item = merge_nodes(inherited_parent, item)
        item["parentIds"] = [inherited_parent["id"]]
    item_id = item["id"]
    if item_id in emitted:
        raise ValueError(f"Duplicate catalog id while compiling multiInheritance: {item_id!r}")
    emitted[item_id] = item
    for child in node.get("children", []):
        _emit_multi_item(child, emitted, item)


def compile_source(source: dict[str, Any]) -> list[dict]:
    emitted: dict[str, dict[str, Any]] = {}
    for root in source.get("trees", []):
        _emit_tree_node(root, None, emitted, None)
    for group in source.get("multiInheritance", []):
        for item in group.get("items", []):
            _emit_multi_item(item, emitted)
    compiled = list(emitted.values())
    compiled.sort(key=lambda item: item["id"])
    return compiled


def _choose_primary_parent(item_id: str, parents: list[str], by_id: dict[str, dict]) -> str:
    if item_id in PRIMARY_PARENT_PREFERENCE:
        preferred = PRIMARY_PARENT_PREFERENCE[item_id]
        if preferred in parents and preferred in by_id:
            return preferred
    # Prefer parent whose name/id appears in child id or name
    item = by_id[item_id]
    name_key = normalize_lookup_key(item.get("name", item_id))
    id_key = normalize_lookup_key(item_id.replace("-", " "))
    best = parents[0]
    best_score = -1
    for parent_id in parents:
        parent = by_id.get(parent_id, {})
        parent_name = normalize_lookup_key(parent.get("name", parent_id))
        score = 0
        if parent_id in item_id:
            score += 3
        if parent_name and parent_name in id_key:
            score += 2
        if parent_name and parent_name in name_key:
            score += 2
        if parent.get("category") == item.get("category"):
            score += 1
        if score > best_score:
            best_score = score
            best = parent_id
    return best


def split_shared_node(item: dict, by_id: dict[str, dict]) -> list[dict]:
    item_id = item["id"]
    parents = parent_ids(item)
    created: list[dict] = []
    for parent_id in parents:
        parent = by_id.get(parent_id)
        if not parent:
            continue
        new_id = f"{parent_id}-{item_id}"
        if new_id in by_id:
            continue
        node = copy.deepcopy(item)
        node["id"] = new_id
        pname = parent.get("name", parent_id).strip()
        node["name"] = f"{pname} {item['name']}".strip()
        node["category"] = parent.get("category", node.get("category"))
        node["parentIds"] = [parent_id]
        aliases = set(node.get("aliases", []))
        aliases.add(f"{pname} {item['name']}")
        node["aliases"] = sorted(a for a in aliases if a)
        created.append(node)
    return created


def apply_post_repair_fixes(items: list[dict]) -> tuple[list[dict], int]:
    by_id = items_by_id(items)
    fixes_applied = 0
    for item in items:
        patch = POST_REPAIR_FIXES.get(item["id"])
        if not patch:
            continue
        for key, value in patch.items():
            item[key] = copy.deepcopy(value)
        fixes_applied += 1

    flour_noise = {"plain flour", "ap flour", "flours", "all purpose flour", "all-purpose flour"}
    beef_noise_prefixes = ("beef bouillon", "beef broth", "beef base", "beef bone", "armour beef", "barbecue beef")
    for item in items:
        parents = parent_ids(item)
        if parents == ["flour"] and item["id"] != "all-purpose":
            cleaned = [alias for alias in item.get("aliases", []) if alias not in flour_noise]
            if cleaned != item.get("aliases", []):
                item["aliases"] = cleaned
                fixes_applied += 1
        if parents == ["beef"] and item["id"] not in POST_REPAIR_FIXES:
            name_tokens = {
                token
                for token in normalize_lookup_key(item.get("name", item["id"]).replace("-", " ")).split()
                if len(token) > 2
            }
            id_tokens = {
                token
                for token in normalize_lookup_key(item["id"].replace("-", " ")).split()
                if len(token) > 2
            }
            keep_tokens = name_tokens.union(id_tokens)
            cleaned = [
                alias
                for alias in item.get("aliases", [])
                if any(token in normalize_lookup_key(alias) for token in keep_tokens)
                and not any(alias.startswith(prefix) for prefix in beef_noise_prefixes)
            ]
            if cleaned != item.get("aliases", []):
                item["aliases"] = cleaned
                fixes_applied += 1
        if parents == ["cheese"] and item["id"] not in POST_REPAIR_FIXES:
            name_tokens = {
                token
                for token in normalize_lookup_key(item.get("name", item["id"]).replace("-", " ")).split()
                if len(token) > 3
            }
            cleaned = [
                alias
                for alias in item.get("aliases", [])
                if not alias.endswith(" cheese") or any(token in normalize_lookup_key(alias) for token in name_tokens)
            ]
            if "pecorino" in normalize_lookup_key(item["id"]) or "pecorino" in normalize_lookup_key(item.get("name", "")):
                cleaned = list(dict.fromkeys(cleaned + ["pecorino", "pecorino cheese", "pecorino romano"]))
            if cleaned != item.get("aliases", []):
                item["aliases"] = cleaned
                fixes_applied += 1
    return items, fixes_applied


def repair_flat_catalog(items: list[dict]) -> tuple[list[dict], dict[str, int]]:
    stats: dict[str, int] = defaultdict(int)
    by_id = items_by_id(items)
    for root_id, root in MISSING_ROOTS.items():
        if root_id not in by_id:
            items.append(copy.deepcopy(root))
            by_id[root_id] = root
            stats["roots_added"] += 1

    # Remove invalid shared nodes and split them
    remove_ids: set[str] = set()
    remove_ids.update(
        iid
        for iid, item in by_id.items()
        if iid in MODIFIER_MULTI_PARENT_IDS and len(parent_ids(item)) > 1
    )
    remove_ids.update(
        iid
        for iid, item in by_id.items()
        if iid in NON_SHAREABLE_MULTI_PARENT_IDS and len(parent_ids(item)) > 1
    )

    new_items: list[dict] = []
    for item in items:
        iid = item["id"]
        if iid in remove_ids:
            for created in split_shared_node(item, by_id):
                new_items.append(created)
                by_id[created["id"]] = created
                stats["shared_nodes_split"] += 1
            stats["shared_nodes_removed"] += 1
            continue
        new_items.append(item)

    items = new_items
    by_id = items_by_id(items)

    # Apply true multi-inheritance and reduce accidental multi-parent
    for item in items:
        iid = item["id"]
        parents = parent_ids(item)
        if iid in TRUE_MULTI_INHERITANCE:
            wanted = [p for p in TRUE_MULTI_INHERITANCE[iid] if p in by_id]
            if len(wanted) >= 2:
                item["parentIds"] = sorted(set(wanted))
                stats["true_multi_assigned"] += 1
            continue
        if len(parents) <= 1:
            continue
        if iid in TRUE_MULTI_INHERITANCE.values():
            continue
        primary = _choose_primary_parent(iid, parents, by_id)
        item["parentIds"] = [primary]
        stats["multi_parent_reduced"] += 1

    # Ensure common homonym products have a parent link
    homonym_parent_fixes = {
        "almond-oil": "oil",
        "almond-flour": "flour",
        "almond": "nut",
        "coconut-oil": "oil",
        "peanut-oil": "oil",
        "sesame-oil": "oil",
        "olive-oil": "oil",
        "vegetable-oil": "oil",
        "canola-oil": "oil",
        "sunflower-oil": "oil",
        "walnut-oil": "oil",
    }
    by_id = items_by_id(items)
    for item_id, parent_id in homonym_parent_fixes.items():
        item = by_id.get(item_id)
        if not item or parent_id not in by_id:
            continue
        if not parent_ids(item):
            item["parentIds"] = [parent_id]
            stats["missing_parent_added"] += 1

    # Fix unsupported units
    for item in items:
        if item.get("defaultUnit") == "box":
            item["defaultUnit"] = "pkg"
            stats["unit_fixed"] += 1

    # Strip invalid parent links
    valid_ids = {item["id"] for item in items}
    for item in items:
        parents = [p for p in parent_ids(item) if p in valid_ids and p != item["id"]]
        if parents != parent_ids(item):
            stats["invalid_parent_links_removed"] += 1
        if parents:
            item["parentIds"] = sorted(set(parents))
        else:
            item.pop("parentIds", None)

    items.sort(key=lambda x: x["id"])
    items, post_fixes = apply_post_repair_fixes(items)
    if post_fixes:
        stats["post_repair_fixes"] = post_fixes
    return items, dict(stats)


def _build_subtree(item: dict[str, Any], items: list[dict], multi_ids: set[str]) -> dict[str, Any]:
    node = copy.deepcopy(item)
    node.pop("parentIds", None)
    children = [
        child
        for child in items
        if parent_ids(child) == [item["id"]] and child["id"] not in multi_ids
    ]
    if children:
        node["children"] = []
        for child in sorted(children, key=lambda x: x["id"]):
            child_subtree = _build_subtree(child, items, multi_ids)
            node["children"].append(sparse_child(node, child_subtree))
    else:
        node.pop("children", None)
    return node


def flat_to_source(items: list[dict]) -> dict[str, Any]:
    multi_ids = {item["id"] for item in items if len(parent_ids(item)) >= 2}
    roots = [
        item
        for item in items
        if not parent_ids(item) and item["id"] not in multi_ids
    ]
    trees = [_build_subtree(root, items, multi_ids) for root in sorted(roots, key=lambda x: x["id"])]

    grouped: dict[str, list[dict]] = defaultdict(list)
    for item in items:
        if item["id"] not in multi_ids:
            continue
        node = copy.deepcopy(item)
        children = [
            child
            for child in items
            if parent_ids(child) == [item["id"]] and child["id"] not in multi_ids
        ]
        if children:
            node["children"] = [
                sparse_child(node, _build_subtree(child, items, multi_ids))
                for child in sorted(children, key=lambda x: x["id"])
            ]
        grouped[_infer_group(item)].append(node)

    multi = [
        {"group": group, "items": sorted(group_items, key=lambda x: x["id"])}
        for group, group_items in sorted(grouped.items())
    ]
    return {"trees": trees, "multiInheritance": multi}


def _infer_group(item: dict[str, Any]) -> str:
    category = item.get("category", "Other")
    name = item.get("name", item.get("id", ""))
    if "sauce" in item["id"] or "sauce" in name.lower():
        return "Sauces & condiments"
    if "broth" in item["id"] or "stock" in item["id"]:
        return "Broths & stocks"
    if "milk" in item["id"]:
        return "Milks & dairy alternatives"
    if "butter" in item["id"]:
        return "Nut butters & spreads"
    if "paste" in item["id"]:
        return "Pastes"
    return category
