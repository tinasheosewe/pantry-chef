"""In-memory ingredient catalog with async-safe operations."""

from __future__ import annotations

import asyncio
import json
import logging
import re
from pathlib import Path
from typing import Optional

from .models import CatalogEntry, Substitution

logger = logging.getLogger(__name__)


class InMemoryCatalog:
    """Thread-safe (async) ingredient catalog.

    Keyed by entry ID. Provides compact summaries for LLM context and
    a post-generation substitution linking pass.
    """

    def __init__(self) -> None:
        self._entries: dict[str, CatalogEntry] = {}
        self._lock = asyncio.Lock()
        # Overlap detection index: normalised token → entry ID
        self._token_index: dict[str, str] = {}

    # -- Overlap detection --------------------------------------------------

    @staticmethod
    def _normalise(text: str) -> str:
        """Lower-case, strip non-alphanumeric, collapse whitespace."""
        return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", "", text.lower())).strip()

    @staticmethod
    def _stem_variants(word: str) -> list[str]:
        """Generate common culinary word stems/variants for overlap matching."""
        stems = [word]
        # powdered→powder, smoked→smoke, roasted→roast, etc.
        if word.endswith("ed"):
            stems.append(word[:-2])
            stems.append(word[:-1])  # "smoked" → "smoke"
        if word.endswith("d") and not word.endswith("ed"):
            stems.append(word[:-1])
        # powder→powdered, smoke→smoked, etc.
        if not word.endswith("ed"):
            stems.append(word + "d")
            stems.append(word + "ed")
        return stems

    def _tokens_for_entry(self, entry: CatalogEntry) -> list[str]:
        """Build the set of normalised tokens an entry "claims".

        Includes:
        - the entry name
        - every alias
        - name combined with each variant/form option  ("cheese cheddar", "garlic powdered")
        - stemmed form variants ("garlic powder" from form=powdered)
        - multi-word variant options on their own       ("extra virgin", "stone ground")
          (single-word variants like "sweet" are too broad for standalone registration)
        """
        tokens: list[str] = [self._normalise(entry.name)]
        for alias in entry.aliases:
            tokens.append(self._normalise(alias))

        base = self._normalise(entry.name)
        for facet in entry.facets:
            if facet.key in ("variant", "form"):
                for opt in facet.options:
                    nopt = self._normalise(opt)
                    # Register original + stemmed combinations
                    for stem in self._stem_variants(nopt):
                        tokens.append(f"{base} {stem}")
                        tokens.append(f"{stem} {base}")
                    # Only register standalone variant tokens for multi-word options;
                    # single words like "sweet", "dried", "hot" cause false positives.
                    if facet.key == "variant" and len(nopt.split()) >= 2:
                        tokens.append(nopt)
        return tokens

    def _register_tokens(self, entry: CatalogEntry) -> None:
        """Add an entry's tokens to the overlap index."""
        for token in self._tokens_for_entry(entry):
            self._token_index.setdefault(token, entry.id)

    def _is_overlap(self, entry: CatalogEntry) -> Optional[str]:
        """Check if *entry* overlaps with something already in the catalog.

        Returns the existing entry ID that causes the overlap, or None.

        Sibling entries that share a base_ingredient are allowed (e.g.
        chicken-breast and chicken-thigh both have base_ingredient='chicken').
        """
        candidate_name = self._normalise(entry.name)
        candidate_words = set(candidate_name.split())

        def _is_sibling(existing_id: str) -> bool:
            """True if candidate and existing entry are siblings in the same family."""
            if not entry.base_ingredient:
                return False
            existing = self._entries.get(existing_id)
            if not existing:
                return False
            return (
                existing.base_ingredient is not None
                and existing.base_ingredient == entry.base_ingredient
                and self._normalise(existing.name) != candidate_name
            )

        def _is_qualified_variant(existing_id: str) -> bool:
            """True if the candidate is a multi-word qualified form of a single-word
            existing entry (e.g. 'Smoked Paprika' vs 'Paprika').  These are
            culinarily distinct products, not overlaps."""
            existing = self._entries.get(existing_id)
            if not existing:
                return False
            existing_words = set(self._normalise(existing.name).split())
            return (
                len(existing_words) == 1
                and len(candidate_words) > 1
                and existing_words < candidate_words
            )

        # Direct name collision with an existing token
        if candidate_name in self._token_index:
            existing_id = self._token_index[candidate_name]
            if existing_id != entry.id and not _is_sibling(existing_id) and not _is_qualified_variant(existing_id):
                return existing_id

        # Check every alias — with name-relevance verification for indirect matches.
        for alias in entry.aliases:
            norm_alias = self._normalise(alias)
            if norm_alias in self._token_index:
                existing_id = self._token_index[norm_alias]
                if existing_id != entry.id and not _is_sibling(existing_id):
                    existing_entry = self._entries.get(existing_id)
                    if not existing_entry:
                        return existing_id
                    existing_name = self._normalise(existing_entry.name)
                    existing_alias_words = set(existing_name.split())
                    # Allow qualified variants: if the candidate name adds a
                    # qualifier to a single-word base (e.g. "Smoked Paprika"
                    # has alias "Paprika" matching existing "Paprika"), that's
                    # a distinct product, not an overlap.
                    is_qualified_of_single_base = (
                        len(existing_alias_words) == 1
                        and len(candidate_words) > 1
                        and existing_alias_words < candidate_words
                    )
                    if is_qualified_of_single_base:
                        continue
                    # Strong match: alias matches existing entry's actual name
                    if norm_alias == existing_name:
                        return existing_id
                    # Indirect match: require name word-subset relationship
                    if existing_alias_words < candidate_words or candidate_words < existing_alias_words:
                        return existing_id

        # Word-superset check: catch new qualifier+base combos not yet indexed.
        # Skip when entries are siblings in the same base_ingredient family.
        # Also allow "qualified variants" — when a multi-word candidate extends a
        # single-word existing entry (e.g. "Smoked Paprika" vs "Paprika"), or vice-
        # versa, because the qualifier typically makes it a distinct product.
        candidate_words = set(candidate_name.split())
        if len(candidate_words) >= 1:
            for existing_id, existing_entry in self._entries.items():
                if existing_id == entry.id:
                    continue
                if existing_entry.category != entry.category:
                    continue
                if _is_sibling(existing_id):
                    continue
                existing_base = self._normalise(existing_entry.name)
                existing_words = set(existing_base.split())
                if existing_base == candidate_name:
                    continue
                if existing_words < candidate_words or candidate_words < existing_words:
                    smaller = min(len(existing_words), len(candidate_words))
                    # A single-word base being extended by a qualifier is a distinct
                    # product (e.g. "sausage" → "andouille sausage", "paprika" →
                    # "smoked paprika"). Only flag as overlap when the smaller name
                    # already has 2+ words — that indicates a true near-duplicate.
                    if smaller >= 2:
                        return existing_id

        return None

    def _rebuild_index(self) -> None:
        """Rebuild the full token index from scratch (used after load)."""
        self._token_index.clear()
        for entry in self._entries.values():
            self._register_tokens(entry)

    # -- Mutations ----------------------------------------------------------

    async def add(self, entry: CatalogEntry) -> bool:
        """Add an entry. Returns False if ID already exists or overlaps."""
        async with self._lock:
            if entry.id in self._entries:
                logger.debug("Catalog: skipping duplicate id=%s", entry.id)
                return False
            overlap_id = self._is_overlap(entry)
            if overlap_id:
                logger.warning(
                    "Catalog: rejecting '%s' — overlaps with existing '%s'",
                    entry.name, overlap_id,
                )
                return False
            self._entries[entry.id] = entry
            self._register_tokens(entry)
            return True

    async def add_many(self, entries: list[CatalogEntry]) -> int:
        """Add multiple entries, rejecting duplicates and overlaps.

        Returns count of newly added.
        """
        added = 0
        async with self._lock:
            for entry in entries:
                if entry.id in self._entries:
                    logger.debug("Catalog: skipping duplicate id=%s", entry.id)
                    continue
                overlap_id = self._is_overlap(entry)
                if overlap_id:
                    logger.warning(
                        "Catalog: rejecting '%s' — overlaps with existing '%s'",
                        entry.name, overlap_id,
                    )
                    continue
                self._entries[entry.id] = entry
                self._register_tokens(entry)
                added += 1
        return added

    def _merge_entries(self, existing: CatalogEntry, incoming: CatalogEntry) -> CatalogEntry:
        """Merge two catalog entries, combining enrichment data.
        
        Strategy:
        - aliases: union, deduplicated, preserving order (existing first)
        - facets: merge options for same key, add new keys
        - substitution_suggestions: union, dedupe by substitute_name
        - substitutions: union, dedupe by substitute_id
        - freshness_by_storage: take max days for overlapping storage types
        - notes/scalar fields: take longer/richer value or incoming if existing is None
        """
        from .models import FacetDefinition, StorageFreshness
        
        # Union aliases (existing first, then new ones)
        seen_aliases = set(a.lower() for a in existing.aliases)
        merged_aliases = list(existing.aliases)
        for alias in incoming.aliases:
            if alias.lower() not in seen_aliases:
                merged_aliases.append(alias)
                seen_aliases.add(alias.lower())
        
        # Merge facets by key
        facet_by_key: dict[str, list[str]] = {}
        for f in existing.facets:
            facet_by_key[f.key] = list(f.options)
        for f in incoming.facets:
            if f.key in facet_by_key:
                # Union options
                seen = set(facet_by_key[f.key])
                for opt in f.options:
                    if opt not in seen:
                        facet_by_key[f.key].append(opt)
                        seen.add(opt)
            else:
                facet_by_key[f.key] = list(f.options)
        merged_facets = [
            FacetDefinition(key=k, options=opts) for k, opts in facet_by_key.items()
        ]
        
        # Union substitution_suggestions by substitute_name
        seen_subs = set(s.substitute_name.lower() for s in existing.substitution_suggestions)
        merged_suggestions = list(existing.substitution_suggestions)
        for s in incoming.substitution_suggestions:
            if s.substitute_name.lower() not in seen_subs:
                merged_suggestions.append(s)
                seen_subs.add(s.substitute_name.lower())
        
        # Union substitutions by substitute_id
        seen_sub_ids = set(s.substitute_id for s in existing.substitutions)
        merged_substitutions = list(existing.substitutions)
        for s in incoming.substitutions:
            if s.substitute_id not in seen_sub_ids:
                merged_substitutions.append(s)
                seen_sub_ids.add(s.substitute_id)
        
        # Merge freshness_by_storage - take max days for each storage type
        freshness_by_storage_type: dict[str, StorageFreshness] = {}
        for f in existing.freshness_by_storage:
            freshness_by_storage_type[f.storage.value] = f
        for f in incoming.freshness_by_storage:
            key = f.storage.value
            if key in freshness_by_storage_type:
                old = freshness_by_storage_type[key]
                freshness_by_storage_type[key] = StorageFreshness(
                    storage=f.storage,
                    min_days=max(old.min_days, f.min_days),
                    max_days=max(old.max_days, f.max_days),
                )
            else:
                freshness_by_storage_type[key] = f
        merged_freshness = list(freshness_by_storage_type.values())
        
        # For scalar fields, take incoming if it provides more info
        merged_base = incoming.base_ingredient if incoming.base_ingredient else existing.base_ingredient
        merged_unit = incoming.default_unit if incoming.default_unit else existing.default_unit
        merged_qty = incoming.default_quantity if incoming.default_quantity else existing.default_quantity
        
        # Use existing entry's id and name (canonical), but merge everything else
        return existing.model_copy(update={
            "aliases": merged_aliases,
            "facets": merged_facets,
            "substitution_suggestions": merged_suggestions,
            "substitutions": merged_substitutions,
            "freshness_by_storage": merged_freshness,
            "base_ingredient": merged_base,
            "default_unit": merged_unit,
            "default_quantity": merged_qty,
            "default_selections": incoming.default_selections if incoming.default_selections else existing.default_selections,
        })

    async def merge(self, entry: CatalogEntry) -> bool:
        """Merge an entry with an existing one by ID.
        
        If the entry doesn't exist, returns False (use add() or add_or_merge() instead).
        If it exists, merges the data and returns True.
        """
        async with self._lock:
            if entry.id not in self._entries:
                logger.debug("Catalog: merge failed, id=%s not found", entry.id)
                return False
            
            existing = self._entries[entry.id]
            merged = self._merge_entries(existing, entry)
            self._entries[entry.id] = merged
            # Re-register tokens in case aliases changed
            self._register_tokens(merged)
            logger.debug("Catalog: merged entry id=%s", entry.id)
            return True

    async def add_or_merge(self, entry: CatalogEntry) -> tuple[bool, str]:
        """Add a new entry or merge with existing if ID matches.
        
        Returns (success, action) where action is 'added', 'merged', or 'rejected'.
        Rejection only happens for overlap with a DIFFERENT entry (not self).
        """
        async with self._lock:
            if entry.id in self._entries:
                # Merge with existing
                existing = self._entries[entry.id]
                merged = self._merge_entries(existing, entry)
                self._entries[entry.id] = merged
                self._register_tokens(merged)
                logger.debug("Catalog: merged entry id=%s", entry.id)
                return (True, "merged")
            
            # Check for overlap with other entries
            overlap_id = self._is_overlap(entry)
            if overlap_id:
                logger.warning(
                    "Catalog: rejecting '%s' — overlaps with existing '%s'",
                    entry.name, overlap_id,
                )
                return (False, "rejected")
            
            # New entry
            self._entries[entry.id] = entry
            self._register_tokens(entry)
            logger.debug("Catalog: added new entry id=%s", entry.id)
            return (True, "added")

    async def add_or_merge_many(self, entries: list[CatalogEntry]) -> dict[str, int]:
        """Add or merge multiple entries.
        
        Returns stats: {added: N, merged: N, rejected: N}.
        """
        stats = {"added": 0, "merged": 0, "rejected": 0}
        async with self._lock:
            for entry in entries:
                if entry.id in self._entries:
                    existing = self._entries[entry.id]
                    merged = self._merge_entries(existing, entry)
                    self._entries[entry.id] = merged
                    self._register_tokens(merged)
                    stats["merged"] += 1
                else:
                    overlap_id = self._is_overlap(entry)
                    if overlap_id:
                        logger.warning(
                            "Catalog: rejecting '%s' — overlaps with existing '%s'",
                            entry.name, overlap_id,
                        )
                        stats["rejected"] += 1
                    else:
                        self._entries[entry.id] = entry
                        self._register_tokens(entry)
                        stats["added"] += 1
        
        logger.info(
            "Catalog add_or_merge_many: %d added, %d merged, %d rejected",
            stats["added"], stats["merged"], stats["rejected"],
        )
        return stats

    # -- Queries ------------------------------------------------------------

    def get(self, entry_id: str) -> CatalogEntry | None:
        return self._entries.get(entry_id)

    def has(self, entry_id: str) -> bool:
        return entry_id in self._entries

    def all_entries(self) -> list[CatalogEntry]:
        return list(self._entries.values())

    @property
    def size(self) -> int:
        return len(self._entries)

    def names(self) -> list[str]:
        """All entry names for dedup context in prompts."""
        return [e.name for e in self._entries.values()]

    def summary_for_prompt(self) -> str:
        """Compact catalog representation for LLM context.

        Lists each entry as: id | name | category | variants
        Kept concise to fit in prompt context windows.
        """
        if not self._entries:
            return "(empty catalog)"
        lines = []
        for e in self._entries.values():
            variants = ""
            for f in e.facets:
                if f.key == "variant":
                    variants = f" variants=[{', '.join(f.options)}]"
                    break
            lines.append(f"- {e.id} | {e.name} | {e.category.value}{variants}")
        return "\n".join(lines)

    def summary_with_facets(self, max_entries: int = 300) -> str:
        """Facet-aware catalog summary for ingredient generation prompts.

        Shows each entry with ALL facet dimensions so the LLM can see which
        variants/forms already exist and avoid creating overlapping entries.
        Capped at *max_entries* to prevent prompt blowup.
        """
        if not self._entries:
            return "(empty catalog)"
        lines = []
        entries = list(self._entries.values())[:max_entries]
        for e in entries:
            facet_parts = []
            for f in e.facets:
                facet_parts.append(f"{f.key}=[{', '.join(f.options)}]")
            facets_str = "; ".join(facet_parts) if facet_parts else "no facets"
            aliases_str = ", ".join(e.aliases[:3]) if e.aliases else ""
            line = f"- {e.name} ({e.category.value})"
            if e.base_ingredient:
                line += f" [family={e.base_ingredient}]"
            line += f" | {facets_str}"
            if aliases_str:
                line += f" | aliases: {aliases_str}"
            lines.append(line)
        if len(self._entries) > max_entries:
            lines.append(f"... and {len(self._entries) - max_entries} more entries")
        return "\n".join(lines)

    def entries_for_resolution(self) -> list[dict]:
        """Catalog entries serialized for the resolution prompt.

        Includes id, name, aliases, and facet options so the LLM
        can match recipe ingredients to catalog entries.
        """
        result = []
        for e in self._entries.values():
            entry_dict: dict = {
                "id": e.id,
                "name": e.name,
                "category": e.category.value,
                "aliases": e.aliases,
            }
            if e.facets:
                entry_dict["facets"] = [
                    {"key": f.key, "options": f.options} for f in e.facets
                ]
            result.append(entry_dict)
        return result

    # -- Substitution linking -----------------------------------------------

    async def link_substitutions(self) -> dict[str, int]:
        """Post-generation pass: convert SubstitutionSuggestions to Substitutions.

        For each entry's substitution_suggestions, looks up substitute_name
        in the catalog. Found → linked Substitution, not found → dropped.

        Returns stats: {linked: N, dropped: N}.
        """
        stats = {"linked": 0, "dropped": 0}
        # Build name→id lookup (case-insensitive)
        name_to_id: dict[str, str] = {}
        async with self._lock:
            for e in self._entries.values():
                name_to_id[e.name.lower()] = e.id
                for alias in e.aliases:
                    name_to_id[alias.lower()] = e.id

            for entry in self._entries.values():
                linked: list[Substitution] = []
                for suggestion in entry.substitution_suggestions:
                    target_id = name_to_id.get(suggestion.substitute_name.lower())
                    if target_id and target_id != entry.id:
                        linked.append(Substitution(
                            substitute_id=target_id,
                            substitute_facets=suggestion.substitute_facets,
                            ratio=suggestion.ratio,
                            taste_impact=suggestion.taste_impact,
                            texture_impact=suggestion.texture_impact,
                            cooking_impact=suggestion.cooking_impact,
                            notes=suggestion.notes,
                        ))
                        stats["linked"] += 1
                    else:
                        stats["dropped"] += 1

                # Update the entry with linked substitutions (replace model)
                updated = entry.model_copy(update={"substitutions": linked})
                self._entries[entry.id] = updated

        logger.info(
            "Substitution linking: %d linked, %d dropped",
            stats["linked"],
            stats["dropped"],
        )
        return stats

    # -- Persistence --------------------------------------------------------

    @classmethod
    def load_from_file(cls, path: Path) -> "InMemoryCatalog":
        """Load a catalog from a previously-exported JSON file."""
        catalog = cls()
        data = json.loads(path.read_text())
        if not isinstance(data, list):
            raise ValueError(f"Expected JSON array in {path}")
        for item in data:
            entry = CatalogEntry.model_validate(item)
            catalog._entries[entry.id] = entry
        catalog._rebuild_index()
        logger.info("Loaded %d entries from %s", len(catalog._entries), path)
        return catalog
