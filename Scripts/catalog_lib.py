"""Shared helpers for catalog validation and migration scripts."""
from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
CATALOG_PATH = SCRIPT_DIR.parent / "PantryChef" / "Resources" / "catalog.json"
FAMILIES_PATH = SCRIPT_DIR.parent / "PantryChef" / "Resources" / "catalog_families.json"
ALIAS_CANDIDATES_PATH = SCRIPT_DIR / "triage_output" / "corpus_alias_candidates.json"

# Nuts & Seeds entries that are not edible nuts for generic `nut` matching.
NUT_FAMILY_EXCLUDE = {
    "chia-seed", "flax-seed", "hemp-seed", "sesame-seed", "sunflower-seed",
    "pumpkin-seed", "poppy-seed", "melon-seed", "lotus-seed", "nigella-seed",
    "egusi-seed", "watermelon-seed", "nut-butter", "corn-nut", "soy-nut", "nut",
}

# Maps specific catalog id → variant label on generic parent.
NUT_VARIANT_OVERRIDES = {
    "black-walnut": "black walnut",
    "pine-nut": "pine",
    "macadamia-nut": "macadamia",
    "brazil-nut": "brazil",
    "mixed-nuts": "mixed",
    "ginkgo-nut": "ginkgo",
    "hickory-nut": "hickory",
}

GENERIC_ONLY_BARE_ALIASES = {
    "nut": {"nut", "nuts", "ground nuts", "ground nut", "chopped nuts", "unsalted nuts"},
    "oil": {"oil", "oils", "neutral oil", "cooking oil", "salad oil", "liquid oil", "frying oil"},
}


def normalize_lookup_key(value: str) -> str:
    text = unicodedata.normalize("NFD", value.lower().strip())
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    text = text.replace("-", " ")
    text = re.sub(r"[^a-z0-9\s]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def load_catalog() -> list[dict]:
    with open(CATALOG_PATH, encoding="utf-8") as f:
        return json.load(f)


def save_catalog(items: list[dict]) -> None:
    items.sort(key=lambda x: x["id"])
    with open(CATALOG_PATH, "w", encoding="utf-8") as f:
        json.dump(items, f, indent=2, ensure_ascii=False)
        f.write("\n")


def load_families() -> dict:
    with open(FAMILIES_PATH, encoding="utf-8") as f:
        return json.load(f)


def save_families(data: dict) -> None:
    with open(FAMILIES_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def load_alias_candidates() -> dict:
    if not ALIAS_CANDIDATES_PATH.exists():
        return {}
    with open(ALIAS_CANDIDATES_PATH, encoding="utf-8") as f:
        return json.load(f)


def items_by_id(items: list[dict]) -> dict[str, dict]:
    return {item["id"]: item for item in items}


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


def add_aliases(item: dict, aliases: list[str]) -> list[str]:
    """Return list of aliases actually added."""
    current = item.setdefault("aliases", [])
    added = []
    for alias in aliases:
        if alias not in current and alias.lower() != item["name"].lower():
            current.append(alias)
            added.append(alias)
    return added


def build_alias_index(items: list[dict]) -> dict[str, str]:
    index: dict[str, str] = {}
    for item in items:
        keys = [normalize_lookup_key(item["name"])] + [
            normalize_lookup_key(a) for a in item.get("aliases", [])
        ]
        for key in keys:
            if key:
                index[key] = item["id"]
    return index


def variant_label_for_specific(specific_id: str, item: dict) -> str:
    if specific_id in NUT_VARIANT_OVERRIDES:
        return NUT_VARIANT_OVERRIDES[specific_id]
    name = item["name"].lower()
    if specific_id.endswith("-nut") and specific_id != "pine-nut":
        return name.replace(" nut", "")
    return name


def build_nut_family(items: list[dict]) -> dict:
    by_id = items_by_id(items)
    specific_ids = sorted(
        i["id"] for i in items
        if i.get("category") == "Nuts & Seeds"
        and i["id"] not in NUT_FAMILY_EXCLUDE
    )
    variant_map = {
        variant_label_for_specific(sid, by_id[sid]): sid
        for sid in specific_ids
        if sid in by_id
    }
    return {
        "genericId": "nut",
        "specificIds": specific_ids,
        "excludedFromGenericMatch": sorted(NUT_FAMILY_EXCLUDE),
        "variantToSpecificId": variant_map,
        "genericOnlyAliases": sorted(GENERIC_ONLY_BARE_ALIASES["nut"]),
        "allowGenericPantrySubstitution": True,
    }


def build_oil_family(items: list[dict]) -> dict:
    specific_ids = sorted(i["id"] for i in items if i["id"].endswith("-oil"))
    by_id = items_by_id(items)
    variant_map = {}
    for sid in specific_ids:
        label = by_id[sid]["name"].lower().replace(" oil", "")
        variant_map[label] = sid
    return {
        "genericId": "oil",
        "specificIds": specific_ids,
        "excludedFromGenericMatch": [],
        "variantToSpecificId": variant_map,
        "genericOnlyAliases": sorted(GENERIC_ONLY_BARE_ALIASES["oil"]),
        "allowGenericPantrySubstitution": True,
    }


def build_generic_only_families(items: list[dict]) -> list[dict]:
    """Catalog entries that use variant facets without separate specific entries."""
    generic_only_ids = [
        "cheese", "beef", "chicken", "beans", "broth", "tomato", "onion", "pepper",
        "cream", "sugar", "flour", "egg", "milk", "yogurt", "pork", "lamb", "turkey",
        "fish", "shrimp", "rice", "pasta", "bread", "potato", "mushroom", "cured-meat",
    ]
    by_id = items_by_id(items)
    families = []
    for gid in generic_only_ids:
        item = by_id.get(gid)
        if not item or not facet_options(item, "variant"):
            continue
        families.append({
            "genericId": gid,
            "specificIds": [],
            "allowGenericPantrySubstitution": False,
            "genericOnly": True,
        })
    return families


def regenerate_families(items: list[dict]) -> dict:
    families = [
        build_nut_family(items),
        build_oil_family(items),
        *build_generic_only_families(items),
    ]
    return {"families": families, "version": 1}
