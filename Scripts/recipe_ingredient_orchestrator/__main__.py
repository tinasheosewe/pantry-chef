"""CLI entrypoint for the recipe/ingredient orchestrator."""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
from pathlib import Path

from .catalog import InMemoryCatalog
from .client import LLMClient
from .config import Settings, configure_logging
from .ingredient_generator import IngredientGenerator
from .recipe_generator import RecipeGenerator
from .models import GenerationRequest, Recipe
from .orchestrator import GenerationOrchestrator
from .reviewer import RecipeReviewer
from .schemas import CuisineType, FoodCategory, GenerationMode, MealType
from .writer import OutputWriter

logger = logging.getLogger(__name__)


# -- LLM response model for prompt interpretation -------------------------

from pydantic import BaseModel, Field
from typing import Optional


class InterpretedRequest(BaseModel):
    """LLM output when interpreting a natural-language prompt."""
    mode: GenerationMode
    count: int = Field(ge=1)
    cuisine: Optional[str] = None
    meal_type: Optional[str] = None
    category: Optional[str] = None


async def interpret_prompt(prompt: str, client: LLMClient, settings: Settings) -> GenerationRequest:
    """Use the LLM to parse a natural-language prompt into a GenerationRequest."""
    from .prompts import request_interpretation_messages

    messages = request_interpretation_messages(prompt)
    result = await client.generate(
        messages=messages,
        response_model=InterpretedRequest,
        model=settings.planner_model,
        temperature=0.0,
    )

    return GenerationRequest(
        mode=result.mode,
        count=result.count,
        cuisine=CuisineType(result.cuisine) if result.cuisine else None,
        meal_type=MealType(result.meal_type) if result.meal_type else None,
        category=FoodCategory(result.category) if result.category else None,
        prompt=prompt,
    )


async def async_main(args: argparse.Namespace) -> None:
    settings = Settings()
    configure_logging(settings)

    if not settings.openai_api_key:
        logger.error("No OpenAI API key found. Set OPENAI_API_KEY or add it to Config/Secrets.xcconfig")
        sys.exit(1)

    # Build catalog (optionally seeded)
    catalog = InMemoryCatalog()
    if args.seed_catalog:
        catalog = InMemoryCatalog.load_from_file(Path(args.seed_catalog))

    # Load existing recipe titles for dedup
    existing_titles: list[str] = []
    if args.seed_recipes:
        data = json.loads(Path(args.seed_recipes).read_text())
        existing_titles = [r["title"] for r in data if "title" in r]
        logger.info("Loaded %d existing recipe titles for dedup", len(existing_titles))

    # Build request
    client = LLMClient(settings)
    try:
        if args.prompt:
            request = await interpret_prompt(args.prompt, client, settings)
            logger.info("Interpreted prompt as: %s", request.model_dump(exclude_none=True))
        else:
            request = GenerationRequest(
                mode=GenerationMode(args.mode),
                count=args.count,
                cuisine=CuisineType(args.cuisine) if args.cuisine else None,
                meal_type=MealType(args.meal_type) if args.meal_type else None,
                category=FoodCategory(args.category) if args.category else None,
            )

        # Override output dir if specified
        if args.output_dir:
            settings.output_dir = args.output_dir

        # Wire up components
        ingredient_gen = IngredientGenerator(client, settings)
        recipe_gen = RecipeGenerator(client, settings)
        reviewer = RecipeReviewer(client, settings)
        writer = OutputWriter(settings.resolved_output_dir)

        orchestrator = GenerationOrchestrator(
            client=client,
            catalog=catalog,
            ingredient_gen=ingredient_gen,
            recipe_gen=recipe_gen,
            reviewer=reviewer,
            writer=writer,
            settings=settings,
        )

        await orchestrator.run(request, existing_titles=existing_titles)
    finally:
        await client.close()


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="recipe_ingredient_orchestrator",
        description="Generate ingredients and recipes for PantryChef",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    gen = subparsers.add_parser("generate", help="Generate ingredients and/or recipes")

    # Either --prompt (NL) or explicit flags
    group = gen.add_mutually_exclusive_group(required=True)
    group.add_argument("--prompt", type=str, help="Natural-language request (e.g. 'add 400 indian spices')")
    group.add_argument("--mode", choices=["ingredients", "recipes", "both"], help="Generation mode")

    gen.add_argument("--count", type=int, default=10, help="Number of items to generate (default: 10)")
    gen.add_argument("--cuisine", type=str, help="Filter by cuisine (e.g. 'Italian')")
    gen.add_argument("--meal-type", type=str, dest="meal_type", help="Filter by meal type (e.g. 'Dinner')")
    gen.add_argument("--category", type=str, help="Filter by food category (e.g. 'Spices & Herbs')")

    # Incremental run support
    gen.add_argument("--seed-catalog", type=str, dest="seed_catalog", help="Path to existing catalog JSON to seed from")
    gen.add_argument("--seed-recipes", type=str, dest="seed_recipes", help="Path to existing recipes JSON for title dedup")
    gen.add_argument("--output-dir", type=str, dest="output_dir", help="Override output directory")

    # Relink-only mode
    relink = subparsers.add_parser("relink", help="Re-run substitution linking on an existing catalog")
    relink.add_argument("--catalog", type=str, required=True, help="Path to catalog JSON")
    relink.add_argument("--output-dir", type=str, dest="output_dir", help="Override output directory")

    args = parser.parse_args()

    if args.command == "relink":
        asyncio.run(_relink(args))
    else:
        asyncio.run(async_main(args))


async def _relink(args: argparse.Namespace) -> None:
    settings = Settings()
    configure_logging(settings)

    catalog = InMemoryCatalog.load_from_file(Path(args.catalog))
    logger.info("Loaded catalog with %d entries", catalog.size)

    stats = await catalog.link_substitutions()
    logger.info("Substitution linking: %s", stats)

    output_dir = Path(args.output_dir) if args.output_dir else settings.resolved_output_dir
    writer = OutputWriter(output_dir)
    writer.write(catalog=catalog.all_entries(), recipes=[])


if __name__ == "__main__":
    main()
