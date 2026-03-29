from __future__ import annotations

import json

from .models import DishSpec, IngredientCandidate, IngredientMention, RecipeCandidate, ResolvedRecipeArtifact, ValidationReport

APP_MEAL_TYPES = ["Breakfast", "Lunch", "Dinner", "Snack", "Dessert"]
APP_CUISINES = [
    "Italian",
    "Mexican",
    "Chinese",
    "Japanese",
    "Indian",
    "Thai",
    "French",
    "Mediterranean",
    "American",
    "Korean",
    "Vietnamese",
    "Greek",
    "Middle Eastern",
    "Ethiopian",
    "Caribbean",
    "Other",
]


FOOD_CATEGORIES = [
    "Dairy",
    "Produce",
    "Protein",
    "Grains & Cereals",
    "Spices & Herbs",
    "Condiments & Sauces",
    "Baking Supplies",
    "Frozen Foods",
    "Canned & Jarred",
    "Beverages",
    "Snacks",
    "Oils & Fats",
    "Pasta & Noodles",
    "Nuts & Seeds",
    "Other",
]

MEASUREMENT_UNITS = [
    "tsp",
    "tbsp",
    "cup",
    "fl oz",
    "ml",
    "L",
    "g",
    "kg",
    "oz",
    "lb",
    "piece",
    "whole",
    "loaf",
    "slice",
    "clove",
    "bunch",
    "can",
    "pkg",
    "pinch",
    "splash",
    "to taste",
]

DIETARY_TAGS = [
    "Vegetarian",
    "Vegan",
    "Gluten-Free",
    "Dairy-Free",
    "Nut-Free",
    "Low Carb",
    "High Protein",
    "Keto",
    "Paleo",
    "Halal",
    "Kosher",
]


def recipe_generation_messages(
    spec: DishSpec,
    awareness_context: dict | None = None,
    revision_feedback: list[str] | None = None,
) -> tuple[str, str]:
    system_prompt = (
        "You generate production-quality original recipes for PantryChef. "
        "Return only structured JSON that is internally consistent, realistic to cook, "
        "and uses ingredients that can be normalized into a pantry catalog. "
        "The recipe must actually be the requested dish itself, not a loose variation or adjacent dessert. "
        "Keep the recipe title exactly equal to the requested dish title. "
        "Prefer broad canonical ingredient names over brand names or overly narrow supermarket labels. "
        "Do not list cookware, packaging, or disposable prep aids as ingredients unless they are materially edible pantry items. "
        "If dietary tags are uncertain, return an empty list instead of guessing. "
        "Never mark a recipe Vegetarian, Vegan, Dairy-Free, or Gluten-Free unless the ingredients clearly support that label. "
        "Never mention copyrights or outside publishers. "
        "Do not produce recipes that duplicate or closely shadow known existing recipes or explicitly avoided titles. "
        "When revision feedback is supplied, fix the cited issues directly instead of paraphrasing them."
    )
    user_prompt = json.dumps(
        {
            "dish": {
                "title": spec.title,
                "cuisine": spec.cuisine,
                "meal_type": spec.meal_type,
                "servings": spec.servings,
                "goals": spec.goals,
                "pantry_focus": spec.pantry_focus,
                "avoid_titles": spec.avoid_titles,
                "notes": spec.notes,
            },
            "requirements": {
                "make_original": True,
                "title_must_match_requested_dish": True,
                "dish_identity_must_match_requested_dish": True,
                "prefer_reasonable_quantities": True,
                "prefer_realistic_techniques": True,
                "prefer_empty_dietary_tags_when_uncertain": True,
                "difficulty_range": [1, 5],
                "allowed_categories": FOOD_CATEGORIES,
                "allowed_units": MEASUREMENT_UNITS,
                "allowed_dietary_tags": DIETARY_TAGS,
                "allowed_meal_types": APP_MEAL_TYPES,
                "allowed_cuisines": APP_CUISINES,
            },
            "corpus_awareness": awareness_context or {},
            "revision_feedback": revision_feedback or [],
        },
        indent=2,
        sort_keys=True,
    )
    return system_prompt, user_prompt


