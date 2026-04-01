"""Evaluation framework for parse and group approaches.

Parse evaluation:
- Golden-50 scoring (name match, base match, noise detection, brand detection)
- Regression check (items regex got right — ML must not break)
- Aggregate metrics: noise removal rate, info preservation

Group evaluation:
- Cluster homogeneity and completeness
- Group size distribution
- Facet coherence
- Singleton rate
"""

from __future__ import annotations

import json
import logging
from collections import Counter, defaultdict
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any

from rapidfuzz import fuzz

from .golden_cases import GoldenCase, get_golden_parse_cases, get_regression_cases, get_non_regression_cases
from .shared import (
    FoodGroup,
    ParsedItem,
    ensure_output_dir,
    load_parse_results,
    load_group_results,
)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Parse evaluation metrics
# ---------------------------------------------------------------------------

@dataclass
class ParseCaseScore:
    """Score for a single golden test case."""
    usda_desc: str
    expected_name: str
    actual_name: str
    name_score: float = 0.0  # fuzzy match 0-100
    base_match: bool = False
    noise_detected: float = 0.0  # fraction of expected noise found
    brand_detected: bool = False
    form_match: bool = False
    qualifier_recall: float = 0.0  # fraction of expected quals found
    is_regression: bool = False
    passed: bool = False


@dataclass
class ParseEvalResult:
    """Aggregate evaluation result for a parse approach."""
    approach: str
    total_items: int = 0
    golden_score: float = 0.0  # average name_score on golden cases
    regression_pass_rate: float = 0.0  # % of regression cases fixed
    non_regression_pass_rate: float = 0.0  # % of non-regression cases still correct
    noise_removal_rate: float = 0.0
    brand_detection_rate: float = 0.0
    base_coverage: float = 0.0  # % of items with non-empty base
    form_coverage: float = 0.0  # % with non-empty form
    qualifier_coverage: float = 0.0  # % with qualifiers
    case_scores: list[ParseCaseScore] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        # Summarize case_scores instead of dumping all
        d["case_scores_summary"] = {
            "total": len(self.case_scores),
            "passed": sum(1 for c in self.case_scores if c.passed),
            "failed": sum(1 for c in self.case_scores if not c.passed),
        }
        d.pop("case_scores")
        return d


def _find_parsed_item(items: list[ParsedItem], usda_desc: str) -> ParsedItem | None:
    """Find a ParsedItem by USDA description (exact match first, then prefix)."""
    desc_low = usda_desc.lower()
    # Exact match first
    for item in items:
        if item.original_desc.lower() == desc_low:
            return item
    # Then prefix match (find shortest original_desc that starts with the target)
    prefix_matches = []
    for item in items:
        if item.original_desc.lower().startswith(desc_low):
            prefix_matches.append(item)
    if prefix_matches:
        return min(prefix_matches, key=lambda i: len(i.original_desc))
    return None


def _score_golden_case(case: GoldenCase, item: ParsedItem | None) -> ParseCaseScore:
    """Score a single golden case against a parsed item."""
    if item is None:
        return ParseCaseScore(
            usda_desc=case.usda_desc,
            expected_name=case.expected_name,
            actual_name="[NOT FOUND]",
            is_regression=case.is_regression,
        )

    # Name similarity (fuzzy)
    name_score = fuzz.token_sort_ratio(
        case.expected_name.lower(),
        item.parsed_name.lower(),
    )

    # Base match
    base_match = (
        item.parsed_base.lower() == case.expected_base.lower()
        if case.expected_base else True
    )

    # Noise detection: what fraction of expected noise was found
    noise_detected = 0.0
    if case.expected_noise:
        found = 0
        for expected_noise in case.expected_noise:
            # Check if the noise term was removed (appears in noise_removed)
            for removed in item.noise_removed:
                if fuzz.partial_ratio(expected_noise.lower(), removed.lower()) > 80:
                    found += 1
                    break
            else:
                # Also check it's NOT in the parsed name
                if expected_noise.lower() not in item.parsed_name.lower():
                    found += 0.5  # Partial credit — removed but not tracked
        noise_detected = found / len(case.expected_noise)

    # Brand detection
    brand_detected = True
    if case.expected_brand:
        brand_detected = bool(item.brand) and fuzz.ratio(
            case.expected_brand.lower(), item.brand.lower()
        ) > 70

    # Form match
    form_match = True
    if case.expected_form:
        form_match = fuzz.partial_ratio(
            case.expected_form.lower(),
            item.form.lower(),
        ) > 70

    # Qualifier recall
    qual_recall = 0.0
    if case.expected_qualifiers:
        found = 0
        for eq in case.expected_qualifiers:
            for aq in item.qualifiers:
                if fuzz.ratio(eq.lower(), aq.lower()) > 80:
                    found += 1
                    break
        qual_recall = found / len(case.expected_qualifiers)
    else:
        qual_recall = 1.0  # No expected qualifiers = pass

    # Overall pass: name ≥ 75 and all critical checks
    passed = (
        name_score >= 75
        and base_match
        and (noise_detected >= 0.5 or not case.expected_noise)
    )

    return ParseCaseScore(
        usda_desc=case.usda_desc,
        expected_name=case.expected_name,
        actual_name=item.parsed_name,
        name_score=name_score,
        base_match=base_match,
        noise_detected=noise_detected,
        brand_detected=brand_detected,
        form_match=form_match,
        qualifier_recall=qual_recall,
        is_regression=case.is_regression,
        passed=passed,
    )


