# PantryChef

PantryChef is a native iOS app (SwiftUI, iOS 17) that keeps track of what is in a home kitchen and works out which recipes can be cooked from it. It is for home cooks who want to use food before it spoils without keeping a precise inventory: for every item the app tracks how fresh it is and, separately, how far it still trusts its own record. Stock, readiness, planning, cook mode, timers and reminders run on the device with no account or backend. Recipe import and generation use OpenAI's GPT-4o and are optional: without an API key those actions return nothing and the rest of the app is unaffected.

## At a glance

- **Governed ingredient catalog.** 2,888 ingredients in 18 categories (`PantryChef/Resources/catalog.json`), each with aliases, facets from a fixed ten-key vocabulary, optional parent links, shelf-life ranges per storage location, density, allergens, dietary tags and substitutions. Governed means two things here: the vocabularies (categories, facet keys, storage, units, allergens, dietary tags) are Swift enums, so a value outside them fails the decode, and `CatalogInvariantTests` runs 15 checks over the whole loaded catalog.
- **Structural readiness engine.** `ReadinessService` answers ready, ready with substitutions, or needs N items for a recipe. It matches by catalog identity and parent lineage (`IngredientMatching`), not by comparing names, and it only counts stock the app still trusts.
- **Deterministic multi-dish cook scheduling.** `MultiCookScheduler` is a pure function that merges several recipes into one step list, the same list for the same input: prep first, then a clock simulation that starts the long hands-off steps and fills their waiting time with hands-on work from the other dishes.
- **Two clocks per item.** `ExpiryEngine` projects days left from the share of shelf life already used, across moves between pantry, fridge and freezer. `ConfidenceEngine` decays the app's trust in a record from the day it was last confirmed.
- **Typed and barcode intake.** A typed phrase goes through a parser written without regular expressions, then a pipeline that accepts a confident catalog match, offers candidates when it is unsure, or creates a custom ingredient. Barcodes are scanned with VisionKit and named through Open Food Facts.
- **Share extension.** "Save to PantryChef" takes a recipe link or text from another app's share sheet and hands it to the app, which imports it.
- **GPT-4o recipe import and generation.** Import from a link, pasted text or a photo of a recipe; generate a recipe from the current pantry. Calls use strict JSON-schema output and every result opens in the editor for review.
- **242 unit tests and a CI workflow.** `PantryChefTests` holds 242 unit tests over the engines, the store and the bundled data. `.github/workflows/ios-quality.yml` builds the checked-in project and runs them on an iPhone simulator for every push to `main` and every pull request, then applies a line-coverage floor.

