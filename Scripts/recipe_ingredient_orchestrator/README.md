# Recipe Ingredient Orchestrator

This package is the external recipe and ingredient corpus pipeline for PantryChef.

It supports two execution modes:

- `demo`: local deterministic generation and heuristic ambiguity resolution for tests and dry runs
- `production`: OpenAI-backed recipe generation plus bounded candidate reranking for ambiguous ingredients

## Environment

Production mode reads:

- `OPENAI_API_KEY`
- `ORCHESTRATOR_OPENAI_MODEL` (defaults to `gpt-4o`)
- `ORCHESTRATOR_PLANNER_MODEL` (defaults to `gpt-4o-mini`)
- `ORCHESTRATOR_REVIEW_MODEL` (defaults to `gpt-4o-mini`)
- `ORCHESTRATOR_AMBIGUITY_MODEL` (defaults to `gpt-4o-mini`)
- `ORCHESTRATOR_OPENAI_BASE_URL` (defaults to `https://api.openai.com/v1`)
- `ORCHESTRATOR_TIMEOUT_SECONDS` (defaults to `90`)
- `ORCHESTRATOR_MAX_RETRIES` (defaults to `3`)
- `ORCHESTRATOR_MAX_DISH_ATTEMPTS` (defaults to `3`)
- `ORCHESTRATOR_MAX_CONCURRENCY` (defaults to `3`)
- `ORCHESTRATOR_REQUESTS_PER_MINUTE` (defaults to `30`)
- `ORCHESTRATOR_LOG_LEVEL` (defaults to `INFO`)
- `ORCHESTRATOR_OUTPUT_ROOT` (defaults to `Scripts/recipe_ingredient_orchestrator/runtime`)
- `ORCHESTRATOR_ACCEPTED_ROOT` (defaults to `Scripts/recipe_ingredient_orchestrator/accepted`)

All model settings must reference GPT-family models.

Key resolution mirrors the app runtime as closely as possible for an external script:

- environment variable first: `OPENAI_API_KEY`
- fallback to the same Xcode config chain the app uses: `Config/Secrets.xcconfig` and `Config/LocalSecrets.xcconfig`

## Commands

Run one dish in demo mode:

```bash
python Scripts/recipe_ingredient_orchestrator/orchestrator.py run-dish --demo --title "Creamy Garlic Chicken Pasta"
```

Plan a natural-language request into a campaign without running generation:

```bash
python Scripts/recipe_ingredient_orchestrator/orchestrator.py plan-request --request "generate 10 indian recipes"
```

Run a natural-language request end to end:

```bash
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py run-request --request "generate a duck confit recipe"
```

Run a true zero-base request with no built-in ingredient seed catalog:

```bash
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py run-request --request "generate 10 french recipes" --empty-catalog
```

Run a production campaign from a spec file:

```bash
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py run-campaign --campaign-file Scripts/recipe_ingredient_orchestrator/examples/campaign.sample.json
```

Run the first larger production batch with bounded parallelism:

```bash
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py run-campaign --campaign-file Scripts/recipe_ingredient_orchestrator/examples/campaign.production.v1.json --max-concurrency 3
```

Resume an existing campaign:

```bash
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py resume-campaign --campaign-dir Scripts/recipe_ingredient_orchestrator/runtime/campaign_xxx
```

Print campaign metrics:

```bash
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py report-campaign --campaign-dir Scripts/recipe_ingredient_orchestrator/runtime/campaign_xxx
```

Print the resolved orchestrator config and model selection:

```bash
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py print-config
```

Run corpus EDA against the current output and accepted roots:

```bash
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py run-eda
```

Grow the first-class ingredient corpus toward a target enriched count:

```bash
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py build-ingredient-corpus --target-count 1000 --batch-size 100 --empty-catalog
```

Grow the accepted recipe corpus toward a target count:

```bash
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py build-recipe-corpus --target-count 1000 --batch-size 25 --max-concurrency 3 --empty-catalog
```

For isolated experiments, override the runtime roots explicitly:

```bash
ORCHESTRATOR_OUTPUT_ROOT=Scripts/recipe_ingredient_orchestrator/runtime_experiment \
ORCHESTRATOR_ACCEPTED_ROOT=Scripts/recipe_ingredient_orchestrator/accepted_experiment \
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py run-eda
```

## Output Format

There are now two recipe export formats on purpose:

- `runs/<dish_id>/exported_recipe.json`: enriched app-shaped single-recipe export with resolved catalog ids and facets for orchestrator review.
- `runs/<dish_id>/app_seed_recipe.json`: exact seed-loader-compatible single recipe export for PantryChef import.

Each completed campaign also writes:

- `app_import/seed_recipes.json`: an array shaped like PantryChef's bundled `seed_recipes.json` resource.
- `app_import/manifest.json`: lightweight metadata describing the bundle and how to use it.

Each orchestrator invocation also logs to:

- `runtime/logs/orchestrator.log`: rolling execution log with planning, retries, campaign progress, and OpenAI request retries.

Command summaries now also include `logPath` so long-running executions can be inspected while they are still running.

