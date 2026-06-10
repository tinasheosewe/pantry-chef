#!/usr/bin/env python3
"""Validate catalog.json integrity for the inheritance model."""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field

from catalog_lib import (
    items_by_id,
    load_catalog,
    normalize_lookup_key,
    parent_ids,
)
from catalog_source_lib import CATALOG_SOURCE_PATH, apply_post_repair_fixes, compile_source, load_source

REQUIRED_FIELDS = {"id", "name", "category", "defaultStorage"}
DEPRECATED_FIELDS = {"isGenericBase", "parentId", "parentFacets", "excludedFromGenericMatch"}
VALID_DEFAULT_UNITS = {
    "tsp",
    "tbsp",
    "cup",
    "fl oz",
    "ml",
    "L",
    "g",
    "kg",
    "oz",
    "lb",
    "piece",
    "whole",
    "loaf",
    "slice",
    "clove",
    "bunch",
    "can",
    "pkg",
    "pinch",
    "splash",
    "to taste",
}
VALID_STORAGES = {"Pantry", "Refrigerated", "Frozen"}
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
}


@dataclass
class Finding:
    severity: str
    rule: str
    message: str
    item_id: str | None = None


@dataclass
class ValidationReport:
    findings: list[Finding] = field(default_factory=list)

    def add(self, severity: str, rule: str, message: str, item_id: str | None = None) -> None:
        self.findings.append(Finding(severity, rule, message, item_id))

    @property
    def errors(self) -> list[Finding]:
        return [f for f in self.findings if f.severity == "error"]

    @property
    def warnings(self) -> list[Finding]:
        return [f for f in self.findings if f.severity == "warning"]


def slugify(value: str) -> str:
    return normalize_lookup_key(value).replace(" ", "-")


def facet_map(item: dict) -> dict[str, set[str]]:
    result: dict[str, set[str]] = {}
    for facet in item.get("facets", []):
        key = facet.get("key")
        if not key:
            continue
        result[key] = set(facet.get("options", []))
    return result


def effective_facet_options(item_id: str, by_id: dict[str, dict]) -> dict[str, set[str]]:
    if item_id not in by_id:
        return {}
    item = by_id[item_id]
    if len(parent_ids(item)) >= 2:
        return facet_map(item)
    options: dict[str, set[str]] = {}
    visited: set[str] = set()
    stack = [item_id]
    while stack:
        current = stack.pop()
        if current in visited:
            continue
        visited.add(current)
        current_item = by_id[current]
        for facet in current_item.get("facets", []):
            key = facet.get("key")
            if not key:
                continue
            options.setdefault(key, set()).update(facet.get("options", []))
        stack.extend(parent_ids(current_item))
    return options


def check_required_fields(items: list[dict], report: ValidationReport) -> None:
    seen_ids: set[str] = set()
    for item in items:
        item_id = item.get("id", "<missing-id>")
        missing = REQUIRED_FIELDS - set(item.keys())
        if missing:
            report.add("error", "required_fields", f"Missing fields {sorted(missing)}", item_id)
        if item_id in seen_ids:
            report.add("error", "duplicate_id", f"Duplicate catalog id {item_id!r}", item_id)
        seen_ids.add(item_id)


def check_supported_defaults(items: list[dict], report: ValidationReport) -> None:
    for item in items:
        item_id = item.get("id", "<missing-id>")
        unit = item.get("defaultUnit")
        storage = item.get("defaultStorage")
        if unit and unit not in VALID_DEFAULT_UNITS:
            report.add(
                "error",
                "unsupported_default_unit",
                f"defaultUnit {unit!r} is not supported by MeasurementUnit",
                item_id,
            )
        if storage and storage not in VALID_STORAGES:
            report.add(
                "error",
                "unsupported_default_storage",
                f"defaultStorage {storage!r} is not supported by PantryStorage",
                item_id,
            )


def check_deprecated_fields(items: list[dict], report: ValidationReport) -> None:
    for item in items:
        for field_name in DEPRECATED_FIELDS:
            if field_name in item:
                report.add(
                    "error",
                    "deprecated_field",
                    f"Deprecated field {field_name!r} present on catalog item",
                    item["id"],
                )


def check_duplicate_aliases(items: list[dict], report: ValidationReport) -> None:
    owner: dict[str, str] = {}
    for item in items:
        keys = [normalize_lookup_key(item["name"])] + [
            normalize_lookup_key(alias) for alias in item.get("aliases", [])
        ]
        for key in keys:
            if not key:
                continue
            if key in owner and owner[key] != item["id"]:
                report.add(
                    "warning",
                    "duplicate_alias",
                    f"Lookup key {key!r} owned by {owner[key]!r} and {item['id']!r}",
                    item["id"],
                )
            else:
                owner[key] = item["id"]


def check_self_aliases(items: list[dict], report: ValidationReport) -> None:
    for item in items:
        name_key = normalize_lookup_key(item["name"])
        for alias in item.get("aliases", []):
            if normalize_lookup_key(alias) == name_key:
                report.add(
                    "warning",
                    "self_alias",
                    f"Alias {alias!r} duplicates item name",
                    item["id"],
                )


