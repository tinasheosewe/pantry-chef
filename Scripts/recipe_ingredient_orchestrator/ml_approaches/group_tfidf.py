"""TF-IDF + Agglomerative clustering for food entry grouping.

Uses TF-IDF vectorization with domain-aware features, then
agglomerative (hierarchical) clustering to group related food entries.
"""

from __future__ import annotations

import logging
from collections import Counter, defaultdict
from typing import Any

import numpy as np
from sklearn.cluster import AgglomerativeClustering
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

from .shared import (
    FoodGroup,
    GroupMember,
    ParsedItem,
    load_parse_results,
    save_group_results,
)

logger = logging.getLogger(__name__)

APPROACH_NAME = "tfidf_agglomerative"


def _build_features(items: list[ParsedItem]) -> np.ndarray:
    """Build TF-IDF feature matrix with domain-aware text construction."""
    # Construct rich text documents for each item
    docs = []
    for item in items:
        parts = []
        # Repeat base ingredient for emphasis (domain signal)
        if item.parsed_base:
            parts.extend([item.parsed_base] * 3)
        # Parsed name tokens
        parts.extend(item.parsed_name.lower().split())
        # Qualifiers
        parts.extend(item.qualifiers)
        # Category (normalized)
        if item.usda_category:
            cat_tokens = item.usda_category.lower().replace(",", "").split()
            parts.extend(cat_tokens)
        docs.append(" ".join(parts))

    logger.info("Building TF-IDF features from %d documents...", len(docs))

    vectorizer = TfidfVectorizer(
        max_features=5000,
        ngram_range=(1, 2),
        min_df=2,
        max_df=0.8,
        sublinear_tf=True,
    )
    tfidf_matrix = vectorizer.fit_transform(docs)

    logger.info("TF-IDF matrix: %s, %d features",
                tfidf_matrix.shape, len(vectorizer.get_feature_names_out()))
    return tfidf_matrix


def _cluster(features: np.ndarray,
             distance_threshold: float = 0.7,
             n_clusters: int | None = None) -> np.ndarray:
    """Run agglomerative clustering on TF-IDF features."""
    # Convert sparse to dense if needed
    if hasattr(features, "toarray"):
        # For large matrices, use connectivity-based approach
        logger.info("Computing cosine similarity matrix...")
        sim_matrix = cosine_similarity(features)
        distance_matrix = 1 - sim_matrix
        # Clip to avoid numerical issues
        distance_matrix = np.clip(distance_matrix, 0, 2)
    else:
        distance_matrix = features

    logger.info("Running agglomerative clustering (threshold=%.2f)...",
                distance_threshold)

    clustering = AgglomerativeClustering(
        n_clusters=n_clusters,
        distance_threshold=distance_threshold if n_clusters is None else None,
        metric="precomputed",
        linkage="average",
    )
    labels = clustering.fit_predict(distance_matrix)

    n_clusters_found = len(set(labels))
    logger.info("Agglomerative: %d clusters", n_clusters_found)
    return labels


def _extract_facets(members: list[ParsedItem]) -> dict[str, list[str]]:
    """Derive facets from within-cluster variation."""
    facets: dict[str, set[str]] = defaultdict(set)

    for m in members:
        for q in m.qualifiers:
            facets["variant"].add(q)
        if m.form:
            for form_part in m.form.split():
                facets["form"].add(form_part)

    # Only keep facets with multiple options (variation)
    result = {}
    for key, options in facets.items():
        if len(options) > 1:
            result[key] = sorted(options)
        elif len(options) == 1 and len(members) > 1:
            # Single option present in some members but not all
            result[key] = sorted(options)

    return result


def _build_groups(items: list[ParsedItem],
                  labels: np.ndarray) -> list[FoodGroup]:
    """Convert cluster labels into FoodGroup objects."""
    clusters: dict[int, list[ParsedItem]] = defaultdict(list)
    for item, label in zip(items, labels):
        clusters[int(label)].append(item)

    groups: list[FoodGroup] = []

    for label, members in sorted(clusters.items()):
        # Determine group name from most frequent base + name
        base_counts = Counter(m.parsed_base for m in members if m.parsed_base)
        name_counts = Counter(m.parsed_name for m in members)
        cat_counts = Counter(m.usda_category for m in members if m.usda_category)

        group_base = base_counts.most_common(1)[0][0] if base_counts else ""
        group_name = name_counts.most_common(1)[0][0] if name_counts else members[0].parsed_name
        group_cat = cat_counts.most_common(1)[0][0] if cat_counts else ""

        facets = _extract_facets(members)

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
            group_id=f"agg-{label}",
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
    """Build TF-IDF features and cluster with agglomerative clustering."""
    if parsed_items is None:
        parsed_items = load_parse_results(parse_approach)
        if not parsed_items:
            raise RuntimeError(
                f"No parse results found for '{parse_approach}'. "
                "Run a parse approach first."
            )

    logger.info("Grouping %d items with TF-IDF + agglomerative...", len(parsed_items))

    features = _build_features(parsed_items)
    labels = _cluster(features)
    groups = _build_groups(parsed_items, labels)

    save_group_results(groups, APPROACH_NAME)
    logger.info("TF-IDF+Agglomerative grouping complete: %d groups from %d items",
                len(groups), len(parsed_items))
    return groups