To run it, open `PantryChef.xcodeproj` in Xcode, choose the `PantryChef` scheme and an iOS 17 or later simulator, and run. No key or account is needed. Details are under [Setup](#setup).

## What the app does

The root view (`PantryChef/UI/Features/RedesignRootView.swift`) shows three spaces, **Today**, **Plan** and **Pantry**, in a bottom navigation band (`Dock`) with a **+** button. A recipe and cook mode open as full-screen covers; adding, planning, shopping and settings are sheets.

**Today** (recipe feed)
- A count of recipes that can be made now, and a hero card for the meal planned for the current part of the day or for a cook in progress.
- Rails ordered by pantry readiness: leftovers to eat first, dishes that use ingredients about to expire, dishes ready now, dishes ready with a substitution, favorites, and dishes that need a shop, fewest missing items first.
- Lens chips (For you, All, Favorites, Make now, With a swap, Shop, Use it up, Quick, High-protein), filters for cuisine, diet, meal type and time, search by name, four sort orders, and a multi-select that starts one cook session for several dishes.
- A menu to write a recipe, paste text or a link, or pick a photo of a recipe, and a sheet to log a meal eaten without a recipe.

**Recipe page**
- Readiness against current stock, allergens, on-hand status per ingredient with gram hints, ranked substitutions that can be applied per line, a servings scaler, and per-serving nutrition (labeled as an estimate when it is derived).
- Favorite, a 1 to 5 rating, notes and cook history; a structured editor; adding missing ingredients to the shopping list; "Cook" or "Cooked it".

**Cook mode**
- A gathering checklist, then one step per screen with per-step timers anchored to the wall clock. Timers keep running across steps and in the background, where each has a matching local notification.
- Several dishes cooked together are interleaved by the scheduler described below. Cooked food is stored as leftovers; a single dish asks how many portions came out.

**Plan**
- A forward timeline from today over a 16-day horizon: planned meals grouped by day and part of day, and expiry dates taken from live stock. Runs of empty days fold, and a date picker plans further ahead.
- Planning a day uses the same browse, search and filter UI as Today and can also schedule a leftover. A planned meal can be resized, moved within its day, cooked or logged, or removed.

**Pantry**
- Stock grouped by category, with a "use soon" band for items within three days of turning and a count on the tab. Each item records its storage (pantry, fridge, freezer), days left or a staple level, and when it was last confirmed.
- A record that has gone stale asks a one-tap question ("still here" or "finished") instead of being trusted silently.
- A shopping list grouped by aisle, and a shopping run that checks items off, adjusts the amounts bought and moves them into stock.

**Adding food (+)**
- A text bar that parses a phrase such as `300 g spinach, fridge` into quantity, unit, ingredient and storage, with a live preview. An uncertain match opens a candidate picker; an unknown ingredient opens a custom-ingredient form.
- Barcode scanning with VisionKit's data scanner. The product name comes from the Open Food Facts API and is matched to the catalog; each scan lands in a list that can be undone. Scanning needs a device camera.

**Also**
- First-run onboarding that builds the pantry from common staples, typed items or barcodes while a count of cookable recipes updates. A sample kitchen can be loaded instead.
- A share extension ("Save to PantryChef") that accepts a web URL or text from other apps and hands it to the app for import. A link on the clipboard is offered for import at launch. Both go through the GPT-4o import, so they need a key.
- Settings: adjust days left when an item changes storage, assume a basic spice rack, expiry reminders, and a dietary profile of avoided allergens that removes conflicting dishes from the feed.
- Optional GPT-4o actions, each started by the user: import a recipe from a link, pasted text or a photo; generate a recipe from the current pantry; clean up a draft; suggest a healthier version; apply a free-text change; fill in the details of a custom ingredient.

## How it is built

- **State and persistence.** One `@Observable` store, `KitchenStore`, holds the kitchen and derives the timeline, readiness and intake results through pure engines. User-owned state (stock, shopping list, planned meals, cook journal, dietary profile, settings, and per-recipe favorites, ratings and notes) is saved as one Codable JSON snapshot in Application Support (`PantryPersistence`): debounced, written atomically, and decoded tolerantly so older files still load. The recipe library (188 bundled recipes in `seed_recipes.json` plus seven defined in code) is rebuilt from the bundle at launch.
- **Ingredient catalog.** `PantryCatalog` decodes `catalog.json` off the main thread behind a loading screen and keeps alias, token, facet and lineage indices for lookup. 2,044 of the 2,888 entries have a parent entry; facet options come from ten keys (color, variant, grade, fat, form, preparation, preservation, processing, texture, medium).
- **Catalog checks.** `CatalogInvariantTests` checks the loaded data: every name resolves to an item of that name, single-word names within their own category, and every alias resolves; every parent exists, there are no inheritance cycles and inherited facets are additive; each facet value belongs to exactly one key; default selections refer to real options; no name or id is a bare modifier word; dietary tags agree with allergens; densities are plausible; substitutions point at real items. `SeedDishCatalogTests` ties the recipes to it: every recipe ingredient resolves to a catalog item and carries its id. Edits after the first build were applied as lists of validated operations (merge, rename, re-parent, re-id, retag) kept under `docs/catalog-*`, with the appliers in `tools/`.
- **Catalog provenance.** The first vocabulary was chosen with a frequency analysis of ingredient names in the RecipeNLG corpus, run locally; entries and their fields were then written and revised with language models and the scripts in `Scripts/` and `tools/`. No third-party food database is bundled. See `THIRD_PARTY_LICENSES.md` and, before re-running the Python side, `Scripts/README.md`.
- **Matching and readiness.** Recipe lines carry a catalog id where one is known. `IngredientMatching` treats a line as on hand when stock holds the same item or one on its parent lineage within the same category. `ReadinessService` is a pure function from a dish's requirements to ready, ready with swaps, or needs N: staples are assumed, optional lines never block, and a dish that would need substitutes for more than about a third of its essential ingredients is not called ready. `CatalogSwaps` ranks substitutes in three tiers (curated, sibling varieties, same family), and only the first two count toward readiness. Results are cached per dish against a fingerprint of trusted stock and the day.
- **Two clocks per item.** `ExpiryEngine` models freshness as the fraction of shelf life consumed, so moving food between pantry, fridge and freezer re-projects the days left. `ConfidenceEngine` decays the app's trust in a record from its last confirmation, on a half-life derived from shelf life and tracking class. Records judged likely gone stop counting toward readiness.
- **Intake.** `IntakeParser` tokenizes a typed phrase by character class, without regular expressions, and fills quantity, unit and storage slots from closed vocabularies; what remains is the ingredient name. `IntakePipeline` then accepts a confident catalog match, offers ranked candidates when the lead is small, or routes to a custom ingredient. The parser handles one item per phrase; `docs/input-system-proposal.md` measures where it goes wrong and proposes its replacement.
- **Search.** `CatalogSearchEngine` matches multi-word facet phrases, classifies each remaining token (exact, Levenshtein with a tolerance scaled to word length, Bitap approximate substring, then prefix), accumulates evidence per candidate, and scores on coverage, exactness and name relevance. `BitapSearcher` is adapted from Fuse-Swift (see `THIRD_PARTY_LICENSES.md`). `RankedTextSearchEngine` is a generic weighted-field engine over the same token matcher; at present only the tests use it.
- **Multi-dish scheduling.** `MultiCookScheduler` takes the dishes and returns one ordered step list. All prep steps come first. The cook phase is a clock simulation: a dish's next step unlocks when its previous step's time has elapsed; at each moment the cook starts the longest hands-off step available, otherwise the shortest hands-on one; a hands-off step occupies the cook only for a short setup. Steps are tagged prep, cook or finish and active or passive, either explicitly or by `StepClassifier` from their wording and timer length.
- **Timeline.** `TimelineComposer` is a pure function from a snapshot (today, horizon, events) to timeline rows. It groups a day's meals, folds runs of two or more empty days, and inserts week markers with planned-meal counts.
- **AI boundary.** `AIService` calls OpenAI Chat Completions (`gpt-4o`) through `URLSession` with strict JSON-schema output. Recipe calls return either a recipe or a rejection, so off-topic or non-recipe input is refused. A response is decoded into DTOs, dropped if it has no ingredients, and mapped to the app's `Dish` model with each ingredient resolved against the catalog; for imported and generated recipes, ingredients the catalog lacks are registered as user catalog items (`SmartIngredient`). A failed request is retried on 429, 5xx and transport errors, up to three attempts in total, and each attempt records a telemetry event. URL import fetches the page the user gave it and prefers its schema.org Recipe JSON-LD over stripped HTML.
- **Recipes and plate art.** The 188 bundled recipes were written with a language model for this project (drafts under `docs/recipe-seed/`), then deduplicated, timed per step and marked essential or optional per ingredient by later passes. Their plate images in `Resources/PlateArt` were generated with OpenAI's `gpt-image-1` from a single art-direction prompt (`tools/generate_plate_art.py`). For other dishes `PlateRenderLibrary` looks in memory, then a disk cache, then the bundle, and only when an OpenAI key is configured requests one image, capped at 12 new renders per launch. Otherwise an emoji plate is shown.
- **Share extension.** The `ShareExtension` target only extracts the shared URL or text and writes it to an App Group inbox (code in `PantryChef/Shared`, compiled into both targets). The app drains the inbox when it becomes active and runs the import there.
- **Notifications and telemetry.** `NotificationService` schedules cook-timer notifications and "use it up" reminders at 10:00 on an item's last good morning, asking for permission in context. `AppTelemetryReporter` logs locally and forwards events to Sentry, which starts only when `SENTRY_DSN` is set.
- **UI.** Theme tokens, the Fraunces display face and the print-style primitives live in `UI/Foundation` and `UI/Primitives`. The palette switches to a dark variant between 20:00 and 05:00, Dynamic Type is supported up to the second accessibility size, and animations respect Reduce Motion.

## Stack and requirements

- Swift 5.9 language mode, SwiftUI with the Observation framework, deployment target iOS 17.0. UIKit is used for the share extension, VisionKit for barcode scanning, PhotosUI for recipe photos and UserNotifications for timers and reminders.
- One Swift package: `sentry-cocoa`, pinned to 9.8.0 in the tracked `Package.resolved` and inactive unless a DSN is configured. Its prebuilt frameworks take about 2 GB of disk on first resolve.
- Network services, all optional: OpenAI Chat Completions and image generation (called with `URLSession`, no SDK) and the Open Food Facts product API.
- Developed with Xcode 26.3 and the iOS 26.2 simulator. The project file is saved in the Xcode 16 format (`objectVersion = 77`), so earlier Xcode versions cannot open it.
- Python 3 for the catalog scripts and Ruby with the `xcodeproj` gem for the project helpers in `tools/`. Neither is needed to build the app.

## Setup

1. Open `PantryChef.xcodeproj` in Xcode. The checked-in project defines the four targets (`PantryChef`, `ShareExtension`, `PantryChefTests`, `PantryChefUITests`) and the Sentry package. No scheme file is tracked: Xcode creates the `PantryChef` scheme for the app target automatically, and its test action covers both test targets. New source files are registered in Xcode or with `ruby tools/xcadd.rb <path>`.
2. Optional: create `Config/LocalSecrets.xcconfig` (git-ignored) containing `OPENAI_API_KEY = <your key>` to enable the GPT-4o actions and plate rendering. `Config/Secrets.xcconfig` includes that file when it exists, the value is substituted into `Info.plist`, and `AppConfig` reads environment variables first and `Info.plist` second. `SENTRY_DSN` is read the same way; xcconfig treats `//` as the start of a comment, so write a DSN URL as `https:/$()/...` or set it as an environment variable in the scheme. The key ends up inside the built app, so this arrangement is for local development builds. No keys are stored in the repository.
3. Signing: the project carries the maintainer's development team and `com.tboya.pantrychef` identifiers. Simulator builds are signed to run locally and do not need them. To run on a device under another Apple team, select your team for the `PantryChef` and `ShareExtension` targets and use bundle identifiers and an App Group of your own. The group id appears in both `.entitlements` files and in `PantryChef/Shared/SharedRecipeInbox.swift`.
4. Run the `PantryChef` scheme on a simulator or device with iOS 17 or later. A first launch opens onboarding with an empty kitchen; "Explore a sample kitchen first" loads demo stock, plans and a shopping list. Barcode scanning needs a device camera.

## Testing

- `PantryChefTests` contains 242 XCTest functions in 28 files. They cover the pure engines (readiness, ingredient matching and lineage, substitution tiers, expiry and storage moves, confidence decay, intake parsing and the intake decision, catalog search and the Bitap matcher, the multi-dish scheduler, the timeline composer, nutrition estimates, unit conversion, serving scaling), store behavior (meal planning, leftovers, cook logging, the shopping list, snapshot round-trips, the share inbox), the mapping from an AI response to a `Dish`, telemetry formatting, and checks over the bundled data (catalog invariants, every seed-recipe ingredient resolves to a catalog item, every seed recipe has plate art).
- `PantryChefUITests` contains two UI tests: a launch test that visits the three spaces, and a test that drives Safari's share sheet to check that "Save to PantryChef" is offered.

Run the unit tests from Xcode (Product > Test) or from the command line, substituting a simulator installed on your machine:

```bash
xcodebuild test -project PantryChef.xcodeproj -scheme PantryChef \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PantryChefTests
```

`bash Scripts/ci/run_quality.sh` does the same on a simulator it picks itself, with code coverage, and then fails if line coverage of the app target drops below 18% (`Scripts/ci/check_coverage.py`; the unit tests cover the engines, the store and the bundled data, not the SwiftUI views, and the figure measured in CI is 19%). The GitHub Actions workflow in `.github/workflows/ios-quality.yml` runs that script on a `macos-26` runner for every push to `main` and every pull request. The UI tests are not part of it: run them with `-only-testing:PantryChefUITests` or `RUN_UI_TESTS=1 bash Scripts/ci/run_quality.sh`. `TESTING.md` has the details, and `tools/verify_share_extension.sh` checks on a booted simulator that the built app registers its share extension.

## Repository map

```text
.
├── PantryChef.xcodeproj/      # checked-in project: four targets, one package
├── PantryChef/                # app target
│   ├── App/                   # @main entry point
│   ├── UI/
│   │   ├── Features/          # RedesignRootView, KitchenStore, LoadingScreen, and one folder per surface:
│   │   │                      #   Today, Timeline (Plan), Stock (Pantry, shopping), Composer, Cook, Now, Onboarding, Settings
│   │   ├── Foundation/        # theme and font loading
│   │   └── Primitives/        # Dock, plates, rules, buttons, motion
│   ├── Services/              # AI, search, intake, readiness, expiry, confidence, scheduler, timeline composer,
│   │                          #   notifications, persistence, plate rendering, product lookup, telemetry
│   ├── Models/                # Dish, catalog, timeline models, enums, tuning constants
│   ├── Helpers/               # ingredient matching, swaps, unit conversion, AI-to-Dish mapping
│   ├── Shared/                # share inbox code compiled into the app and the extension
│   ├── Utils/                 # AppConfig, launch options, logging, extensions
│   └── Resources/             # catalog.json, seed_recipes.json, PlateArt/, Fonts/
├── ShareExtension/            # "Save to PantryChef" share extension
├── PantryChefTests/           # unit tests
├── PantryChefUITests/         # UI tests
├── Config/                    # Secrets.xcconfig (includes the untracked LocalSecrets.xcconfig)
├── Scripts/                   # Python catalog scripts (see Scripts/README.md) and ci/
├── tools/                     # project-file helpers (xcadd.rb, xcrm.rb, add_share_extension.rb),
│                              #   catalog and recipe data appliers, plate-art and icon generators
├── docs/                      # specs, proposals, backlog, and the inputs and outputs of the data passes
├── Documentation/             # March 2026 feature specification and archived notes
├── .github/                   # CI workflow, assistant instruction files
└── TESTING.md, THIRD_PARTY_LICENSES.md
```

Not referenced by the current code, and kept from the app as it was before the June 2026 redesign: `Models/StepTask.swift`, `Models/LLMBatchSchedule.swift`, `Models/AppError.swift` and `Utils/PantryAddFrequencyTracker.swift`. `Resources/catalog.source.json` is the tree-shaped source the catalog was once compiled from; it is behind `catalog.json` and the app does not load it.

## Further reading

Current:

- `TESTING.md`: how to run the tests, the coverage gate and the manual checks.
- `THIRD_PARTY_LICENSES.md`: dependencies, adapted code, fonts, and where the bundled data and images came from.
- `docs/README.md`: an index of the documents and data-pass folders under `docs/`.
- `docs/input-system-proposal.md`: a proposal dated 2 September 2026 for reworking ingredient entry, marked "for decision".
- `docs/TODO.md`: running backlog and decision log.

Describing an earlier design or state (each is dated, or carries a dated note, at its top):

- `docs/redesign-spec.md`: the design spec for the June 2026 redesign. It records intent; the implemented spaces, visual style and input methods differ in places.
- `docs/catalog-model.md`, `docs/catalog-remodel-spec.md`, `docs/catalog-inheritance-plan.md`, `Scripts/remodel/README.md`: the catalog model and the source-compile pipeline as of May and early June 2026.
- `docs/feature-inventory.md`, `docs/feature-audit.md`: snapshots from 10 and 11 June 2026 of the pre-redesign feature list and of the first redesign build.
- `Documentation/FEATURES.md`: the March 2026 feature specification for the previous four-tab app.
- `Documentation/ARCHIVE/PANTRY_INTAKE_NOTES.md`: March 2026 notes on pantry intake and receipt OCR. Receipt OCR was not built.

## License

Personal project. Not licensed for distribution. Third-party components keep their own licenses; see `THIRD_PARTY_LICENSES.md`.