def ambiguity_resolution_messages(
    spec: DishSpec,
    recipe: RecipeCandidate,
    mention: IngredientMention,
    candidates: list[IngredientCandidate],
) -> tuple[str, str]:
    system_prompt = (
        "You resolve pantry ingredient ambiguity. "
        "Choose only from the supplied candidates. "
        "If none can be selected confidently, return unresolved."
    )
    user_prompt = json.dumps(
        {
            "dish": {
                "title": spec.title,
                "cuisine": spec.cuisine,
                "meal_type": spec.meal_type,
            },
            "recipe_context": {
                "title": recipe.title,
                "description": recipe.description,
                "steps": [step.instruction for step in recipe.steps],
            },
            "ingredient_mention": {
                "raw_name": mention.raw_name,
                "quantity": mention.quantity,
                "unit": mention.unit,
                "category": mention.category,
            },
            "candidates": [
                {
                    "candidate_id": candidate.candidate_id,
                    "catalog_item_id": candidate.catalog_item_id,
                    "display_name": candidate.display_name,
                    "score": candidate.score,
                    "rationale": candidate.rationale,
                    "facets": [{"key": facet.key, "value": facet.value} for facet in candidate.facets],
                }
                for candidate in candidates
            ],
        },
        indent=2,
        sort_keys=True,
    )
    return system_prompt, user_prompt


def ingredient_enrichment_messages(
    spec: DishSpec,
    recipe: RecipeCandidate,
    unresolved_mentions: list[IngredientMention],
) -> tuple[str, str]:
    system_prompt = (
        "You normalize unresolved recipe ingredient mentions into first-class pantry ingredient records. "
        "For real edible items, choose a broad canonical pantry ingredient name and keep the original phrase as an alias. "
        "When the subtype matters, keep it as structured qualifiers such as variant, form, base, or preservation instead of making the subtype the top-level identity. "
        "Aliases may carry facet selections that capture meaningful culinary distinctions: variety (e.g. jasmine for rice), form (e.g. fillet, ground, juice, zest), "
        "preparation state (e.g. roasted, smoked, frozen), or cut (e.g. steak, florets). "
        "NEVER use plurality, count, or the ingredient name itself as a facet. "
        "For obvious tools, packaging, or non-ingredient process aids, mark them as ignore. "
        "For edible ingredients, provide substitute ingredients that are themselves ingredients, not prose. "
        "Also provide practical storage preferences when they are knowable. "
        "If the exact subtype is uncertain, still return the broad edible pantry ingredient rather than leaving it unresolved. "
        "Do not leave branded or hyper-specific names as the canonical ingredient when a broader pantry concept exists."
    )
    user_prompt = json.dumps(
        {
            "dish": {
                "title": spec.title,
                "cuisine": spec.cuisine,
                "meal_type": spec.meal_type,
            },
            "recipe": {
                "title": recipe.title,
                "description": recipe.description,
                "steps": [step.instruction for step in recipe.steps],
            },
            "unresolved_mentions": [
                {
                    "raw_name": mention.raw_name,
                    "quantity": mention.quantity,
                    "unit": mention.unit,
                    "category": mention.category,
                    "is_optional": mention.is_optional,
                }
                for mention in unresolved_mentions
            ],
            "allowed_categories": FOOD_CATEGORIES,
            "allowed_units": MEASUREMENT_UNITS,
        },
        indent=2,
        sort_keys=True,
    )
    return system_prompt, user_prompt


def request_intent_messages(request_text: str) -> tuple[str, str]:
    system_prompt = (
        "You extract recipe-request intent for PantryChef. "
        "Return a strict JSON interpretation of the user's request without inventing unsupported constraints. "
        "If the user is asking for one specific named dish, preserve it exactly in exact_title."
    )
    user_prompt = json.dumps(
        {
            "request": request_text,
            "allowed_cuisines": APP_CUISINES,
            "allowed_meal_types": APP_MEAL_TYPES,
        },
        indent=2,
        sort_keys=True,
    )
    return system_prompt, user_prompt


