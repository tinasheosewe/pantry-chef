from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from .models import DishSpec, RecipeCandidate


def normalize_text(value: str) -> str:
    normalized: list[str] = []
    previous_was_space = True
    for character in value.lower():
        if character.isalnum():
            normalized.append(character)
            previous_was_space = False
            continue
        if not previous_was_space:
            normalized.append(" ")
            previous_was_space = True
    return "".join(normalized).strip()


STOP_WORDS = {
    "a",
    "an",
    "and",
    "for",
    "in",
    "of",
    "on",
    "recipe",
    "style",
    "the",
    "to",
    "with",
}


@dataclass(frozen=True)
class ExistingRecipeRecord:
    title: str
    cuisine: str | None
    meal_type: str | None
    ingredients: tuple[str, ...]
    description: str | None = None
    steps: tuple[str, ...] = ()

    @property
    def normalized_title(self) -> str:
        return normalize_text(self.title)

    @property
    def title_tokens(self) -> set[str]:
        return meaningful_tokens(self.title)

    @property
    def ingredient_tokens(self) -> set[str]:
        tokens: set[str] = set()
        for ingredient in self.ingredients:
            tokens.update(meaningful_tokens(ingredient))
        return tokens

    @property
    def description_tokens(self) -> set[str]:
        return meaningful_tokens(self.description or "")

    @property
    def step_tokens(self) -> set[str]:
        tokens: set[str] = set()
        for step in self.steps:
            tokens.update(meaningful_tokens(step))
        return tokens


class RecipeCorpusIndex:
    def __init__(self, recipes: list[ExistingRecipeRecord]) -> None:
        self._recipes = recipes

    @classmethod
    def from_project_root(
        cls,
        project_root: Path,
        output_root: Path | None = None,
        accepted_root: Path | None = None,
        include_bundled_seed: bool = True,
    ) -> "RecipeCorpusIndex":
        recipe_paths: list[Path] = []
        bundled_seed_path = project_root / "PantryChef" / "Resources" / "seed_recipes.json"
        if include_bundled_seed and bundled_seed_path.exists():
            recipe_paths.append(bundled_seed_path)

        if output_root is not None and output_root.exists():
            recipe_paths.extend(sorted(output_root.rglob("app_import/seed_recipes.json")))

        if accepted_root is not None and accepted_root.exists():
            recipe_paths.extend(sorted(accepted_root.rglob("seed_recipes.json")))

        records: list[ExistingRecipeRecord] = []
        seen_titles: set[str] = set()
        for path in recipe_paths:
            for record in load_recipe_records(path):
                if record.normalized_title in seen_titles:
                    continue
                records.append(record)
                seen_titles.add(record.normalized_title)

        return cls(records)

    @property
    def recipe_count(self) -> int:
        return len(self._recipes)

    def awareness_context_for_spec(self, spec: DishSpec, rejected_titles: list[str] | None = None) -> dict:
        related_records = self._related_records(spec)
        related_titles = [record.title for record in related_records[:12]]
        avoid_titles = _unique_preserving_order([
            *spec.avoid_titles,
            *(rejected_titles or []),
            *related_titles,
        ])
        related_ingredients = sorted(
            {
                ingredient
                for record in related_records[:12]
                for ingredient in record.ingredients
            }
        )[:30]

        return {
            "existing_recipe_count": self.recipe_count,
            "related_existing_titles": related_titles,
            "related_existing_ingredients": related_ingredients,
            "avoid_titles": avoid_titles[:40],
        }

    def infer_dish_brief(self, title: str, cuisine: str | None = None, meal_type: str | None = None) -> dict:
        related_records = self._related_records(DishSpec(title=title, cuisine=cuisine, meal_type=meal_type))
        ingredient_counts: dict[str, int] = {}
        cuisine_counts: dict[str, int] = {}
        meal_type_counts: dict[str, int] = {}

        for record in related_records[:12]:
            if record.cuisine:
                cuisine_counts[record.cuisine] = cuisine_counts.get(record.cuisine, 0) + 1
            if record.meal_type:
                meal_type_counts[record.meal_type] = meal_type_counts.get(record.meal_type, 0) + 1
            for ingredient in record.ingredients:
                ingredient_counts[ingredient] = ingredient_counts.get(ingredient, 0) + 1

        pantry_focus = [
            ingredient
            for ingredient, _ in sorted(ingredient_counts.items(), key=lambda item: (-item[1], item[0]))[:8]
        ]
        inferred_cuisine = cuisine or _most_common_value(cuisine_counts)
        inferred_meal_type = meal_type or _most_common_value(meal_type_counts)

        return {
            "title": title,
            "cuisine": inferred_cuisine,
            "meal_type": inferred_meal_type,
            "pantry_focus": pantry_focus,
            "related_titles": [record.title for record in related_records[:8]],
        }

    def duplicate_reason_for_title(self, title: str, extra_avoid_titles: list[str] | None = None) -> str | None:
        normalized_title = normalize_text(title)
        if not normalized_title:
            return "Recipe title is empty after normalization."

        blocked_titles = {normalize_text(value) for value in extra_avoid_titles or [] if value.strip()}
        if normalized_title in blocked_titles:
            return f"Title '{title}' matches an explicitly avoided title."

        title_tokens = meaningful_tokens(title)
        title_char_ngrams = character_ngrams(title)
        for record in self._recipes:
            if normalized_title == record.normalized_title:
                return f"Title '{title}' duplicates existing recipe '{record.title}'."

            title_similarity = jaccard_similarity(title_tokens, record.title_tokens)
            character_similarity = jaccard_similarity(title_char_ngrams, character_ngrams(record.title))
            if title_similarity >= 0.75 or character_similarity >= 0.68:
                return f"Title '{title}' is too similar to existing recipe '{record.title}'."

        return None

    def duplicate_reason_for_candidate(self, candidate: RecipeCandidate, extra_avoid_titles: list[str] | None = None) -> str | None:
        title_reason = self.duplicate_reason_for_title(candidate.title, extra_avoid_titles=extra_avoid_titles)
        if title_reason is not None:
            return title_reason

        candidate_title_tokens = meaningful_tokens(candidate.title)
        candidate_title_char_ngrams = character_ngrams(candidate.title)
        candidate_ingredient_tokens = {
            token
            for ingredient in candidate.ingredients
            for token in meaningful_tokens(ingredient.name)
        }
        candidate_step_tokens = {
            token
            for step in candidate.steps
            for token in meaningful_tokens(step.instruction)
        }
        candidate_description_tokens = meaningful_tokens(candidate.description or "")
        for record in self._recipes:
            title_similarity = jaccard_similarity(candidate_title_tokens, record.title_tokens)
            character_similarity = jaccard_similarity(candidate_title_char_ngrams, character_ngrams(record.title))
            ingredient_similarity = jaccard_similarity(candidate_ingredient_tokens, record.ingredient_tokens)
            step_similarity = jaccard_similarity(candidate_step_tokens, record.step_tokens)
            description_similarity = jaccard_similarity(candidate_description_tokens, record.description_tokens)
            if (title_similarity >= 0.55 or character_similarity >= 0.68) and (
                ingredient_similarity >= 0.45
                or step_similarity >= 0.35
                or description_similarity >= 0.4
            ):
                return (
                    f"Generated recipe '{candidate.title}' is too similar to existing recipe '{record.title}' "
                    f"by title and content overlap."
                )

        return None

    def _related_records(self, spec: DishSpec) -> list[ExistingRecipeRecord]:
        spec_title_tokens = meaningful_tokens(spec.title)
        spec_focus_tokens = {token for value in spec.pantry_focus for token in meaningful_tokens(value)}
        desired_cuisine = normalize_text(spec.cuisine or "")
        desired_meal_type = normalize_text(spec.meal_type or "")

        scored: list[tuple[float, ExistingRecipeRecord]] = []
        for record in self._recipes:
            score = 0.0
            if desired_cuisine and normalize_text(record.cuisine or "") == desired_cuisine:
                score += 2.0
            if desired_meal_type and normalize_text(record.meal_type or "") == desired_meal_type:
                score += 1.0
            score += jaccard_similarity(spec_title_tokens, record.title_tokens) * 2.0
            score += jaccard_similarity(spec_focus_tokens, record.ingredient_tokens)
            if score > 0:
                scored.append((score, record))

        scored.sort(key=lambda pair: (-pair[0], pair[1].title))
        return [record for _, record in scored]