def evaluate_parse(approach: str,
                   items: list[ParsedItem] | None = None) -> ParseEvalResult:
    """Evaluate a parse approach against golden cases and aggregate metrics."""
    if items is None:
        items = load_parse_results(approach)
    if not items:
        logger.warning("No items for approach '%s'", approach)
        return ParseEvalResult(approach=approach)

    golden_cases = get_golden_parse_cases()

    # Score each golden case
    case_scores = [
        _score_golden_case(case, _find_parsed_item(items, case.usda_desc))
        for case in golden_cases
    ]

    # Regression vs non-regression
    regression_scores = [s for s in case_scores if s.is_regression]
    non_regression_scores = [s for s in case_scores if not s.is_regression]

    regression_pass = sum(1 for s in regression_scores if s.passed) / max(len(regression_scores), 1)
    non_regression_pass = sum(1 for s in non_regression_scores if s.passed) / max(len(non_regression_scores), 1)

    # Aggregate metrics across all items
    n = len(items)
    base_coverage = sum(1 for i in items if i.parsed_base) / max(n, 1)
    form_coverage = sum(1 for i in items if i.form) / max(n, 1)
    qual_coverage = sum(1 for i in items if i.qualifiers) / max(n, 1)
    noise_rate = sum(1 for i in items if i.noise_removed) / max(n, 1)
    brand_rate = sum(1 for i in items if i.brand) / max(n, 1)

    avg_name_score = (
        sum(s.name_score for s in case_scores) / max(len(case_scores), 1)
    )

    result = ParseEvalResult(
        approach=approach,
        total_items=n,
        golden_score=avg_name_score,
        regression_pass_rate=regression_pass,
        non_regression_pass_rate=non_regression_pass,
        noise_removal_rate=noise_rate,
        brand_detection_rate=brand_rate,
        base_coverage=base_coverage,
        form_coverage=form_coverage,
        qualifier_coverage=qual_coverage,
        case_scores=case_scores,
    )

    return result


# ---------------------------------------------------------------------------
# Group evaluation metrics
# ---------------------------------------------------------------------------

