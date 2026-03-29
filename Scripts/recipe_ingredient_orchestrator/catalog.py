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
            if facet.key.value in ("variant", "form"):
                for opt in facet.options:
                    nopt = self._normalise(opt)
                    # Register original + stemmed combinations
                    for stem in self._stem_variants(nopt):
                        tokens.append(f"{base} {stem}")
                        tokens.append(f"{stem} {base}")
                    # Only register standalone variant tokens for multi-word options;
                    # single words like "sweet", "dried", "hot" cause false positives.
                    if facet.key.value == "variant" and len(nopt.split()) >= 2:
                        tokens.append(nopt)
        return tokens

    def _register_tokens(self, entry: CatalogEntry) -> None:
        """Add an entry's tokens to the overlap index."""
        for token in self._tokens_for_entry(entry):
            self._token_index.setdefault(token, entry.id)

    def _is_overlap(self, entry: CatalogEntry) -> Optional[str]:
        """Check if *entry* overlaps with something already in the catalog.

        Returns the existing entry ID that causes the overlap, or None.
        """
        candidate_name = self._normalise(entry.name)
        candidate_words = set(candidate_name.split())

        # Direct name collision with an existing token
        if candidate_name in self._token_index:
            existing_id = self._token_index[candidate_name]
            if existing_id != entry.id:
                return existing_id

        # Check every alias — with name-relevance verification for indirect matches.
        # Direct match (alias == existing name) is always accepted.
        # Indirect match (alias == existing alias/token) requires that the candidate
        # and existing entry names have a word-subset relationship, preventing
        # false positives from generic aliases like "Nut Oil" or "Dried Herb".
        for alias in entry.aliases:
            norm_alias = self._normalise(alias)
            if norm_alias in self._token_index:
                existing_id = self._token_index[norm_alias]
                if existing_id != entry.id:
                    existing_entry = self._entries.get(existing_id)
                    if not existing_entry:
                        return existing_id
                    existing_name = self._normalise(existing_entry.name)
                    # Strong match: alias matches existing entry's actual name
                    if norm_alias == existing_name:
                        return existing_id
                    # Indirect match: require name word-subset relationship
                    existing_words = set(existing_name.split())
                    if existing_words < candidate_words or candidate_words < existing_words:
                        return existing_id

        # Word-superset check: catch new qualifier+base combos not yet in the token index
        # e.g. "parmesan cheese" when "cheese" exists but doesn't have variant=parmesan
        # Only applies when names share a subset relationship AND are the same category
        # (avoids: "avocado" (Produce) vs "avocado oil" (Oils) are legitimately different)
        candidate_words = set(candidate_name.split())
        if len(candidate_words) >= 1:
            for existing_id, existing_entry in self._entries.items():
                if existing_id == entry.id:
                    continue
                if existing_entry.category != entry.category:
                    continue
                existing_base = self._normalise(existing_entry.name)
                existing_words = set(existing_base.split())
                if existing_base == candidate_name:
                    continue
                if existing_words < candidate_words or candidate_words < existing_words:
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
                if f.key.value == "variant":
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
                facet_parts.append(f"{f.key.value}=[{', '.join(f.options)}]")
            facets_str = "; ".join(facet_parts) if facet_parts else "no facets"
            aliases_str = ", ".join(e.aliases[:3]) if e.aliases else ""
            line = f"- {e.name} ({e.category.value}) | {facets_str}"
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
                    {"key": f.key.value, "options": f.options} for f in e.facets
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
