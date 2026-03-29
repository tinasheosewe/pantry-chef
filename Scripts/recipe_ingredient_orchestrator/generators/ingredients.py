"""Ingredient catalog generation via LLM."""

from __future__ import annotations

import logging

from pydantic import BaseModel, Field

from ..catalog import InMemoryCatalog
from ..client import LLMClient
from ..config import Settings
from ..models import CatalogEntry
from ..prompts import ingredient_generation_messages

logger = logging.getLogger(__name__)


class IngredientBatchResponse(BaseModel):
    """LLM response model for a batch of ingredient catalog entries."""
    entries: list[CatalogEntry] = Field(min_length=1)


class IngredientGenerator:
    """Generates fully-rich ingredient catalog entries in batches."""

    def __init__(self, client: LLMClient, settings: Settings) -> None:
        self._client = client
        self._settings = settings

    async def generate(
        self,
        count: int,
        catalog: InMemoryCatalog,
        *,
        category_filter: str | None = None,
        prompt_context: str | None = None,
    ) -> list[CatalogEntry]:
        """Generate `count` ingredients across one or more batches.

        Each batch is aware of the current catalog state so it avoids duplicates
        and maintains the generic-base pattern.
        """
        generated: list[CatalogEntry] = []
        remaining = count

        while remaining > 0:
            batch_size = min(remaining, self._settings.ingredient_batch_size)
            logger.info(
                "Generating ingredient batch: %d of %d remaining (catalog size: %d)",
                batch_size,
                remaining,
                catalog.size,
            )

            messages = ingredient_generation_messages(
                count=batch_size,
                existing_names=catalog.names(),
                category_filter=category_filter,
                prompt_context=prompt_context,
            )

            response = await self._client.generate(
                messages=messages,
                response_model=IngredientBatchResponse,
                model=self._settings.enrichment_model,
                temperature=0.7,
            )

            added = await catalog.add_many(response.entries)
            generated.extend(response.entries[:added] if added < len(response.entries) else response.entries)
            remaining -= added

            if added == 0:
                logger.warning("Batch produced 0 new entries — retrying with fresh context")
                # Avoid infinite loop: if two consecutive batches add nothing, stop
                remaining -= batch_size

            logger.info("Batch done: %d new entries added, %d remaining", added, remaining)

        logger.info("Ingredient generation complete: %d total entries", len(generated))
        return generated
