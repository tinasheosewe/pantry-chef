from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

if __package__ in {None, ""}:
    package_dir = Path(__file__).resolve().parent
    sys.path.insert(0, str(package_dir.parent))
    from recipe_ingredient_orchestrator.artifacts import ArtifactWriter
    from recipe_ingredient_orchestrator.campaigns import RecipeCampaignRunner, load_campaign_spec, load_campaign_spec_from_dir
    from recipe_ingredient_orchestrator.corpus_builder import IngredientCorpusBuilder, RecipeCorpusBuilder, analyze_corpus, export_app_ingredient_catalog
    from recipe_ingredient_orchestrator.corpus import RecipeCorpusIndex
    from recipe_ingredient_orchestrator.config import OrchestratorConfig
    from recipe_ingredient_orchestrator.logging_utils import get_logger, setup_logging
    from recipe_ingredient_orchestrator.models import CampaignSpec, DishSpec
    from recipe_ingredient_orchestrator.openai_client import OpenAIChatClient
    from recipe_ingredient_orchestrator.pipeline import build_demo_orchestrator, build_production_orchestrator
    from recipe_ingredient_orchestrator.promotion import IngredientPromotionStore
    from recipe_ingredient_orchestrator.request_planning import RequestPlanningService
else:
    from .artifacts import ArtifactWriter
    from .campaigns import RecipeCampaignRunner, load_campaign_spec, load_campaign_spec_from_dir
    from .corpus_builder import IngredientCorpusBuilder, RecipeCorpusBuilder, analyze_corpus, export_app_ingredient_catalog
    from .corpus import RecipeCorpusIndex
    from .config import OrchestratorConfig
    from .logging_utils import get_logger, setup_logging
    from .models import CampaignSpec, DishSpec
    from .openai_client import OpenAIChatClient
    from .pipeline import build_demo_orchestrator, build_production_orchestrator
    from .promotion import IngredientPromotionStore
    from .request_planning import RequestPlanningService


logger = get_logger("cli")


