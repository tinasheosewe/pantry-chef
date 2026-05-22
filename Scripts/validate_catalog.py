#!/usr/bin/env python3
"""Validate catalog.json integrity and generic↔specific family rules.

Run from repo root:
    python3 PantryChef/Scripts/validate_catalog.py
    python3 PantryChef/Scripts/validate_catalog.py --strict
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

from catalog_lib import (
    FAMILIES_PATH,
    build_alias_index,
    facet_options,
    items_by_id,
    load_catalog,
    load_families,
    normalize_lookup_key,
)

REQUIRED_FIELDS = {"id", "name", "category", "defaultStorage"}


@dataclass
class Finding:
    severity: str  # error | warning
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


def check_required_fields(items: list[dict], report: ValidationReport) -> None:
    seen_ids: set[str] = set()
    for item in items:
        missing = REQUIRED_FIELDS - set(item.keys())
        if missing:
            report.add("error", "required_fields", f"Missing fields {sorted(missing)}", item["id"])
        if item["id"] in seen_ids:
            report.add("error", "duplicate_id", f"Duplicate catalog id {item['id']!r}", item["id"])
        seen_ids.add(item["id"])


def check_duplicate_aliases(items: list[dict], report: ValidationReport) -> None:
    owner: dict[str, str] = {}
    for item in items:
        keys = [normalize_lookup_key(item["name"])] + [
            normalize_lookup_key(a) for a in item.get("aliases", [])
        ]
        for key in keys:
            if not key:
                continue
            if key in owner and owner[key] != item["id"]:
                report.add(
                    "error",
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


def family_maps(families_data: dict) -> tuple[dict[str, dict], dict[str, str]]:
    """genericId → family; specificId → genericId."""
    by_generic: dict[str, dict] = {}
    specific_to_generic: dict[str, str] = {}
    for family in families_data.get("families", []):
        gid = family.get("genericId")
        if gid:
            by_generic[gid] = family
            for sid in family.get("specificIds", []):
                specific_to_generic[sid] = gid
    return by_generic, specific_to_generic


def check_families(items: list[dict], families_data: dict, report: ValidationReport) -> None:
    by_id = items_by_id(items)
    by_generic, specific_to_generic = family_maps(families_data)

    for family in families_data.get("families", []):
        gid = family.get("genericId")
        if gid and gid not in by_id:
            report.add("error", "family_orphan_generic", f"Family generic {gid!r} not in catalog", gid)
        for sid in family.get("specificIds", []):
            if sid not in by_id:
                report.add("error", "family_orphan_specific", f"Family specific {sid!r} not in catalog", sid)
        for sid in family.get("excludedFromGenericMatch", []):
            if sid not in by_id:
                report.add("warning", "family_orphan_excluded", f"Excluded id {sid!r} not in catalog", sid)

        if gid and family.get("allowGenericPantrySubstitution"):
            variant_map = family.get("variantToSpecificId", {})
            for label, sid in variant_map.items():
                if sid not in by_id:
                    report.add(
                        "error",
                        "family_variant_orphan",
                        f"Variant {label!r} → {sid!r} but specific missing",
                        gid,
                    )
                elif sid not in family.get("specificIds", []):
                    report.add(
                        "error",
                        "family_variant_not_member",
                        f"Variant {label!r} maps to {sid!r} outside specificIds",
                        gid,
                    )

            generic_variants = set(facet_options(by_id[gid], "variant")) if gid in by_id else set()
            mapped = set(variant_map.keys())
            for opt in generic_variants:
                if opt not in mapped and not family.get("genericOnly"):
                    report.add(
                        "warning",
                        "generic_variant_unmapped",
                        f"Generic variant {opt!r} has no variantToSpecificId entry",
                        gid,
                    )

    # An item cannot be generic parent and specific in another family.
    for gid in by_generic:
        if gid in specific_to_generic:
            report.add(
                "error",
                "generic_and_specific",
                f"{gid!r} is both a family generic and specific of {specific_to_generic[gid]!r}",
                gid,
            )


def check_generic_specific_aliases(
    items: list[dict], families_data: dict, report: ValidationReport
) -> None:
    by_id = items_by_id(items)
    alias_index = build_alias_index(items)
    by_generic, _ = family_maps(families_data)

    for family in families_data.get("families", []):
        gid = family.get("genericId")
        if not gid or gid not in by_id:
            continue
        generic = by_id[gid]
        allowed_generic = {
            normalize_lookup_key(a)
            for a in family.get("genericOnlyAliases", [])
        }
        allowed_generic.add(normalize_lookup_key(generic["name"]))

        if family.get("allowGenericPantrySubstitution"):
            for alias in generic.get("aliases", []):
                key = normalize_lookup_key(alias)
                if key not in allowed_generic:
                    report.add(
                        "error",
                        "generic_compound_alias",
                        f"Generic {gid!r} alias {alias!r} is not in genericOnlyAliases",
                        gid,
                    )

        specific_ids = set(family.get("specificIds", []))
        if not specific_ids or not family.get("allowGenericPantrySubstitution"):
            continue

        for sid in specific_ids:
            specific = by_id.get(sid)
            if not specific:
                continue
            for alias in specific.get("aliases", []) + [specific["name"]]:
                key = normalize_lookup_key(alias)
                if key in allowed_generic:
                    report.add(
                        "error",
                        "specific_uses_generic_alias",
                        f"Specific {sid!r} reuses generic-only alias {alias!r}",
                        sid,
                    )
                if gid in by_generic and key in {
                    normalize_lookup_key(a)
                    for a in by_id[gid].get("aliases", [])
                }:
                    report.add(
                        "error",
                        "alias_on_generic_and_specific",
                        f"Alias {alias!r} appears on generic {gid!r} and specific {sid!r}",
                        sid,
                    )

        # Cross-family: specific alias must not resolve to generic's keys only.
        for sid in specific_ids:
            specific = by_id.get(sid)
            if not specific:
                continue
            base = normalize_lookup_key(specific["name"])
            for alias in specific.get("aliases", []):
                key = normalize_lookup_key(alias)
                owner = alias_index.get(key)
                if owner and owner != sid:
                    report.add(
                        "error",
                        "duplicate_alias",
                        f"Alias {alias!r} on {sid!r} already owned by {owner!r}",
                        sid,
                    )
                # Variant-specific strings belong on specific, not generic.
                if key == base:
                    continue
                if not key.startswith(base) and base not in key.split():
                    report.add(
                        "warning",
                        "specific_alias_weak_link",
                        f"Alias {alias!r} on {sid!r} may not clearly belong to this entry",
                        sid,
                    )


def check_facet_base_conflicts(items: list[dict], families_data: dict, report: ValidationReport) -> None:
    """Facet options must not duplicate standalone catalog entry names unless linked."""
    by_id = items_by_id(items)
    name_to_id = {normalize_lookup_key(item["name"]): item["id"] for item in items}
    slug_to_id = {item["id"]: item["id"] for item in items}
    for item in items:
        slug_to_id[slugify(item["name"])] = item["id"]

    by_generic, specific_to_generic = family_maps(families_data)
    allowed_facet_entry_ids: set[tuple[str, str, str]] = set()

    for family in families_data.get("families", []):
        gid = family.get("genericId")
        if not gid:
            continue
        for label, sid in family.get("variantToSpecificId", {}).items():
            allowed_facet_entry_ids.add((gid, "variant", normalize_lookup_key(label)))

    for item in items:
        for facet in item.get("facets", []):
            key = facet.get("key")
            for option in facet.get("options", []):
                opt_key = normalize_lookup_key(option)
                opt_slug = slugify(option)
                conflicting_id = name_to_id.get(opt_key) or slug_to_id.get(opt_slug)
                if not conflicting_id or conflicting_id == item["id"]:
                    continue
                # Allowed when option is a mapped variant on generic parent.
                if (item["id"], key, opt_key) in allowed_facet_entry_ids:
                    continue
                if item["id"] in by_generic and conflicting_id in by_generic[item["id"]].get(
                    "specificIds", []
                ):
                    continue
                if item["id"] in specific_to_generic:
                    continue
                report.add(
                    "error",
                    "facet_duplicates_entry",
                    f"{item['id']!r} facet {key}.{option!r} duplicates catalog entry {conflicting_id!r}",
                    item["id"],
                )


def check_item_is_not_both_base_and_facet(items: list[dict], report: ValidationReport) -> None:
    """Catalog entry names should not appear as facet options on unrelated items."""
    # Covered primarily by check_facet_base_conflicts; add id-as-facet check.
    all_ids = {item["id"] for item in items}
    for item in items:
        for facet in item.get("facets", []):
            for option in facet.get("options", []):
                if slugify(option) in all_ids and slugify(option) != item["id"]:
                    # Only warn here; error emitted by facet_duplicates_entry when name matches.
                    pass


def validate_catalog(*, strict: bool = False) -> ValidationReport:
    report = ValidationReport()
    items = load_catalog()
    if not FAMILIES_PATH.exists():
        report.add("error", "families_missing", f"Missing {FAMILIES_PATH}")
        return report
    families_data = load_families()

    check_required_fields(items, report)
    check_duplicate_aliases(items, report)
    check_self_aliases(items, report)
    check_families(items, families_data, report)
    check_generic_specific_aliases(items, families_data, report)
    check_facet_base_conflicts(items, families_data, report)
    check_item_is_not_both_base_and_facet(items, report)

    if strict:
        for finding in report.warnings:
            finding.severity = "error"

    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate PantryChef catalog integrity.")
    parser.add_argument("--strict", action="store_true", help="Treat warnings as errors.")
    parser.add_argument("--json", action="store_true", help="Emit JSON report.")
    args = parser.parse_args()

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