def exact_dish_brief_messages(request_text: str, title: str, awareness_context: dict | None = None) -> tuple[str, str]:
    system_prompt = (
        "You create a production recipe brief for one exact requested dish. "
        "Preserve the exact requested title, infer a plausible cuisine and meal type when possible, "
        "and provide pantry focus ingredients and cooking goals that make the dish realistic."
    )
    user_prompt = json.dumps(
        {
            "request": request_text,
            "exact_title": title,
            "allowed_cuisines": APP_CUISINES,
            "allowed_meal_types": APP_MEAL_TYPES,
            "corpus_awareness": awareness_context or {},
        },
        indent=2,
        sort_keys=True,
    )
    return system_prompt, user_prompt


def recipe_review_messages(
    spec: DishSpec,
    candidate: RecipeCandidate,
    resolved_recipe: ResolvedRecipeArtifact,
    validation: ValidationReport,
    attempt_number: int,
) -> tuple[str, str]:
    system_prompt = (
        "You are PantryChef's recipe quality reviewer. "
        "Judge whether a generated recipe is reasonable, internally consistent, plausible to cook, "
        "and aligned with the requested dish. "
        "Treat title mismatch with the requested dish as a blocking failure, never an acceptable variation. "
        "Treat adjacent dishes, reinterpretations, renamed variants, and cuisine substitutions as failures unless the requested title explicitly asks for a variation. "
        "Use accept only if the recipe is genuinely production-worthy. "
        "Use revise when the recipe can be salvaged with targeted changes. "
        "Use reject when the concept is materially wrong, incoherent, or unsafe."
    )
    user_prompt = json.dumps(
        {
            "attempt_number": attempt_number,
            "requested_dish": {
                "title": spec.title,
                "cuisine": spec.cuisine,
                "meal_type": spec.meal_type,
                "servings": spec.servings,
                "goals": spec.goals,
                "pantry_focus": spec.pantry_focus,
            },
            "generated_recipe": {
                "title": candidate.title,
                "description": candidate.description,
                "ingredients": [
                    {
                        "name": ingredient.name,
                        "quantity": ingredient.quantity,
                        "unit": ingredient.unit,
                        "category": ingredient.category,
                        "is_optional": ingredient.is_optional,
                        "notes": ingredient.notes,
                    }
                    for ingredient in candidate.ingredients
                ],
                "steps": [
                    {
                        "step_number": step.step_number,
                        "instruction": step.instruction,
                        "timer_minutes": step.timer_minutes,
                        "estimated_duration_seconds": step.estimated_duration_seconds,
                        "tip": step.tip,
                    }
                    for step in candidate.steps
                ],
                "servings": candidate.servings,
                "prep_time_minutes": candidate.prep_time_minutes,
                "cook_time_minutes": candidate.cook_time_minutes,
                "difficulty": candidate.difficulty,
                "dietary_tags": candidate.dietary_tags,
                "meal_type": candidate.meal_type,
                "cuisine": candidate.cuisine,
            },
            "resolved_recipe": resolved_recipe.to_app_recipe_dict(),
            "validation": {
                "is_valid": validation.is_valid,
                "errors": validation.errors,
                "warnings": validation.warnings,
                "error_codes": validation.error_codes,
                "warning_codes": validation.warning_codes,
            },
        },
        indent=2,
        sort_keys=True,
    )
    return system_prompt, user_prompt