The import bundle is designed so approved recipes can be merged directly into `PantryChef/Resources/seed_recipes.json` with minimal or no transformation.

## Request Planning

The orchestrator now supports request-style entrypoints such as:

- `generate 10 indian recipes`
- `generate 5 korean dinner recipes`
- `generate a duck confit recipe`

Planning behavior:

- request interpretation uses a structured model response only; there is no heuristic regex or keyword fallback path
- explicit single-dish requests are planned through an exact-dish briefing path so the requested dish title is preserved while pantry focus and technique are inferred more richly
- open-ended multi-recipe requests are decomposed into distinct dish briefs with cuisine, meal type, pantry focus, and goals
- request planning is aware of the existing PantryChef recipe corpus before it selects dishes
- request-based entrypoints require `OPENAI_API_KEY`, including `run-request --demo`, because planning remains model-backed even when generation is mocked

## Empty Catalog Mode

`--empty-catalog` disables built-in seed ingredient entries and forces the pipeline to build ingredient knowledge from unresolved mentions or corpus-build prompts.

Use it for:

- validating true zero-base recipe generation
- measuring first-class ingredient enrichment behavior without seed assistance
- building fresh ingredient and recipe corpus roots for experiments

It is supported on:

- `run-dish`
- `run-campaign`
- `run-request`
- `resume-campaign`
- `build-ingredient-corpus`
- `build-recipe-corpus`

## Corpus Awareness And Duplicates

The orchestrator checks the existing recipe corpus from:

- `PantryChef/Resources/seed_recipes.json`
- approved generated bundles under the orchestrator runtime output when they exist

Duplicate prevention happens in two places:

- during request planning, where duplicate or near-duplicate dish titles are filtered out before a campaign is created
- during recipe generation, where generated candidates are checked against the existing corpus and retried if they collide with existing or explicitly avoided titles

The known corpus now includes a durable accepted corpus outside transient runtime output:

- runtime-generated `app_import/seed_recipes.json` bundles when they exist
- machine-accepted bundles under `ORCHESTRATOR_ACCEPTED_ROOT`

This means duplicate awareness survives runtime cleanup.

## Review And Retries

Every generated recipe now goes through two gates before acceptance:

- deterministic validation for structural issues such as unresolved ingredients, invalid quantities, missing steps, and non-sequential step numbering
- semantic recipe review, which uses an LLM in production to decide whether a recipe should be accepted, revised, or rejected

If a recipe fails validation or semantic review, the orchestrator now retries the dish with bounded per-dish attempts and feeds the revision instructions back into the next generation attempt.

Failure handling is categorized explicitly so campaign state and metrics can distinguish between classes such as:

- `openai_request_failed`
- `duplicate_recipe_generated`
- `ingredient_resolution_failed`
- `recipe_validation_failed`
- `semantic_review_revision`
- `semantic_review_rejected`

## Runtime Layout

Each campaign directory contains:

- `state.json`: resumable campaign state
- `campaign_metrics.json`: aggregate throughput, success/failure, promotion, quarantine, and per-dish runtime metrics
- `campaign_spec.json`: the resolved input spec
- `runs/<dish_id>/pipeline_run.json`: detailed structured pipeline output
- `runs/<dish_id>/exported_recipe.json`: app-shaped recipe export
- `runs/<dish_id>/app_seed_recipe.json`: seed-loader-compatible single recipe export
- `recipes/*.json`: campaign recipe corpus exports
- `app_import/seed_recipes.json`: approval-ready app import bundle matching PantryChef seed recipe format
- `app_import/manifest.json`: bundle metadata and handoff notes
- `ingredient_corpus/promoted/*.json`: promoted ingredient evidence documents
- `ingredient_corpus/quarantine/*.json`: unresolved ingredient evidence for later review

Accepted campaign bundles are also mirrored to the durable accepted corpus root so future planning and generation runs see them even after runtime cleanup.

## Corpus Build And EDA

The corpus builder layer exists for large-scale autonomous growth, not just per-request recipe generation.

`build-ingredient-corpus`:

- grows the persisted ingredient catalog toward a target enriched count
- steers each batch toward underrepresented categories
- filters duplicate or low-value generic canonical names before persisting
- writes a JSON build report under `corpus_builds/ingredients/`

`build-recipe-corpus`:

- plans unique dish briefs against the current known corpus
- executes production generation through the same review and validation pipeline as normal campaigns
- writes a JSON build report under `corpus_builds/recipes/`

`run-eda`:

- summarizes ingredient category coverage, substitute/storage coverage, and alias richness
- summarizes accepted recipe counts, cuisine spread, meal-type spread, and duplicate-title posture
- is meant to be run between corpus-build passes to decide where the next batch should push coverage

## Parallelism

Parallelism is intentionally bounded at the dish level:

- campaigns run multiple dishes concurrently via a thread pool
- OpenAI requests are rate-limited globally in-process
- ingredient extraction, resolution, and reconciliation stay sequential within a dish so recipe quality and traceability do not degrade

Use `max_concurrency` in a campaign file or `--max-concurrency` on the CLI to tune throughput without changing the workflow model.