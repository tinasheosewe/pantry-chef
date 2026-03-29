"""Prompt builders for every LLM call in the pipeline.

Each function returns a list of message dicts (system + user).
Response schemas are Pydantic models passed to client.generate() separately.

All controlled vocabularies are injected dynamically from schemas.py so
generated data always uses values the app can consume.
"""

from __future__ import annotations

from .schemas import (
    CookingImpact,
    CuisineType,
    DietaryTag,
    DifficultyLevel,
    FacetKey,
    FoodCategory,
    MealType,
    MeasurementUnit,
    PantryStorage,
    SubstitutionImpact,
    enum_values,
)

# ---------------------------------------------------------------------------
# Shared vocabulary block injected into every relevant prompt
# ---------------------------------------------------------------------------

_VOCAB_BLOCK = f"""## Controlled Vocabularies (use ONLY these exact values)

Food Categories: {enum_values(FoodCategory)}
Measurement Units: {enum_values(MeasurementUnit)}
Dietary Tags: {enum_values(DietaryTag)}
Difficulty Levels: {enum_values(DifficultyLevel)} (1=Beginner … 5=Expert)
Meal Types: {enum_values(MealType)}
Cuisines: {enum_values(CuisineType)}
Storage Types: {enum_values(PantryStorage)}
Facet Keys: {enum_values(FacetKey)}
Substitution Impact: {enum_values(SubstitutionImpact)}
Cooking Impact: {enum_values(CookingImpact)}"""


# ---------------------------------------------------------------------------
# 1. Request interpretation (NL → GenerationRequest)
# ---------------------------------------------------------------------------

def request_interpretation_messages(user_text: str) -> list[dict[str, str]]:
    system = f"""You interpret natural-language requests about generating ingredients
and/or recipes for a cooking app. Extract the structured intent.

{_VOCAB_BLOCK}

Rules:
- If the request is about ingredients/spices/condiments/pantry items → mode "ingredients"
- If the request is about recipes/dishes/meals → mode "recipes"
- If unclear or both → mode "both"
- Extract count, cuisine, meal_type, category constraints when mentioned
- If no count is explicit, infer a reasonable one (default 10)"""

    user = f"Request: {user_text}"
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


# ---------------------------------------------------------------------------
# 2. Ingredient generation (batch of CatalogEntry items)
# ---------------------------------------------------------------------------