def recipe_generation_schema() -> dict:
    return {
        "type": "object",
        "required": [
            "title",
            "description",
            "ingredients",
            "steps",
            "servings",
            "prep_time_minutes",
            "cook_time_minutes",
            "difficulty",
            "dietary_tags",
            "meal_type",
            "cuisine",
        ],
        "properties": {
            "title": {"type": "string"},
            "description": {"type": ["string", "null"]},
            "servings": {"type": "integer", "minimum": 1},
            "prep_time_minutes": {"type": ["integer", "null"], "minimum": 0},
            "cook_time_minutes": {"type": ["integer", "null"], "minimum": 0},
            "difficulty": {"type": "integer", "minimum": 1, "maximum": 5},
            "dietary_tags": {"type": "array", "items": {"type": "string", "enum": DIETARY_TAGS}},
            "meal_type": {"type": ["string", "null"]},
            "cuisine": {"type": ["string", "null"]},
            "ingredients": {
                "type": "array",
                "minItems": 1,
                "items": {
                    "type": "object",
                    "required": ["name", "quantity", "unit", "category", "is_optional", "notes"],
                    "properties": {
                        "name": {"type": "string"},
                        "quantity": {"type": "number", "minimum": 0},
                        "unit": {"type": ["string", "null"], "enum": MEASUREMENT_UNITS + [None]},
                        "category": {"type": "string", "enum": FOOD_CATEGORIES},
                        "is_optional": {"type": "boolean"},
                        "notes": {"type": ["string", "null"]},
                    },
                    "additionalProperties": False,
                },
            },
            "steps": {
                "type": "array",
                "minItems": 1,
                "items": {
                    "type": "object",
                    "required": ["step_number", "instruction", "timer_minutes", "estimated_duration_seconds", "tip"],
                    "properties": {
                        "step_number": {"type": "integer", "minimum": 1},
                        "instruction": {"type": "string"},
                        "timer_minutes": {"type": ["integer", "null"], "minimum": 0},
                        "estimated_duration_seconds": {"type": ["integer", "null"], "minimum": 0},
                        "tip": {"type": ["string", "null"]},
                    },
                    "additionalProperties": False,
                },
            },
        },
        "additionalProperties": False,
    }


def request_intent_schema() -> dict:
    return {
        "type": "object",
        "required": ["desired_count", "cuisine", "meal_type", "exact_title"],
        "properties": {
            "desired_count": {"type": "integer", "minimum": 1, "maximum": 50},
            "cuisine": {"type": ["string", "null"], "enum": APP_CUISINES + [None]},
            "meal_type": {"type": ["string", "null"], "enum": APP_MEAL_TYPES + [None]},
            "exact_title": {"type": ["string", "null"]},
        },
        "additionalProperties": False,
    }


def exact_dish_brief_schema() -> dict:
    return {
        "type": "object",
        "required": ["title", "cuisine", "meal_type", "servings", "pantry_focus", "goals", "notes"],
        "properties": {
            "title": {"type": "string"},
            "cuisine": {"type": ["string", "null"], "enum": APP_CUISINES + [None]},
            "meal_type": {"type": ["string", "null"], "enum": APP_MEAL_TYPES + [None]},
            "servings": {"type": "integer", "minimum": 1, "maximum": 12},
            "pantry_focus": {"type": "array", "items": {"type": "string"}, "maxItems": 8},
            "goals": {"type": "array", "items": {"type": "string"}, "maxItems": 6},
            "notes": {"type": ["string", "null"]},
        },
        "additionalProperties": False,
    }


def recipe_review_schema() -> dict:
    return {
        "type": "object",
        "required": ["status", "reviewer", "rationale", "issues", "revision_instructions", "retryable"],
        "properties": {
            "status": {"type": "string", "enum": ["accepted", "revise", "rejected"]},
            "reviewer": {"type": "string"},
            "rationale": {"type": "string"},
            "issues": {
                "type": "array",
                "items": {
                    "type": "object",
                    "required": ["code", "severity", "message"],
                    "properties": {
                        "code": {"type": "string"},
                        "severity": {"type": "string", "enum": ["info", "warning", "error"]},
                        "message": {"type": "string"},
                    },
                    "additionalProperties": False,
                },
            },
            "revision_instructions": {"type": "array", "items": {"type": "string"}},
            "retryable": {"type": "boolean"},
        },
        "additionalProperties": False,
    }


def ambiguity_resolution_schema(candidate_ids: list[str]) -> dict:
    return {
        "type": "object",
        "required": [
            "status",
            "selected_candidate_id",
            "selected_catalog_item_id",
            "confidence",
            "rationale",
        ],
        "properties": {
            "status": {"type": "string", "enum": ["resolved", "unresolved"]},
            "selected_candidate_id": {"type": ["string", "null"], "enum": candidate_ids + [None]},
            "selected_catalog_item_id": {"type": ["string", "null"]},
            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            "rationale": {"type": "string"},
        },
        "additionalProperties": False,
    }


