#!/usr/bin/env python3
"""Autonomous micro-batch validator/fixer for PantryChef catalog data.

This tool is intentionally dimension-scoped:
- names pass: detects/fixes ambiguous child names lacking parent context
- aliases pass: removes obviously noisy/cannibalizing aliases

It can run deterministically or optionally consult Anthropic in small batches.
All writes target catalog.source.json, then rebuild/validate runs.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, TypeVar

from catalog_lib import normalize_lookup_key, parent_ids
from catalog_source_lib import (
    CATALOG_SOURCE_PATH,
    apply_post_repair_fixes,
    compile_source,
    load_source,
    save_source,
)

SCRIPT_DIR = Path(__file__).resolve().parent
REPORTS_DIR = SCRIPT_DIR.parent / "reports"


@dataclass
class NameIssue:
    item_id: str
    current_name: str
    proposed_name: str
    parent_id: str
    parent_name: str
    category: str
    reason: str
    confidence: float
    source: str  # deterministic | llm


@dataclass
class AliasIssue:
    item_id: str
    item_name: str
    parent_id: str
    parent_name: str
    removed_aliases: list[str]
    proposed_aliases: list[str]
    reason: str
    confidence: float
    source: str  # deterministic | llm


@dataclass
class SemanticIssue:
    item_id: str
    item_name: str
    parent_id: str
    parent_name: str
    proposed_name: str | None
    proposed_aliases: list[str] | None
    reason: str
    confidence: float
    source: str  # deterministic | llm


GENERIC_MODIFIER_ALIASES = {
    "fresh",
    "frozen",
    "dried",
    "canned",
    "smoked",
    "raw",
    "cooked",
    "plain",
    "regular",
    "standard",
    "classic",
    "original",
    "light",
    "dark",
    "white",
    "yellow",
    "red",
    "green",
    "black",
    "small",
    "large",
    "medium",
    "young",
    "old",
    "gluten free",
    "gluten-free",
}

LLM_INPUT_PRICE_PER_MTOK = 15.0
LLM_OUTPUT_PRICE_PER_MTOK = 75.0
T = TypeVar("T")


def _item_words(value: str) -> set[str]:
    return {
        token
        for token in normalize_lookup_key(value).split()
        if token and token != "and"
    }


def _build_name_collision_keys(items: list[dict[str, Any]]) -> set[str]:
    counts: dict[str, int] = {}
    for item in items:
        key = normalize_lookup_key(item.get("name", ""))
        if key:
            counts[key] = counts.get(key, 0) + 1
    return {key for key, count in counts.items() if count > 1}


def _name_contains_parent(name: str, parent_name: str) -> bool:
    parent_words = _item_words(parent_name)
    item_words = _item_words(name)
    return bool(parent_words) and parent_words.issubset(item_words)


def _looks_atomic_token(name: str) -> bool:
    key = normalize_lookup_key(name)
    if not key:
        return False
    tokens = key.split()
    if len(tokens) > 2:
        return False
    if any(any(ch.isdigit() for ch in token) for token in tokens):
        return False
    return True


def _human_phrase(value: str) -> str:
    return re.sub(r"\s+", " ", value.replace("-", " ")).strip()


def _compose_scoped_name(item: dict[str, Any], parent: dict[str, Any]) -> str:
    child = _human_phrase(str(item.get("name", "")))
    parent_name = _human_phrase(str(parent.get("name", "")))
    item_id = item.get("id", "")
    parent_id = parent.get("id", "")

    if item_id.startswith(f"{parent_id}-"):
        composed = f"{parent_name} {child}"
    elif item_id.endswith(f"-{parent_id}"):
        composed = f"{child} {parent_name}"
    else:
        composed = f"{child} {parent_name}"

    return re.sub(r"\s+", " ", composed).strip()


def _name_tokens_for_item(item: dict[str, Any]) -> set[str]:
    tokens = _item_words(item.get("name", ""))
    tokens.update(_item_words(str(item.get("id", "")).replace("-", " ")))
    return {token for token in tokens if len(token) > 2}


def _chunked(values: list[T], size: int) -> list[list[T]]:
    return [values[i : i + size] for i in range(0, len(values), max(1, size))]


def collect_name_issues(items: list[dict[str, Any]]) -> list[NameIssue]:
    by_id = {item["id"]: item for item in items}
    duplicate_name_keys = _build_name_collision_keys(items)
    issues: list[NameIssue] = []

    for item in items:
        parents = parent_ids(item)
        if len(parents) != 1:
            continue
        parent = by_id.get(parents[0])
        if not parent:
            continue
        current_name = item.get("name", "").strip()
        if not current_name:
            continue
        if _name_contains_parent(current_name, parent.get("name", "")):
            continue

        normalized_name = normalize_lookup_key(current_name)
        is_collision = normalized_name in duplicate_name_keys
        if not (is_collision or _looks_atomic_token(current_name)):
            continue

        proposed_name = _compose_scoped_name(item, parent)
        if normalize_lookup_key(proposed_name) == normalized_name:
            continue

        reason = "duplicate_name_key" if is_collision else "atomic_child_name_without_parent_context"
        confidence = 0.98 if is_collision else 0.92
        issues.append(
            NameIssue(
                item_id=item["id"],
                current_name=current_name,
                proposed_name=proposed_name,
                parent_id=parent["id"],
                parent_name=parent.get("name", ""),
                category=item.get("category", ""),
                reason=reason,
                confidence=confidence,
                source="deterministic",
            )
        )
    return issues


def collect_alias_issues(items: list[dict[str, Any]]) -> list[AliasIssue]:
    by_id = {item["id"]: item for item in items}
    issues: list[AliasIssue] = []

    for item in items:
        aliases = list(item.get("aliases", []))
        if not aliases:
            continue

        parent = None
        parents = parent_ids(item)
        if len(parents) == 1:
            parent = by_id.get(parents[0])

        item_name_key = normalize_lookup_key(item.get("name", ""))
        item_tokens = _name_tokens_for_item(item)
        parent_name_key = normalize_lookup_key(parent.get("name", "")) if parent else ""
        parent_tokens = _name_tokens_for_item(parent) if parent else set()
        if parent and not parent_tokens:
            parent_tokens = _item_words(parent.get("name", ""))

        seen_alias_keys: set[str] = set()
        removed: list[str] = []
        cleaned: list[str] = []
        for alias in aliases:
            alias_key = normalize_lookup_key(alias)
            if not alias_key:
                removed.append(alias)
                continue
            if alias_key in seen_alias_keys:
                removed.append(alias)
                continue
            seen_alias_keys.add(alias_key)

            alias_tokens = _item_words(alias_key)

            # Self-alias duplicates item name exactly.
            if alias_key == item_name_key:
                removed.append(alias)
                continue

            # Child alias cannibalizes generic parent lookup (e.g. child "beef-brisket" alias "beef").
            if parent and alias_key == parent_name_key:
                removed.append(alias)
                continue

            # Very generic modifiers on child nodes are high-noise aliases.
            if parent and alias_key in GENERIC_MODIFIER_ALIASES:
                removed.append(alias)
                continue

            # Alias only overlaps parent tokens and has no child tokens -> likely over-broad.
            if parent and alias_tokens:
                overlaps_child = bool(alias_tokens.intersection(item_tokens))
                overlaps_parent = bool(alias_tokens.intersection(parent_tokens))
                if overlaps_parent and not overlaps_child:
                    removed.append(alias)
                    continue

            cleaned.append(alias)

        if not removed:
            continue
        issues.append(
            AliasIssue(
                item_id=item["id"],
                item_name=item.get("name", ""),
                parent_id=parent["id"] if parent else "",
                parent_name=parent.get("name", "") if parent else "",
                removed_aliases=removed,
                proposed_aliases=cleaned,
                reason="deterministic_alias_cleanup",
                confidence=0.95,
                source="deterministic",
            )
        )
    return issues


def _build_lookup_owner_map(items: list[dict[str, Any]]) -> dict[str, list[dict[str, str]]]:
    owners: dict[str, list[dict[str, str]]] = {}
    for item in items:
        keys = [normalize_lookup_key(item.get("name", ""))]
        keys.extend(normalize_lookup_key(alias) for alias in item.get("aliases", []))
        seen: set[str] = set()
        for key in keys:
            if not key or key in seen:
                continue
            seen.add(key)
            owners.setdefault(key, []).append(
                {
                    "item_id": item["id"],
                    "name": item.get("name", ""),
                    "category": item.get("category", ""),
                }
            )
    return owners


def _build_cross_pollution_bundles(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    owners = _build_lookup_owner_map(items)
    bundles: list[dict[str, Any]] = []
    for key, key_owners in owners.items():
        unique_ids = {owner["item_id"] for owner in key_owners}
        if len(unique_ids) <= 1:
            continue
        # Ignore tiny throwaway keys.
        if len(key) <= 2:
            continue
        categories = {owner["category"] for owner in key_owners if owner.get("category")}
        bundles.append(
            {
                "lookup_key": key,
                "owner_count": len(unique_ids),
                "categories": sorted(categories),
                "owners": key_owners[:10],
            }
        )
    bundles.sort(key=lambda x: x["owner_count"], reverse=True)
    return bundles


def _anthropic_suggest_names(
    batch: list[NameIssue],
    *,
    api_key: str,
    model: str,
    max_retries: int = 3,
) -> dict[str, tuple[str, float, str]]:
    endpoint = "https://api.anthropic.com/v1/messages"
    payload = {
        "model": model,
        "max_tokens": 1600,
        "temperature": 0.1,
        "system": (
            "You are validating ingredient catalog naming. "
            "Return STRICT JSON only. "
            "Keep names concise, food-realistic, and parent-scoped."
        ),
        "messages": [
            {
                "role": "user",
                "content": (
                    "Given these candidate items, return JSON object:\n"
                    "{ \"updates\": [{\"item_id\": str, \"proposed_name\": str, \"confidence\": float, \"reason\": str}] }\n"
                    "Rules: proposed_name must include parent context when child is ambiguous. "
                    "Do not invent new taxonomy.\n\n"
                    f"Candidates:\n{json.dumps([asdict(x) for x in batch], indent=2)}"
                ),
            }
        ],
    }

    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")

    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                raw = response.read().decode("utf-8")
            parsed = json.loads(raw)
            content_blocks = parsed.get("content", [])
            text = "".join(block.get("text", "") for block in content_blocks if block.get("type") == "text").strip()
            text = re.sub(r"^```json\s*", "", text)
            text = re.sub(r"\s*```$", "", text)
            data = json.loads(text)
            updates = {}
            for row in data.get("updates", []):
                item_id = str(row.get("item_id", "")).strip()
                proposed_name = str(row.get("proposed_name", "")).strip()
                confidence = float(row.get("confidence", 0))
                reason = str(row.get("reason", "")).strip() or "llm_review"
                if item_id and proposed_name:
                    updates[item_id] = (proposed_name, confidence, reason)
            return updates
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError, ValueError):
            if attempt == max_retries - 1:
                return {}
            time.sleep(2 ** attempt)
    return {}


def _anthropic_suggest_aliases(
    batch: list[AliasIssue],
    *,
    api_key: str,
    model: str,
    max_retries: int = 3,
) -> dict[str, tuple[list[str], float, str]]:
    endpoint = "https://api.anthropic.com/v1/messages"
    payload = {
        "model": model,
        "max_tokens": 1800,
        "temperature": 0.1,
        "system": (
            "You are validating ingredient catalog aliases. "
            "Return STRICT JSON only. Keep aliases precise and non-cannibalizing."
        ),
        "messages": [
            {
                "role": "user",
                "content": (
                    "Given alias cleanup candidates, return JSON object:\n"
                    "{ \"updates\": [{\"item_id\": str, \"proposed_aliases\": [str], \"confidence\": float, \"reason\": str}] }\n"
                    "Rules: avoid over-broad aliases; keep useful specific aliases; preserve culinary realism.\n\n"
                    f"Candidates:\n{json.dumps([asdict(x) for x in batch], indent=2)}"
                ),
            }
        ],
    }
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")

    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req, timeout=60) as response:
                raw = response.read().decode("utf-8")
            parsed = json.loads(raw)
            content_blocks = parsed.get("content", [])
            text = "".join(block.get("text", "") for block in content_blocks if block.get("type") == "text").strip()
            text = re.sub(r"^```json\s*", "", text)
            text = re.sub(r"\s*```$", "", text)
            data = json.loads(text)
            updates: dict[str, tuple[list[str], float, str]] = {}
            for row in data.get("updates", []):
                item_id = str(row.get("item_id", "")).strip()
                proposed_aliases = row.get("proposed_aliases", [])
                confidence = float(row.get("confidence", 0))
                reason = str(row.get("reason", "")).strip() or "llm_alias_review"
                if not item_id or not isinstance(proposed_aliases, list):
                    continue
                cleaned_aliases = [str(alias).strip() for alias in proposed_aliases if str(alias).strip()]
                updates[item_id] = (cleaned_aliases, confidence, reason)
            return updates
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError, ValueError):
            if attempt == max_retries - 1:
                return {}
            time.sleep(2 ** attempt)
    return {}


def _anthropic_review_semantics(
    batch_items: list[dict[str, Any]],
    *,
    collision_context: list[dict[str, Any]],
    api_key: str,
    model: str,
    max_retries: int = 3,
) -> list[SemanticIssue]:
    endpoint = "https://api.anthropic.com/v1/messages"
    payload = {
        "model": model,
        "max_tokens": 2400,
        "temperature": 0.1,
        "system": (
            "You are a food ontology QA reviewer. "
            "Return STRICT JSON only. "
            "Find naming/alias pollution and propose minimal safe fixes."
        ),
        "messages": [
            {
                "role": "user",
                "content": (
                    "Review these ingredient records and collision context.\n"
                    "Return JSON object:\n"
                    "{ \"issues\": ["
                    "{\"item_id\": str, \"proposed_name\": str|null, \"proposed_aliases\": [str]|null, "
                    "\"confidence\": float, \"reason\": str}"
                    "] }\n"
                    "Rules:\n"
                    "- Propose edits only when high confidence.\n"
                    "- Keep culinary realism.\n"
                    "- Prefer removing polluted aliases over adding many new aliases.\n"
                    "- Use parent context when a child name is too generic.\n\n"
                    f"Items:\n{json.dumps(batch_items, indent=2)}\n\n"
                    f"Collision context:\n{json.dumps(collision_context, indent=2)}"
                ),
            }
        ],
    }
    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")

    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(req, timeout=75) as response:
                raw = response.read().decode("utf-8")
            parsed = json.loads(raw)
            content_blocks = parsed.get("content", [])
            text = "".join(block.get("text", "") for block in content_blocks if block.get("type") == "text").strip()
            text = re.sub(r"^```json\s*", "", text)
            text = re.sub(r"\s*```$", "", text)
            data = json.loads(text)
            by_id = {row["id"]: row for row in batch_items if row.get("id")}
            issues: list[SemanticIssue] = []
            for row in data.get("issues", []):
                item_id = str(row.get("item_id", "")).strip()
                if not item_id or item_id not in by_id:
                    continue
                confidence = float(row.get("confidence", 0))
                reason = str(row.get("reason", "")).strip() or "semantic_review"
                proposed_name_raw = row.get("proposed_name")
                proposed_name = _human_phrase(str(proposed_name_raw)) if isinstance(proposed_name_raw, str) and proposed_name_raw.strip() else None
                proposed_aliases_raw = row.get("proposed_aliases")
                proposed_aliases: list[str] | None = None
                if isinstance(proposed_aliases_raw, list):
                    seen: set[str] = set()
                    proposed_aliases = []
                    for alias in proposed_aliases_raw:
                        alias_text = str(alias).strip()
                        key = normalize_lookup_key(alias_text)
                        if not alias_text or not key or key in seen:
                            continue
                        seen.add(key)
                        proposed_aliases.append(alias_text)
                item = by_id[item_id]
                parent_ids_val = item.get("parentIds", []) or []
                issues.append(
                    SemanticIssue(
                        item_id=item_id,
                        item_name=item.get("name", ""),
                        parent_id=parent_ids_val[0] if parent_ids_val else "",
                        parent_name="",
                        proposed_name=proposed_name,
                        proposed_aliases=proposed_aliases,
                        reason=reason,
                        confidence=confidence,
                        source="llm",
                    )
                )
            return issues
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError, ValueError):
            if attempt == max_retries - 1:
                return []
            time.sleep(2 ** attempt)
    return []


def maybe_enrich_with_llm(
    issues: list[NameIssue],
    *,
    use_llm: bool,
    model: str,
    batch_size: int,
) -> list[NameIssue]:
    if not use_llm:
        return issues
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        print("Warning: ANTHROPIC_API_KEY not set; continuing with deterministic fixes.")
        return issues

    issues_by_id = {issue.item_id: issue for issue in issues}
    for idx in range(0, len(issues), batch_size):
        batch = issues[idx : idx + batch_size]
        updates = _anthropic_suggest_names(batch, api_key=api_key, model=model)
        for item_id, (proposed_name, confidence, reason) in updates.items():
            issue = issues_by_id.get(item_id)
            if not issue:
                continue
            # Only trust confident updates.
            if confidence < 0.8:
                continue
            issue.proposed_name = _human_phrase(proposed_name)
            issue.confidence = confidence
            issue.reason = reason
            issue.source = "llm"
    return issues


def maybe_enrich_aliases_with_llm(
    issues: list[AliasIssue],
    *,
    use_llm: bool,
    model: str,
    batch_size: int,
) -> list[AliasIssue]:
    if not use_llm:
        return issues
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        print("Warning: ANTHROPIC_API_KEY not set; continuing with deterministic alias fixes.")
        return issues

    issues_by_id = {issue.item_id: issue for issue in issues}
    for idx in range(0, len(issues), batch_size):
        batch = issues[idx : idx + batch_size]
        updates = _anthropic_suggest_aliases(batch, api_key=api_key, model=model)
        for item_id, (proposed_aliases, confidence, reason) in updates.items():
            issue = issues_by_id.get(item_id)
            if not issue or confidence < 0.8:
                continue
            current_key_set = {normalize_lookup_key(alias) for alias in issue.proposed_aliases}
            proposed = []
            seen: set[str] = set()
            for alias in proposed_aliases:
                key = normalize_lookup_key(alias)
                if not key or key in seen:
                    continue
                seen.add(key)
                proposed.append(alias)
            issue.removed_aliases = [alias for alias in issue.removed_aliases if normalize_lookup_key(alias) not in current_key_set]
            issue.proposed_aliases = proposed
            issue.confidence = confidence
            issue.reason = reason
            issue.source = "llm"
    return issues


def collect_semantic_issues(
    items: list[dict[str, Any]],
    *,
    use_llm: bool,
    model: str,
    batch_size: int,
    llm_thorough: bool,
) -> list[SemanticIssue]:
    deterministic: list[SemanticIssue] = []

    if not use_llm:
        return deterministic
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        print("Warning: ANTHROPIC_API_KEY not set; semantic pass continuing with deterministic findings only.")
        return deterministic

    by_id = {item["id"]: item for item in items}
    collisions = _build_cross_pollution_bundles(items)
    item_rows: list[dict[str, Any]] = []
    for item in items:
        # thorough=true => review entire catalog
        if not llm_thorough:
            # light mode keeps LLM focused on already suspicious items
            if not any(issue.item_id == item["id"] for issue in deterministic):
                continue
        item_rows.append(
            {
                "id": item["id"],
                "name": item.get("name", ""),
                "category": item.get("category", ""),
                "parentIds": parent_ids(item),
                "aliases": item.get("aliases", [])[:25],
                "facet_keys": [facet.get("key", "") for facet in item.get("facets", [])],
            }
        )

    llm_issues: list[SemanticIssue] = []
    for batch in _chunked(item_rows, batch_size):
        batch_ids = {row["id"] for row in batch}
        relevant_collisions = []
        for bundle in collisions:
            owners = bundle.get("owners", [])
            owner_ids = {owner.get("item_id") for owner in owners}
            if owner_ids.intersection(batch_ids):
                relevant_collisions.append(bundle)
            if len(relevant_collisions) >= 60:
                break
        llm_issues.extend(
            _anthropic_review_semantics(
                batch,
                collision_context=relevant_collisions,
                api_key=api_key,
                model=model,
            )
        )

    # Merge deterministic + LLM by item ID, keeping highest confidence.
    merged: dict[str, SemanticIssue] = {issue.item_id: issue for issue in deterministic}
    for issue in llm_issues:
        existing = merged.get(issue.item_id)
        if existing is None or issue.confidence > existing.confidence:
            parent = by_id.get(issue.parent_id)
            issue.parent_name = parent.get("name", "") if parent else ""
            merged[issue.item_id] = issue
    return list(merged.values())


def _iter_source_nodes(source: dict[str, Any]) -> dict[str, dict[str, Any]]:
    nodes: dict[str, dict[str, Any]] = {}

    def walk(node: dict[str, Any]) -> None:
        node_id = node.get("id")
        if node_id:
            nodes[node_id] = node
        for child in node.get("children", []) or []:
            if isinstance(child, dict):
                walk(child)

    for root in source.get("trees", []) or []:
        if isinstance(root, dict):
            walk(root)
    for node in source.get("multiInheritance", []) or []:
        if isinstance(node, dict) and node.get("id"):
            nodes[node["id"]] = node
    return nodes


def apply_name_updates_to_source(source: dict[str, Any], issues: list[NameIssue]) -> int:
    nodes = _iter_source_nodes(source)
    updates = 0
    for issue in issues:
        node = nodes.get(issue.item_id)
        if not node:
            continue
        if normalize_lookup_key(node.get("name", "")) == normalize_lookup_key(issue.proposed_name):
            continue
        node["name"] = issue.proposed_name
        updates += 1
    return updates


def apply_alias_updates_to_source(source: dict[str, Any], issues: list[AliasIssue]) -> int:
    nodes = _iter_source_nodes(source)
    updates = 0
    for issue in issues:
        node = nodes.get(issue.item_id)
        if not node:
            continue
        current_aliases = list(node.get("aliases", []))
        if [normalize_lookup_key(a) for a in current_aliases] == [normalize_lookup_key(a) for a in issue.proposed_aliases]:
            continue
        node["aliases"] = issue.proposed_aliases
        updates += 1
    return updates


def apply_semantic_updates_to_source(source: dict[str, Any], issues: list[SemanticIssue]) -> int:
    nodes = _iter_source_nodes(source)
    updates = 0
    for issue in issues:
        if issue.confidence < 0.86:
            continue
        node = nodes.get(issue.item_id)
        if not node:
            continue
        changed = False
        if issue.proposed_name:
            if normalize_lookup_key(node.get("name", "")) != normalize_lookup_key(issue.proposed_name):
                node["name"] = issue.proposed_name
                changed = True
        if issue.proposed_aliases is not None:
            current_aliases = list(node.get("aliases", []))
            if [normalize_lookup_key(a) for a in current_aliases] != [normalize_lookup_key(a) for a in issue.proposed_aliases]:
                node["aliases"] = issue.proposed_aliases
                changed = True
        if changed:
            updates += 1
    return updates


def write_name_reports(issues: list[NameIssue], *, name: str = "catalog_validation_names") -> None:
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    json_path = REPORTS_DIR / f"{name}.json"
    md_path = REPORTS_DIR / f"{name}.md"

    payload = {
        "issue_count": len(issues),
        "issues": [asdict(issue) for issue in issues],
    }
    json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Catalog Name Validation Report",
        "",
        f"- Issues: {len(issues)}",
        "",
        "| item_id | current_name | proposed_name | parent | confidence | source | reason |",
        "|---|---|---|---|---:|---|---|",
    ]
    for issue in issues:
        lines.append(
            f"| {issue.item_id} | {issue.current_name} | {issue.proposed_name} | "
            f"{issue.parent_name} | {issue.confidence:.2f} | {issue.source} | {issue.reason} |"
        )
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote reports: {json_path} and {md_path}")


def write_alias_reports(issues: list[AliasIssue], *, name: str = "catalog_validation_aliases") -> None:
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    json_path = REPORTS_DIR / f"{name}.json"
    md_path = REPORTS_DIR / f"{name}.md"

    payload = {
        "issue_count": len(issues),
        "issues": [asdict(issue) for issue in issues],
    }
    json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Catalog Alias Validation Report",
        "",
        f"- Issues: {len(issues)}",
        "",
        "| item_id | item_name | removed_aliases | parent | confidence | source | reason |",
        "|---|---|---|---|---:|---|---|",
    ]
    for issue in issues:
        removed = ", ".join(issue.removed_aliases) if issue.removed_aliases else "-"
        lines.append(
            f"| {issue.item_id} | {issue.item_name} | {removed} | {issue.parent_name or '-'} | "
            f"{issue.confidence:.2f} | {issue.source} | {issue.reason} |"
        )
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote reports: {json_path} and {md_path}")


def write_semantic_reports(issues: list[SemanticIssue], *, name: str = "catalog_validation_semantics") -> None:
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    json_path = REPORTS_DIR / f"{name}.json"
    md_path = REPORTS_DIR / f"{name}.md"

    payload = {"issue_count": len(issues), "issues": [asdict(issue) for issue in issues]}
    json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Catalog Semantic Validation Report",
        "",
        f"- Issues: {len(issues)}",
        "",
        "| item_id | current_name | proposed_name | aliases_update | confidence | source | reason |",
        "|---|---|---|---|---:|---|---|",
    ]
    for issue in issues:
        alias_flag = "yes" if issue.proposed_aliases is not None else "-"
        lines.append(
            f"| {issue.item_id} | {issue.item_name} | {issue.proposed_name or '-'} | "
            f"{alias_flag} | {issue.confidence:.2f} | {issue.source} | {issue.reason} |"
        )
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote reports: {json_path} and {md_path}")


def estimate_llm_usage(
    items: list[dict[str, Any]],
    *,
    pass_name: str,
    batch_size: int,
    llm_thorough: bool,
) -> dict[str, float | int]:
    if pass_name == "names":
        count = len(collect_name_issues(items))
    elif pass_name == "aliases":
        count = len(collect_alias_issues(items))
    else:
        count = len(items) if llm_thorough else max(1, len(collect_semantic_issues(items, use_llm=False, model="", batch_size=batch_size, llm_thorough=False)))

    calls = len(_chunked(list(range(count)), batch_size))
    # Conservative token assumptions per call
    if pass_name == "semantics":
        input_tokens_per_call = 14000 if llm_thorough else 7000
        output_tokens_per_call = 2200 if llm_thorough else 1200
    elif pass_name == "aliases":
        input_tokens_per_call = 8500
        output_tokens_per_call = 1400
    else:
        input_tokens_per_call = 7000
        output_tokens_per_call = 1200

    input_tokens_total = calls * input_tokens_per_call
    output_tokens_total = calls * output_tokens_per_call
    cost_usd = (input_tokens_total / 1_000_000) * LLM_INPUT_PRICE_PER_MTOK + (
        output_tokens_total / 1_000_000
    ) * LLM_OUTPUT_PRICE_PER_MTOK
    return {
        "item_count": count,
        "estimated_calls": calls,
        "estimated_input_tokens": input_tokens_total,
        "estimated_output_tokens": output_tokens_total,
        "estimated_cost_usd": round(cost_usd, 2),
    }


def run_rebuild_and_validate() -> None:
    subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "compile_catalog.py")],
        check=True,
    )
    subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "validate_catalog.py"), "--source"],
        check=True,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Autonomous micro-batch catalog validator/fixer.")
    parser.add_argument("--pass", dest="pass_name", choices=["names", "aliases", "semantics"], default="names")
    parser.add_argument("--apply", action="store_true", help="Apply fixes to catalog.source.json and rebuild catalog.")
    parser.add_argument("--use-llm", action="store_true", help="Use Anthropic micro-batches for refinement.")
    parser.add_argument(
        "--llm-thorough",
        action="store_true",
        help="For semantic pass, review entire catalog with LLM (not only deterministic candidates).",
    )
    parser.add_argument(
        "--estimate-cost",
        action="store_true",
        help="Print estimated LLM call count/tokens/cost for selected pass and exit.",
    )
    parser.add_argument("--model", default=os.getenv("ANTHROPIC_MODEL", "claude-opus-4.6"))
    parser.add_argument("--batch-size", type=int, default=25)
    parser.add_argument("--max-items", type=int, default=0, help="Limit issues processed (0 = all).")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = load_source()
    compiled = compile_source(source)
    compiled, _ = apply_post_repair_fixes(compiled)
    if args.estimate_cost:
        estimate = estimate_llm_usage(
            compiled,
            pass_name=args.pass_name,
            batch_size=max(1, args.batch_size),
            llm_thorough=args.llm_thorough,
        )
        print(json.dumps({"pass": args.pass_name, "batch_size": args.batch_size, "llm_thorough": args.llm_thorough, **estimate}, indent=2))
        return 0

    if args.pass_name == "names":
        issues = collect_name_issues(compiled)
        issues.sort(key=lambda x: (x.confidence, x.item_id), reverse=True)
        if args.max_items > 0:
            issues = issues[: args.max_items]
        issues = maybe_enrich_with_llm(
            issues,
            use_llm=args.use_llm,
            model=args.model,
            batch_size=max(1, args.batch_size),
        )
        write_name_reports(issues)
        print(f"Detected {len(issues)} name issues.")
        if not args.apply:
            return 0
        applied = apply_name_updates_to_source(source, issues)
    elif args.pass_name == "aliases":
        issues = collect_alias_issues(compiled)
        issues.sort(key=lambda x: (x.confidence, x.item_id), reverse=True)
        if args.max_items > 0:
            issues = issues[: args.max_items]
        issues = maybe_enrich_aliases_with_llm(
            issues,
            use_llm=args.use_llm,
            model=args.model,
            batch_size=max(1, args.batch_size),
        )
        write_alias_reports(issues)
        print(f"Detected {len(issues)} alias issues.")
        if not args.apply:
            return 0
        applied = apply_alias_updates_to_source(source, issues)
    else:
        issues = collect_semantic_issues(
            compiled,
            use_llm=args.use_llm,
            model=args.model,
            batch_size=max(1, args.batch_size),
            llm_thorough=args.llm_thorough,
        )
        issues.sort(key=lambda x: (x.confidence, x.item_id), reverse=True)
        if args.max_items > 0:
            issues = issues[: args.max_items]
        write_semantic_reports(issues)
        print(f"Detected {len(issues)} semantic issues.")
        if not args.apply:
            return 0
        applied = apply_semantic_updates_to_source(source, issues)

    save_source(source)
    print(f"Applied {applied} source updates to {CATALOG_SOURCE_PATH}.")
    run_rebuild_and_validate()
    return 0


if __name__ == "__main__":
    sys.exit(main())