def ingredient_generation_messages(
    count: int,
    existing_names: list[str],
    *,
    category_filter: str | None = None,
    prompt_context: str | None = None,
    catalog_summary: str | None = None,
) -> list[dict[str, str]]:
    system = f"""You are a culinary ingredient database expert. Generate pantry catalog
entries for a cooking app.

{_VOCAB_BLOCK}

## CRITICAL: Generic Base + Facet Specificity Pattern

Each entry must be a GENERIC BASE ITEM with specificity expressed through facets.
DO NOT create separate entries for variants — use facets instead.

CORRECT: One entry "Vinegar" with facets: variant=[balsamic, red wine, rice, apple cider, white wine, malt, sherry]
WRONG: Separate entries for "Balsamic Vinegar", "Red Wine Vinegar", "Rice Vinegar"

CORRECT: One entry "Cheese" with facets: variant=[cheddar, mozzarella, parmesan, feta, gruyère, brie, gouda]
WRONG: Separate entries for "Cheddar Cheese", "Mozzarella", "Parmesan", "Feta Cheese"

CORRECT: One entry "Rice" with facets: variant=[white, brown, basmati, jasmine, arborio, sushi]
WRONG: Separate entries for "Basmati Rice", "Brown Rice"

CORRECT: One entry "Potatoes" with facets: variant=[russet, sweet, yukon gold, red, fingerling]
WRONG: Separate entries for "Sweet Potatoes", "Russet Potatoes"

## OVERLAP REJECTION RULES

Before creating ANY entry, check the existing catalog below. An entry is FORBIDDEN if:
1. Its name matches an existing entry's name, alias, or variant option
2. Its name is a variant of an existing generic base (e.g. "Feta Cheese" when "Cheese" exists with variant=feta)
3. Its name is a more specific form of an existing entry (e.g. "Garlic Powder" when "Garlic" exists with form=powdered)
4. Its name is a more generic form that would subsume an existing entry
5. It overlaps with or is contained in any existing entry name

If an existing entry is missing a variant, ADD that variant to the existing entry's facets instead of creating a new entry.
Since you cannot modify existing entries, simply SKIP any ingredient that would overlap.

## Richness Requirements

Every entry MUST include:
- id: kebab-case slug (e.g. "olive-oil", "bell-pepper")
- name: generic base display name (e.g. "Olive Oil", "Bell Pepper")
- category: from allowed Food Categories
- default_unit: most common measurement unit for this ingredient
- default_quantity: sensible default quantity for pantry tracking
- default_storage: primary storage location
- aliases: alternative names, abbreviations, regional terms (at least 2)
- facets: relevant facet dimensions with comprehensive options
  - variant: different types/varieties (MOST entries should have this)
  - form: physical forms (whole, chopped, minced, ground, sliced, diced, etc.)
  - preservation: how it's preserved (fresh, dried, frozen, canned, pickled)
  - Other keys as relevant: processing, preparation, texture, concentration, base
- default_selections: the most common variant/form combination
- substitution_suggestions: 2-4 substitutes with ratio and impact ratings
  - substitute_name should be a generic base name that could be another catalog entry
- freshness_by_storage: list of {{storage, min_days, max_days}} for each applicable storage type

## Substitution Rules
- substitute_name must be a GENERIC BASE ingredient name (not a variant)
- Include ratio (e.g. "1:1"), taste_impact, texture_impact, cooking_impact
- Be realistic about impacts"""

    existing_block = ""
    if catalog_summary:
        existing_block = f"\n\n## Existing Catalog (DO NOT duplicate or overlap with these):\n{catalog_summary}"
    elif existing_names:
        existing_block = f"\n\nAlready in catalog (DO NOT duplicate): {existing_names}"

    constraints = ""
    if category_filter:
        constraints += f"\nFocus on category: {category_filter}"
    if prompt_context:
        constraints += f"\nUser request context: {prompt_context}"

    user = f"Generate {count} unique, fully-rich pantry catalog entries.{constraints}{existing_block}"
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


# ---------------------------------------------------------------------------
# 3. Recipe planning (dish briefs for a batch)
# ---------------------------------------------------------------------------

def recipe_planning_messages(
    count: int,
    existing_titles: list[str],
    *,
    cuisine_filter: str | None = None,
    meal_type_filter: str | None = None,
    prompt_context: str | None = None,
) -> list[dict[str, str]]:
    system = f"""You are a recipe planning expert. Plan diverse, appealing dishes for
a cooking app. Each dish brief will be used to generate a full recipe.

{_VOCAB_BLOCK}

Rules:
- Plan dishes that are distinct from each other (different techniques, proteins, flavor profiles)
- Spread across difficulty levels
- Include a mix of comfort food, weeknight meals, and impressive dishes
- pantry_focus: 2-4 key ingredients that define the dish
- goals: 1-3 words describing the dish character (e.g. "quick weeknight", "comfort food", "dinner party")
- Do NOT plan dishes that duplicate existing titles"""

    existing_block = ""
    if existing_titles:
        existing_block = f"\n\nExisting recipes (avoid these titles): {existing_titles}"

    constraints = ""
    if cuisine_filter:
        constraints += f"\nCuisine: {cuisine_filter}"
    if meal_type_filter:
        constraints += f"\nMeal type: {meal_type_filter}"
    if prompt_context:
        constraints += f"\nUser request context: {prompt_context}"

    user = f"Plan {count} diverse dish briefs.{constraints}{existing_block}"
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


# ---------------------------------------------------------------------------
# 4. Recipe generation (single recipe from a dish brief)
# ---------------------------------------------------------------------------

