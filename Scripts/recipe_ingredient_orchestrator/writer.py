"""Serializes catalog and recipes to JSON output files."""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from pathlib import Path

from .models import CatalogEntry, Recipe

logger = logging.getLogger(__name__)


class OutputWriter:
    """Writes generation results to JSON files."""

    def __init__(self, output_dir: Path) -> None:
        self._output_dir = output_dir

    def write(
        self,
        catalog: list[CatalogEntry],
        recipes: list[Recipe],
    ) -> None:
        self._output_dir.mkdir(parents=True, exist_ok=True)

        # Catalog
        if catalog:
            catalog_path = self._output_dir / "ingredient_catalog.json"
            catalog_data = [e.model_dump(mode="json", exclude_none=True) for e in catalog]
            catalog_path.write_text(json.dumps(catalog_data, indent=2, ensure_ascii=False))
            logger.info("Wrote %d catalog entries to %s", len(catalog), catalog_path)

        # Recipes
        if recipes:
            recipes_path = self._output_dir / "recipes.json"
            recipes_data = [r.model_dump(mode="json", exclude_none=True) for r in recipes]
            recipes_path.write_text(json.dumps(recipes_data, indent=2, ensure_ascii=False))
            logger.info("Wrote %d recipes to %s", len(recipes), recipes_path)

        # Summary
        summary = {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "catalog_entries": len(catalog),
            "recipes": len(recipes),
        }
        summary_path = self._output_dir / "summary.json"
        summary_path.write_text(json.dumps(summary, indent=2))
        logger.info("Wrote summary to %s", summary_path)
