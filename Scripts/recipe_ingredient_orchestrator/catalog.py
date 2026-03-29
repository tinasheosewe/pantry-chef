"""In-memory ingredient catalog with async-safe operations."""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path

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

    # -- Mutations ----------------------------------------------------------

    async def add(self, entry: CatalogEntry) -> bool:
        """Add an entry. Returns False if ID already exists (no overwrite)."""
        async with self._lock:
            if entry.id in self._entries:
                logger.debug("Catalog: skipping duplicate id=%s", entry.id)
                return False
            self._entries[entry.id] = entry
            return True

    async def add_many(self, entries: list[CatalogEntry]) -> int:
        """Add multiple entries. Returns count of newly added."""
        added = 0
        async with self._lock:
            for entry in entries:
                if entry.id not in self._entries:
                    self._entries[entry.id] = entry
                    added += 1
                else:
                    logger.debug("Catalog: skipping duplicate id=%s", entry.id)
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
        logger.info("Loaded %d entries from %s", len(catalog._entries), path)
        return catalog