def load_spec(spec_file: Path | None, title: str | None) -> DishSpec:
    if spec_file is not None:
        payload = json.loads(spec_file.read_text(encoding="utf-8"))
        return DishSpec(
            title=payload["title"],
            cuisine=payload.get("cuisine"),
            meal_type=payload.get("meal_type"),
            servings=payload.get("servings", 4),
            goals=payload.get("goals", []),
            pantry_focus=payload.get("pantry_focus", []),
            notes=payload.get("notes"),
        )

    return DishSpec(
        title=title or "Creamy Garlic Chicken Pasta",
        cuisine="Italian",
        meal_type="Dinner",
        servings=4,
        goals=["Mock end-to-end orchestration slice"],
    )


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the PantryChef recipe and ingredient orchestrator.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    run_dish = subparsers.add_parser("run-dish", help="Generate one recipe pipeline run.")
    run_dish.add_argument("--title", help="Dish title to use for the run.")
    run_dish.add_argument("--spec-file", type=Path, help="Optional JSON file containing a DishSpec payload.")
    run_dish.add_argument("--demo", action="store_true", help="Use the local demo generator and resolver.")
    run_dish.add_argument(
        "--output-dir",
        type=Path,
        help="Directory where pipeline artifacts will be written.",
    )
    run_dish.add_argument("--empty-catalog", action="store_true", help="Start without built-in seed ingredient entries.")

    run_campaign = subparsers.add_parser("run-campaign", help="Run a batch campaign from a JSON spec file.")
    run_campaign.add_argument("--campaign-file", required=True, type=Path, help="Campaign JSON file.")
    run_campaign.add_argument("--demo", action="store_true", help="Use the local demo generator and resolver.")
    run_campaign.add_argument("--max-concurrency", type=int, help="Override the bounded dish-level parallelism for this run.")
    run_campaign.add_argument("--empty-catalog", action="store_true", help="Start without built-in seed ingredient entries.")

    plan_request = subparsers.add_parser("plan-request", help="Convert a natural language request into a campaign spec.")
    plan_request.add_argument("--request", required=True, help="Natural language request, for example 'generate 10 indian recipes'.")
    plan_request.add_argument("--demo", action="store_true", help="Ignored for planning. Request planning always uses GPT; --demo only affects downstream generation in run-request.")
    plan_request.add_argument("--output-file", type=Path, help="Optional path to write the planned campaign JSON.")

    run_request = subparsers.add_parser("run-request", help="Plan and run a natural language request as a campaign.")
    run_request.add_argument("--request", required=True, help="Natural language request, for example 'generate a duck confit recipe'.")
    run_request.add_argument("--demo", action="store_true", help="Use demo generation after GPT request planning.")
    run_request.add_argument("--max-concurrency", type=int, help="Override the bounded dish-level parallelism for this run.")
    run_request.add_argument("--plan-output-file", type=Path, help="Optional path to write the planned campaign JSON.")
    run_request.add_argument("--empty-catalog", action="store_true", help="Start without built-in seed ingredient entries.")

    resume_campaign = subparsers.add_parser("resume-campaign", help="Resume a campaign directory.")
    resume_campaign.add_argument("--campaign-dir", required=True, type=Path, help="Existing campaign directory.")
    resume_campaign.add_argument("--demo", action="store_true", help="Use the local demo generator and resolver.")
    resume_campaign.add_argument("--max-concurrency", type=int, help="Override the bounded dish-level parallelism for this resume.")
    resume_campaign.add_argument("--empty-catalog", action="store_true", help="Start without built-in seed ingredient entries.")

    report_campaign = subparsers.add_parser("report-campaign", help="Print campaign metrics for a campaign directory.")
    report_campaign.add_argument("--campaign-dir", required=True, type=Path, help="Existing campaign directory.")

    build_ingredient_corpus = subparsers.add_parser("build-ingredient-corpus", help="Grow the first-class ingredient corpus to a target enriched size.")
    build_ingredient_corpus.add_argument("--target-count", type=int, default=1000, help="Target enriched ingredient count.")
    build_ingredient_corpus.add_argument("--batch-size", type=int, default=100, help="Maximum ingredients to request per batch.")
    build_ingredient_corpus.add_argument("--empty-catalog", action="store_true", help="Start from an empty ingredient catalog instead of built-in seed entries.")
    build_ingredient_corpus.add_argument("--report-file", type=Path, help="Optional path for the build report JSON.")

    build_recipe_corpus = subparsers.add_parser("build-recipe-corpus", help="Grow the accepted recipe corpus to a target count.")
    build_recipe_corpus.add_argument("--target-count", type=int, default=1000, help="Target accepted recipe count.")
    build_recipe_corpus.add_argument("--batch-size", type=int, default=25, help="Maximum dishes to plan per batch.")
    build_recipe_corpus.add_argument("--max-concurrency", type=int, help="Override bounded dish-level parallelism for corpus builds.")
    build_recipe_corpus.add_argument("--empty-catalog", action="store_true", help="Start without built-in seed ingredient entries.")
    build_recipe_corpus.add_argument("--report-file", type=Path, help="Optional path for the build report JSON.")

    run_eda = subparsers.add_parser("run-eda", help="Analyze the ingredient and recipe corpus state.")
    run_eda.add_argument("--output-file", type=Path, help="Optional path for the EDA report JSON.")

    export_ingredient_catalog = subparsers.add_parser("export-app-ingredient-catalog", help="Export the ingredient catalog in an app-aligned JSON bundle.")
    export_ingredient_catalog.add_argument("--output-file", type=Path, help="Optional output path for the exported app ingredient catalog JSON.")

    subparsers.add_parser("print-config", help="Print resolved orchestrator configuration.")
    return parser


def build_runtime_orchestrator(config: OrchestratorConfig, demo: bool, include_seed_catalog: bool = True):
    if demo:
        return build_demo_orchestrator(include_seed_catalog=include_seed_catalog)
    return build_production_orchestrator(config, include_seed_catalog=False)


def build_campaign_runner(
    config: OrchestratorConfig,
    demo: bool,
    max_workers: int | None = None,
    include_seed_catalog: bool = True,
) -> RecipeCampaignRunner:
    orchestrator = build_runtime_orchestrator(config, demo, include_seed_catalog=include_seed_catalog)
    return RecipeCampaignRunner(
        orchestrator=orchestrator,
        artifact_writer=ArtifactWriter(),
        promotion_store=IngredientPromotionStore(),
        root_dir=config.output_root,
        accepted_root=config.accepted_root,
        max_workers=max_workers or config.max_concurrency,
    )


def build_request_planner(config: OrchestratorConfig) -> RequestPlanningService:
    config.require_request_planning_support()
    project_root = Path(__file__).resolve().parents[2]
    corpus_index = RecipeCorpusIndex.from_project_root(
        project_root,
        output_root=config.output_root,
        accepted_root=config.accepted_root,
        include_bundled_seed=False,
    )
    client = OpenAIChatClient(config)
    return RequestPlanningService(corpus_index=corpus_index, client=client, planning_model=config.planner_model)