def check_parent_links(items: list[dict], report: ValidationReport) -> None:
    by_id = items_by_id(items)
    for item in items:
        item_id = item["id"]
        for parent_id in parent_ids(item):
            if parent_id == item_id:
                report.add("error", "self_parent", "Item cannot parent itself", item_id)
            elif parent_id not in by_id:
                report.add("error", "orphan_parent", f"Parent {parent_id!r} not found", item_id)


def check_non_shareable_multi_parent(items: list[dict], report: ValidationReport) -> None:
    for item in items:
        item_id = item.get("id", "")
        if item_id in NON_SHAREABLE_MULTI_PARENT_IDS and len(parent_ids(item)) > 1:
            report.add(
                "error",
                "non_shareable_multi_parent",
                f"{item_id!r} is a scoped cut/state name and must not be shared across multiple parents",
                item_id,
            )


def check_cycles(items: list[dict], report: ValidationReport) -> None:
    by_id = items_by_id(items)
    visiting: set[str] = set()
    visited: set[str] = set()

    def dfs(node: str, stack: list[str]) -> None:
        if node in visited:
            return
        if node in visiting:
            cycle = " -> ".join(stack + [node])
            report.add("error", "inheritance_cycle", f"Inheritance cycle detected: {cycle}", node)
            return
        visiting.add(node)
        for parent_id in parent_ids(by_id.get(node, {})):
            if parent_id in by_id:
                dfs(parent_id, stack + [node])
        visiting.remove(node)
        visited.add(node)

    for item_id in by_id:
        dfs(item_id, [])


def check_additive_facets(items: list[dict], report: ValidationReport) -> None:
    by_id = items_by_id(items)
    for item in items:
        if len(parent_ids(item)) >= 2:
            # Multi-inheritance entries own a complete definition; parentIds are matching-only.
            continue
        child_facets = facet_map(item)
        for parent_id in parent_ids(item):
            parent = by_id.get(parent_id)
            if not parent:
                continue
            for key, parent_options in facet_map(parent).items():
                child_options = child_facets.get(key, set())
                if parent_options and not parent_options.issubset(child_options):
                    missing = sorted(parent_options - child_options)
                    report.add(
                        "error",
                        "non_additive_facet_override",
                        f"Child missing inherited options for {key}: {missing}",
                        item["id"],
                    )


def check_facet_aliases(items: list[dict], report: ValidationReport) -> None:
    by_id = items_by_id(items)
    for item in items:
        valid_options = effective_facet_options(item["id"], by_id)
        for alias_definition in item.get("facetAliases", []):
            text = alias_definition.get("text", "")
            if not text.strip():
                report.add("error", "invalid_facet_alias", "facetAlias.text must be non-empty", item["id"])
                continue
            for selection in alias_definition.get("facets", []):
                key = selection.get("key")
                value = selection.get("value")
                if key not in valid_options:
                    report.add(
                        "error",
                        "facet_alias_unknown_key",
                        f"facetAlias key {key!r} is not defined for this class hierarchy",
                        item["id"],
                    )
                    continue
                if value not in valid_options.get(key, set()):
                    report.add(
                        "error",
                        "facet_alias_unknown_value",
                        f"facetAlias value {value!r} is not valid for key {key!r}",
                        item["id"],
                    )


# State facets legitimately use generic words ("fresh", "paste") that also name
# generic catalog roots; only narrowing facets are checked for entry collisions.
NARROWING_KEYS = {"variant", "color", "grade", "fat"}
STATE_KEYS = {"form", "preparation", "preservation", "processing", "texture", "medium"}


def check_facet_entry_collisions(items: list[dict], report: ValidationReport) -> None:
    by_id = items_by_id(items)
    name_to_id = {normalize_lookup_key(item["name"]): item["id"] for item in items}
    slug_to_id = {item["id"]: item["id"] for item in items}
    for item in items:
        slug_to_id[slugify(item["name"])] = item["id"]

    for item in items:
        for facet in item.get("facets", []):
            key = facet.get("key")
            if key in STATE_KEYS:
                continue
            for option in facet.get("options", []):
                option_key = normalize_lookup_key(option)
                option_slug = slugify(option)
                conflict_id = name_to_id.get(option_key) or slug_to_id.get(option_slug)
                if not conflict_id or conflict_id == item["id"]:
                    continue
                related = conflict_id in parent_ids(item) or item["id"] in parent_ids(by_id.get(conflict_id, {}))
                if related:
                    continue
                report.add(
                    "warning",
                    "facet_duplicates_entry",
                    f"{item['id']!r} facet {key}.{option!r} duplicates catalog entry {conflict_id!r}",
                    item["id"],
                )


VALID_FACET_KEYS = {"color", "variant", "grade", "fat", "form", "preparation",
                    "preservation", "processing", "texture", "medium"}
