# PantryChef — Feature Inventory

A full scan of the app's feature surface (iOS, SwiftUI, SwiftData, local-first).

## Navigation
Four root tabs + modal cooking surfaces:
- **Today** (Home dashboard)
- **Recipes** (My Recipes / Discover)
- **Kitchen** (segmented: Pantry / Prepared / Shopping)
- **Plan** (weekly meal plan)
- Modals: Cook Mode, Multi-Cook Mode, Cook Queue, Use-Up Ingredients, plus a persistent **mini-player** to resume an active cook.

## Recipes
- Two libraries: **My Recipes** (user/imported/AI) and **Discover** (bundled seed recipes).
- Rich model: ingredients (catalog-backed, with facets), steps, servings, prep/cook time, difficulty, cuisine, meal type, dietary tags, nutrition, source, source URL, favorite, timesCooked, rating (1–5).
- Search, multi-facet filter, sort; **"What can I make"** (can-make filter against pantry).
- Serving **scaling** (re-computes ingredient quantities).
- Manual recipe builder/editor.

## Recipe acquisition (AI-heavy)
- **Generate from a natural-language query** (with preferences) + streamed "status messages."
- **Suggest recipe names** from ingredients, then **generate the full recipe** from a chosen name (two-step flow).
- **Modify a recipe** from freeform feedback ("make it spicier", "no dairy").
- **Import from URL** (JSON-LD/schema.org scraping + LLM fallback) and **import from pasted text**.
- **Leftover transformer** (recipes from a set of leftover ingredients).
- **Suggest recipes from pantry**.
- **AI ingredient definition** — creates a catalog item on the fly for an unknown ingredient.
- All AI output passes through an **AIOutputValidator**.

## Pantry / inventory
- Catalog-backed items with **facets** (the variant/grade/fat/form/… model).
- **Storage states**: Pantry / Refrigerated / Frozen.
- **Freshness/expiry tracking**: estimated (from catalog shelf-life) or user-provided.
- **Quantity modes**: exact quantity vs. presence-only.
- **Bulk add** (search-composer staging), default-preference memory per item.
- **Custom ingredients** + catalog customization (add facet values, aliases, default overrides) via the Ingredient Catalog settings screen.

## Shopping
- **Pantry-aware list generation** from a recipe or from the whole meal plan (subtracts what you already have).
- Check-off, quantities, and **add checked items to pantry**.

## Meal planning
- **Weekly calendar**, plan meals by day and meal type, navigate weeks.
- **Eaten-servings** tracking; **generate shopping list** from the week; **weekly nutrition** rollup.

## Prepared dishes (leftovers)
- Track cooked dishes with **servings remaining**, storage, and **use-by date / expiry**; surfaced on Today and in Kitchen.

## Cooking
- **Cook Mode**: step-by-step single recipe, ingredient-gathering screen, timers.
- **Voice assistant**: hands-free voice-to-voice via OpenAI Realtime API during cooking; on-device speech recognition + TTS; voice commands (next/previous/timer).
- **"Continue in background"**: AI pre-schedules rich step notifications so you can keep cooking after the voice session disconnects; notifications deep-link back.
- **Multi-Cook**: AI **batch scheduler** interleaves several recipes into time blocks so they finish together; multi-cook session UI.
- **Cook Queue**: line up multiple recipes/stages; resume via mini-player.
- **Substitutions**: curated + catalog-backed, pantry-aware ("you have tofu, swap it for the chicken").

## Today dashboard
Greeting, today's plan, **expiring-soon pantry items**, **expiring prepared dishes**, a recipe suggestion, weekly nutrition card, batch-prep card.

## Search
4-strategy ranked engine over the catalog: exact → fuzzy (Levenshtein) → Bitap substring → prefix, with facet-aware matching.

## Catalog (the data backbone)
~2,277 governed ingredient entities; 10-key facet taxonomy; per-item enrichment: **gramsPerCup / gramsPerPiece** (density), **allergens**, **dietaryTags**, **swaps**; shelf-life by storage; aliases. Validated by a Python pipeline + Swift invariant tests.

## Infrastructure
- **Local-first** persistence (SwiftData) + UserDefaults for prefs. No cloud sync.
- **Sentry** crash reporting + a telemetry reporter.
- 875 automated tests.

## Notable absences
- No user **profile / dietary-restriction / allergen settings** (despite the catalog now carrying allergens & dietary tags).
- No **barcode scanning** for pantry entry.
- No **widgets**, no **share extension**, no **HealthKit**, no **multi-device sync**.
- The catalog's `allergens`, `gramsPerCup`, `gramsPerPiece`, and `swaps` are **not yet consumed** by any feature.
