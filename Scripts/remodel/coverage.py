#!/usr/bin/env python3
"""Stage C: canonical-staple repair + coverage additions.

Fixes core staples whose canonical id was occupied by a derived product
(olive-oil -> "olive oil cooking spray", lemon -> "lemon cucumber"), preserves
the displaced products as their own items, backfills recipe-term aliases, and
adds commonly-missing staples.

  python3 remodel/coverage.py          # report
  python3 remodel/coverage.py --apply  # rewrite catalog.json + catalog.source.json
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR.parent))

from catalog_lib import load_catalog, normalize_lookup_key, save_catalog  # noqa: E402
from catalog_source_lib import flat_to_source, save_source  # noqa: E402

# id -> patch. "name"/"category"/"parentIds" overwrite; "aliases" are added (union).
CANONICAL_FIXES: dict[str, dict] = {
    "olive-oil": {"name": "olive oil", "category": "Oils & Fats", "parentIds": ["oil"],
                  "aliases": ["olive oils", "extra virgin olive oil", "evoo", "virgin olive oil"]},
    "honey": {"name": "honey", "category": "Baking & Sweeteners", "parentIds": [],
              "aliases": ["raw honey", "honeys", "clover honey"]},
    "tofu": {"name": "tofu", "category": "Protein", "parentIds": [],
             "aliases": ["bean curd", "firm tofu", "silken tofu", "soft tofu", "extra firm tofu"]},
    "tuna": {"name": "tuna", "category": "Protein", "parentIds": ["oily-fish"],
             "aliases": ["canned tuna", "tuna steak", "ahi tuna", "albacore", "tuna fish"]},
    "bacon": {"name": "bacon", "category": "Protein", "parentIds": ["cured-meat"],
              "aliases": ["bacon strips", "smoked bacon", "streaky bacon", "bacon rashers"]},
    "mustard": {"name": "mustard", "category": "Condiments & Sauces", "parentIds": ["sauce"],
                "aliases": ["yellow mustard", "prepared mustard", "mustards"]},
    "vanilla": {"name": "vanilla extract", "category": "Baking & Sweeteners", "parentIds": [],
                "aliases": ["vanilla", "pure vanilla extract", "vanilla essence"]},
    "almond": {"name": "almond", "category": "Nuts & Seeds", "parentIds": ["nut"],
               "aliases": ["almonds", "raw almonds", "sliced almonds", "whole almonds"]},
    "walnut": {"name": "walnut", "category": "Nuts & Seeds", "parentIds": ["nut"],
               "aliases": ["walnuts", "walnut halves", "chopped walnuts"]},
    "shallot": {"name": "shallot", "category": "Produce", "parentIds": ["onion"],
                "aliases": ["shallots", "french shallot", "eschalot"]},
    "zucchini": {"name": "zucchini", "category": "Produce", "parentIds": ["squash"],
                 "aliases": ["zucchinis", "courgette", "courgettes"]},
    "pumpkin": {"name": "pumpkin", "category": "Produce", "parentIds": ["squash"],
                "aliases": ["pumpkins", "sugar pumpkin", "pie pumpkin"]},
    "panko": {"name": "panko", "category": "Breads & Bakery", "parentIds": ["breadcrumb"],
              "aliases": ["panko breadcrumbs", "panko bread crumbs", "japanese breadcrumbs"]},
    "sriracha": {"name": "sriracha", "category": "Condiments & Sauces", "parentIds": ["chili-sauce"],
                 "aliases": ["sriracha sauce", "rooster sauce"]},
    "tortilla": {"name": "tortilla", "category": "Breads & Bakery", "parentIds": ["flatbread"],
                 "aliases": ["tortillas", "flour tortilla", "corn tortilla", "wraps", "soft taco"]},
    "lemon": {"name": "lemon", "category": "Produce", "parentIds": [],
              "aliases": ["lemons", "fresh lemon", "whole lemon"]},
    "banana": {"name": "banana", "category": "Produce", "parentIds": [],
               "aliases": ["bananas", "ripe banana", "cavendish banana"]},
    "salmon-oily-fish": {"name": "salmon", "category": "Protein", "parentIds": ["oily-fish"],
                         "aliases": ["salmon fillet", "atlantic salmon", "fresh salmon", "salmon fillets"]},
    "1": {"name": "1% milk", "aliases": ["one percent milk", "1 percent milk", "lowfat milk"]},
    "t-bone": {"name": "t-bone steak", "aliases": ["t bone steak", "tbone steak", "porterhouse"]},
}

# Cross-regional synonym groups, migrated out of app code (was
# PantryCatalog.universalSynonyms) into catalog aliases. Each non-canonical term is
# added as an alias of the group's canonical item; hygiene later strips any term
# that collides with a different item's name, so equivalences between distinct
# items (shrimp/prawn) are handled by substitutions rather than aliasing.
SYNONYM_GROUPS: list[list[str]] = [
    ["green onion", "scallion", "spring onion"],
    ["shallot", "french shallot"],
    ["bell pepper", "capsicum", "sweet pepper"],
    ["chili pepper", "chilli", "chile", "hot pepper"],
    ["jalapeno", "jalapeño"],
    ["cilantro", "coriander", "coriander leaf"],
    ["parsley", "flat leaf parsley", "italian parsley"],
    ["cornstarch", "corn starch", "corn flour"],
    ["potato starch", "potato flour"],
    ["heavy cream", "whipping cream", "double cream"],
    ["sour cream", "crème fraîche"],
    ["greek yogurt", "greek yoghurt", "strained yogurt"],
    ["all purpose flour", "plain flour", "ap flour"],
    ["bread flour", "strong flour"],
    ["olive oil", "extra virgin olive oil", "evoo"],
    ["soy sauce", "shoyu"],
    ["fish sauce", "nam pla"],
    ["granulated sugar", "white sugar"],
    ["brown sugar", "dark brown sugar", "light brown sugar"],
    ["powdered sugar", "confectioner sugar", "icing sugar"],
    ["eggplant", "aubergine"],
    ["zucchini", "courgette"],
    ["arugula", "rocket"],
    ["beet", "beetroot"],
    ["baking soda", "bicarbonate of soda", "bicarb"],
    ["baking powder", "raising agent"],
    ["cream cheese", "neufchatel"],
    ["chickpea", "garbanzo"],
]

# Reparent items (id -> new single parent id). Used to fix mis-parented cuts, e.g.
# chicken cuts hung under the "chicken meatball" item instead of chicken-the-meat.
REPARENT: dict[str, str] = {
    "chicken-breast": "chicken-meat",
    "chicken-thigh": "chicken-meat",
    "chicken-drumstick": "chicken-meat",
    "chicken-wing": "chicken-meat",
    "chicken-neck": "chicken-meat",
    "chicken-whole": "chicken-meat",
    "chicken-ground": "chicken-meat",
    "chicken-liver": "chicken-meat",
}

# Aliases to remove from items (because a canonical fix now owns that term).
ALIAS_REMOVE: dict[str, list[str]] = {
    "salmon": ["salmon"],  # the furikake item must not own "salmon"
}

# Recipe-term aliases to add to already-correct items.
ALIAS_ADD: dict[str, list[str]] = {
    "parmesan": ["parmesan", "parmigiano", "parmigiano reggiano", "grated parmesan", "parmesan cheese"],
    "mozzarella": ["mozzarella", "fresh mozzarella", "mozzarella cheese"],
    "cheddar": ["cheddar", "sharp cheddar", "cheddar cheese"],
    "feta": ["feta", "feta cheese"],
    "parmesan-reggiano": [],
    "beef-ground": ["ground beef", "minced beef", "hamburger meat", "ground chuck"],
    "yogurt": ["plain yogurt", "yoghurt"],
    "peppercorn": ["black pepper", "ground black pepper", "cracked black pepper",
                   "freshly ground black pepper", "fresh ground black pepper",
                   "black peppercorn", "ground pepper"],
    "baguette": ["baguette", "french bread", "french baguette"],
    "sweet-potato": ["sweet potatoes", "yam", "yams"],
}

# Bad facetAliases to delete (cross-ingredient confusions from polluted baseline
# aliases that the collapse turned into facetAliases).
FACET_ALIAS_REMOVE: dict[str, list[str]] = {
    "cardamom": ["black pepper"],
}

# Facet (key, value) options to remove from an item — used to promote a value back
# to its own row (e.g. greek yogurt earns a dedicated row, not a yogurt variant).
FACET_VALUE_REMOVE: dict[str, list[tuple[str, str]]] = {
    "yogurt": [("variant", "greek")],
}

# Products displaced from a canonical id -> re-added under a clean new id.
DISPLACED_NEW: list[dict] = [
    {"id": "olive-oil-spray", "name": "olive oil cooking spray", "category": "Oils & Fats",
     "parentIds": ["cooking-spray"], "aliases": ["olive oil spray"]},
    {"id": "lemon-cucumber", "name": "lemon cucumber", "category": "Produce",
     "parentIds": ["cucumber"], "aliases": ["lemon cucumbers"]},
    {"id": "banana-pepper", "name": "banana pepper", "category": "Produce",
     "parentIds": ["pepper"], "aliases": ["banana peppers"]},
    {"id": "honey-glaze", "name": "honey glaze", "category": "Condiments & Sauces",
     "parentIds": ["sauce"], "aliases": []},
]

# Commonly-missing staples (id : name, category, [aliases], parent?, unit, storage).
STAPLE_NEW: list[dict] = [
    ("black-beans", "black beans", "Legumes & Beans", ["black bean", "turtle beans"], "beans", "cup", "Pantry"),
    ("chocolate-chips", "chocolate chips", "Baking & Sweeteners",
     ["chocolate chip", "choc chips", "semisweet chocolate chips", "chocolate morsels"], None, "cup", "Pantry"),
    ("greek-yogurt", "Greek yogurt", "Dairy & Eggs",
     ["greek yoghurt", "strained yogurt", "greek"], "yogurt", "cup", "Refrigerated"),
    ("dijon-mustard", "Dijon mustard", "Condiments & Sauces", ["dijon", "grey poupon"], "mustard", "tbsp", "Refrigerated"),
    ("cod", "cod", "Protein", ["cod fillet", "cod fish", "atlantic cod", "pacific cod"], "white-fish", "lb", "Refrigerated"),
    ("chicken-meat", "chicken", "Protein", ["whole chicken", "chicken meat", "raw chicken", "chicken pieces"], None, "lb", "Refrigerated"),
    ("powdered-sugar", "powdered sugar", "Baking & Sweeteners",
     ["confectioners sugar", "icing sugar", "10x sugar"], "sugar", "cup", "Pantry"),
    ("light-brown-sugar", "light brown sugar", "Baking & Sweeteners", ["brown sugar"], "sugar", "cup", "Pantry"),
    ("baking-chocolate", "baking chocolate", "Baking & Sweeteners",
     ["unsweetened chocolate", "dark chocolate", "bittersweet chocolate"], None, "oz", "Pantry"),
    ("coconut-flakes", "coconut flakes", "Baking & Sweeteners",
     ["shredded coconut", "desiccated coconut", "coconut shreds"], None, "cup", "Pantry"),
    ("cream-of-tartar", "cream of tartar", "Baking & Sweeteners", ["cream of tartar"], None, "tsp", "Pantry"),
    ("cooking-spray", "cooking spray", "Oils & Fats", ["nonstick spray", "pan spray"], None, "splash", "Pantry"),
    ("club-soda", "club soda", "Beverages", ["soda water", "sparkling water", "seltzer"], None, "fl oz", "Refrigerated"),
    ("chicken-stock", "chicken stock", "Canned & Jarred", ["chicken broth", "chicken bouillon"], "broth", "cup", "Pantry"),
    ("vegetable-stock", "vegetable stock", "Canned & Jarred", ["vegetable broth", "veggie broth"], "broth", "cup", "Pantry"),
]

DEFAULT_FRESH = {"Pantry": [180, 365], "Refrigerated": [7, 21], "Frozen": [90, 365]}


def make_item(iid, name, cat, aliases, parent, unit, storage) -> dict:
    item = {
        "id": iid, "name": name, "category": cat, "defaultStorage": storage,
        "defaultUnit": unit, "defaultQuantity": 1.0, "aliases": aliases,
        "facets": [], "defaultSelections": [],
        "freshnessByStorage": {storage: DEFAULT_FRESH.get(storage, [7, 30])},
    }
    if parent:
        item["parentIds"] = [parent]
    return item


def run(apply: bool) -> int:
    cat = load_catalog()
    by_id = {x["id"]: x for x in cat}
    stats = {"canonical_fixed": 0, "alias_added": 0, "alias_removed": 0,
             "displaced_added": 0, "staples_added": 0, "skipped_existing": 0}

    for iid, patch in CANONICAL_FIXES.items():
        item = by_id.get(iid)
        if not item:
            continue
        for k, v in patch.items():
            if k == "aliases":
                cur = item.setdefault("aliases", [])
                for a in v:
                    if a not in cur:
                        cur.append(a)
            elif k == "parentIds":
                if all(p in by_id for p in v):
                    item["parentIds"] = v
                elif not v:
                    item.pop("parentIds", None)
            else:
                item[k] = v
        stats["canonical_fixed"] += 1

    for iid, aliases in ALIAS_ADD.items():
        item = by_id.get(iid)
        if not item:
            continue
        cur = item.setdefault("aliases", [])
        for a in aliases:
            if a not in cur:
                cur.append(a)
                stats["alias_added"] += 1

    for iid, aliases in ALIAS_REMOVE.items():
        item = by_id.get(iid)
        if not item:
            continue
        rm = {a.lower() for a in aliases}
        before = len(item.get("aliases", []))
        item["aliases"] = [a for a in item.get("aliases", []) if a.lower() not in rm]
        stats["alias_removed"] += before - len(item["aliases"])

    for iid, texts in FACET_ALIAS_REMOVE.items():
        item = by_id.get(iid)
        if not item or not item.get("facetAliases"):
            continue
        rm = {t.lower() for t in texts}
        before = len(item["facetAliases"])
        item["facetAliases"] = [e for e in item["facetAliases"] if e["text"].lower() not in rm]
        stats["facet_alias_removed"] = stats.get("facet_alias_removed", 0) + before - len(item["facetAliases"])

    for iid, pairs in FACET_VALUE_REMOVE.items():
        item = by_id.get(iid)
        if not item:
            continue
        rm = {(k, v) for k, v in pairs}
        for facet in item.get("facets", []):
            facet["options"] = [o for o in facet["options"] if (facet["key"], o) not in rm]
        item["facets"] = [f for f in item.get("facets", []) if f["options"]]
        if item.get("facetAliases"):
            item["facetAliases"] = [
                e for e in item["facetAliases"]
                if not any((s["key"], s["value"]) in rm for s in e.get("facets", []))
            ]
        item.setdefault("defaultSelections", [])
        item["defaultSelections"] = [s for s in item["defaultSelections"] if (s["key"], s["value"]) not in rm]
        stats["facet_value_removed"] = stats.get("facet_value_removed", 0) + 1

    for iid, name, c, aliases, parent, unit, storage in STAPLE_NEW:
        if iid in by_id:
            stats["skipped_existing"] += 1
            continue
        if parent and parent not in by_id:
            parent = None
        item = make_item(iid, name, c, aliases, parent, unit, storage)
        cat.append(item)
        by_id[iid] = item
        stats["staples_added"] += 1

    for spec in DISPLACED_NEW:
        if spec["id"] in by_id:
            stats["skipped_existing"] += 1
            continue
        item = dict(spec)
        item.setdefault("defaultStorage", "Pantry")
        item.setdefault("defaultUnit", "piece")
        item.setdefault("defaultQuantity", 1.0)
        item.setdefault("facets", [])
        item.setdefault("defaultSelections", [])
        item.setdefault("freshnessByStorage", {item["defaultStorage"]: DEFAULT_FRESH.get(item["defaultStorage"], [7, 30])})
        if item.get("parentIds") and not all(p in by_id for p in item["parentIds"]):
            item.pop("parentIds", None)
        cat.append(item)
        by_id[item["id"]] = item
        stats["displaced_added"] += 1

    for iid, new_parent in REPARENT.items():
        item = by_id.get(iid)
        if item and new_parent in by_id:
            item["parentIds"] = [new_parent]
            stats["reparented"] = stats.get("reparented", 0) + 1

    # Migrate cross-regional synonyms into catalog aliases.
    alias_index: dict[str, str] = {}
    for x in cat:
        alias_index.setdefault(normalize_lookup_key(x["name"]), x["id"])
        for a in (x.get("aliases") or []):
            alias_index.setdefault(normalize_lookup_key(a), x["id"])
    for group in SYNONYM_GROUPS:
        target = next((alias_index[normalize_lookup_key(t)] for t in group
                       if normalize_lookup_key(t) in alias_index), None)
        if not target:
            continue
        item = by_id[target]
        existing = {normalize_lookup_key(a) for a in (item.get("aliases") or [])}
        existing.add(normalize_lookup_key(item["name"]))
        for term in group:
            tk = normalize_lookup_key(term)
            # skip terms that already resolve elsewhere (distinct items handle their
            # own equivalence via substitutions); only fill genuine name gaps.
            if tk in existing or alias_index.get(tk) not in (None, target):
                continue
            item.setdefault("aliases", []).append(term)
            existing.add(tk)
            stats["synonym_aliases_added"] = stats.get("synonym_aliases_added", 0) + 1

    print("=== COVERAGE SUMMARY ===")
    for k, v in stats.items():
        print(f"  {k}: {v}")
    print(f"  total items now: {len(cat)}")

    if not apply:
        print("\n(dry run — pass --apply to write)")
        return 0
    save_catalog(cat)
    save_source(flat_to_source(cat))
    print(f"\nwrote catalog.json ({len(cat)} items) + catalog.source.json")
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    sys.exit(run(ap.parse_args().apply))
