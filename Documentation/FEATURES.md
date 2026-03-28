# PantryChef — Comprehensive Feature Specification

> This document describes the implemented PantryChef feature set as of March 28, 2026. It focuses on shipped data models, services, workflows, and business logic, and explicitly calls out infrastructure-only or research-only capabilities where relevant.

## Implementation Status Notes

### Current App Shell
- The shipped app is organized around four root tabs: **Today**, **Recipes**, **Kitchen**, and **Plan**.
- The **Today** dashboard is a live operational summary rather than a static welcome screen.
   - It surfaces today's meal-plan entries.
   - It highlights expiring pantry items and expiring prepared dishes.
   - It provides quick actions for "What can I make?", shopping generation from the meal plan, and meal planning.
   - It can show a pantry-based suggested recipe and a weekly nutrition summary.
   - On weekends it surfaces a batch-prep prompt.
- The **Recipes** workspace is split into **My Recipes** and **Discover** sections with shared search/filter infrastructure.
- The **Kitchen** workspace is a segmented container over pantry items, prepared dishes, and shopping items.
- An active-cook mini player appears above the tab bar when a cooking session or queued stage is active, and tapping it opens cook-queue management.
- Notification taps can deep-link directly back into cook mode for the relevant recipe and step.

### Explicitly Not Shipped in the Current Build
- **Receipt OCR and barcode pantry intake** are still research-only. The product ships with manual pantry entry and structured bulk-add flows, not camera-based intake.
- **Supabase-backed sync or cloud persistence** is not active. The shipping app is local-first and runs entirely on SwiftData plus lightweight local caches/preferences.
- **Realtime voice cook mode** is the primary shipped voice experience. The AVSpeechSynthesizer/SFSpeechRecognizer stack exists as fallback infrastructure, but it is not the main cook-mode path.

---

## Table of Contents

