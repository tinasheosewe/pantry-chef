# Recipe & Ingredient Orchestrator

LLM-powered pipeline for generating a rich ingredient catalog and fully-resolved recipes for the PantryChef iOS app.

## Quick Start

```bash
# Install dependencies
pip install -r requirements.txt

# Generate 50 ingredients and 20 recipes
python -m recipe_ingredient_orchestrator generate --mode both --count 50

# Generate from a natural-language prompt
python -m recipe_ingredient_orchestrator generate --prompt "30 pantry staples and 10 quick weeknight dinners"

# Generate only ingredients in a specific category
python -m recipe_ingredient_orchestrator generate --mode ingredients --count 25 --category "Produce"

# Generate recipes for a specific cuisine
python -m recipe_ingredient_orchestrator generate --mode recipes --count 10 --cuisine "Japanese"
```

## Configuration

The pipeline reads the OpenAI API key from (in priority order):

1. `OPENAI_API_KEY` environment variable
2. `Config/LocalSecrets.xcconfig` (`OPENAI_API_KEY = sk-...`)
3. `Config/Secrets.xcconfig`

Other settings (all optional env vars):

| Variable | Default | Description |
|---|---|---|
| `MODEL` | `gpt-4o` | Main generation model |
| `REVIEW_MODEL` | `gpt-4o-mini` | Recipe review model |
| `ENRICHMENT_MODEL` | `gpt-4o-mini` | Ingredient generation & resolution |
| `PLANNER_MODEL` | `gpt-4o-mini` | Dish planning model |
| `MAX_CONCURRENCY` | `5` | Concurrent LLM calls |
| `INGREDIENT_BATCH_SIZE` | `25` | Entries per LLM batch |
| `RECIPE_BATCH_SIZE` | `10` | Recipes per planning batch |
| `MAX_RETRIES` | `3` | Review retry limit |
| `OUTPUT_DIR` | `output/` | Where JSON files are written |

## Pipeline Modes

### `ingredients` — Catalog generation only

Generates `CatalogEntry` objects following the **generic-base-with-facet-specificity** pattern: one entry for "Vinegar" with `variant=[balsamic, red wine, rice, ...]`, not separate entries per type.

Each entry includes: category, aliases, facet definitions & defaults, storage type, freshness ranges, and substitution suggestions.

### `recipes` — Recipe generation only

1. **Plan** — LLM plans diverse dish briefs
2. **Generate** — Each brief becomes a raw recipe
3. **Resolve** — Ingredients are matched to existing catalog entries (or new entries created) via LLM
4. **Review** — Quality gate: accept / revise / reject

### `both` — Full pipeline

Runs ingredient generation first, then recipe generation. Recipes reference the just-built catalog.

## Incremental Runs

Seed from previous output to avoid duplicates:

```bash
python -m recipe_ingredient_orchestrator generate \
  --mode both --count 20 \
  --seed-catalog output/ingredient_catalog.json \
  --seed-recipes output/recipes.json
```

## Substitution Linking

Substitution suggestions are free-text during generation. A post-generation pass links them to actual catalog entries (by name or alias). Unresolvable suggestions are dropped — never created.

To re-run linking on an existing catalog:

```bash
python -m recipe_ingredient_orchestrator relink output/ingredient_catalog.json
```

## Output

- `ingredient_catalog.json` — Array of `CatalogEntry`
- `recipes.json` — Array of `Recipe`
- `summary.json` — Stats (counts, timestamp)

## Testing

```bash
pip install pytest pytest-asyncio
cd Scripts/recipe_ingredient_orchestrator
pytest tests/ -v
```

## Architecture

```
recipe_ingredient_orchestrator/
├── __main__.py          CLI entry point
├── schemas.py           Enums (FoodCategory, MeasurementUnit, …)
├── models.py            Pydantic data models
├── config.py            Settings from env / xcconfig
├── client.py            Async OpenAI wrapper with structured outputs
├── prompts.py           All prompt builders
├── catalog.py           In-memory catalog with substitution linking
├── ingredient_generator.py  Batched ingredient generation
├── recipe_generator.py      Plan → generate → resolve pipeline
├── reviewer.py              LLM quality gate
├── orchestrator.py      Main coordinator
├── writer.py            JSON output
└── tests/
    ├── conftest.py      Fixtures & mock factories
    ├── test_models.py   Pydantic validation
    ├── test_catalog.py  Catalog operations & linking
    ├── test_generators.py  Generator flows
    ├── test_reviewer.py    Review outcomes
    └── test_orchestrator.py  Full pipeline scenarios
```
