from __future__ import annotations

from ..models import RecipeCandidate, ResolvedIngredient, ResolvedRecipeArtifact, ValidationReport


class RecipeReconciliationWorker:
    def build(
        self,
        recipe: RecipeCandidate,
        ingredients: list[ResolvedIngredient],
    ) -> ResolvedRecipeArtifact:
        return ResolvedRecipeArtifact(
            recipe_id=recipe.recipe_id,
            title=recipe.title,
            description=recipe.description,
            ingredients=ingredients,
            steps=recipe.steps,
            servings=recipe.servings,
            prep_time_minutes=recipe.prep_time_minutes,
            cook_time_minutes=recipe.cook_time_minutes,
            difficulty=recipe.difficulty,
            dietary_tags=list(recipe.dietary_tags),
            meal_type=recipe.meal_type,
            cuisine=recipe.cuisine,
            source=recipe.source,
        )


class RecipeValidationWorker:
    def validate(self, artifact: ResolvedRecipeArtifact) -> ValidationReport:
        errors: list[str] = []
        warnings: list[str] = []
        error_codes: list[str] = []
        warning_codes: list[str] = []

        if not artifact.title.strip():
            errors.append("Recipe title is required.")
            error_codes.append("title_missing")
        if not artifact.ingredients:
            errors.append("Recipe must contain at least one ingredient.")
            error_codes.append("ingredients_missing")
        if not artifact.steps:
            errors.append("Recipe must contain at least one step.")
            error_codes.append("steps_missing")

        for ingredient in artifact.ingredients:
            if ingredient.quantity <= 0:
                errors.append(f"Ingredient '{ingredient.raw_name}' has a non-positive quantity.")
                error_codes.append("ingredient_quantity_invalid")

        unresolved = artifact.unresolved_ingredients()
        if unresolved:
            warnings.append(
                "Unresolved ingredients remain: "
                + ", ".join(sorted(ingredient.raw_name for ingredient in unresolved))
            )
            warning_codes.append("unresolved_ingredients")

        seen_step_numbers: set[int] = set()
        actual_step_numbers: list[int] = []
        for step in artifact.steps:
            actual_step_numbers.append(step.step_number)
            if step.step_number in seen_step_numbers:
                errors.append(f"Duplicate step number {step.step_number}.")
                error_codes.append("duplicate_step_number")
            seen_step_numbers.add(step.step_number)
            if step.step_number <= 0:
                errors.append("Step numbers must be positive.")
                error_codes.append("step_number_invalid")
            if not step.instruction.strip():
                errors.append(f"Step {step.step_number} is missing instruction text.")
                error_codes.append("step_instruction_missing")
            if step.timer_minutes is not None and step.timer_minutes < 0:
                errors.append(f"Step {step.step_number} has an invalid timer value.")
                error_codes.append("timer_invalid")
            if step.estimated_duration_seconds is not None and step.estimated_duration_seconds <= 0:
                errors.append(f"Step {step.step_number} has an invalid estimated duration.")
                error_codes.append("estimated_duration_invalid")

        expected_step_numbers = [] if not artifact.steps else list(range(1, len(artifact.steps) + 1))
        if actual_step_numbers and actual_step_numbers != expected_step_numbers:
            errors.append(f"Step numbers must be sequential starting at 1. Found {actual_step_numbers}.")
            error_codes.append("step_numbers_nonsequential")

        if artifact.cook_time_minutes is None and artifact.prep_time_minutes is None:
            warnings.append("Recipe has no explicit prep or cook time.")
            warning_codes.append("times_missing")

        return ValidationReport(
            is_valid=not errors,
            errors=errors,
            warnings=warnings,
            error_codes=error_codes,
            warning_codes=warning_codes,
        )