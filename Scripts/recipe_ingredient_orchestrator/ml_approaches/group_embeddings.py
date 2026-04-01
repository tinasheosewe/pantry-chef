"""Embedding + HDBSCAN clustering for food entry grouping.

Uses sentence-transformers (all-MiniLM-L6-v2) to embed parsed food names,
then HDBSCAN to find natural clusters of related items.
Facets are derived from within-cluster variation.
"""

from __future__ import annotations

import logging
from collections import Counter, defaultdict
from typing import Any

import hdbscan
import numpy as np
from sentence_transformers import SentenceTransformer

from .shared import (
    FoodGroup,
    GroupMember,
    ParsedItem,
    load_parse_results,
    save_group_results,
)

logger = logging.getLogger(__name__)

APPROACH_NAME = "embeddings_hdbscan"


def _build_embeddings(items: list[ParsedItem],
                      model_name: str = "all-MiniLM-L6-v2") -> np.ndarray:
    """Encode parsed names + base + category as sentence embeddings."""
    logger.info("Loading sentence-transformer model '%s'...", model_name)
    model = SentenceTransformer(model_name)

    # Build rich text for embedding: combine name, base, qualifiers, category
    texts = []
    for item in items:
        parts = [item.parsed_name]
        if item.parsed_base:
            parts.append(item.parsed_base)
        if item.qualifiers:
            parts.append(" ".join(item.qualifiers))
        if item.usda_category:
            parts.append(item.usda_category)
        texts.append(" | ".join(parts))

    logger.info("Encoding %d items...", len(texts))
    embeddings = model.encode(texts, show_progress_bar=True, batch_size=128)
    return np.array(embeddings)


def _cluster(embeddings: np.ndarray,
             min_cluster_size: int = 2,
             min_samples: int = 1) -> np.ndarray:
    """Run HDBSCAN clustering on embeddings."""
    logger.info("Running HDBSCAN (min_cluster=%d, min_samples=%d)...",
                min_cluster_size, min_samples)
    # Precompute cosine distance matrix (HDBSCAN BallTree doesn't support cosine)
    from sklearn.metrics.pairwise import cosine_distances
    dist_matrix = cosine_distances(embeddings).astype(np.float64)
    clusterer = hdbscan.HDBSCAN(
        min_cluster_size=min_cluster_size,
        min_samples=min_samples,
        metric="precomputed",
        cluster_selection_method="leaf",
    )
    labels = clusterer.fit_predict(dist_matrix)

    n_clusters = len(set(labels)) - (1 if -1 in labels else 0)
    n_noise = (labels == -1).sum()
    logger.info("HDBSCAN: %d clusters, %d noise points", n_clusters, n_noise)
    return labels


def _extract_facets(members: list[ParsedItem]) -> dict[str, list[str]]:
    """Derive facets from within-cluster variation."""
    facets: dict[str, set[str]] = defaultdict(set)

    # Collect all qualifiers across cluster members
    all_quals: list[str] = []
    all_forms: list[str] = []
    all_bases: set[str] = set()

    for m in members:
        all_quals.extend(m.qualifiers)
        if m.form:
            all_forms.append(m.form)
        if m.parsed_base:
            all_bases.add(m.parsed_base)

    # If members have different qualifiers, those are variant facets
    qual_counts = Counter(all_quals)
    # Qualifiers that appear in some but not all members → variant facets
    for qual, count in qual_counts.items():
        if qual and count < len(members):
            facets["variant"].add(qual)

    # Forms → form facet
    form_set = set(all_forms)
    if len(form_set) > 1:
        facets["form"] = form_set

    # If qualifiers include color terms → variant
    colors = {"red", "green", "yellow", "white", "black", "brown"}
    for qual in qual_counts:
        if qual.lower() in colors:
            facets["variant"].add(qual)

    # If qualifiers include fat-level terms → processing facet
    fat_terms = {"nonfat", "low-fat", "reduced-fat", "fat-free", "part-skim", "whole"}
    for qual in qual_counts:
        if qual.lower() in fat_terms:
            facets["processing"].add(qual)

    return {k: sorted(v) for k, v in facets.items() if v}


def _build_groups(items: list[ParsedItem],
                  labels: np.ndarray) -> list[FoodGroup]:
    """Convert cluster labels into FoodGroup objects."""
    # Group items by cluster label
    clusters: dict[int, list[ParsedItem]] = defaultdict(list)
    for item, label in zip(items, labels):
        clusters[int(label)].append(item)

    groups: list[FoodGroup] = []

    for label, members in sorted(clusters.items()):
        if label == -1:
            # Noise points become singleton groups
            for m in members:
                groups.append(FoodGroup(
                    group_id=f"singleton-{m.fdc_id}",
                    group_name=m.parsed_name,
                    base_ingredient=m.parsed_base,
                    category=m.usda_category,
                    members=[GroupMember(
                        fdc_id=m.fdc_id,
                        parsed_name=m.parsed_name,
                        distinguishing_attrs={},
                    )],
                    suggested_facets={},
                ))
            continue

        # Find most common base and name for group
        base_counts = Counter(m.parsed_base for m in members if m.parsed_base)
        name_counts = Counter(m.parsed_name for m in members)

        group_base = base_counts.most_common(1)[0][0] if base_counts else ""
        group_name = name_counts.most_common(1)[0][0] if name_counts else members[0].parsed_name

        # Category from most common
        cat_counts = Counter(m.usda_category for m in members)
        group_cat = cat_counts.most_common(1)[0][0] if cat_counts else ""

        # Extract facets from variation within cluster
        facets = _extract_facets(members)

        # Build member list with distinguishing attributes
        group_members = []
        for m in members:
            attrs: dict[str, str] = {}
            if m.qualifiers:
                attrs["qualifiers"] = ", ".join(m.qualifiers)
            if m.form:
                attrs["form"] = m.form
            group_members.append(GroupMember(
                fdc_id=m.fdc_id,
                parsed_name=m.parsed_name,
                distinguishing_attrs=attrs,
            ))

        groups.append(FoodGroup(
            group_id=f"cluster-{label}",
            group_name=group_name,
            base_ingredient=group_base,
            category=group_cat,
            members=group_members,
            suggested_facets=facets,
        ))

    return groups


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def run(parsed_items: list[ParsedItem] | None = None,
        parse_approach: str = "taxonomy") -> list[FoodGroup]:
    """Embed parsed items and cluster with HDBSCAN."""
    if parsed_items is None:
        parsed_items = load_parse_results(parse_approach)
        if not parsed_items:
            raise RuntimeError(
                f"No parse results found for '{parse_approach}'. "
                "Run a parse approach first."
            )

    logger.info("Grouping %d items with embeddings + HDBSCAN...", len(parsed_items))

    embeddings = _build_embeddings(parsed_items)
    labels = _cluster(embeddings)
    groups = _build_groups(parsed_items, labels)

    save_group_results(groups, APPROACH_NAME)
    logger.info("Embedding+HDBSCAN grouping complete: %d groups from %d items",
                len(groups), len(parsed_items))
    return groups