# values allowed to appear under more than one facet key (genuinely context-dependent)
ORTHOGONALITY_EXCEPTIONS = {"whole"}


def state_modifier_values(items: list[dict]) -> set:
    """Modifier vocabulary derived from the catalog itself: every value used under
    a STATE facet (any key except `variant`, which holds genuine kinds). Used to
    detect bare-state ids/names without a hardcoded word list."""
    values = set()
    for item in items:
        for facet in item.get("facets", []):
            if facet.get("key") == "variant":
                continue
            for option in facet.get("options", []):
                values.add(normalize_lookup_key(option))
    return values


def check_valid_facet_keys(items: list[dict], report: ValidationReport) -> None:
    for item in items:
        for facet in item.get("facets", []):
            key = facet.get("key")
            if key not in VALID_FACET_KEYS:
                report.add("error", "invalid_facet_key",
                           f"Unknown facet key {key!r}", item["id"])


def check_facet_orthogonality(items: list[dict], report: ValidationReport) -> None:
    value_keys: dict[str, set[str]] = {}
    for item in items:
        for facet in item.get("facets", []):
            for option in facet.get("options", []):
                value_keys.setdefault(option.lower(), set()).add(facet.get("key"))
    for value, keys in sorted(value_keys.items()):
        if len(keys) > 1 and value not in ORTHOGONALITY_EXCEPTIONS:
            report.add("warning", "facet_key_not_orthogonal",
                       f"Value {value!r} appears under multiple keys {sorted(keys)}")


def check_bare_state_ids(items: list[dict], report: ValidationReport) -> None:
    state_values = state_modifier_values(items)
    for item in items:
        iid = item.get("id", "")
        if "-" in iid or normalize_lookup_key(iid) not in state_values:
            continue
        # only flag a misleading id — one that disagrees with its own name's slug
        # (so a real ingredient whose id equals its name is never flagged).
        if iid != slugify(item.get("name", "")):
            report.add("warning", "bare_state_id",
                       f"Id {iid!r} is a bare state word but names {item.get('name')!r}", iid)


def check_multi_inheritance_completeness(items: list[dict], report: ValidationReport) -> None:
    required = REQUIRED_FIELDS | {"facets"}
    for item in items:
        if len(parent_ids(item)) < 2:
            continue
        missing = required - set(item.keys())
        if missing:
            report.add(
                "error",
                "multi_inheritance_incomplete",
                f"Multi-inheritance item missing required fields {sorted(missing)}",
                item["id"],
            )


def validate_source_catalog(source: dict) -> ValidationReport:
    report = ValidationReport()
    try:
        compiled = compile_source(source)
        compiled, _ = apply_post_repair_fixes(compiled)
    except ValueError as exc:
        report.add("error", "source_compile_error", str(exc))
        return report
    validate_catalog_items(compiled, report)
    return report


def validate_catalog_items(items: list[dict], report: ValidationReport) -> None:
    check_required_fields(items, report)
    check_supported_defaults(items, report)
    check_deprecated_fields(items, report)
    check_duplicate_aliases(items, report)
    check_self_aliases(items, report)
    check_parent_links(items, report)
    check_non_shareable_multi_parent(items, report)
    check_multi_inheritance_completeness(items, report)
    check_cycles(items, report)
    check_additive_facets(items, report)
    check_facet_aliases(items, report)
    check_facet_entry_collisions(items, report)
    check_valid_facet_keys(items, report)
    check_facet_orthogonality(items, report)
    check_bare_state_ids(items, report)


def validate_catalog(*, strict: bool = False) -> ValidationReport:
    report = ValidationReport()
    items = load_catalog()
    validate_catalog_items(items, report)

    if strict:
        for finding in report.warnings:
            finding.severity = "error"
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate PantryChef catalog inheritance integrity.")
    parser.add_argument("--strict", action="store_true", help="Treat warnings as errors.")
    parser.add_argument("--json", action="store_true", help="Emit JSON report.")
    parser.add_argument("--source", action="store_true", help="Validate catalog.source.json instead of catalog.json.")
    args = parser.parse_args()

    if args.source:
        if not CATALOG_SOURCE_PATH.exists():
            print(f"Missing source catalog: {CATALOG_SOURCE_PATH}")
            return 1
        report = validate_source_catalog(load_source())
    else:
        report = validate_catalog(strict=args.strict)
    if args.json:
        payload = {
            "errors": [f.__dict__ for f in report.errors],
            "warnings": [f.__dict__ for f in report.warnings],
        }
        print(json.dumps(payload, indent=2))
    else:
        for finding in report.findings:
            prefix = finding.severity.upper()
            item = f" [{finding.item_id}]" if finding.item_id else ""
            print(f"{prefix} ({finding.rule}){item}: {finding.message}")
        print()
        print(
            f"Summary: {len(report.errors)} error(s), {len(report.warnings)} warning(s), "
            f"{len(report.findings)} total"
        )
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main())
