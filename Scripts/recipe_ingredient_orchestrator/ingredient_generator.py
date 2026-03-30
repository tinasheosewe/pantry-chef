"""Ingredient catalog generation via LLM."""

from __future__ import annotations

import asyncio
import logging

from pydantic import BaseModel, Field

from .catalog import InMemoryCatalog
from .client import LLMClient
from .config import Settings
from .models import CatalogEntry
from .prompts import ingredient_generation_messages

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
        """Generate `count` ingredients across parallel batches.

        Multiple batches run concurrently, and the catalog's add_many
        handles deduplication of any overlapping entries.
        """
        generated: list[CatalogEntry] = []
        remaining = count
        max_parallel = self._settings.max_concurrency

        while remaining > 0:
            # Determine how many parallel batches to run
            batches_needed = (remaining + self._settings.ingredient_batch_size - 1) // self._settings.ingredient_batch_size
            parallel_count = min(batches_needed, max_parallel)

            logger.info(
                "Generating %d parallel ingredient batches (%d remaining, catalog size: %d)",
                parallel_count,
                remaining,
                catalog.size,
            )

            async def generate_single_batch() -> list[CatalogEntry]:
                batch_size = min(remaining, self._settings.ingredient_batch_size)
                messages = ingredient_generation_messages(
                    count=batch_size,
                    existing_names=catalog.names(),
                    category_filter=category_filter,
                    prompt_context=prompt_context,
                    catalog_summary=catalog.summary_with_facets(),
                )
                response = await self._client.generate(
                    messages=messages,
                    response_model=IngredientBatchResponse,
                    model=self._settings.enrichment_model,
                    temperature=0.7,
                )
                return response.entries

            # Run batches in parallel
            tasks = [generate_single_batch() for _ in range(parallel_count)]
            results = await asyncio.gather(*tasks, return_exceptions=True)

            # Merge all entries and add to catalog (dedupes automatically)
            all_entries: list[CatalogEntry] = []
            for result in results:
                if isinstance(result, Exception):
                    logger.error("Batch failed: %s", result)
                else:
                    all_entries.extend(result)

            added = await catalog.add_many(all_entries)
            generated.extend(all_entries[:added] if added < len(all_entries) else all_entries)
            remaining -= added

            if added == 0:
                logger.warning("Parallel batches produced 0 new entries — stopping")
                break

            logger.info("Parallel batch done: %d new entries added, %d remaining", added, remaining)

        logger.info("Ingredient generation complete: %d total entries", len(generated))
        return generated
