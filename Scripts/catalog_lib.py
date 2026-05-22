"""Shared helpers for catalog validation and migration scripts."""
from __future__ import annotations

import json
import re
import unicodedata
from collections import deque
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
CATALOG_PATH = SCRIPT_DIR.parent / "PantryChef" / "Resources" / "catalog.json"
ALIAS_CANDIDATES_PATH = SCRIPT_DIR / "triage_output" / "corpus_alias_candidates.json"


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


def slugify(value: str) -> str:
    return normalize_lookup_key(value).replace(" ", "-")


def parent_ids(item: dict) -> list[str]:
    return list(item.get("parentIds", []))


def children_by_parent(items: list[dict]) -> dict[str, set[str]]:
    result: dict[str, set[str]] = {}
    for item in items:
        for parent_id in parent_ids(item):
            result.setdefault(parent_id, set()).add(item["id"])
    return result


def ancestors_of(item_id: str, by_id: dict[str, dict]) -> set[str]:
    if item_id not in by_id:
        return set()
    visited: set[str] = set()
    stack = [item_id]
    while stack:
        current = stack.pop()
        if current in visited:
            continue
        visited.add(current)
        stack.extend(parent_ids(by_id.get(current, {})))
    return visited


def descendants_of(root_id: str, by_id: dict[str, dict]) -> set[str]:
    if root_id not in by_id:
        return set()
    child_map = children_by_parent(list(by_id.values()))
    visited: set[str] = set()
    queue: deque[str] = deque([root_id])
    while queue:
        current = queue.popleft()
        if current in visited:
            continue
        visited.add(current)
        queue.extend(child_map.get(current, set()))
    return visited