def write_campaign_spec(spec: CampaignSpec, output_file: Path) -> None:
    output_file.parent.mkdir(parents=True, exist_ok=True)
    output_file.write_text(json.dumps(spec, default=_json_default, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _json_default(value):
    if hasattr(value, "__dataclass_fields__"):
        from dataclasses import asdict

        return asdict(value)
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def main(argv: list[str] | None = None) -> int:
    parser = build_argument_parser()
    args = parser.parse_args(argv)
    config = OrchestratorConfig.from_env(base_dir=Path(__file__).resolve().parent)
    log_path = setup_logging(config.output_root, config.log_level)
    logger.info("Command started command=%s", args.command)

    if args.command == "print-config":
        print(
            json.dumps(
                {
                    "generationModel": config.generation_model,
                    "plannerModel": config.planner_model,
                    "reviewModel": config.review_model,
                    "ambiguityModel": config.ambiguity_model,
                    "ingredientModel": config.ingredient_model,
                    "baseUrl": config.base_url,
                    "timeoutSeconds": config.timeout_seconds,
                    "maxRetries": config.max_retries,
                    "maxDishAttempts": config.max_dish_attempts,
                    "maxResolutionCycles": config.max_resolution_cycles,
                    "maxConcurrency": config.max_concurrency,
                    "requestsPerMinute": config.requests_per_minute,
                    "logLevel": config.log_level,
                    "logPath": str(log_path),
                    "outputRoot": str(config.output_root),
                    "acceptedRoot": str(config.accepted_root),
                    "hasOpenAIKey": bool(config.openai_api_key),
                    "openAIKeySource": config.openai_api_key_source,
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 0

    if args.command == "plan-request":
        planner = build_request_planner(config)
        spec = planner.plan(args.request)
        if args.output_file is not None:
            write_campaign_spec(spec, args.output_file)
        logger.info("Request planning completed campaign_id=%s", spec.campaign_id)
        print(json.dumps(spec, default=_json_default, indent=2, sort_keys=True))
        return 0

    if args.command == "run-dish":
        spec = load_spec(args.spec_file, args.title)
        orchestrator = build_runtime_orchestrator(config, args.demo, include_seed_catalog=not args.empty_catalog)
        pipeline_run = orchestrator.run(spec)
        output_dir = args.output_dir or (config.output_root / pipeline_run.run_id)
        artifact_paths = ArtifactWriter().write(pipeline_run, output_dir)

        summary = {
            "runId": pipeline_run.run_id,
            "valid": pipeline_run.validation.is_valid,
            "reviewStatus": None if pipeline_run.review is None else pipeline_run.review.status,
            "failureCode": pipeline_run.failure_code,
            "logPath": str(log_path),
            "errors": pipeline_run.validation.errors,
            "warnings": pipeline_run.validation.warnings,
            "pipelineRun": artifact_paths["pipeline_run"],
            "exportedRecipe": artifact_paths["exported_recipe"],
            "startedAt": pipeline_run.started_at,
            "durationSeconds": pipeline_run.duration_seconds,
            "resolvedIngredients": len(pipeline_run.resolved_recipe.ingredients),
        }
        print(json.dumps(summary, indent=2, sort_keys=True))
        accepted = pipeline_run.validation.is_valid and (pipeline_run.review is None or pipeline_run.review.status == "accepted")
        logger.info("run-dish completed run_id=%s accepted=%s", pipeline_run.run_id, accepted)
        return 0 if accepted else 1

    if args.command == "run-campaign":
        spec = load_campaign_spec(args.campaign_file)
        max_workers = args.max_concurrency or spec.max_concurrency or config.max_concurrency
        runner = build_campaign_runner(config, args.demo, max_workers=max_workers, include_seed_catalog=not args.empty_catalog)
        state = runner.run_campaign(spec)
        print(
            json.dumps(
                {
                    "campaignId": state.campaign_id,
                    "status": state.status,
                    "items": len(state.items),
                    "maxConcurrency": max_workers,
                    "logPath": str(log_path),
                    "metricsPath": str(config.output_root / state.campaign_id / "campaign_metrics.json"),
                    "appImportBundle": str(config.output_root / state.campaign_id / "app_import" / "seed_recipes.json"),
                },
                indent=2,
                sort_keys=True,
            )
        )
        logger.info("run-campaign completed campaign_id=%s status=%s", state.campaign_id, state.status)
        return 0 if state.status == "completed" else 1

    if args.command == "run-request":
        planner = build_request_planner(config)
        spec = planner.plan(args.request)
        if args.plan_output_file is not None:
            write_campaign_spec(spec, args.plan_output_file)
        max_workers = args.max_concurrency or spec.max_concurrency or config.max_concurrency
        runner = build_campaign_runner(config, args.demo, max_workers=max_workers, include_seed_catalog=not args.empty_catalog)
        state = runner.run_campaign(spec)
        print(
            json.dumps(
                {
                    "campaignId": state.campaign_id,
                    "status": state.status,
                    "items": len(state.items),
                    "maxConcurrency": max_workers,
                    "logPath": str(log_path),
                    "metricsPath": str(config.output_root / state.campaign_id / "campaign_metrics.json"),
                    "appImportBundle": str(config.output_root / state.campaign_id / "app_import" / "seed_recipes.json"),
                },
                indent=2,
                sort_keys=True,
            )
        )
        logger.info("run-request completed campaign_id=%s status=%s", state.campaign_id, state.status)
        return 0 if state.status == "completed" else 1

    if args.command == "resume-campaign":
        spec = load_campaign_spec_from_dir(args.campaign_dir)
        max_workers = args.max_concurrency or spec.max_concurrency or config.max_concurrency
        runner = build_campaign_runner(config, args.demo, max_workers=max_workers, include_seed_catalog=not args.empty_catalog)
        state = runner.resume_campaign(args.campaign_dir)
        print(
            json.dumps(
                {
                    "campaignId": state.campaign_id,
                    "status": state.status,
                    "items": len(state.items),
                    "maxConcurrency": max_workers,
                    "logPath": str(log_path),
                    "metricsPath": str(args.campaign_dir / "campaign_metrics.json"),
                    "appImportBundle": str(args.campaign_dir / "app_import" / "seed_recipes.json"),
                },
                indent=2,
                sort_keys=True,
            )
        )
        logger.info("resume-campaign completed campaign_id=%s status=%s", state.campaign_id, state.status)
        return 0 if state.status == "completed" else 1

    if args.command == "report-campaign":
        metrics_path = args.campaign_dir / "campaign_metrics.json"
        if not metrics_path.exists():
            raise RuntimeError(f"Campaign metrics file not found: {metrics_path}")
        print(metrics_path.read_text(encoding="utf-8").rstrip())
        return 0

    if args.command == "build-ingredient-corpus":
        config.require_openai_api_key()
        builder = IngredientCorpusBuilder(OpenAIChatClient(config), model=config.ingredient_model)
        report_path = args.report_file or (config.output_root / "corpus_builds" / "ingredients" / "latest.json")
        report = builder.build(
            target_count=max(1, args.target_count),
            batch_size=max(1, args.batch_size),
            storage_dir=config.output_root / "ingredient_catalog",
            report_path=report_path,
            include_seed_entries=False,
        )
        print(json.dumps({"reportPath": str(report_path), **report["metrics"]}, indent=2, sort_keys=True))
        return 0 if report["metrics"]["enriched_count"] >= args.target_count else 1

    if args.command == "build-recipe-corpus":
        config.require_openai_api_key()
        max_workers = args.max_concurrency or config.max_concurrency
        runner = build_campaign_runner(config, False, max_workers=max_workers, include_seed_catalog=not args.empty_catalog)
        builder = RecipeCorpusBuilder(OpenAIChatClient(config), runner=runner, model=config.planner_model)
        project_root = Path(__file__).resolve().parents[2]
        report_path = args.report_file or (config.output_root / "corpus_builds" / "recipes" / "latest.json")
        report = builder.build(
            project_root=project_root,
            output_root=config.output_root,
            accepted_root=config.accepted_root,
            target_count=max(1, args.target_count),
            batch_size=max(1, args.batch_size),
            report_path=report_path,
        )
        print(json.dumps({"reportPath": str(report_path), **report["metrics"]}, indent=2, sort_keys=True))
        return 0 if report["metrics"]["accepted_recipe_count"] >= args.target_count else 1

    if args.command == "run-eda":
        project_root = Path(__file__).resolve().parents[2]
        report = analyze_corpus(project_root, config.output_root, config.accepted_root)
        if args.output_file is not None:
            args.output_file.parent.mkdir(parents=True, exist_ok=True)
            args.output_file.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0

    if args.command == "export-app-ingredient-catalog":
        output_path = args.output_file or (config.output_root / "app_import" / "ingredient_catalog.json")
        report = export_app_ingredient_catalog(config.output_root / "ingredient_catalog", output_path)
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0

    raise RuntimeError(f"Unknown command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())