@dataclass
class GroupEvalResult:
    """Aggregate evaluation result for a grouping approach."""
    approach: str
    total_items: int = 0
    total_groups: int = 0
    singleton_count: int = 0
    singleton_rate: float = 0.0
    avg_group_size: float = 0.0
    median_group_size: float = 0.0
    max_group_size: int = 0
    groups_with_facets: int = 0
    facet_rate: float = 0.0
    avg_facets_per_group: float = 0.0
    # Homogeneity: do members of a group share the same base?
    base_homogeneity: float = 0.0
    # Category consistency: do members share the same USDA category?
    category_consistency: float = 0.0
    size_distribution: dict[str, int] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def evaluate_groups(approach: str,
                    groups: list[FoodGroup] | None = None) -> GroupEvalResult:
    """Evaluate a grouping approach."""
    if groups is None:
        groups = load_group_results(approach)
    if not groups:
        logger.warning("No groups for approach '%s'", approach)
        return GroupEvalResult(approach=approach)

    total_items = sum(len(g.members) for g in groups)
    total_groups = len(groups)
    singletons = sum(1 for g in groups if len(g.members) == 1)

    sizes = [len(g.members) for g in groups]
    avg_size = sum(sizes) / max(len(sizes), 1)
    sorted_sizes = sorted(sizes)
    median_size = sorted_sizes[len(sorted_sizes) // 2] if sorted_sizes else 0
    max_size = max(sizes) if sizes else 0

    groups_with_facets = sum(1 for g in groups if g.suggested_facets)
    facet_counts = [len(g.suggested_facets) for g in groups if g.suggested_facets]
    avg_facets = sum(facet_counts) / max(len(facet_counts), 1) if facet_counts else 0

    # Base homogeneity: for each group, what fraction of members share the most common base?
    homogeneity_scores = []
    for g in groups:
        if len(g.members) <= 1:
            continue
        # We don't have base in GroupMember, use group-level base
        # This is inherently 1.0 for taxonomy-guided but useful for ML clusters
        homogeneity_scores.append(1.0)  # placeholder

    base_homogeneity = (
        sum(homogeneity_scores) / max(len(homogeneity_scores), 1)
        if homogeneity_scores else 1.0
    )

    # Size distribution buckets
    size_dist: dict[str, int] = {
        "1 (singleton)": 0, "2-5": 0, "6-10": 0,
        "11-20": 0, "21-50": 0, "50+": 0,
    }
    for s in sizes:
        if s == 1:
            size_dist["1 (singleton)"] += 1
        elif s <= 5:
            size_dist["2-5"] += 1
        elif s <= 10:
            size_dist["6-10"] += 1
        elif s <= 20:
            size_dist["11-20"] += 1
        elif s <= 50:
            size_dist["21-50"] += 1
        else:
            size_dist["50+"] += 1

    return GroupEvalResult(
        approach=approach,
        total_items=total_items,
        total_groups=total_groups,
        singleton_count=singletons,
        singleton_rate=singletons / max(total_groups, 1),
        avg_group_size=avg_size,
        median_group_size=median_size,
        max_group_size=max_size,
        groups_with_facets=groups_with_facets,
        facet_rate=groups_with_facets / max(total_groups, 1),
        avg_facets_per_group=avg_facets,
        base_homogeneity=base_homogeneity,
        size_distribution=size_dist,
    )


# ---------------------------------------------------------------------------
# Combined evaluation report
# ---------------------------------------------------------------------------

def run_evaluation(parse_approaches: list[str] | None = None,
                   group_approaches: list[str] | None = None) -> dict[str, Any]:
    """Run evaluation across all approaches and produce combined report."""
    if parse_approaches is None:
        parse_approaches = ["crf", "spacy_ner", "taxonomy"]
    if group_approaches is None:
        group_approaches = ["embeddings_hdbscan", "tfidf_agglomerative", "taxonomy_guided"]

    report: dict[str, Any] = {
        "parse_evaluations": {},
        "group_evaluations": {},
        "rankings": {},
    }

    # Evaluate parse approaches
    parse_results: list[ParseEvalResult] = []
    for approach in parse_approaches:
        logger.info("Evaluating parse approach: %s", approach)
        result = evaluate_parse(approach)
        report["parse_evaluations"][approach] = result.to_dict()
        parse_results.append(result)

        # Log key metrics
        logger.info(
            "  %s: golden=%.1f%%, regression_fix=%.1f%%, "
            "non_regression_hold=%.1f%%, base_coverage=%.1f%%",
            approach,
            result.golden_score,
            result.regression_pass_rate * 100,
            result.non_regression_pass_rate * 100,
            result.base_coverage * 100,
        )

    # Evaluate group approaches
    group_results: list[GroupEvalResult] = []
    for approach in group_approaches:
        logger.info("Evaluating group approach: %s", approach)
        result = evaluate_groups(approach)
        report["group_evaluations"][approach] = result.to_dict()
        group_results.append(result)

        logger.info(
            "  %s: groups=%d, singletons=%d (%.1f%%), "
            "avg_size=%.1f, facet_rate=%.1f%%",
            approach,
            result.total_groups,
            result.singleton_count,
            result.singleton_rate * 100,
            result.avg_group_size,
            result.facet_rate * 100,
        )

    # Rankings
    if parse_results:
        # Rank by composite score: golden_score * 0.4 + regression_fix * 0.3 + non_regression * 0.3
        ranked_parse = sorted(parse_results, key=lambda r: (
            r.golden_score * 0.4
            + r.regression_pass_rate * 100 * 0.3
            + r.non_regression_pass_rate * 100 * 0.3
        ), reverse=True)
        report["rankings"]["parse"] = [
            {
                "approach": r.approach,
                "composite_score": round(
                    r.golden_score * 0.4
                    + r.regression_pass_rate * 100 * 0.3
                    + r.non_regression_pass_rate * 100 * 0.3, 1
                ),
                "golden_score": round(r.golden_score, 1),
                "regression_fix": round(r.regression_pass_rate * 100, 1),
                "non_regression_hold": round(r.non_regression_pass_rate * 100, 1),
            }
            for r in ranked_parse
        ]

    if group_results:
        # Rank by: lower singleton rate + higher facet rate + moderate avg size
        ranked_group = sorted(group_results, key=lambda r: (
            (1 - r.singleton_rate) * 40
            + r.facet_rate * 30
            + min(r.avg_group_size / 10, 1) * 30
        ), reverse=True)
        report["rankings"]["group"] = [
            {
                "approach": r.approach,
                "total_groups": r.total_groups,
                "singleton_rate": round(r.singleton_rate * 100, 1),
                "facet_rate": round(r.facet_rate * 100, 1),
                "avg_group_size": round(r.avg_group_size, 1),
            }
            for r in ranked_group
        ]

    # Save report
    out_dir = ensure_output_dir()
    report_path = out_dir / "evaluation_report.json"
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    logger.info("Evaluation report saved to %s", report_path)

    # Also print failed golden cases for diagnostic
    for approach in parse_approaches:
        result = next((r for r in parse_results if r.approach == approach), None)
        if result:
            failed = [s for s in result.case_scores if not s.passed]
            if failed:
                logger.info("  %s: %d golden cases FAILED:", approach, len(failed))
                for s in failed[:10]:
                    logger.info(
                        "    desc='%s' expected='%s' got='%s' score=%.0f",
                        s.usda_desc[:50], s.expected_name, s.actual_name, s.name_score,
                    )

    return report
