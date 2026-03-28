from __future__ import annotations

import json
from pathlib import Path

from .models import PipelineRun, ResolvedRecipeArtifact, slugify, utc_now_iso


class ArtifactWriter:
    def write(self, pipeline_run: PipelineRun, output_dir: Path) -> dict[str, str]:
        output_dir.mkdir(parents=True, exist_ok=True)

        pipeline_run_path = output_dir / "pipeline_run.json"
        exported_recipe_path = output_dir / "exported_recipe.json"
        app_seed_recipe_path = output_dir / "app_seed_recipe.json"

        pipeline_run_path.write_text(
            json.dumps(pipeline_run.to_dict(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        exported_recipe_path.write_text(
            json.dumps(pipeline_run.resolved_recipe.to_app_recipe_dict(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        app_seed_recipe_path.write_text(
            json.dumps(pipeline_run.resolved_recipe.to_seed_recipe_dict(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        return {
            "pipeline_run": str(pipeline_run_path),
            "exported_recipe": str(exported_recipe_path),
            "app_seed_recipe": str(app_seed_recipe_path),
        }

    def write_recipe_export(self, recipe: ResolvedRecipeArtifact, output_dir: Path) -> str:
        output_dir.mkdir(parents=True, exist_ok=True)
        recipe_path = output_dir / f"{slugify(recipe.title)}-{recipe.recipe_id}.json"
        recipe_path.write_text(
            json.dumps(recipe.to_app_recipe_dict(), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return str(recipe_path)

    def write_campaign_app_import_bundle(
        self,
        app_seed_recipe_paths: list[str],
        output_dir: Path,
        *,
        campaign_id: str,
        campaign_name: str | None,
    ) -> dict[str, str]:
        output_dir.mkdir(parents=True, exist_ok=True)

        recipes = [
            json.loads(Path(path).read_text(encoding="utf-8"))
            for path in app_seed_recipe_paths
        ]
        bundle_path = output_dir / "seed_recipes.json"
        manifest_path = output_dir / "manifest.json"

        bundle_path.write_text(
            json.dumps(recipes, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        manifest_path.write_text(
            json.dumps(
                {
                    "format": "pantrychef.seed_recipes.v1",
                    "generated_at": utc_now_iso(),
                    "campaign_id": campaign_id,
                    "campaign_name": campaign_name,
                    "recipe_count": len(recipes),
                    "bundle_file": str(bundle_path),
                    "notes": [
                        "seed_recipes.json is directly shaped for PantryChef's bundled seed recipe loader.",
                        "After approval, merge or replace entries in PantryChef/Resources/seed_recipes.json.",
                    ],
                    "recipes": [
                        {
                            "title": recipe.get("title"),
                            "mealType": recipe.get("mealType"),
                            "cuisine": recipe.get("cuisine"),
                        }
                        for recipe in recipes
                    ],
                },
                indent=2,
                sort_keys=True,
            ) + "\n",
            encoding="utf-8",
        )

        return {
            "seed_recipes_bundle": str(bundle_path),
            "manifest": str(manifest_path),
        }