def ingredient_enrichment_schema() -> dict:
    return {
        "type": "object",
        "required": ["decisions"],
        "properties": {
            "decisions": {
                "type": "array",
                "items": {
                    "type": "object",
                    "required": [
                        "raw_name",
                        "action",
                        "canonical_name",
                        "category",
                        "aliases",
                        "default_unit",
                        "default_quantity",
                        "facet_definitions",
                        "default_facets",
                        "substitutes",
                        "storage",
                        "rationale",
                    ],
                    "properties": {
                        "raw_name": {"type": "string"},
                        "action": {"type": "string", "enum": ["add_catalog_entry", "ignore"]},
                        "canonical_name": {"type": ["string", "null"]},
                        "category": {"type": ["string", "null"], "enum": FOOD_CATEGORIES + [None]},
                        "aliases": {"type": "array", "items": {"type": "string"}},
                        "default_unit": {"type": ["string", "null"], "enum": MEASUREMENT_UNITS + [None]},
                        "default_quantity": {"type": ["number", "null"], "minimum": 0},
                        "facet_definitions": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "required": ["key", "options"],
                                "properties": {
                                    "key": {"type": "string"},
                                    "options": {"type": "array", "items": {"type": "string"}},
                                },
                                "additionalProperties": False,
                            },
                        },
                        "default_facets": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "required": ["key", "value"],
                                "properties": {
                                    "key": {"type": "string"},
                                    "value": {"type": "string"},
                                },
                                "additionalProperties": False,
                            },
                        },
                        "substitutes": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "required": [
                                    "name",
                                    "rationale",
                                    "facets",
                                    "ratio",
                                    "tasteImpact",
                                    "textureImpact",
                                    "cookingImpact",
                                    "nutritionImpact",
                                    "notes",
                                    "dietary",
                                ],
                                "properties": {
                                    "name": {"type": "string"},
                                    "rationale": {"type": ["string", "null"]},
                                    "facets": {
                                        "type": "array",
                                        "items": {
                                            "type": "object",
                                            "required": ["key", "value"],
                                            "properties": {
                                                "key": {"type": "string"},
                                                "value": {"type": "string"},
                                            },
                                            "additionalProperties": False,
                                        },
                                    },
                                    "ratio": {"type": ["string", "null"]},
                                    "tasteImpact": {"type": ["string", "null"]},
                                    "textureImpact": {"type": ["string", "null"]},
                                    "cookingImpact": {"type": ["string", "null"]},
                                    "nutritionImpact": {"type": ["string", "null"]},
                                    "notes": {"type": ["string", "null"]},
                                    "dietary": {"type": "array", "items": {"type": "string"}},
                                },
                                "additionalProperties": False,
                            },
                        },
                        "storage": {
                            "type": ["object", "null"],
                            "required": ["preferred", "pantry_days", "refrigerator_days", "freezer_days", "notes"],
                            "properties": {
                                "preferred": {"type": ["string", "null"], "enum": ["pantry", "refrigerator", "freezer", None]},
                                "pantry_days": {"type": ["integer", "null"], "minimum": 0},
                                "refrigerator_days": {"type": ["integer", "null"], "minimum": 0},
                                "freezer_days": {"type": ["integer", "null"], "minimum": 0},
                                "notes": {"type": ["string", "null"]},
                            },
                            "additionalProperties": False,
                        },
                        "rationale": {"type": "string"},
                    },
                    "additionalProperties": False,
                },
            }
        },
        "additionalProperties": False,
    }