def recipe_generation_messages(
    brief: dict,
    catalog_summary: str,
) -> list[dict[str, str]]:
    system = f"""You are an expert chef and recipe writer. Generate a complete,
original recipe from the given dish brief.

{_VOCAB_BLOCK}

## Rules
- Title must match the brief's title exactly
- All quantities must be realistic and precise
- Steps must be clear, sequential, and numbered starting from 1
- Include timer_minutes for any step with a specific wait/cook time
- Include estimated_duration_seconds for every step (hands-on time)
- Dietary tags must be accurate — only tag Vegetarian if NO meat/fish ingredients
- Nutrition values must be realistic estimates for the full recipe divided by servings
- Use ingredient names that match the catalog when possible (see catalog below)
- For ingredients not in the catalog, use clear generic base names

## Available Ingredient Catalog
{catalog_summary}"""

    import json
    user = f"Generate a complete recipe for this dish:\n{json.dumps(brief)}"
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


# ---------------------------------------------------------------------------
# 5. Ingredient resolution (map recipe ingredients → catalog)
# ---------------------------------------------------------------------------

def ingredient_resolution_messages(
    recipe_ingredients: list[dict],
    catalog_entries: list[dict],
) -> list[dict[str, str]]:
    system = f"""You are a pantry catalog expert. Your job is to resolve recipe
ingredients against an existing ingredient catalog.

{_VOCAB_BLOCK}

## Resolution Rules

For EACH recipe ingredient, do one of:

1. **Map to existing catalog entry**: If the ingredient matches a catalog entry
   (directly or as a variant), set catalog_entry_id to that entry's id and
   pick the appropriate facet_selections.
   Example: "balsamic vinegar" → catalog_entry_id: "vinegar", facet_selections: [{{key: "variant", value: "balsamic"}}]

2. **Create new catalog entry**: If no catalog entry fits, create a new one following
   the generic-base-with-facet pattern. The new entry must have full richness
   (aliases, facets, substitutions, storage, freshness).
   Example: "tahini" not in catalog → create a new CatalogEntry for "Tahini"

## Generic Base Pattern
- Map specific variants to their generic base: "basmati rice" → "rice" + variant: basmati
- Map prepared forms to their base: "minced garlic" → "garlic" + form: minced
- Only create a NEW entry when no existing base covers the ingredient

## New Entry Requirements (same as ingredient generation)
- Each new entry must be a generic base with facets, aliases, substitutions, freshness, storage
- substitute_name on substitution_suggestions must be generic base names"""

    import json
    user = f"""Resolve these recipe ingredients against the catalog.

Recipe ingredients:
{json.dumps(recipe_ingredients, indent=2)}

Current catalog:
{json.dumps(catalog_entries, indent=2)}"""

    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


# ---------------------------------------------------------------------------
# 6. Recipe review (quality gate)
# ---------------------------------------------------------------------------

def recipe_review_messages(recipe: dict) -> list[dict[str, str]]:
    system = f"""You are a strict recipe quality reviewer for a cooking app.
Review the recipe and decide: accept, revise, or reject.

{_VOCAB_BLOCK}

## Review Criteria
- Title is descriptive and appetizing
- Description accurately summarizes the dish
- Ingredients are realistic, complete (nothing missing for the steps), and properly quantified
- Steps are clear, complete, logically sequenced, and actionable
- Timing is realistic (prep + cook times match step durations)
- Difficulty rating matches the actual complexity
- Dietary tags are accurate (e.g. not tagged Vegetarian if it contains meat)
- Nutrition estimates are plausible
- Servings count is realistic for the quantities

## Decisions
- "accepted": Recipe is good to use as-is
- "revise": Recipe has fixable issues — provide specific feedback
- "rejected": Recipe is fundamentally flawed (nonsensical, dangerous, culturally insensitive)

Be practical — minor imperfections in a generally good recipe should be accepted.
Only request revision for issues that would confuse or mislead a home cook."""

    import json
    user = f"Review this recipe:\n{json.dumps(recipe, indent=2)}"
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]
