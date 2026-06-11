# Feature audit — old flow vs. Kitchen Timeline redesign

Honest accounting as of the runnable redesign (sample data). Legend:
**✅ present** · **◑ partial** (UI exists but not wired, or display-only) · **✗ missing** ·
**↔ intentionally changed**.

The headline: the redesign is a complete *UI shell on seeded sample data*. Most
**functional** capabilities (AI, shopping, real cooking, persistence, planning
actions) are designed but **not yet wired** — that's the "production wiring" task,
not lost work. But several are genuine regressions to restore, flagged ⚠️.

## Recipes / Library
| Old | Redesign | Notes |
|---|---|---|
| My Recipes / Discover sections | ◑ one gallery | sections not yet split |
| Search | ✗ ⚠️ | engine exists (used by composer); no Library search box |
| Multi-facet filter | ✗ ⚠️ | no filter bar (issue #4) |
| Sort | ✗ | |
| "What can I make" can-make | ✅ | readiness per cell, live via ReadinessService |
| Serving scaling | ✗ | |
| Manual recipe builder/editor | ✗ | |
| Recipe detail page (ingredients, steps) | ✗ ⚠️ | needed for mise en place (issue #2) |
| Nutrition / dietary / cuisine / difficulty display | ✗ | data exists on Recipe model |
| Favorite / rating / timesCooked | ✗ | |
| Dietary/allergen profile, substitutions, density conversion | ✗ ⚠️ | the §"what to add" items (issue #4) — never built in either flow |

## Recipe acquisition (AI)
| Old | Redesign | Notes |
|---|---|---|
| Generate from query | ✗ | composer has no AI path yet |
| Suggest names → generate | ✗ | |
| Modify with feedback | ✗ | |
| Import from URL / text | ◑ | composer "paste a recipe" is a doorway stub |
| Leftover transformer | ✗ | |
| Suggest from pantry | ◑ | the fan is the spiritual replacement, but hand-seeded now |
| AI ingredient definition | ✗ | IntakeParser flags unresolved; AI enrich not wired |

## Pantry / Stock
| Old | Redesign | Notes |
|---|---|---|
| Catalog-backed items + facets | ◑ | shown; no facet editing |
| Storage states (pantry/fridge/freezer) | ◑ | shown; not editable in UI (issue #3) |
| Freshness/expiry tracking | ✅ | day counts; honest staple presence (issue #1 fixed) |
| Quantity modes (exact/presence) | ↔ | replaced by resolution classes |
| Bulk add | ◑ | composer multi-card staging (not persisted) |
| Custom ingredients | ✗ ⚠️ | composer keeps unresolved as custom, but no real creation (issue #3) |
| Edit / remove a staged or stocked item | ✗ ⚠️ | issue #3 |
| Catalog customization screen | ✗ | |

## Shopping
| Old | Redesign | Notes |
|---|---|---|
| Pantry-aware list generation | ✗ ⚠️ | "on your list" is referenced but no List surface |
| From recipe / meal plan | ✗ | |
| Check-off, add to pantry | ✗ | |

## Meal planning
| Old | Redesign | Notes |
|---|---|---|
| Weekly grid | ↔ | becomes the timeline future + day-unfurl (deferred) |
| Assign meal to day | ◑ | PlannedMeal model + timeline rows; commit UI not wired |
| Eaten-servings | ↔ | absorbed by meal events (not wired) |
| Weekly nutrition | ✗ | |

## Prepared dishes (leftovers)
| Old | Redesign | Notes |
|---|---|---|
| Track cooked dishes / servings / use-by | ◑ | Stock "Made by you" shows it; no add/consume actions |

## Cooking ⚠️ (issue #5)
| Old | Redesign | Notes |
|---|---|---|
| Cook Mode step-by-step | ◑ | CookInstrumentView (hardcoded sample steps; not recipe-driven) |
| Ingredient gathering / mise en place | ✗ ⚠️ | removed — issue #2 |
| Real timers | ✗ | static "02:00" |
| Voice assistant (OpenAI Realtime) | ✗ | |
| Continue-in-background notifications | ✗ | |
| **Multi-cook batch scheduling** | ✗ ⚠️ | the differentiator — gone; must fold into one Cook surface |
| Cook Queue | ✗ | to consolidate into Cook |
| Substitutions surfacing in cook/recipe | ✗ ⚠️ | swaps data + ReadinessService ready; not surfaced |

## Today / dashboard
| Old | Redesign | Notes |
|---|---|---|
| Greeting, today's plan, expiring, suggestions | ✅ ↔ | folded into the timeline + now-module |
| Weekly nutrition / batch-prep cards | ✗ | |

## Infrastructure
| Old | Redesign | Notes |
|---|---|---|
| SwiftData persistence | ✗ ⚠️ | redesign runs on in-memory sample data |
| Sentry / telemetry | ✅ | still initialised in PantryChefApp |
| Tests | ✅ | 55 redesign engine tests (legacy 875 until legacy removed) |

## Restore priority (the ⚠️ regressions) — status after the interaction pass
1. ✅ **Recipe detail + ingredient gathering** — detail view (hero/readiness/allergens/
   swaps/method) → mise en place → steps with real timers.
2. ✅ **Composer editing** — staged cards editable (amount/unit/storage/name) and
   removable; custom ingredients and unrecognized units handled; destinations
   (Stock/List/Tonight's meal) commit for real.
3. ✅ **Library filtering + enrichment** — filter bar, search, favorites toggle,
   allergens shown, dietary-profile conflicts flagged, interactive swaps, density
   gram-hints.
4. ✅ **Multi-cook** — "Cook together" select → merged gather → interleaved steps.
5. ✅ **Shopping list (minimal)** — lives in Stock ("On the list"), fed by the
   composer and removable; stock rows editable.
6. ⏳ **Persistence** — still sample data (the KitchenStore seam).
7. ⏳ **AI flows** (generate/import/suggest), **voice**, **notifications** — engines
   survive in Services/, none wired to the new UI.
8. Minor known dead affordances: composer/cook mic icons (decorative until voice
   wires in), Library sort, cooked-card rating, week-marker rows.
