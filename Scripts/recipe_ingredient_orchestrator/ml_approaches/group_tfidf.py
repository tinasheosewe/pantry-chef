"""TF-IDF + Agglomerative clustering for food entry grouping.

Uses TF-IDF vectorization with domain-aware features, then
agglomerative (hierarchical) clustering to group related food entries.

Refinements:
- Per-category clustering: items only cluster within the same USDA category,
  preventing cross-category leakage (e.g., "Kid's Menu Chicken" + "Kid's Menu Cheese").
- Hierarchical splitting: groups larger than MEGA_GROUP_THRESHOLD are re-clustered
  with a tighter distance threshold to produce meaningful sub-groups.
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

# Groups larger than this will be re-split hierarchically
MEGA_GROUP_THRESHOLD = 50

# Distance threshold for the initial pass
PRIMARY_DISTANCE_THRESHOLD = 0.7

# Tighter threshold used when splitting mega-groups
SPLIT_DISTANCE_THRESHOLD = 0.5


def _build_features(items: list[ParsedItem]) -> np.ndarray:
    """Build TF-IDF feature matrix with domain-aware text construction."""
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
        # NOTE: category is NOT included here — per-category clustering
        # handles category separation, so including it would be redundant
        # and would skew similarity within a category.
        docs.append(" ".join(parts))

    logger.info("Building TF-IDF features from %d documents...", len(docs))

    # Adapt min_df for small document sets: use 1 when fewer than 20 docs
    # to avoid dropping valid features in small categories
    effective_min_df = 1 if len(docs) < 20 else 2

    vectorizer = TfidfVectorizer(
        max_features=5000,
        ngram_range=(1, 2),
        min_df=effective_min_df,
        max_df=0.8,
        sublinear_tf=True,
    )
    tfidf_matrix = vectorizer.fit_transform(docs)

    logger.info("TF-IDF matrix: %s, %d features",
                tfidf_matrix.shape, len(vectorizer.get_feature_names_out()))
    return tfidf_matrix


def _cluster(features: np.ndarray,
             distance_threshold: float = PRIMARY_DISTANCE_THRESHOLD,
             n_clusters: int | None = None) -> np.ndarray:
    """Run agglomerative clustering on TF-IDF features."""
    if hasattr(features, "toarray"):
        logger.info("Computing cosine similarity matrix...")
        sim_matrix = cosine_similarity(features)
        distance_matrix = 1 - sim_matrix
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
            result[key] = sorted(options)

    return result


def _pick_group_name(members: list[ParsedItem]) -> str:
    """Choose the best display name for a group.

    Prefers the shortest frequent parsed_base (title-cased) when available,
    falling back to the most common parsed_name.  Strips trim/fat descriptors
    that make names awkward.
    """
    base_counts = Counter(m.parsed_base for m in members if m.parsed_base)
    if base_counts:
        # Pick the most common base; on ties, pick shortest (cleaner)
        top_count = base_counts.most_common(1)[0][1]
        candidates = [b for b, c in base_counts.items() if c == top_count]
        best_base = min(candidates, key=len)
        return best_base.title()

    name_counts = Counter(m.parsed_name for m in members)
    return name_counts.most_common(1)[0][0] if name_counts else members[0].parsed_name


def _build_group(group_id: str, members: list[ParsedItem]) -> FoodGroup:
    """Build a single FoodGroup from a list of members."""
    base_counts = Counter(m.parsed_base for m in members if m.parsed_base)
    cat_counts = Counter(m.usda_category for m in members if m.usda_category)

    group_base = base_counts.most_common(1)[0][0] if base_counts else ""
    group_name = _pick_group_name(members)
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

    return FoodGroup(
        group_id=group_id,
        group_name=group_name,
        base_ingredient=group_base,
        category=group_cat,
        members=group_members,
        suggested_facets=facets,
    )


# ---------------------------------------------------------------------------
# Per-category clustering
# ---------------------------------------------------------------------------

def _cluster_per_category(items: list[ParsedItem]) -> list[FoodGroup]:
    """Cluster items independently within each USDA category.

    This prevents cross-category leakage (e.g., "Kid's Menu Chicken Nuggets"
    clustering with "Kid's Menu Cheese Pizza" due to shared text patterns).
    """
    # Partition items by USDA category
    by_category: dict[str, list[ParsedItem]] = defaultdict(list)
    for item in items:
        cat = item.usda_category or "_uncategorized"
        by_category[cat].append(item)

    logger.info("Per-category clustering across %d categories...",
                len(by_category))

    all_groups: list[FoodGroup] = []
    global_label = 0

    for cat, cat_items in sorted(by_category.items()):
        if len(cat_items) == 1:
            # Singleton category — just make a group of one
            all_groups.append(_build_group(f"agg-{global_label}", cat_items))
            global_label += 1
            continue

        # Build features and cluster within this category
        features = _build_features(cat_items)
        labels = _cluster(features, distance_threshold=PRIMARY_DISTANCE_THRESHOLD)

        # Build groups from within-category clusters
        clusters: dict[int, list[ParsedItem]] = defaultdict(list)
        for item, label in zip(cat_items, labels):
            clusters[int(label)].append(item)

        for _label, members in sorted(clusters.items()):
            all_groups.append(_build_group(f"agg-{global_label}", members))
            global_label += 1

        logger.info("  %s: %d items → %d groups",
                     cat, len(cat_items), len(set(labels)))

    logger.info("Per-category clustering: %d total groups", len(all_groups))
    return all_groups


# ---------------------------------------------------------------------------
# Hierarchical splitting of mega-groups
# ---------------------------------------------------------------------------

def _split_mega_groups(groups: list[FoodGroup],
                       items_by_fdc: dict[int, ParsedItem]) -> list[FoodGroup]:
    """Re-cluster groups larger than MEGA_GROUP_THRESHOLD with a tighter threshold.

    This breaks up overly broad groups (e.g., 603-item "Beef" group) into
    meaningful sub-groups (beef loin, beef round, beef chuck, etc.).
    """
    refined: list[FoodGroup] = []
    split_count = 0
    sub_label = 0

    for group in groups:
        if len(group.members) <= MEGA_GROUP_THRESHOLD:
            refined.append(group)
            continue

        # Recover ParsedItem objects for re-clustering
        member_items = []
        for m in group.members:
            pi = items_by_fdc.get(m.fdc_id)
            if pi:
                member_items.append(pi)

        if len(member_items) < 2:
            refined.append(group)
            continue

        logger.info("Splitting mega-group '%s' (%d members)...",
                     group.group_name, len(member_items))

        # Build features within the mega-group — use a higher max_df since
        # the shared base ingredient (e.g. "beef") will be very frequent but
        # is still useful signal for sub-grouping by cut/part.
        features = _build_features(member_items)
        labels = _cluster(features, distance_threshold=SPLIT_DISTANCE_THRESHOLD)

        sub_clusters: dict[int, list[ParsedItem]] = defaultdict(list)
        for item, label in zip(member_items, labels):
            sub_clusters[int(label)].append(item)

        # Merge back any singletons from the split into the nearest non-singleton
        # sub-cluster to avoid fragmenting mega-groups into noise singletons.
        if len(sub_clusters) > 1:
            singleton_labels = [l for l, m in sub_clusters.items() if len(m) == 1]
            multi_labels = [l for l, m in sub_clusters.items() if len(m) > 1]

            if multi_labels and singleton_labels:
                # Build centroids for multi-member clusters
                from sklearn.feature_extraction.text import TfidfVectorizer as _TV
                all_sub_items = member_items
                docs_all = []
                for it in all_sub_items:
                    parts = []
                    if it.parsed_base:
                        parts.extend([it.parsed_base] * 3)
                    parts.extend(it.parsed_name.lower().split())
                    parts.extend(it.qualifiers)
                    docs_all.append(" ".join(parts))
                vec = _TV(max_features=2000, ngram_range=(1, 2), min_df=1,
                          max_df=0.95, sublinear_tf=True)
                mat = vec.fit_transform(docs_all)
                item_to_idx = {it.fdc_id: i for i, it in enumerate(all_sub_items)}

                for sl in singleton_labels:
                    solo = sub_clusters[sl][0]
                    solo_vec = mat[item_to_idx[solo.fdc_id]]
                    best_label = None
                    best_sim = -1.0
                    for ml in multi_labels:
                        cluster_idxs = [item_to_idx[m.fdc_id] for m in sub_clusters[ml]]
                        centroid = np.asarray(mat[cluster_idxs].mean(axis=0))
                        sim = float(cosine_similarity(solo_vec, centroid)[0, 0])
                        if sim > best_sim:
                            best_sim = sim
                            best_label = ml
                    if best_label is not None:
                        sub_clusters[best_label].append(solo)
                        del sub_clusters[sl]

        n_subs = len(sub_clusters)
        logger.info("  → split into %d sub-groups", n_subs)

        for _label, members in sorted(sub_clusters.items()):
            sub_group = _build_group(
                f"{group.group_id}-sub{sub_label}",
                members,
            )
            # Inherit parent category
            sub_group.category = group.category
            refined.append(sub_group)
            sub_label += 1

        split_count += 1

    logger.info("Hierarchical splitting: split %d mega-groups, %d total groups now",
                split_count, len(refined))
    return refined


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def run(parsed_items: list[ParsedItem] | None = None,
        parse_approach: str = "taxonomy") -> list[FoodGroup]:
    """Build TF-IDF features and cluster with agglomerative clustering.

    Pipeline:
    1. Per-category clustering (prevents cross-category leakage)
    2. Hierarchical splitting of groups > MEGA_GROUP_THRESHOLD
    """
    if parsed_items is None:
        parsed_items = load_parse_results(parse_approach)
        if not parsed_items:
            raise RuntimeError(
                f"No parse results found for '{parse_approach}'. "
                "Run a parse approach first."
            )

    logger.info("Grouping %d items with TF-IDF + agglomerative...", len(parsed_items))

    # Build fdc_id → ParsedItem lookup for mega-group splitting
    items_by_fdc = {item.fdc_id: item for item in parsed_items}

    # Phase 1: cluster within each USDA category
    groups = _cluster_per_category(parsed_items)

    # Phase 2: split mega-groups
    groups = _split_mega_groups(groups, items_by_fdc)

    # Re-number group IDs sequentially
    for i, group in enumerate(groups):
        group.group_id = f"agg-{i}"

    save_group_results(groups, APPROACH_NAME)
    logger.info("TF-IDF+Agglomerative grouping complete: %d groups from %d items",
                len(groups), len(parsed_items))
    return groups
