# PantryChef

PantryChef is a local-first iOS cooking and kitchen-planning app built with SwiftUI. The current build centers on structured pantry entry, recipe management, meal planning, shopping generation, prepared-dish tracking, and guided cook mode, with AI features layered on top when keys are configured.

## Current Implementation

The shipped app is organized around four root tabs:

- Today: dashboard for today's meals, expiring inventory, suggested recipes, and quick actions.
- Recipes: My Recipes plus Discover, with pantry-aware filtering and AI-assisted recipe workflows.
- Kitchen: pantry, prepared dishes, and shopping management in one workspace.
- Plan: meal planning, plan review, and shopping generation.

Current product status:

- Pantry intake is manual-first through structured single-item and bulk-add flows backed by a canonical pantry catalog.
- Core persistence is local SwiftData. No active Supabase sync or backend is required to run the app.
- Realtime voice cook mode is implemented through the OpenAI Realtime API and the vendored `swift-realtime-openai` fork.
- Receipt OCR and barcode pantry intake remain research-only and are not part of the shipped intake flow.
- Crash reporting and telemetry are wired for Sentry, but remain disabled unless `SENTRY_DSN` is set.

## Major Capabilities

- Pantry inventory with quantity modes, storage-aware freshness, category grouping, duplicate merging, and post-cook review.
- Canonical pantry catalog with aliases, structured facets, substitution metadata, freshness defaults, and saved user preferences.
- Recipe library spanning bundled discover recipes, imported recipes, user recipes, and AI-generated recipes.
- Pantry-aware recipe matching, substitution surfacing, and what-can-I-make workflows.
- Meal planning with prepared-dish integration and shopping-list generation.
- Interactive cook mode with timers, notifications, resume support, and cook-queue management.
- Prepared-dish tracking for leftovers and meal prep.
- Optional AI helpers for recipe generation, healthier variants, leftovers, shopping assistance, and conversational cook support.

## Stack

- iOS 17.0+
- Swift 5.9
- SwiftUI
- XcodeGen
- SwiftData
- OpenAI Chat Completions plus OpenAI Realtime API
- Sentry Cocoa (optional crash reporting and telemetry)
- Vendored `swift-realtime-openai` fork in `Vendor/`

## Setup

### Prerequisites

- macOS with Xcode 15 or newer
- XcodeGen
- An OpenAI API key if you want AI-backed features enabled

Install XcodeGen if needed:

```bash
brew install xcodegen
```

### 1. Generate The Project

```bash
cd PantryChef
xcodegen generate
open PantryChef.xcodeproj
```

### 2. Configure Secrets

The app loads `Config/Secrets.xcconfig`, which in turn includes `Config/LocalSecrets.xcconfig` for developer-local values.

Supported config values:

- `OPENAI_API_KEY`: enables AI recipe generation, shopping helpers, and realtime cook assistance.
- `SENTRY_DSN`: optional; enables crash reporting and telemetry forwarding to Sentry.

`AppConfig` checks environment variables first, then `Info.plist` values.

### 3. Adjust Local Build Settings If Needed

`project.yml` currently contains a hardcoded `DEVELOPMENT_TEAM` for the primary maintainer. If you are building under a different Apple team, change signing in Xcode or override the project setting after regenerating the project.

### 4. Build And Run

Open the `PantryChef` scheme in Xcode and run on an iOS 17 simulator or device.

On first launch, the app seeds local sample data unless UI-test launch arguments request an empty state.

## Testing

Run the canonical quality command:

```bash
bash Scripts/ci/run_quality.sh
```

That script:

- regenerates the Xcode project with XcodeGen
- auto-selects an available iPhone simulator
- runs the unit bundle and coverage gate
- runs the UI smoke bundle separately

See `TESTING.md` for direct `xcodebuild` commands, coverage details, performance budgets, and release checklists.

## External Orchestrator

The repository also contains an external GPT-backed recipe and ingredient corpus pipeline under `Scripts/recipe_ingredient_orchestrator/`.

It supports:

- natural-language request planning into recipe campaigns
- zero-base generation with `--empty-catalog`
- first-class ingredient enrichment and promotion
- corpus EDA plus large-scale ingredient and recipe corpus growth

Useful entrypoints:

```bash
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py print-config
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py run-eda
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py run-request --request "generate 10 french recipes" --empty-catalog
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py build-ingredient-corpus --target-count 1000 --batch-size 100 --empty-catalog
python3 Scripts/recipe_ingredient_orchestrator/orchestrator.py build-recipe-corpus --target-count 1000 --batch-size 25 --max-concurrency 3 --empty-catalog
```

See `Scripts/recipe_ingredient_orchestrator/README.md` for the full command surface and runtime layout.

## Repository Map

```text
PantryChef/
├── project.yml
├── README.md
├── TESTING.md
├── THIRD_PARTY_LICENSES.md
├── Config/
├── Documentation/
│   ├── FEATURES.md
│   └── ARCHIVE/
├── PantryChef/
│   ├── App/                # app entry, shared state, navigation, tab shell
│   ├── Helpers/            # ingredient, matching, and audio helpers
│   ├── Models/             # pantry, recipes, planning, AI, cooking, and intake models
│   ├── Resources/          # bundled seed recipes and assets
│   ├── Services/           # storage, AI, realtime, notifications, telemetry
│   ├── Utils/              # config, launch options, logging, shared utilities
│   ├── ViewModels/         # feature presentation state
│   └── Views/              # SwiftUI feature screens and components
├── PantryChefTests/
├── PantryChefUITests/
├── Scripts/
│   └── ci/
├── Supabase/
│   └── migrations/
└── Vendor/
    └── swift-realtime-openai/
```

## Notes

- The app is local-first today. Supabase migrations are present for future work, but no active backend path is required.
- AI features degrade gracefully when `OPENAI_API_KEY` is missing.
- Realtime cook mode requires microphone permission and an OpenAI key.
- Sentry starts only when `SENTRY_DSN` is configured.

## Related Docs

- `TESTING.md`
- `Documentation/FEATURES.md`
- `Documentation/ARCHIVE/PANTRY_INTAKE_NOTES.md`
- `Documentation/ARCHIVE/OCR_NOTES.md`
- `Vendor/swift-realtime-openai/PantryChefForkNotes.md`

## License

Personal project. Not licensed for distribution.