def load_recipe_records(path: Path) -> list[ExistingRecipeRecord]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, list):
        return []

    records: list[ExistingRecipeRecord] = []
    for item in payload:
        if not isinstance(item, dict):
            continue
        title = str(item.get("title", "")).strip()
        if not title:
            continue
        ingredients_payload = item.get("ingredients", [])
        ingredients = tuple(
            str(ingredient.get("name", "")).strip()
            for ingredient in ingredients_payload
            if isinstance(ingredient, dict) and str(ingredient.get("name", "")).strip()
        )
        steps = tuple(
            str(step.get("instruction", "")).strip()
            for step in item.get("steps", [])
            if isinstance(step, dict) and str(step.get("instruction", "")).strip()
        )
        records.append(
            ExistingRecipeRecord(
                title=title,
                cuisine=_optional_string(item.get("cuisine")),
                meal_type=_optional_string(item.get("mealType")),
                ingredients=ingredients,
                description=_optional_string(item.get("description")),
                steps=steps,
            )
        )
    return records


def meaningful_tokens(value: str) -> set[str]:
    return {
        token
        for token in normalize_text(value).split()
        if token and token not in STOP_WORDS
    }


def jaccard_similarity(left: set[str], right: set[str]) -> float:
    if not left or not right:
        return 0.0
    return len(left & right) / len(left | right)


def character_ngrams(value: str, size: int = 3) -> set[str]:
    normalized = normalize_text(value).replace(" ", "")
    if not normalized:
        return set()
    if len(normalized) <= size:
        return {normalized}
    return {normalized[index:index + size] for index in range(0, len(normalized) - size + 1)}


def _optional_string(value: object) -> str | None:
    if value is None:
        return None
    cleaned = str(value).strip()
    return cleaned or None


def _unique_preserving_order(values: list[str]) -> list[str]:
    seen: set[str] = set()
    unique: list[str] = []
    for value in values:
        cleaned = value.strip()
        if not cleaned:
            continue
        normalized = normalize_text(cleaned)
        if normalized in seen:
            continue
        seen.add(normalized)
        unique.append(cleaned)
    return unique


def _most_common_value(counts: dict[str, int]) -> str | None:
    if not counts:
        return None
    return sorted(counts.items(), key=lambda item: (-item[1], item[0]))[0][0]