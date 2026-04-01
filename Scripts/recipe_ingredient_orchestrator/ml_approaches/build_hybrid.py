"""Hybrid approach builder.

Combines the best parse and group approaches based on evaluation results.
Strategy: take the best parser's output, combine with the best grouper,
then apply targeted fixes for known failure patterns.
"""

from __future__ import annotations

import json
import logging
from collections import Counter
from pathlib import Path
from typing import Any

from .shared import (
    FoodGroup,
    GroupMember,
    ParsedItem,
    ensure_output_dir,
    load_parse_results,
    load_group_results,
    save_parse_results,
    save_group_results,
)

logger = logging.getLogger(__name__)

APPROACH_NAME = "hybrid"


# ---------------------------------------------------------------------------
# Post-processing fixes for known failure patterns
# ---------------------------------------------------------------------------

# Consumer-friendly name overrides for specific patterns
_NAME_FIXES: dict[str, str] = {
    # "sweet" peppers → "bell" peppers in consumer language
    "Sweet Red Pepper": "Red Bell Pepper",
    "Sweet Green Pepper": "Green Bell Pepper",
    "Sweet Yellow Pepper": "Yellow Bell Pepper",
    # Milk shorthand
    "Reduced Fat Milk": "2% Milk",
    "Low Fat Milk": "1% Milk",
    "Fat Free Milk": "Skim Milk",
}

# Patterns to strip from names (post-parse cleanup)
_STRIP_FROM_NAME = [
    "Pasteurized Process ",
    "Commercially Prepared ",
    "Ready-To-Serve ",
    "Ready-To-Eat ",
    "Frozen Concentrate ",
]


def _apply_name_fixes(items: list[ParsedItem]) -> list[ParsedItem]:
    """Apply targeted name fixes to parsed items."""
    for item in items:
        # Check direct overrides
        if item.parsed_name in _NAME_FIXES:
            item.parsed_name = _NAME_FIXES[item.parsed_name]

        # Strip noise phrases from names
        for strip in _STRIP_FROM_NAME:
            if strip.lower() in item.parsed_name.lower():
                idx = item.parsed_name.lower().find(strip.lower())
                item.parsed_name = (
                    item.parsed_name[:idx]
                    + item.parsed_name[idx + len(strip):]
                ).strip()
                if strip.strip() not in [n.lower() for n in item.noise_removed]:
                    item.noise_removed.append(strip.strip().lower())

        # Ensure name is not empty after fixes
        if not item.parsed_name.strip():
            item.parsed_name = item.original_desc.split(",")[0].strip().title()

    return items


def _merge_parse_results(
    primary: list[ParsedItem],
    secondary: list[ParsedItem],
) -> list[ParsedItem]:
    """Merge two parse results, preferring primary but filling gaps from secondary."""
    secondary_map = {s.fdc_id: s for s in secondary}
    merged = []

    for item in primary:
        sec = secondary_map.get(item.fdc_id)

        # Fill missing base from secondary
        if not item.parsed_base and sec and sec.parsed_base:
            item.parsed_base = sec.parsed_base

        # Fill missing form from secondary
        if not item.form and sec and sec.form:
            item.form = sec.form

        # Fill missing qualifiers from secondary
        if not item.qualifiers and sec and sec.qualifiers:
            item.qualifiers = sec.qualifiers

        # Merge noise (union)
        if sec and sec.noise_removed:
            existing_noise = set(n.lower() for n in item.noise_removed)
            for noise in sec.noise_removed:
                if noise.lower() not in existing_noise:
                    item.noise_removed.append(noise)

        merged.append(item)

    return merged


def _merge_group_results(
    primary: list[FoodGroup],
    secondary: list[FoodGroup],
) -> list[FoodGroup]:
    """Merge group results, using primary structure but enriching facets from secondary."""
    # Build a map from fdc_id → secondary group id
    sec_member_map: dict[int, FoodGroup] = {}
    for group in secondary:
        for member in group.members:
            sec_member_map[member.fdc_id] = group

    for group in primary:
        # Collect facets from secondary groups that contain same members
        secondary_facets: dict[str, set[str]] = {}
        for member in group.members:
            sec_group = sec_member_map.get(member.fdc_id)
            if sec_group:
                for k, v_list in sec_group.suggested_facets.items():
                    if k not in secondary_facets:
                        secondary_facets[k] = set()
                    secondary_facets[k].update(v_list)

        # Merge facets
        for k, v_set in secondary_facets.items():
            if k not in group.suggested_facets:
                group.suggested_facets[k] = sorted(v_set)
            else:
                existing = set(group.suggested_facets[k])
                existing.update(v_set)
                group.suggested_facets[k] = sorted(existing)

    return primary


# ---------------------------------------------------------------------------
# Hybrid construction
# ---------------------------------------------------------------------------

def build_hybrid(
    eval_report: dict[str, Any] | None = None,
) -> tuple[list[ParsedItem], list[FoodGroup]]:
    """Build hybrid from best parse + best group approach.

    If eval_report is not provided, loads from ml_outputs/evaluation_report.json.
    """
    out_dir = ensure_output_dir()

    # Load evaluation report
    if eval_report is None:
        report_path = out_dir / "evaluation_report.json"
        if report_path.exists():
            with open(report_path) as f:
                eval_report = json.load(f)
        else:
            logger.warning("No evaluation report found. Using taxonomy as default.")
            eval_report = {"rankings": {}}

    # Determine best approaches from rankings
    parse_ranking = eval_report.get("rankings", {}).get("parse", [])
    group_ranking = eval_report.get("rankings", {}).get("group", [])

    best_parse = parse_ranking[0]["approach"] if parse_ranking else "taxonomy"
    second_parse = parse_ranking[1]["approach"] if len(parse_ranking) > 1 else None
    best_group = group_ranking[0]["approach"] if group_ranking else "taxonomy_guided"
    second_group = group_ranking[1]["approach"] if len(group_ranking) > 1 else None

    logger.info("Hybrid: best parse=%s, best group=%s", best_parse, best_group)

    # Load parse results
    primary_parse = load_parse_results(best_parse)
    secondary_parse = load_parse_results(second_parse) if second_parse else []

    # Merge parse results
    if secondary_parse:
        hybrid_parse = _merge_parse_results(primary_parse, secondary_parse)
    else:
        hybrid_parse = primary_parse

    # Apply name fixes
    hybrid_parse = _apply_name_fixes(hybrid_parse)

    # Load group results
    primary_groups = load_group_results(best_group)
    secondary_groups = load_group_results(second_group) if second_group else []

    # Merge group results
    if secondary_groups:
        hybrid_groups = _merge_group_results(primary_groups, secondary_groups)
    else:
        hybrid_groups = primary_groups

    # Save hybrid outputs
    save_parse_results(hybrid_parse, APPROACH_NAME)
    save_group_results(hybrid_groups, APPROACH_NAME)

    logger.info("Hybrid built: %d parsed items, %d groups",
                len(hybrid_parse), len(hybrid_groups))

    return hybrid_parse, hybrid_groups


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def run(eval_report: dict[str, Any] | None = None) -> tuple[list[ParsedItem], list[FoodGroup]]:
    """Build hybrid approach."""
    return build_hybrid(eval_report)