def ingredient_corpus_batch_messages(
    *,
    batch_size: int,
    existing_item_ids: list[str],
    existing_names: list[str],
    focus_categories: list[str],
    category_targets: dict[str, int],
    remaining_target: int,
    attempt_number: int,
) -> tuple[str, str]:
    system_prompt = (
        "You are building PantryChef's first-class ingredient corpus. "
        "Return diverse canonical pantry ingredients, not brands, recipes, tools, or packaging. "
        "Each ingredient must be broad enough to be reusable across many recipes, but still be a real pantry concept. "
        "Use app-style canonical roots with structured qualifiers when needed: for example sugar plus variant granulated, or broth plus base chicken, instead of promoting the subtype as the top-level identity. "
        "Aliases may carry facet selections that describe meaningful culinary distinctions: variety (e.g. jasmine for rice, granny smith for apple), "
        "form (e.g. fillet, ground, juice, zest, rolled), preparation (e.g. roasted, smoked, frozen, rendered), or cut (e.g. steak, florets, lardons). "
        "NEVER use plurality or count as a facet. NEVER use the ingredient name itself as a facet value. "
        "Provide practical aliases, substitutes, and storage preferences. "
        "Do not return duplicates of existing items, and do not emit placeholder-quality entries. "
        "Return exactly the requested number of ingredients. If one idea is weak, replace it with another rather than returning fewer items. "
        "Follow the requested category distribution closely. Think broadly about what real cooks stock in each category."
    )
    user_prompt = json.dumps(
        {
            "attempt_number": attempt_number,
            "batch_size": batch_size,
            "remaining_target": remaining_target,
            "allowed_categories": FOOD_CATEGORIES,
            "allowed_units": MEASUREMENT_UNITS,
            "focus_categories": focus_categories,
            "category_targets": category_targets,
            "existing_item_ids": existing_item_ids,
            "existing_names": existing_names,
            "requirements": {
                "quality_status": "enriched",
                "must_be_first_class_ingredients": True,
                "must_be_reusable_across_recipes": True,
                "avoid_brands": True,
                "avoid_tools_and_packaging": True,
                "avoid_existing_or_adjacent_duplicates": True,
                "prefer_broad_roots_with_structured_qualifiers": True,
                "facets_only_for_culinary_distinctions": True,
                "never_use_count_or_plurality_as_facets": True,
            },
        },
        indent=2,
        sort_keys=True,
    )
    return system_prompt, user_prompt


def ingredient_corpus_batch_schema(batch_size: int) -> dict:
    return {
        "type": "object",
        "required": ["ingredients"],
        "properties": {
            "ingredients": {
                "type": "array",
                "minItems": 1,
                "maxItems": batch_size,
                "items": {
                    "type": "object",
                    "required": [
                        "name",
                        "category",
                        "aliases",
                        "default_unit",
                        "default_quantity",
                        "facet_definitions",
                        "default_facets",
                        "substitutes",
                        "storage",
                        "rationale",
                    ],
                    "properties": {
                        "name": {"type": "string"},
                        "category": {"type": "string", "enum": FOOD_CATEGORIES},
                        "aliases": {"type": "array", "items": {"type": "string"}},
                        "default_unit": {"type": ["string", "null"], "enum": MEASUREMENT_UNITS + [None]},
                        "default_quantity": {"type": ["number", "null"], "minimum": 0},
                        "facet_definitions": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "required": ["key", "options"],
                                "properties": {
                                    "key": {"type": "string"},
                                    "options": {"type": "array", "items": {"type": "string"}},
                                },
                                "additionalProperties": False,
                            },
                        },
                        "default_facets": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "required": ["key", "value"],
                                "properties": {
                                    "key": {"type": "string"},
                                    "value": {"type": "string"},
                                },
                                "additionalProperties": False,
                            },
                        },
                        "substitutes": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "required": [
                                    "name",
                                    "rationale",
                                    "facets",
                                    "ratio",
                                    "tasteImpact",
                                    "textureImpact",
                                    "cookingImpact",
                                    "nutritionImpact",
                                    "notes",
                                    "dietary",
                                ],
                                "properties": {
                                    "name": {"type": "string"},
                                    "rationale": {"type": ["string", "null"]},
                                    "facets": {
                                        "type": "array",
                                        "items": {
                                            "type": "object",
                                            "required": ["key", "value"],
                                            "properties": {
                                                "key": {"type": "string"},
                                                "value": {"type": "string"},
                                            },
                                            "additionalProperties": False,
                                        },
                                    },
                                    "ratio": {"type": ["string", "null"]},
                                    "tasteImpact": {"type": ["string", "null"]},
                                    "textureImpact": {"type": ["string", "null"]},
                                    "cookingImpact": {"type": ["string", "null"]},
                                    "nutritionImpact": {"type": ["string", "null"]},
                                    "notes": {"type": ["string", "null"]},
                                    "dietary": {"type": "array", "items": {"type": "string"}},
                                },
                                "additionalProperties": False,
                            },
                        },
                        "storage": {
                            "type": ["object", "null"],
                            "required": ["preferred", "pantry_days", "refrigerator_days", "freezer_days", "notes"],
                            "properties": {
                                "preferred": {"type": ["string", "null"], "enum": ["pantry", "refrigerator", "freezer", None]},
                                "pantry_days": {"type": ["integer", "null"], "minimum": 0},
                                "refrigerator_days": {"type": ["integer", "null"], "minimum": 0},
                                "freezer_days": {"type": ["integer", "null"], "minimum": 0},
                                "notes": {"type": ["string", "null"]},
                            },
                            "additionalProperties": False,
                        },
                        "rationale": {"type": "string"},
                    },
                    "additionalProperties": False,
                },
            }
        },
        "additionalProperties": False,
    }


