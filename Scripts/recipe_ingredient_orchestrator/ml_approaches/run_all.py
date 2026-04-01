#!/usr/bin/env python3
"""Run all ML approaches, evaluate, build hybrid, and produce summary.

Usage:
    python -m ml_approaches.run_all          # full pipeline
    python -m ml_approaches.run_all --parse   # parse-only
    python -m ml_approaches.run_all --group   # group-only (uses best parse)
    python -m ml_approaches.run_all --eval    # eval-only (uses cached results)
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from pathlib import Path
from typing import Any

# ---- Setup ----------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s  %(name)s  %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("run_all")

from .shared import (
    load_usda_foods,
    ensure_output_dir,
    save_parse_results,
    save_group_results,
    load_parse_results,
)
from . import parse_crf
from . import parse_spacy_ner
from . import parse_taxonomy
from . import group_embeddings
from . import group_tfidf
from . import group_taxonomy
from . import evaluate as eval_module
from . import build_hybrid


# ---- Phase runners ---------------------------------------------------------

def run_parse_phase() -> dict[str, list]:
    """Run all 3 parse approaches, return dict[approach → parsed items]."""
    foods = load_usda_foods()
    logger.info("Loaded %d USDA foods for parsing", len(foods))

    results: dict[str, list] = {}

    start = time.time()
    for label, mod in [
        ("crf", parse_crf),
        ("spacy_ner", parse_spacy_ner),
        ("taxonomy", parse_taxonomy),
    ]:
        t0 = time.time()
        logger.info("── Running parse approach: %s", label)
        try:
            items = mod.run(foods)
            save_parse_results(items, label)
            results[label] = items
            logger.info("   %s → %d items  (%.1fs)", label, len(items), time.time() - t0)
        except Exception:
            logger.exception("   %s FAILED", label)
            results[label] = []

    logger.info("Parse phase complete in %.1fs", time.time() - start)
    return results


def run_group_phase(parse_results: dict[str, list] | None = None) -> dict[str, list]:
    """Run all 3 group approaches using each parse result set.

    Returns dict[approach → food groups].
    """
    # If not provided, load cached results
    if parse_results is None:
        parse_results = {}
        for label in ["crf", "spacy_ner", "taxonomy"]:
            try:
                parse_results[label] = load_parse_results(label)
            except FileNotFoundError:
                logger.warning("No cached parse results for %s", label)

    # Use the first available parse result for grouping
    parse_items = None
    parse_label = None
    for label in ["taxonomy", "crf", "spacy_ner"]:  # prefer taxonomy
        if label in parse_results and parse_results[label]:
            parse_items = parse_results[label]
            parse_label = label
            break

    if parse_items is None:
        logger.error("No parse results available for grouping")
        return {}

    logger.info("Using parse results from '%s' for grouping (%d items)", parse_label, len(parse_items))

    results: dict[str, list] = {}

    start = time.time()
    for label, mod in [
        ("embeddings", group_embeddings),
        ("tfidf", group_tfidf),
        ("taxonomy_guided", group_taxonomy),
    ]:
        t0 = time.time()
        logger.info("── Running group approach: %s", label)
        try:
            groups = mod.run(parse_items)
            save_group_results(groups, label)
            results[label] = groups
            logger.info("   %s → %d groups  (%.1fs)", label, len(groups), time.time() - t0)
        except Exception:
            logger.exception("   %s FAILED", label)
            results[label] = []

    logger.info("Group phase complete in %.1fs", time.time() - start)
    return results


def run_evaluation_phase() -> dict[str, Any]:
    """Run evaluation across all approaches."""
    logger.info("── Running evaluation")
    t0 = time.time()
    report = eval_module.run_evaluation()
    logger.info("Evaluation complete in %.1fs", time.time() - t0)
    return report


def run_hybrid_phase(eval_report: dict[str, Any]) -> None:
    """Build hybrid from evaluation results."""
    logger.info("── Building hybrid")
    t0 = time.time()
    hybrid_parse, hybrid_groups = build_hybrid.run(eval_report)
    logger.info("Hybrid: %d items, %d groups  (%.1fs)",
                len(hybrid_parse), len(hybrid_groups), time.time() - t0)


# ---- Summary ---------------------------------------------------------------

def print_summary(report: dict[str, Any]) -> None:
    """Print human-readable summary to stdout."""
    out_dir = ensure_output_dir()

    print("\n" + "=" * 70)
    print("  ML APPROACH EVALUATION SUMMARY")
    print("=" * 70)

    # Parse rankings
    parse_ranking = report.get("rankings", {}).get("parse", [])
    if parse_ranking:
        print("\n  PARSE APPROACH RANKINGS:")
        print("  " + "-" * 40)
        for i, entry in enumerate(parse_ranking, 1):
            print(f"    {i}. {entry['approach']:15s}  composite={entry['composite_score']:.1f}")

        # Detail for best parse
        best_parse = parse_ranking[0]["approach"]
        parse_details = report.get("parse_results", {}).get(best_parse, {})
        if parse_details:
            print(f"\n  Best parser: {best_parse}")
            print(f"    Golden-50 score:     {parse_details.get('golden_score', 0):.2f}")
            print(f"    Regression fix rate: {parse_details.get('regression_pass_rate', 0):.1%}")
            print(f"    Non-regression hold: {parse_details.get('non_regression_pass_rate', 0):.1%}")
            print(f"    Noise removal rate:  {parse_details.get('noise_removal_rate', 0):.1%}")
            print(f"    Base coverage:       {parse_details.get('base_coverage', 0):.1%}")

    # Group rankings
    group_ranking = report.get("rankings", {}).get("group", [])
    if group_ranking:
        print("\n  GROUP APPROACH RANKINGS:")
        print("  " + "-" * 40)
        for i, entry in enumerate(group_ranking, 1):
            sr = entry.get('singleton_rate', 0)
            fr = entry.get('facet_rate', 0)
            print(f"    {i}. {entry['approach']:20s}  singletons={sr:.1f}%  facets={fr:.1f}%")

        best_group = group_ranking[0]["approach"]
        group_details = report.get("group_results", {}).get(best_group, {})
        if group_details:
            print(f"\n  Best grouper: {best_group}")
            print(f"    Total groups:    {group_details.get('total_groups', 0)}")
            print(f"    Singleton rate:  {group_details.get('singleton_rate', 0):.1%}")
            print(f"    Facet rate:      {group_details.get('facet_rate', 0):.1%}")
            print(f"    Avg group size:  {group_details.get('avg_group_size', 0):.1f}")
            print(f"    Homogeneity:     {group_details.get('base_homogeneity', 0):.2f}")

    print("\n  Full report: " + str(out_dir / "evaluation_report.json"))
    print("=" * 70 + "\n")


# ---- Main ------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Run ML ingredient pipeline")
    parser.add_argument("--parse", action="store_true", help="Run parse phase only")
    parser.add_argument("--group", action="store_true", help="Run group phase only")
    parser.add_argument("--eval", action="store_true", help="Run evaluation only")
    parser.add_argument("--hybrid", action="store_true", help="Build hybrid only")
    args = parser.parse_args()

    # Ensure output directory exists
    ensure_output_dir()

    total_start = time.time()

    # If specific phase requested, run only that
    if args.parse:
        run_parse_phase()
        return

    if args.group:
        run_group_phase()
        return

    if args.eval:
        report = run_evaluation_phase()
        print_summary(report)
        return

    if args.hybrid:
        report_path = ensure_output_dir() / "evaluation_report.json"
        if report_path.exists():
            with open(report_path) as f:
                report = json.load(f)
        else:
            report = run_evaluation_phase()
        run_hybrid_phase(report)
        return

    # Full pipeline
    logger.info("=" * 50)
    logger.info("STARTING FULL ML PIPELINE")
    logger.info("=" * 50)

    # Phase 1: Parse
    parse_results = run_parse_phase()

    # Phase 2: Group
    group_results = run_group_phase(parse_results)

    # Phase 3: Evaluate
    report = run_evaluation_phase()

    # Phase 4: Hybrid
    run_hybrid_phase(report)

    # Phase 5: Summary
    elapsed = time.time() - total_start
    logger.info("Total pipeline time: %.1fs", elapsed)
    print_summary(report)


if __name__ == "__main__":
    main()