1. [Pantry Inventory Management](#1-pantry-inventory-management)
2. [Pantry Catalog & Canonical Food Identity](#2-pantry-catalog--canonical-food-identity)
3. [Ingredient Lexicon & Text Normalization](#3-ingredient-lexicon--text-normalization)
4. [Ingredient Matching & Pantry Resolution](#4-ingredient-matching--pantry-resolution)
5. [Recipe Management](#5-recipe-management)
6. [Recipe Ingredient Resolution](#6-recipe-ingredient-resolution)
7. [Recipe Completeness Inference](#7-recipe-completeness-inference)
8. [Substitution System](#8-substitution-system)
9. [AI-Powered Features](#9-ai-powered-features)
10. [Conversational Voice Cooking (Realtime API)](#10-conversational-voice-cooking-realtime-api)
11. [Text-to-Speech & Speech Recognition](#11-text-to-speech--speech-recognition)
12. [Multi-Recipe Scheduling & Task Graphs](#12-multi-recipe-scheduling--task-graphs)
13. [Interactive Cook Mode](#13-interactive-cook-mode)
14. [Cook Queue & Session Management](#14-cook-queue--session-management)
15. [Meal Planning](#15-meal-planning)
16. [Prepared Dishes (Meal Prep Tracking)](#16-prepared-dishes-meal-prep-tracking)
17. [Shopping List Intelligence](#17-shopping-list-intelligence)
18. [Notification System](#18-notification-system)
19. [Persistence & Storage Architecture](#19-persistence--storage-architecture)
20. [Performance & Caching Infrastructure](#20-performance--caching-infrastructure)
21. [Configuration & Launch Options](#21-configuration--launch-options)

---

## 1. Pantry Inventory Management

### Purpose
Track the user's real-world food inventory with quantities, storage locations, expiry tracking, and structured qualifiers (facets).

### Data Model: `PantryItem`
| Field | Type | Description |
|---|---|---|
| `id` | UUID | Stable identifier |
| `name` | String | Display name incorporating facets (e.g., "Whole Wheat Flour") |
| `category` | FoodCategory | One of 15 categories (dairy, produce, protein, grains, spices, condiments, bakingSupplies, frozenFoods, canned, beverages, snacks, oils, pasta, nuts, other) |
| `quantity` | Double? | Numeric amount (nil when presence-only) |
| `unit` | MeasurementUnit? | Volume (tsp, tbsp, cup, fl oz, ml, L), weight (g, kg, oz, lb), or count (piece, whole, loaf, slice, clove, bunch, can, package, pinch, splash, toTaste) |
| `expiryDate` | Date? | Manual or estimated expiry |
| `dateAdded` | Date | Timestamp of intake |
| `notes` | String? | Freeform user notes |
| `catalogItemID` | String? | Link to canonical `PantryCatalogItemDefinition` |
| `facets` | [PantryFacetSelection] | Structured qualifiers (variant, form, preservation, processing, preparation, texture, concentration, base) |
| `storage` | PantryStorage | pantry, refrigerated, or frozen |
| `freshnessSource` | PantryFreshnessSource | none, estimated, or userProvided |
| `quantityMode` | PantryQuantityMode | exact (has numeric quantity) or presenceOnly |

### Quantity Tracking Modes
- **Exact**: User specifies a precise quantity (e.g., "500g chicken breast"). Matching compares numeric values with unit conversion.
- **Presence-only**: Item is simply marked as "in stock" without a numeric quantity. Matching returns optimistic results.
- Mode merging rule: if either side of a merge is `presenceOnly`, the result is `presenceOnly`.

### Expiry & Freshness
- **ExpiryStatus** enum: `fresh`, `expiringSoon` (within 3 days), `expired`.
- **Freshness estimation**: If no manual date is provided, the system estimates based on the catalog item's `freshnessByStorage` ranges (e.g., milk: refrigerated = 5–10 days, frozen = 30–90 days).
- **FreshnessSource tracking**: Distinguishes between user-provided dates (high confidence) and system-estimated dates (displayed as estimates, not facts).
- Storage changes trigger immediate freshness recalculation.

### Pantry Intake Workflow
Items enter the pantry through a structured drafting process (`PantryIntakeRowDraft`):

1. **Search or browse** the catalog of 100+ canonical food items.
2. **Select facets** — variant (e.g., "whole wheat"), form (e.g., "ground"), preservation (e.g., "frozen"), etc.
3. **Specify quantity/unit** — auto-suggested from catalog defaults, overridable by user.
4. **Set storage location** — pantry, refrigerated, frozen (defaulted from catalog).
5. **Set expiry** — manual date or auto-estimated from catalog freshness ranges.
6. **Validation** produces blocking/warning/informational diagnostics (missing item, unsupported input, invalid facet combination, missing required state, missing quantity).

### Bulk Add
- Users can type comma-separated or newline-separated ingredient names.
- Each token is resolved against the catalog via `PantryCatalog.resolveExact()`.
- Resolved items get staged with catalog defaults pre-applied.
- Unresolved tokens become custom items.
- All staged items go through the validation pipeline before commit.

### Pantry Workspace Flow
- Pantry is managed through a search-and-filter list grouped by category.
- Empty state drives users into the structured bulk-add flow instead of a plain freeform item form.
- Bulk add has two phases:
   - **Selection**: browse categories, search the catalog, pick common staples, or fall back to a custom item.
   - **Review**: edit each staged draft, inspect warnings, save catalog defaults, and then commit only valid rows.
- Existing pantry items are edited through the same draft-backed form used for intake, with swipe-to-delete from the pantry list.

### Preference Store
- Per-catalog-item, the system remembers the user's last-used facets, storage, quantity, unit, and expiry offset.
- Stored in `PantryItemDefaultPreference` via UserDefaults.
- On future intake of the same catalog item, saved preferences are auto-applied as defaults.

### Pantry Merging (Duplicate Detection)
When adding a new item, the system checks for identity matches:
- **Catalog-backed items**: Match on `catalogItemID` + identical facet set.
- **Custom items**: Match on normalized name + category + storage.
- If a match is found, quantities are merged (summed) rather than creating a duplicate entry.

### Post-Cook Pantry Review
After completing a cooking session, the system generates `PantryCookReviewItem` objects showing each ingredient used and the quantity consumed. The user can then:
- **Keep**: Leave the pantry item unchanged.
- **Remove**: Completely remove the item from the pantry.
- **Subtract**: Reduce by the recipe-specified quantity (with unit conversion).
- If no current pantry items are matched for the cooked recipe, the review flow is blocked with a user-facing error rather than showing an empty review surface.

---

## 2. Pantry Catalog & Canonical Food Identity

### Purpose
Provide a curated, structured database of 100+ common food items with their properties, aliases, facets, storage defaults, freshness ranges, and substitution rules.

### Data Model: `PantryCatalogItemDefinition`
| Field | Type | Description |
|---|---|---|
| `id` | String | Item identifier (e.g., "flour", "chicken", "tomato") |
| `name` | String | Base display name |
| `category` | FoodCategory | Classification |
| `defaultUnit` | MeasurementUnit? | Suggested unit for this item |
| `defaultQuantity` | Double? | Suggested typical quantity |
| `defaultStorage` | PantryStorage | Default storage location |
| `aliases` | [String] | All names that resolve to this item (e.g., "all-purpose flour", "AP flour", "plain flour" all → "flour") |
| `facets` | [PantryFacetDefinition] | Available qualifier types with their option lists |
| `defaultSelections` | [PantryFacetSelection] | Pre-set facet combinations for default display |
| `substitutions` | [PantrySubstitutionDefinition] | Defined ingredient substitutes with ratios and impact assessments |
| `unitOverrides` | [PantryFacetKey: [String: MeasurementUnit]] | Facet-specific unit overrides (e.g., "ground" beef uses "lb" instead of "piece") |
| `freshnessByStorage` | [PantryStorage: ClosedRange<Int>] | Days-until-expiry ranges by storage location |

### Facet System
Eight facet keys define structured qualifiers for food items:

| Facet Key | Example Values |
|---|---|
| `variant` | whole wheat, all-purpose, whole grain, basmati, jasmine |
| `form` | ground, diced, sliced, whole, minced, shredded |
| `preservation` | canned, frozen, dried, fresh |
| `processing` | bleached, unbleached, refined, unrefined |
| `preparation` | cooked, raw, roasted, smoked |
| `texture` | smooth, chunky, creamy |
| `concentration` | concentrated, diluted, full-strength |
| `base` | vegetable, chicken, beef (for stocks/broths) |

### Display Name Construction
The catalog generates display names from facets using prefix + name + suffix logic:
- Certain facet values (variant, preservation, processing) appear as prefixes: "Whole Wheat Flour"
- Others (form, preparation, texture) appear as suffixes or context-dependent

### Catalog Index
- `allItems`: Full array of ~100+ item definitions.
- `itemsByID`: Dictionary index by item ID for O(1) lookup.
- `aliasIndex`: Maps every normalized alias (lookup key) to its parent item ID. Built from both item names and explicit aliases.

### Coverage
Catalog includes: flour, rice, pasta, oats, milk (variants), yogurt, cheese, cream, cream cheese, butter, eggs, chicken, beef, pork, turkey, lamb, fish, shrimp, tofu, tomato, avocado, banana, peppers, broccoli, carrot, garlic, onion, potato, spinach, lettuce, cucumber, mushroom, corn, green beans, lemon, lime, apple, orange, berries, mango, canned tomatoes, canned beans, coconut milk, canned tuna, broth, soy sauce, vinegar, honey, mustard, ketchup, mayonnaise, hot sauce, olive oil, vegetable oil, sesame oil, coconut oil, salt, pepper, cumin, paprika, cinnamon, oregano, chili powder, turmeric, ginger, sugar, baking powder, baking soda, vanilla extract, chocolate, bread, tortillas, peanut butter, nuts (mixed), and more — each with appropriate aliases, facets, storage defaults, substitution rules, and freshness windows.

---

## 3. Ingredient Lexicon & Text Normalization

### Purpose
A static, high-performance text processing engine for normalizing, tokenizing, and comparing ingredient names. Used across resolution, matching, and search.

### Core Algorithms

#### Normalization Pipeline: `IngredientLexicon.parse()`
1. **Lookup key generation**: Lowercase → split on non-alphanumeric → rejoin with spaces.
2. **Ingredient normalization**: Strip qualifier words (fresh, dried, frozen, organic, chopped, minced, diced, sliced, crushed, ground, whole, raw, cooked, boneless, skinless, etc.) via compiled regex patterns.
3. **Pluralization handling**: Strips plurals with rules for -ies→-y, -oes→drop, -es→drop (unless -ses), -s→drop (unless -ss).
4. **Tokenization**: Split on spaces after normalization.

#### Token-Weighted Scoring
`weightedTokenScore(queryTokens:, candidateTokens:)` → 0.0–1.0
- Computes set overlap between query and candidate tokens.
- **Head token gets a 1.35× weight boost** — the first word of an ingredient name is typically the most semantically important (e.g., "chicken" in "chicken breast").
- Score = weighted matches / total weighted tokens.

#### Fuzzy Similarity
`fuzzySimilarity(_:, _:)` → 0.0–1.0
- Computes Levenshtein edit distance between two strings.
- Score = 1 - (distance / max(length1, length2)).
- Used as a fallback when token-based matching fails.

#### Synonym Groups
Hard-coded synonym sets for common ingredient name equivalences:
- ["shallot", "french shallot"]
- ["scallion", "green onion", "spring onion"]
- ["bell pepper", "capsicum"]
- ["cilantro", "coriander leaves"]
- etc.

Bidirectional indexes (`lookupSynonymIndex`, `normalizedSynonymIndex`) enable fast group retrieval.

#### Catalog Phrase Generation
`generatedCatalogPhrases(for:)` generates all searchable phrases for a catalog item:
- Base item name (source: `name`)
- All aliases (source: `alias`)
- All faceted combinations: prefix facet values × item name (source: `template`)
- Each phrase stores its lookup key, tokens, and source item ID.

---

## 4. Ingredient Matching & Pantry Resolution

### Purpose
Determine which pantry items satisfy recipe ingredient requirements, compute match percentages, and identify substitution opportunities.

### Core Algorithm: `IngredientMatcher.match()`

#### Input
- A `Recipe` (with ingredients list)
- A `[PantryItem]` (current inventory)

#### Output: `PantryMatchResult`
- `matchedIngredients`: Ingredients fully satisfied by pantry.
- `missingIngredients`: Ingredients not in pantry.
- `matchPercentage`: 0–100 (matched / total × 100).
- `substitutableIngredients`: Missing ingredients that have available substitutions.
- `canMakeWithSubstitutions`: True if all missing ingredients are substitutable.
- `effectiveMatchPercentage`: Match percentage counting substitutable ingredients as available.

#### Matching Algorithm (per ingredient)
1. **Direct catalog ID match**: If both the ingredient and a pantry item reference the same `catalogItemID`, check facet compatibility.
2. **Unresolved name match**: If no catalog ID, normalize both names and compare:
   - Exact normalized key match.
   - Substring containment match (for compound names).
   - Synonym group match via IngredientLexicon.
   - Token overlap match (for multi-word ingredients).
3. **Quantity validation**: If both sides have exact quantities, convert units and compare. Supports conversions across:
   - Volume: tsp ↔ tbsp ↔ cup ↔ fl oz ↔ ml ↔ L
   - Weight: g ↔ kg ↔ oz ↔ lb
   - Returns "enough" only if pantry quantity ≥ ingredient quantity.
   - If either side is `presenceOnly`, quantity check returns optimistic positive.

#### Facet Satisfaction
When matching catalog-backed items, all required facets must be satisfied. The value `"generic"` acts as a wildcard — a pantry item with `form: "generic"` satisfies any required form value.

#### Pantry Indexing
The matcher maintains a cached `PantryIndex` with signature-based invalidation:
- **Resolved index**: Dictionary of `catalogItemID → [PantryCandidate]` for catalog-backed items.
- **Unresolved index**: Dictionary of normalized name → `[PantryCandidate]` for custom items.
- Signature = hash of all pantry item IDs, names, quantities, units, catalog IDs, facets, storage locations.
- Index is rebuilt only when the signature changes.

---

## 5. Recipe Management

### Data Model: `Recipe`
| Field | Type | Description |
|---|---|---|
| `id` | UUID | Stable identifier (deterministic for bundled recipes) |
| `title` | String | Recipe name |
| `description` | String? | Brief description |
| `ingredients` | [Ingredient] | Structured ingredient list |
| `steps` | [RecipeStep] | Ordered cooking instructions |
| `servings` | Int | Default serving count |
| `prepTimeMinutes` | Int? | Preparation time |
| `cookTimeMinutes` | Int? | Cooking time |
| `difficulty` | DifficultyLevel | beginner (1) through expert (5) |
| `dietaryTags` | [DietaryTag] | vegetarian, vegan, glutenFree, dairyFree, nutFree, lowCarb, highProtein, keto, paleo, halal, kosher |
| `mealType` | MealType? | breakfast, lunch, dinner, snack, dessert |
| `cuisine` | CuisineType? | 16 cuisine types (Italian, Mexican, Chinese, Japanese, Indian, Thai, French, Mediterranean, American, Korean, Vietnamese, Greek, Middle Eastern, Ethiopian, Caribbean, Other) |
| `source` | RecipeSource | user, bundled, imported, aiGenerated |
| `nutrition` | NutritionInfo? | Per-serving macros (calories, protein, carbs, fat, fiber, sugar, sodium) |
| `sourceURL` | String? | Origin URL (for imported recipes) |
| `isFavorite` | Bool | User bookmark |
| `dateAdded` | Date | Creation timestamp |
| `timesCooked` | Int | Usage counter |
| `rating` | Int? | 1–5 stars |

### Sub-Model: `Ingredient`
| Field | Type | Description |
|---|---|---|
| `id` | UUID | Identifier |
| `rawName` | String | Original ingredient text (as authored or parsed) |
| `quantity` | Double | Amount needed |
| `unit` | MeasurementUnit? | Unit of measurement |
| `category` | FoodCategory | Food classification |
| `isOptional` | Bool | Whether the ingredient is optional |
| `notes` | String? | Preparation notes |
| `catalogItemID` | String? | Resolved catalog link |
| `facets` | [PantryFacetSelection] | Resolved qualifier facets |

An ingredient can be in one of two states:
- **Resolved**: Has a `catalogItemID` and validated facets, enabling precise pantry matching.
- **Unresolved**: Only has `rawName`, relies on fuzzy text matching.

### Sub-Model: `RecipeStep`
| Field | Type | Description |
|---|---|---|
| `stepNumber` | Int | 1-indexed ordinal |
| `instruction` | String | Human-readable cooking instruction |
| `timerMinutes` | Int? | User-visible countdown timer for this step |
| `tip` | String? | Optional cooking advice |
| `estimatedDurationSeconds` | Int? | Wall-clock duration for scheduling |
| `tasks` | [StepTask] | Atomic sub-tasks for parallel scheduling |

The `effectiveDurationSeconds` is computed as: `estimatedDurationSeconds` (if set) > `timerMinutes × 60` (if set) > 90 seconds (default).

### Recipe Sources
| Source | Description | Auto-resolves ingredients? | Appears in "My Recipes"? |
|---|---|---|---|
| `user` | Created manually in the app | No (user controls) | Yes |
| `bundled` | Shipped with the app (seed recipes) | Yes (via TrustedRecipeCanonicalizer) | No (Discover only) |
| `imported` | Parsed from URL or text | Via user review | After user saves |
| `aiGenerated` | Generated by AI from prompts | Via user review | After user saves |

### Recipe Library Surface
- The Recipes tab is divided into two user-facing collections:
   - **My Recipes** for user-owned and favorited recipes.
   - **Discover** for bundled and cached non-user recipes.
- Shared library controls include search with debounce, filters for can-make status, substitution allowance, cuisine, meal type, favorites, and dietary tags, and sort orders for recent, name, difficulty, total time, most cooked, and pantry match percentage.
- Discover supports progressive loading and background prewarming of pantry-match metrics so large catalogs remain responsive.
- When the user types a query of at least 3 characters in Discover, the grid can prepend an AI-generate tile that opens the recipe builder for that query.

### Recipe Intake Surfaces
- Manual add flow supports free-form recipe pasting through `AddRecipeView`.
   - URLs are detected and routed through URL import.
   - Non-URL text is routed through text import.
   - Successful imports open a structured review/editor before save.
- URL-only import is also exposed through a focused import sheet.
- AI generation is exposed through `RecipeBuilderView`, which lets the user configure servings, spice level, max time bucket, dietary tags, and whether pantry ingredients should be considered.
- During AI generation, short status messages are shown while the recipe request is in flight.

### Recipe Detail Workflow
- Recipe detail is a working surface, not just a read-only page.
- It supports favorite toggling, in-place editing, saving an edited recipe as a new recipe, serving scaling up to 100 servings, pantry-match visualization, ingredient gathering before a new cook session, resuming an existing session, adding the recipe to the cook queue, shopping preview, substitutions, healthier suggestions, AI recipe modification, and pantry review initiation.
- Ingredient rows are rendered with availability status against the current pantry.
- Step rows render timers and tips inline.

### Serving Scaling
`recipe.scaled(to: newServings)` returns a copy where:
- All ingredient quantities are multiplied by `newServings / originalServings`.
- Nutrition values are scaled proportionally.
- Steps and metadata remain unchanged.

### Recipe Repository
A caching layer manages recipe discovery:
- **Seed recipes**: Loaded from a bundled `seed_recipes.json` file (currently 10+ recipes across multiple cuisines). Cached to disk with resource fingerprint validation — if the bundle file changes, the cache is rebuilt.
- **Cached API recipes**: AI-generated or imported recipes are cached to `~/.caches/cached_recipes.json` with a 7-day TTL. Pruned automatically.
- **Merged discover store**: Combines seed + cached recipes, deduplicated by title (case-insensitive).
- **Filtering**: Supports multi-dimension filtering by cuisine, meal type, difficulty, dietary tags, search query, pantry makeability, and "can make with substitutions."

### Favorite Toggle Behavior
- Favoriting a discover recipe copies it into the user's "My Recipes" collection.
- Unfavoriting removes it from "My Recipes."
- Favorite state persists across both discover and user recipe collections via stable UUIDs.

---

## 6. Recipe Ingredient Resolution

### Purpose
Map free-text ingredient names to canonical catalog items with structured facets, enabling precise pantry matching and shopping list generation.

### Resolution Architecture (Hybrid Local + AI)

#### Stage 1: Local Candidate Retrieval (`IngredientCandidateParser`)
For each unresolved ingredient, the parser retrieves candidates in this order:

| Stage | Source | Score Range | Description |
|-------|--------|-------------|-------------|
| 0 | Exact name | 1.0 | Direct match on catalog item name |
| 1 | Exact alias | 0.995 | Match against registered aliases |
| 2 | Exact template | 0.99 | Faceted combination match (e.g., "whole wheat flour") |
| 3 | Template tokens | 0.985 | Token set intersection on faceted templates |
| 4 | Synonym lookup | 0.96 | Semantic synonym groups |
| 5 | Lexical candidates | up to 0.94 | Token overlap with weighted scoring |
| 6 | Generic fallbacks | varies | Base ingredient with generic facets |
| 7 | Fuzzy retrieval | up to 0.82 | Levenshtein similarity-based |

Candidates are scored, filtered, and capped at 4 per ingredient.

#### Stage 2: Local Fallback Resolution
Before invoking AI, the system attempts deterministic resolution:
- **Resolved** if: exact template with matching facets (score ≥ 0.985), OR single high-confidence candidate (score ≥ 0.9), OR top candidate has 4%+ lead over runner-up (both ≥ 0.98).
- **Ambiguous** if: multiple plausible candidates without clear winner.
- **Unknown** if: no credible candidates found.

#### Stage 3: AI Disambiguation
For remaining ambiguous/unknown ingredients, the system calls the AI service with:
- The ingredient's raw name, quantity, unit, category, notes.
- Up to 4 candidate catalog items with their IDs, facets, scores, and rationales.
- AI returns a decision per ingredient: status (resolved/ambiguous/unknown), selected candidate ID, confidence (0–1), and rationale.

#### Trusted Recipe Canonicalization
Bundled seed recipes bypass the AI path entirely. `TrustedRecipeCanonicalizer` resolves ingredients using only high-confidence local matches or direct catalog lookups. This ensures bundled recipes always have resolved ingredients without network calls.

### Indexing Infrastructure (`CatalogPhraseIndex`)
A pre-built multi-index enables fast retrieval:
- **Exact phrase indices**: By source type (name/alias/template) + lookup key.
- **Lookup key indices**: Normalized key → phrase array positions.
- **Template token set indices**: Token set string → phrase positions (for token-set matching).
- **Token-to-phrase indices**: Individual tokens → phrase positions sets (for flexible intersection).
- **Leading character indices**: First character → phrase positions (for fuzzy candidate pruning).
- **Normalized length indices**: String length → phrase positions (for fuzzy edit-distance pruning).

Thread-safe caching with NSLock prevents redundant computation across ingredients.

---

## 7. Recipe Completeness Inference

### Purpose
Automatically fill in missing metadata for recipes that arrive incomplete (from AI generation, URL import, or user creation).

### Algorithm: `RecipeCompletenessInferer.complete()`

#### Meal Type Inference
Scans a concatenated corpus of the recipe's title, description, ingredients, and steps for keyword presence:
- **Dessert**: cake, cookie, brownie, chocolate, frosting, ice cream, custard, pie (sweet), tart, mousse, etc.
- **Breakfast**: egg, bacon, pancake, waffle, oatmeal, cereal, toast, breakfast, brunch, etc.
- **Snack**: chip, dip, trail mix, popcorn, granola bar, snack, appetizer, etc.
- **Lunch**: sandwich, wrap, salad (as main), soup (light), burger, etc.
- **Dinner**: default fallback if no other keywords match.

#### Cuisine Inference
Keyword matching against cuisine-specific ingredient and technique vocabulary:
- Italian: pasta, parmesan, marinara, risotto, prosciutto, etc.
- Mexican: tortilla, taco, burrito, salsa, jalapeño, etc.
- Chinese: wok, soy sauce, ginger, sesame, stir-fry, etc.
- (Covers all 16 CuisineType values)

#### Time Estimation
1. If steps have `estimatedDurationSeconds`, sum them and split 40/60 between prep and cook time.
2. If no step durations, use meal type defaults:
   - Breakfast: 10 prep / 15 cook
   - Lunch: 15 prep / 20 cook
   - Dinner: 20 prep / 30 cook
   - Snack: 10 prep / 10 cook
   - Dessert: 20 prep / 35 cook

#### Nutrition Estimation
If no nutrition data is provided, estimates per-serving values from ingredient categories:
- Per-category base profiles (e.g., protein items: ~25g protein, ~180 kcal; dairy: ~8g protein, ~120 kcal; etc.).
- Unit-specific portion normalization (e.g., 1 cup ≈ 1.0 "abstract serving", 1 tbsp ≈ 0.15, 1 piece ≈ 0.5).
- Per-meal-type baselines provide fallback ranges: dinner baseline ~500 kcal, breakfast ~350 kcal, etc.
- Results are clamped to reasonable meal-type-specific min/max ranges.

---

## 8. Substitution System

### Purpose
Enable cooking with available ingredients by suggesting viable alternatives — with impact assessments and pantry awareness.

### Substitution Data Model
Each catalog item can define an array of `PantrySubstitutionDefinition`:

| Field | Type | Description |
|---|---|---|
| `substituteItemID` | String | Catalog item ID of the replacement |
| `substituteFacets` | [PantryFacetSelection] | Required facets for the substitute |
| `ratio` | String | Conversion ratio (e.g., "1:1", "3/4:1", "1 can for 3-4 tomatoes") |
| `tasteImpact` | SubstitutionImpact | none, slight, moderate, significant |
| `textureImpact` | SubstitutionImpact | Same scale |
| `cookingImpact` | CookingImpact | none, slightAdjustment, moderateAdjustment, majorAdjustment |
| `nutritionImpact` | String? | Human-readable description (e.g., "Higher in sodium") |
| `notes` | String? | Usage notes (e.g., "Adjust bake time +5 min") |
| `dietary` | [DietaryTag]? | Dietary relevance of the substitution |

### Repository Logic (`SubstitutionRepository`)
- Looks up substitutions by resolving ingredient name → catalog item → item.substitutions.
- Filters out substitutions involving "generic" facets (generic items are fallbacks, not recommended substitutes).
- **Pantry enrichment**: Checks whether each substitute exists in the user's current pantry (matching catalog ID + facets). Marks `inPantry = true` and sorts in-pantry substitutions first.
- Substitution suggestions in the current implementation come from the static catalog definitions. The repository does not currently augment them with AI-generated alternatives.

### Integration with Recipe Matching
When computing `PantryMatchResult`, the matcher:
1. Identifies missing ingredients.
2. For each missing ingredient, queries `SubstitutionRepository.substitutions(for:pantry:)`.
3. If substitutions exist for all missing ingredients, sets `canMakeWithSubstitutions = true`.
4. Computes `effectiveMatchPercentage` counting substitutable ingredients as available.

---

## 9. AI-Powered Features

### Infrastructure
- **Model**: GPT-4o via OpenAI Chat Completions API.
- **Structured output**: All AI calls use `json_schema` response format with strict validation.
- **Retry logic**: Up to 3 retries with exponential backoff (1.5s, 3s). Retries on 429 (rate limit) and 5xx errors. Gives up on 4xx errors.
- **Temperature**: 0.7 (balanced creativity/consistency).
- **Validation**: All AI-generated recipes pass through `AIOutputValidator` before acceptance — checking for: empty titles, missing ingredients/steps, non-sequential step numbers, invalid quantities/timers/durations, and wrong-language detection (using NLLanguageRecognizer with confidence threshold ≥ 0.5).

### Feature: Recipe Generation
- **Input**: Free-text query (e.g., "quick Italian dinner for 2") plus `RecipeGenerationPreferences`:
  - Servings (default 4)
  - Max time in minutes (optional)
  - Spice level (none / mild / medium / spicy / extraSpicy)
  - Dietary tags (any combination of 11 tags)
  - Use pantry ingredients (flag + ingredient list)
- **Output**: Complete `Recipe` with full nutrition, tasks with dependency chains, effort levels, and equipment requirements.
- **Status messages**: Parallel call generates 8 short progress messages (≤8 words each) for streaming feedback during generation.

### Feature: Recipe Modification
- **Input**: Existing recipe + free-text feedback (e.g., "make it spicier and add more protein") + pantry ingredient list.
- **Output**: Modified recipe preserving the original recipe's ID and metadata.

### Feature: Recipe Import from URL
1. Fetches page HTML with desktop Chrome User-Agent headers.
2. **JSON-LD extraction** (preferred): Regex extracts `<script type="application/ld+json">` blocks, recursively searches for `@type: "Recipe"` objects (handles `@graph` nesting), and formats the structured recipe data.
3. **Fallback text extraction**: Strips HTML (removes script/style tags, decodes 20+ HTML entities, collapses whitespace), truncates to 12,000 chars, and sends to AI for parsing.
4. AI parses the text into a structured `RecipeImportResult` via the recipe import JSON schema.

### Feature: Recipe Import from Text
- Accepts pasted text (from cookbooks, screenshots, etc.) and sends directly to AI for structured parsing using the same schema as URL import.

### Feature: AI Recipe Suggestions
- **Input**: Current pantry items (names only).
- **Output**: 5 complete recipes that can be made with available ingredients.
- Prioritizes ingredients that are expiring soon.
- Returns complete recipes with tasks, dependencies, and nutrition.

### Feature: Healthier Version
- **Input**: A recipe.
- **Output**: `HealthierSuggestion` containing an array of `HealthTweak` objects (each with a change and benefit), estimated calorie reduction, and overall impact assessment.

### Feature: Leftover Transformer
- **Input**: Array of leftover ingredient names.
- **Output**: 3 creative recipes using those ingredients.
- Prioritizes quick, beginner-friendly recipes.

### Feature: AI Shopping List
- **Input**: Recipe + current pantry.
- **Output**: Array of `ShoppingItem` objects listing only genuinely needed items (not already in pantry in sufficient quantity).

### Feature: AI Ingredient Resolution
- **Input**: Array of `IngredientResolutionRequest` (raw name, quantity, unit, category, notes, candidate list).
- **Output**: Array of `IngredientResolutionDecision` (status, selected candidate, confidence, rationale).
- Separate `disambiguateIngredients` endpoint forces a single best choice (no ambiguous returns).

### Feature: Step Duration Estimation
- For recipes with missing `estimatedDurationSeconds`, a single AI call estimates durations for all steps, including active work + waiting + cooking time.

---

## 10. Conversational Voice Cooking (Realtime API)

### Purpose
Enable hands-free, real-time voice interaction while cooking. The AI reads steps aloud, answers cooking questions, and executes navigation/timer commands via function calls.

### Architecture
- **Protocol**: WebRTC via OpenAI Realtime API SDK.
- **Voice**: "Sage" (configurable).
- **Speech recognition model**: gpt-4o-mini (for transcription).
- **Turn detection**: Server-side Voice Activity Detection (VAD) with:
  - Silence duration: 1000ms (1 second of silence ends a turn).
  - Threshold: 0.88 (sensitivity to speech vs. noise).
  - Prefix padding: 500ms (catches speech start buffering).

### Connection Lifecycle
1. **Ephemeral key fetch**: POST to `https://api.openai.com/v1/realtime/client_secrets` → short-lived WebRTC auth token.
2. **Audio session configuration**: AVAudioSession set to `.playAndRecord` with `.voiceChat` mode and `.defaultToSpeaker`.
3. **Realtime session connection**: The SDK's `Conversation` object manages the WebRTC-backed session and signaling lifecycle.
4. **Session configuration wait**: Polls until `conv.session.audio.output.voice == .sage` (up to 5 seconds) to ensure round-trip session update is confirmed.
5. **State sync loop**: Background task polls SDK state every 50ms and copies to observable properties.

### Function Calling
The AI model can invoke these tool functions during conversation:

| Function | Parameters | Action |
|----------|-----------|--------|
| `next_step` | none | Advance to next cooking step |
| `previous_step` | none | Go back one step |
| `go_to_step` | `step_number: Int` | Jump to specific step |
| `repeat_step` | none | Re-read current step instructions |
| `start_timer` | `minutes: Int` | Start a countdown timer |
| `pause_timer` | none | Pause/resume timer |
| `stop_timer` | none | Cancel active timer |
| `finish_cooking` | none | Complete the cooking session |

Function call dispatch flow:
1. AI model generates a function call with arguments.
2. Service sends acknowledgment (`{ "status": "done" }`) back to model.
3. Callback fires to ViewModel, which executes the action.
4. Follow-up response is triggered so the model can narrate the new state.

### Garbage Transcription Filtering
Kitchen environments produce noise (sizzling, clanking, timers) that speech recognition can misinterpret. The system filters these:
- Empty or whitespace-only transcriptions → rejected.
- Punctuation/symbol-only transcriptions → rejected.
- Single non-Latin character → rejected.
- When garbage is detected: the response is cancelled, audio is cleared, and the noise message is deleted from the conversation history.

### System Prompt Construction
The AI receives a detailed system prompt including:
- All recipe steps with timers and tips.
- Full ingredients list.
- Behavioral rules:
  - Natural, conversational speech (no mechanical reading).
  - Answer any cooking-related questions.
  - Use function calls for navigation (never just say "next step" — actually call the function).
  - **Absolute stop rule**: If the user says "stop", "pause", "quiet", or similar — stop speaking immediately. Do not continue, do not advance.
  - Reject kitchen noise — don't respond to sizzling, clanking, or similar sounds.

### Audio Pipeline
- `AudioPipelineHelper` converts between PCM16 (OpenAI Realtime API format) and Float32 (AVAudioEngine format).
- Chunk threshold calculation ensures minimum ~100ms audio buffers for smooth streaming.
- Direct memory writes via unsafe pointers for zero-copy conversion in the real-time path.

---

## 11. Text-to-Speech & Speech Recognition

### Purpose
Provide fallback voice capabilities independent of the Realtime API. This infrastructure supports spoken step playback and on-device command recognition, but the primary shipped cook-mode experience uses the Realtime API described in section 10.

### Text-to-Speech (AVSpeechSynthesizer)
- Rate: 0.48 (configurable per call).
- Pitch: 1.0.
- Voice: en-US.
- Pre/post utterance delays: 0.2s / 0.3s.
- **TTS/Recognition coordination**: Recognition is paused during TTS to prevent feedback loops. Automatically restarts after TTS completes.

### Speech Recognition (SFSpeechRecognizer)
- Uses Apple's on-device recognition when available.
- Audio tap: 1024-sample buffers from AVAudioEngine input node.
- **Command debouncing**: 600ms delay after speech settles before dispatching a command. Prevents multiple dispatches of partial results.
- **Duplicate rejection**: Compares against `lastDispatchedCommand` to avoid firing the same command twice.
- **Auto-restart**: After recognition completes (error or final result), automatically restarts after 500ms if the user wants to keep listening.

### Voice Command Parser
Parses recognized text into structured commands:

| Command | Trigger Words |
|---------|--------------|
| `next` | "next", "forward", "continue", "done" |
| `previous` | "back", "previous", "before" |
| `repeatStep` | "repeat", "again", "what" |
| `startTimer` | "timer", "start", "go" |
| `pauseTimer` | "pause" |
| `stopTimer` | "stop", "cancel" |

Matching strategy: First checks last word of transcription, then falls back to substring containment in full text.

### Audio Session Management
- Recording mode: `.playAndRecord` with `.defaultToSpeaker` and `.allowBluetoothHFP`.
- Playback mode: `.playback` only.
- Configures appropriate mode based on current capability needs.

---

## 12. Multi-Recipe Scheduling & Task Graphs

### Purpose
Intelligently interleave tasks from multiple recipes to minimize total cooking time while respecting dependency constraints and human effort capacity.

### Task Model: `StepTask`
| Field | Type | Description |
|---|---|---|
| `id` | UUID | Unique task identifier |
| `action` | CookingAction | Typed action (cut/sauté/bake/etc.) with sub-types (CutStyle, FryStyle) |
| `ingredient` | String? | What ingredient this task operates on |
| `quantity` | Double? | Amount processed |
| `unit` | String? | Unit of the amount |
| `durationSeconds` | Int | Expected wall-clock time |
| `type` | TaskType | `active` (requires attention) or `passive` (timer-based wait) |
| `requiresEquipment` | String? | Equipment needed (stovetop, cutting board, oven, etc.) |
| `temperature` | Int? | Degrees Fahrenheit (for merging preheat steps) |
| `effort` | EffortLevel | easy (1 point), medium (2 points), hard (3 points) |
| `dependsOn` | [UUID] | Task IDs that must complete before this task can start |
| `recipeId` | UUID? | Which recipe this task belongs to |
| `recipeName` | String? | Display name of source recipe |
| `sourceStepNumber` | Int? | Which step this task originated from |

### Cooking Action Taxonomy
- **Prep phase**: cut(dice/mince/julienne/slice/chop/rough/halve), peel, measure, mix, marinate, season
- **Cook phase**: heat, sauté, boil, simmer, fry(pan/deep/stir), bake, roast, grill, steam, scramble
- **Finish phase**: plate, garnish, rest, serve, toss
- **Generic**: other(String)

Each action maps to an `ActionClass` with a phase priority (0–4): prepCut → prepOther → heatSetup → activeCook → passiveCook → finish.

### Scheduling Algorithm: `MultiRecipeScheduler`

#### Single-Recipe Mode
Steps are converted linearly to `ScheduledBlock` objects. Each block wraps one step's tasks, marked active or passive based on task types.

#### Multi-Recipe Mode (DAG-Based Effort-Budget Packing)

**Constants**:
- `effortBudget = 3` — Maximum effort points a cook can handle simultaneously.

**Algorithm**:
1. **Extract all tasks** from all recipes into a flat list, enriching each with `recipeId` and `recipeName`.
2. **Build dependency graph**: `[taskID → Set<prerequisiteTaskIDs>]`.
3. **Build reverse graph** (dependents): `[taskID → Set<dependentTaskIDs>]`.
4. **Compute critical path lengths**: Memoized DFS from each task through its dependents, computing `own duration + max(downstream durations)`. Longer critical paths get scheduling priority.
5. **Iterative scheduling loop**:
   a. Find all **ready tasks** (all dependencies satisfied).
   b. **Separate passive tasks** (background timers, 0 effort). Emit each as its own block.
   c. **Sort active ready tasks** by:
      - Critical path length (longest first — prevents bottlenecks).
      - Phase priority (prep → cook → finish — natural cooking flow).
      - Effort level (higher effort if critical paths tied).
      - Duration (longer tasks if everything else tied).
   d. **Greedily pack** active tasks into a block up to `effortBudget` (3 points).
   e. Mark packed tasks as completed, repeat.
6. **Safety**: Loop terminates after `tasks.count × 3` iterations maximum.

#### Time Estimation
- `estimatedTotalTime`: Sum of all active block durations + longest single passive block duration.
- `sequentialTime`: Sum of all step durations across all recipes (as-if sequential).
- `timeSaved`: sequential − interleaved (minimum 0).

### Output: `ScheduledBlock`
| Field | Type | Description |
|---|---|---|
| `id` | UUID | Block identifier |
| `tasks` | [StepTask] | Tasks running simultaneously in this block |
| `type` | TaskType | active or passive |
| `totalDurationSeconds` | Int | Max task duration in the block |

Computed properties: `totalEffort`, `actionClass`, `displayInstruction` (combined human-readable text), `label`, `recipeNames`, `sourceInfo`.

---

## 13. Interactive Cook Mode

### Purpose
Guide users through a recipe step-by-step with voice interaction, timers, background notifications, and post-cook pantry adjustment.

### Session State
- **Step tracking**: Current step index (0-based) with forward/back/jump navigation.
- **Timer**: Date-based countdown timer that survives app backgrounding:
  - Stores `timerStartDate` and `timerDuration` rather than a decrementing counter.
  - On return to foreground, `recalculateTimerSeconds()` recomputes remaining time from the stored start date.
  - Supports pause (snaps remaining time), resume, and auto-start (if the current step has `timerMinutes`).
- **Voice conversation**: Full Realtime API connection (see section 10).
- **Rating**: Post-cook 1–5 star rating (toggleable — tap same star to deselect).

### Background Mode
When the user leaves the app during cooking:
1. **Schedule step notifications**: For each remaining step, compute cumulative delay from step durations and schedule a local notification:
   - Title: "Step X of Y — RecipeName"
   - Body: Step instruction
   - Subtitle: "Next: [preview of next step]" (if applicable)
   - Includes timer info in body if step has a timer.
2. **Schedule session expiry notification**: After the last step's delay + 2 hours.
3. **Save cooking session**: Persist current step index, recipe info, and timing to UserDefaults.
4. **Disconnect voice**: Clean up WebRTC connection.

### Resume from Background
- Cancel all pending notifications.
- Reconnect voice (with modified greeting: "user is resuming from step N").
- Recalculate timer from stored dates.
- Restore step position.

### Notification Actions
Two actions are registered:
- **"Done ✓"**: Advances the step in the persisted CookingSession without opening the app (pure background processing via notification delegate).
- **Tap / "Open Cook Mode"**: Updates session step + sets `deepLinkCookModeRecipeId` to reopen the full cook mode interface.

### Post-Cook Flow
1. **Completion screen**: Shows recipe summary and allows rating.
2. **Prepared dish creation**: Optionally create a `PreparedDish` from the completed recipe.
3. **Pantry review**: Shows all ingredients used, allows keep/remove/subtract actions on pantry items.

---

## 14. Cook Queue & Session Management

### Purpose
Organize multiple recipes into a cooking sequence with support for parallel batching, stage reordering, and session lifecycle management.

### Data Model: `CookQueue`
| Field | Type | Description |
|---|---|---|
| `id` | UUID | Queue identifier |
| `name` | String | Queue display name |
| `createdAt` | Date | Creation timestamp |
| `updatedAt` | Date | Last modification |
| `stages` | [CookQueueStage] | Ordered cooking stages |

### Data Model: `CookQueueStage`
| Field | Type | Description |
|---|---|---|
| `id` | UUID | Stage identifier |
| `recipeIDs` | [UUID] | Recipes in this stage (1 for serial, 2+ for parallel) |
| `recipeTitleSnapshots` | [String] | Title snapshots (captured at add time, survive recipe deletion) |
| `sourceMealPlanEntryIDs` | [UUID] | Tracking origin from meal plan |
| `addedAt` | Date | When this stage was added |
| `status` | CookQueueStageStatus | pending, active, completed, skipped |

### Stage State Machine
```
pending → active → completed
                 → skipped
```
- The enum supports `pending`, `active`, `completed`, and `skipped` states.
- Only one retained stage can be `active` at a time.
- Starting a new stage returns any other active stage to `pending`.
- In the current persisted queue implementation, **completed** and **skipped** stages are removed from the queue rather than kept as historical entries.

### Stage Operations
| Operation | Description |
|-----------|-------------|
| `appendStages` | Add stages to the end of the queue |
| `replaceStages` | Replace all stages |
| `startStage` | Set a stage to active (demotes other active stage) |
| `completeStage` | Remove a stage from the queue after it is finished |
| `skipStage` | Remove a stage from the queue without cooking it |
| `removeStage` | Delete a stage from the queue |
| `moveStage` | Reorder a stage by offset (±n positions) |
| `bundleStageWithNext` | Merge two pending stages into a parallel batch |
| `splitStage` | Split a parallel batch into separate serial stages |

### Meal Plan Integration
`MealPlanCookQueueReviewWorkspace` enables building a cook queue from meal plan entries:
1. User selects which planned meals to include.
2. Each entry becomes a `MealPlanCookQueueReviewDraft` with:
   - Inclusion flag (include/exclude).
   - Stage placement (new stage vs. cook with previous).
3. `buildStages()` converts drafts into `CookQueueStage` objects, respecting parallel batch grouping.
4. Estimated total time uses `MultiRecipeScheduler` for parallel batches.

### Active Session Tracking (`ActiveCooksManager`)
- Wraps `CookingSession` UserDefaults persistence.
- Tracks all non-expired active cooking sessions.
- Sessions have a 2-hour expiry timeout.
- Per-element corruption recovery: if a session in the array is corrupted (invalid JSON), it's skipped rather than failing the entire array.

### CookingSession Persistence
| Field | Type | Description |
|---|---|---|
| `recipeId` | UUID | Recipe being cooked |
| `recipeName` | String | Display name |
| `totalSteps` | Int | Number of steps |
| `stepSummaries` | [StepSummary] | Step number + instruction + timer for each step |
| `currentStepIndex` | Int | Current progress |
| `startedAt` | Date | Session start |
| `backgroundedAt` | Date | When app was backgrounded |
| `isActive` | Bool | Whether active |
| `expiryTimeoutSeconds` | TimeInterval | Default 7200 (2 hours) |
| `multiCookSessionId` | UUID? | Groups parallel cooking sessions |
| `queueId` | UUID? | Cook queue reference |
| `queueStageId` | UUID? | Cook queue stage reference |

---

## 15. Meal Planning

### Purpose
Organize recipes and prepared foods into a weekly meal schedule with serving control, consumption tracking, and shopping integration.

### Data Model: `MealPlanEntry`
| Field | Type | Description |
|---|---|---|
| `id` | UUID | Entry identifier |
| `date` | Date | Scheduled date |
| `mealType` | MealType | breakfast, lunch, dinner, snack, dessert |
| `recipe` | Recipe? | Linked recipe (if recipe-based) |
| `preparedDish` | PreparedDish? | Linked prepared dish (if meal-prep) |
| `preparedFoodNameSnapshot` | String? | Name snapshot for prepared food |
| `preparedFoodRecipeID` | UUID? | Recipe that produced the prepared food |
| `preparedFoodIdentityID` | UUID? | Stable identity for non-recipe prepared foods |
| `customMealName` | String? | Freeform text (e.g., "Takeout Pizza") |
| `plannedServings` | Int? | User override for serving count |
| `eatenServings` | Int? | Consumption tracking |
| `notes` | String? | Meal notes |

### Meal Plan Sources
A meal plan entry can reference exactly one of:
1. **Recipe**: Full recipe with ingredients, steps, nutrition.
2. **Prepared dish**: Pre-cooked food from the prepared dishes inventory.
3. **Custom meal name**: Freeform text for untracked meals (takeout, restaurant, etc.).

### Serving Scaling
- `plannedServings` overrides the recipe's default serving count.
- `scaledRecipeForPlanning` returns a recipe scaled to `effectivePlannedServings`.
- Can be used throughout shopping and cooking flows to adjust quantities.

### Consumption Tracking
- `eatenServings` tracks how many servings have been consumed.
- Clamped to `trackingPlannedServings` to prevent over-tracking.
- `isFullyEaten`: All planned servings consumed.
- `remainingTrackedServings`: How many servings left.
- `eatenProgressLabel`: Human-readable text (e.g., "2 of 3 eaten").

### Meal Logging
`logMealPlanEntriesEaten()` processes an array of `MealPlanEatenLoggingSelection`:
- Updates `eatenServings` on each meal plan entry.
- For entries linked to prepared dishes: decrements the source dish's `servingsRemaining`.
- If a prepared dish reaches 0 servings, it's automatically deleted.

### Prepared Food Match Key
`PreparedFoodMatchKey` provides stable linking between meal plan entries and prepared dishes:
- `.recipe(UUID)`: When the prepared dish originated from a recipe.
- `.preparedFoodIdentity(UUID)`: When it's a standalone prepared food (e.g., "Takeout Pasta").

### Week Generation
`MealPlanEntry.emptyWeek(from:)` generates an empty 7-day structure with entries for all meal types (breakfast, lunch, dinner) × 7 days.

---

## 16. Prepared Dishes (Meal Prep Tracking)

### Purpose
Track pre-cooked meals, leftovers, and meal-prep items as a separate inventory from raw pantry ingredients.

### Key Distinction from Pantry Items
- Prepared dishes represent **cooked, ready-to-eat food** — not raw ingredients.
- They **do not participate** in: substitution logic, pantry-match scoring, ingredient resolution, or shopping list generation.
- They **do participate** in: meal planning, consumption tracking, freshness/use-soon alerts, and nutrition tracking.

### Data Model: `PreparedDish`
| Field | Type | Description |
|---|---|---|
| `id` | UUID | Dish identifier |
| `foodIdentityID` | UUID | Persistent identity (stable across re-preparations) |
| `name` | String | Display name |
| `mealTypes` | [MealType] | Applicable meal types |
| `servingsRemaining` | Int | Remaining portions |
| `storage` | PantryStorage | pantry, refrigerated, frozen |
| `useByDate` | Date? | Manual or estimated use-by date |
| `dateAdded` | Date | When added |
| `notes` | String? | User notes |
| `recipeID` | UUID? | Source recipe (optional) |
| `nutrition` | NutritionInfo? | Per-serving nutrition |

### Freshness Policy (`PreparedDishFreshnessPolicy`)
Estimated use-by dates by storage:
- Pantry: 2 days from preparation.
- Refrigerated: 4 days from preparation.
- Frozen: 90 days from preparation.

### History Tracking (`PreparedDishHistoryItem`)
When a prepared dish is added, or when edits materially change its reusable template, a history record is created or refreshed:
| Field | Type | Description |
|---|---|---|
| `foodIdentityID` | UUID | Persistent identity |
| `name` | String | Name at time of preparation |
| `mealTypes` | [MealType] | Meal types |
| `defaultServings` | Int | Typical serving count |
| `storage` | PantryStorage | Storage location |
| `notes` | String? | Notes |
| `recipeID` | UUID? | Source recipe |
| `nutrition` | NutritionInfo? | Nutrition data |
| `createdAt` | Date | First preparation |
| `lastPreparedAt` | Date | Most recent preparation |
| `lastUsedAt` | Date | Most recent modification |
| `timesPrepared` | Int | Preparation count |

History enables:
- Suggesting frequently-prepared dishes for quick re-add.
- Providing defaults when creating a new dish (from history template).
- `canonicalMatchKey` matches on recipe UUID (if linked) or normalized `name|mealTypes` combination.

### Consumption Model
- `consumeServing()` decrements `servingsRemaining`.
- When `servingsRemaining` reaches 0, the dish is completely deleted.
- Meal plan eating logs can also decrement servings from linked prepared dishes.

### Prepared Dishes Workspace Flow
- Prepared dishes are searchable and filterable by meal type.
- Users can add a single prepared dish, create prepared dishes from meal-plan selections, edit or delete dishes, decrement servings directly from the list with quick actions, and open a reusable-history picker when prior prepared-dish templates exist.
- Quick-consume actions produce transient success feedback so the user can see whether a serving was used or the dish was fully removed.
- History reuse is a first-class workflow: previously prepared dishes can be searched, reopened as drafts, and re-added with refreshed defaults.

### Draft System (`PreparedDishDraft`)
A mutable workspace for creating or editing prepared dishes, supporting:
- Text-based nutrition input (calories, protein, carbs, fat as strings → parsed to `NutritionInfo`).
- Manual vs. estimated use-by date (estimated from storage + dateAdded, manual overrides).
- Recipe linking: `applyLinkedRecipeDefaults()` fills blanks from a linked recipe (name, meal types, nutrition).
- Validation: name required, at least one meal type, servings > 0, nutrition must be either fully empty or fully valid (partial fills are rejected).

---

## 17. Shopping List Intelligence

### Purpose
Generate, manage, and convert shopping lists — with smart merging, pantry-aware deduplication, and "purchased → pantry" transfer workflows.

### Data Model: `ShoppingItem`
| Field | Type | Description |
|---|---|---|
| `id` | UUID | Item identifier |
| `name` | String | Display name with facets |
| `quantity` | Double? | Amount needed for recipe |
| `unit` | MeasurementUnit? | Unit of measurement |
| `category` | FoodCategory | Classification |
| `isChecked` | Bool | Shopping status |
| `recipeSource` | String? | Which recipe required this |
| `catalogItemID` | String? | Catalog link |
| `facets` | [PantryFacetSelection] | Resolved facets |
| `pantryQuantity` | Double? | Amount user plans to keep on hand |
| `pantryUnit` | MeasurementUnit? | Pantry unit |
| `pantryQuantityMode` | PantryQuantityMode | exact or presenceOnly |

### Identity Key System
Each shopping item has a computed `identityKey` for deduplication:
- **Catalog-backed**: `catalogItemID + sorted facet summary` (e.g., "flour~variant:whole-wheat|form:all-purpose").
- **Custom**: `normalized name + category raw value`.

This enables merging across recipes — if two recipes both need "all-purpose flour," they're combined into a single shopping item with summed quantities.

### Shopping List Generation from Meal Plan
1. Collect all planned recipes for the relevant time period.
2. Scale each recipe's ingredients by `plannedServings / recipe.servings`.
3. Compute which ingredients are already in the pantry (via `IngredientMatcher`).
4. Generate `ShoppingItem` objects for missing ingredients only.
5. Merge items with the same `identityKey`, summing quantities when units match (with conversion).

### Pantry Plan Customization
Each shopping item can have a separate "pantry plan" — the amount the user wants to maintain on hand (may differ from the immediate recipe need). The `isPantryPlanCustomized` flag tracks whether the user has adjusted the pantry plan from defaults.

### Purchased-to-Pantry Transfer
When items are checked off the shopping list:
- `pantryItemForTransfer()` converts the `ShoppingItem` into a `PantryItem`.
- Uses the reviewed `pantryQuantity` and `pantryUnit` pantry-plan fields, not necessarily the raw recipe-required amount.
- Applies the pantry quantity mode (exact vs. presenceOnly).
- The UI can route checked items through a review step before transfer via `completeCheckedToPantry(with:)`.
- Adds to pantry with automatic merging if the item already exists.

### Shopping Workspace Flow
- Shopping items are grouped by category and expose progress as `checked / total` with a progress bar.
- Users can add catalog-backed items manually, fall back to custom items when catalog search is insufficient, toggle checked state inline, delete items, clear all checked items, and review checked items before moving them into Pantry.
- Each shopping item can expose three layers of information simultaneously: display name and facet summary, recipe-required quantity, and pantry-plan quantity that will actually transfer into pantry.
- Pantry-plan editing supports switching between exact quantity and presence-only tracking, adjusting unit and quantity, and adjusting catalog facets for what was actually purchased.
- The checked-to-pantry review sheet is intentionally explicit about the difference between recipe need and pantry intake, so shopping completion does not silently overfit to recipe quantities.

### Facet Normalization
Shopping item facets are normalized via a two-stage process:
1. Start with catalog default selections.
2. Overlay user-specified facets (replacing defaults for the same keys).
3. Filter to only keys supported by the catalog item.
4. Order by `facetDisplayOrder`: variant → form → preservation → processing → preparation → texture → concentration → base.

---

## 18. Notification System

### Purpose
Support "continue cooking in background" mode by scheduling local notifications for each remaining step and enabling basic interaction via notification actions.

### Notification Types

#### Step Notifications
- **Title**: "Step X of Y — RecipeName"
- **Body**: Step instruction text, including timer info if present.
- **Subtitle**: "Next: [preview of next step]" (if not the last step).
- **Category**: `COOK_MODE_STEP` (enables action buttons).
- **Timing**: Cumulative delays based on `effectiveDurationSeconds` of each step.

#### Session Expiry Notification
- **Title**: "RecipeName"
- **Body**: "Cooking session ended"
- **Timing**: Last step delay + 2 hours.

### Notification Actions
| Action | Identifier | Behavior |
|--------|-----------|----------|
| "Done ✓" | `COOK_MODE_DONE` | Advances step in persisted CookingSession (background, no UI) |
| "Open Cook Mode" | `COOK_MODE_OPEN` | Launches app + deep-links to cook mode interface |

### Delegation
- Delegate handles both background tap and foreground presentation.
- Deep-linking works via `appState.deepLinkCookModeRecipeId` which the root view watches.
- Notifications are displayed with banner + sound even when the app is in the foreground.

### Cancellation
- All notifications for a specific recipe can be cancelled by prefix-matching on the notification identifier.
- On resume from background, all cook-mode notifications are cancelled immediately.

---

## 19. Persistence & Storage Architecture

### Technology
- **Primary store**: SwiftData (SQLite-backed) via the actor-isolated `StorageService`.
- **Persistent store location**: Application Support `default.store` plus the associated WAL/SHM files.
- **Auxiliary stores**: UserDefaults for lightweight preferences and session state (`PantryItemPreferenceStore`, `CookingSession`, cook-mode mute preference).
- **File storage**: JSON files under `~/Library/Caches/PantryChef/` for recipe repository caches and persisted recipe-match metrics.

### Schema
Current schema version: **14**. All records carry a `schemaVersion` field for future migration support.

### Record Types (SwiftData @Model)

| Record | Domain Model | Relationships |
|--------|-------------|---------------|
| `PantryItemRecord` | PantryItem | → cascade PantryFacetRecord[] |
| `PantryFacetRecord` | PantryFacetSelection | ← PantryItemRecord |
| `PreparedDishRecord` | PreparedDish | (flat, nutrition fields inline) |
| `PreparedDishHistoryRecord` | PreparedDishHistoryItem | (payload as encoded Data) |
| `RecipeRecord` | Recipe | → cascade IngredientRecord[], RecipeStepRecord[] |
| `IngredientRecord` | Ingredient | → cascade IngredientFacetRecord[] |
| `IngredientFacetRecord` | PantryFacetSelection | ← IngredientRecord |
| `RecipeStepRecord` | RecipeStep | → cascade StepTaskRecord[] |
| `StepTaskRecord` | StepTask | → cascade StepTaskDependencyRecord[] |
| `StepTaskDependencyRecord` | UUID (dependsOn) | ← StepTaskRecord |
| `MealPlanRecord` | MealPlanEntry | (references by ID, hydrated at fetch) |
| `ShoppingItemRecord` | ShoppingItem | → cascade ShoppingFacetRecord[] |
| `ShoppingFacetRecord` | PantryFacetSelection | ← ShoppingItemRecord |
| `CookQueueRecord` | CookQueue | (payload as encoded Data) |

### CRUD Patterns
- All operations use actor isolation for thread safety.
- Mutation pattern: `ensureBootstrap → mutation → saveContext`.
- Shopping list uses upsert semantics: fetch all, update existing by ID, insert new, delete unlisted.
- Cooking queue keeps only the most recent entry.

### Sort Orders
| Domain | Sort | Rationale |
|--------|------|-----------|
| Pantry items | expiryDate ascending | Use-soon items first |
| Prepared dishes | useByDate, then dateAdded | Use-soon first |
| Recipes | dateAdded descending | Newest first |
| Shopping items | name ascending | Alphabetical |
| Meal plan | date ascending | Chronological |

### Bootstrap
On first launch:
1. If bootstrapping is enabled for the launch mode and no relevant local data exists, the app can seed pantry items, user recipes, and discover recipes.
2. Bundled seed recipes go through `TrustedRecipeCanonicalizer` to ensure all ingredients are resolved.
3. Bootstrap is gated inside `StorageService` and runs only once via the `didBootstrap` guard.

### Error Recovery
- **Container creation failure**: Destroys existing store files (.sqlite, .shm, .wal) and retries.
- **CookingSession corruption**: Per-element decoding — corrupt sessions are skipped rather than failing the entire array.
- **Recipe decoding**: Individual record failures are logged and skipped.

### Startup Snapshot
`fetchStartupSnapshot()` performs a batch load of all domains in a single method call, pre-building lookup tables (`[UUID: Recipe]`, `[UUID: PreparedDish]`) and hydrating meal plan entries with their referenced objects. This avoids N+1 query patterns.

### Encoding Codecs
- `RecipeSourceCodec`: Serializes/deserializes `RecipeSource` as kind + optional externalId.
- `CookingActionCodec`: Serializes cooking actions as `{kind, parameter}` pairs (e.g., `{kind: "cut", parameter: "dice"}`).

---

## 20. Performance & Caching Infrastructure

### Recipe Match Metrics
The recipe filtering system maintains a multi-layer caching architecture:

#### Layer 1: In-Memory LRU Match Map
- `matchMapCache`: Dictionary of `[Recipe.id → PantryMatchResult]`.
- Up to 8 entries (keyed by pantry+recipe signature).
- Used for hot-path filtering and sorting by match percentage.

#### Layer 2: Disk-Persisted Metrics
- Stored in `~/Library/Caches/PantryChef/match_metrics_v2.json`.
- Structure: Array of `(pantrySignature, [recipeID → RecipeMatchMetrics])`.
- Up to 8 pantry signatures retained (LRU eviction).
- Loaded once on first metrics access.
- Enables instant match percentages on cold restart.

#### Layer 3: Dependency-Aware Seeding
- `ingredientDependencyIndex`: Maps each ingredient dependency key → set of recipe IDs that use it.
- `pantryDependencyState`: Fingerprints each pantry item (id, name, catalog ID, quantity, unit, facets, storage).
- When pantry changes, only recipes whose dependency keys are affected need recomputation.
- Unaffected recipes inherit metrics from the previous pantry state.

### Search Index
- `RecipeSearchIndex`: Pre-tokenizes all searchable recipe text (title, description, cuisine, meal type, ingredients).
- Builds `token → Set<recipeID>` reverse index.
- Multi-token queries use AND intersection across token sets.
- Fallback to substring matching for short queries or no token matches.

### Background Prewarming
- `prewarmDiscover(visibleCount:)`: Computes match metrics for first N visible discover recipes.
- `scheduleBackgroundMatchPrewarm()`: Utility-priority background task.
- `scheduleFullMetricsCoverage()`: Chunked precomputation (128-recipe chunks) at utility priority.
- All prewarming is cancellable if pantry/recipes change.

### Filtered Result Caching
- `cachedUserFilterResult` / `cachedDiscoverFilterResult`: LRU cache for filtered+sorted recipe arrays.
- Cache key includes: search query, all filter selections, sort order, pantry revision, recipe revision.
- Avoids recomputation when scrolling/navigating without changing filters.

### Debouncing
- `TaskDebouncer`: Reusable debouncer with configurable delay.
- Standard durations:
  - `quickSearch`: 150ms (pantry/recipe search).
  - `apiSearch`: 400ms (AI-backed operations).
- Auto-cancels pending task when a new one is scheduled.

---

## 21. Configuration & Launch Options

### App Configuration (`AppConfig`)
| Key | Source | Description |
|-----|--------|-------------|
| `openAIAPIKey` | Environment variable → Info.plist | Required for all AI features |
| `expiryWarningDays` | Hardcoded: 3 | Days before expiry to show warnings |
| `maxRecipeSuggestions` | Hardcoded: 5 | AI suggestions per request |
| `defaultServings` | Hardcoded: 4 | Default recipe servings |

API key lookup: environment variables are checked first (for CI/testing), then Info.plist (for production). Missing keys are marked with a `__MISSING_CONFIG__` prefix.

### Launch Options (`AppLaunchOptions`)
Configurable via process arguments (for UI testing):

| Argument | Effect |
|----------|--------|
| `UITEST_MODE` | Ephemeral in-memory storage, no persistence |
| `UITEST_EMPTY_STATE` | Disables sample data seeding |
| `RESET_PERSISTENT_STORE` | Clears all persisted data on startup |
| `UITEST_RECIPE_DETAIL` | Auto-opens first recipe detail screen |

### Logging
`AppLog` provides structured logging:
- Four levels: debug, info, warn, error.
- Format: `"yyyy-MM-dd HH:mm:ss.SSS [LEVEL] file:line function | message"`.
- Autoclosure for deferred message evaluation (no computation cost if level is filtered).
- Thread-safe with NSLock on shared DateFormatter.

### Unit Conversion
`UnitConverter` supports:
- **Volume → milliliters**: tsp (4.93), tbsp (14.79), cup (236.59), fl oz (29.57), ml (1), L (1000).
- **Weight → grams**: g (1), kg (1000), oz (28.35), lb (453.59).
- **Cross-unit conversion**: From any supported unit to any compatible unit.
- **Fractional display**: Renders quantities as common fractions (¼, ⅓, ½, ⅔, ¾, etc.) when applicable.

---

## Appendix: Data Model Relationships

```
Recipe
├── ingredients: [Ingredient]
│   ├── catalogItemID? → PantryCatalogItemDefinition
│   └── facets: [PantryFacetSelection]
├── steps: [RecipeStep]
│   └── tasks: [StepTask]
│       ├── dependsOn: [UUID] → other StepTasks
│       ├── action: CookingAction (with CutStyle/FryStyle sub-types)
│       └── effort: EffortLevel
├── nutrition: NutritionInfo?
├── dietaryTags: [DietaryTag]
├── mealType: MealType?
├── cuisine: CuisineType?
└── source: RecipeSource

PantryItem
├── catalogItemID? → PantryCatalogItemDefinition
├── facets: [PantryFacetSelection]
├── category: FoodCategory
├── storage: PantryStorage
├── quantityMode: PantryQuantityMode
└── freshnessSource: PantryFreshnessSource

PantryCatalogItemDefinition
├── aliases: [String]
├── facets: [PantryFacetDefinition] (available options)
├── defaultSelections: [PantryFacetSelection]
├── substitutions: [PantrySubstitutionDefinition]
│   └── substituteItemID → PantryCatalogItemDefinition
├── freshnessByStorage: [PantryStorage: ClosedRange<Int>]
└── unitOverrides: [PantryFacetKey: [String: MeasurementUnit]]

MealPlanEntry
├── recipe? → Recipe
├── preparedDish? → PreparedDish
├── mealType: MealType
├── plannedServings / eatenServings
└── preparedFoodMatchKey? → PreparedFoodMatchKey

PreparedDish
├── recipeID? → Recipe
├── mealTypes: [MealType]
├── storage: PantryStorage
├── nutrition: NutritionInfo?
└── preparedFoodMatchKey → PreparedFoodMatchKey

CookQueue
└── stages: [CookQueueStage]
    ├── recipeIDs: [UUID] → Recipes
    ├── status: CookQueueStageStatus (state machine)
    └── sourceMealPlanEntryIDs: [UUID] → MealPlanEntry

ShoppingItem
├── catalogItemID? → PantryCatalogItemDefinition
├── facets: [PantryFacetSelection]
├── recipeSource: String? (recipe name)
├── pantryQuantity/pantryUnit (for pantry transfer)
└── identityKey (for deduplication)

CookingSession
├── recipeId → Recipe
├── queueId? → CookQueue
├── queueStageId? → CookQueueStage
└── multiCookSessionId? (groups parallel sessions)
```