def recipe_corpus_batch_messages(
    *,
    batch_size: int,
    existing_titles: list[str],
    underrepresented_cuisines: list[str],
    underrepresented_meal_types: list[str],
    remaining_target: int,
    attempt_number: int,
) -> tuple[str, str]:
    system_prompt = (
        "You are planning a diverse PantryChef recipe corpus batch. "
        "Return specific dish briefs, each for one exact dish title, with realistic pantry focus ingredients. "
        "Do not propose duplicates, near-duplicates, generic placeholders, or titles already present in the corpus. "
        "Return exactly the requested number of distinct dishes whenever possible. "
        "Spread the batch across cuisines and meal types, with extra weight on underrepresented areas. "
        "Avoid title templates that merely swap one ingredient into an existing dish frame such as close salad, soup, curry, noodle, bowl, taco, or pasta variants."
    )
    user_prompt = json.dumps(
        {
            "batch_size": batch_size,
            "remaining_target": remaining_target,
            "attempt_number": attempt_number,
            "allowed_cuisines": APP_CUISINES,
            "allowed_meal_types": APP_MEAL_TYPES,
            "underrepresented_cuisines": underrepresented_cuisines,
            "underrepresented_meal_types": underrepresented_meal_types,
            "existing_titles": existing_titles,
            "requirements": {
                "exact_dish_titles": True,
                "avoid_existing_titles": True,
                "prefer_diverse_courses": True,
                "prefer_globally_diverse_real_dishes": True,
                "target_exact_batch_size": True,
                "avoid_template_variants_of_existing_titles": True,
            },
        },
        indent=2,
        sort_keys=True,
    )
    return system_prompt, user_prompt


def recipe_corpus_batch_schema(batch_size: int) -> dict:
    return {
        "type": "object",
        "required": ["name", "dishes"],
        "properties": {
            "name": {"type": ["string", "null"]},
            "dishes": {
                "type": "array",
                "minItems": 1,
                "maxItems": min(50, max(batch_size, batch_size * 2)),
                "items": {
                    "type": "object",
                    "required": ["title", "cuisine", "meal_type", "servings", "goals", "pantry_focus", "notes"],
                    "properties": {
                        "title": {"type": "string"},
                        "cuisine": {"type": ["string", "null"], "enum": APP_CUISINES + [None]},
                        "meal_type": {"type": ["string", "null"], "enum": APP_MEAL_TYPES + [None]},
                        "servings": {"type": "integer", "minimum": 1, "maximum": 12},
                        "goals": {"type": "array", "items": {"type": "string"}},
                        "pantry_focus": {"type": "array", "items": {"type": "string"}},
                        "notes": {"type": ["string", "null"]},
                    },
                    "additionalProperties": False,
                },
            },
        },
        "additionalProperties": False,
    }