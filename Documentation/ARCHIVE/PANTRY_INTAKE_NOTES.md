# Pantry Intake And OCR Notes

Date: 2026-03-21

## Core Conclusions

- Substitutions are core to the product.
- Expiry and freshness are useful, but they should be modeled as estimates with confidence unless the user provides a real date.
- Raw receipt strings are weak evidence, not truth.
- Pantry intelligence should be built on canonical food identities plus structured qualifiers, not raw product names.

## Canonical Item Model

Separate observed input from canonical identity.

Recommended layers:

1. Observed text or scan result
2. Normalized interpretation
3. Canonical food identity
4. Qualifiers and state

Example:

- branded product text -> canonical identity like butter, flour, or muffin -> qualifiers like salted, all-purpose, frozen, or refrigerated

## Substitution Design

- Model substitutions as compatibility rules, not string mappings.
- Use base ingredient plus structured qualifiers.
- Compare pantry items and recipe ingredients in two stages:
  1. resolve canonical identity
  2. evaluate qualifier compatibility
- Return outcomes like exact match, acceptable, acceptable with warning, poor substitute, or no substitute.

## Expiry And Freshness Design

- Do not present guessed dates as exact truth.
- Freshness should depend on:
  - canonical identity
  - storage state
  - packaging or opened state
  - acquisition or purchase date
- Frozen items should be treated as long-lived, low-urgency inventory, not literally never-expiring.
- If storage changes, freshness estimates should recalculate immediately.

## Warning Taxonomy

Keep warnings semantic and limited:

- unresolved identity
- inferred field
- conflicting field
- missing required field
- downstream-impact warning

Warning severity should be separate from warning type.

## Barcode And Receipt Intake Conclusions

- Barcode scan is more deterministic and lower complexity than receipt OCR.
- Receipt OCR is useful, but should not be MVP-critical unless low-friction pantry onboarding is the main launch thesis.
- Receipt parsers extract structure and line items, but they do not reliably solve grocery product identity on their own.

## Recommended Stack

1. On-device capture for photo and barcode UX
2. Cloud receipt parser for structured extraction when receipt intake is added
3. Hosted or local product cache for enrichment
4. Deterministic canonicalization and freshness rules owned by the product
5. User review only for uncertain fields

## Hosted Or Local Enrichment Strategy

- Prefer owning the enrichment layer rather than depending fully on premium APIs.
- Seed with downloadable and open data sources such as Open Food Facts and USDA FoodData Central.
- Treat the hosted cache as a long-term knowledge asset containing:
  - product records
  - aliases
  - merchant-specific abbreviations
  - user-confirmed mappings
  - candidate retrieval support

## LLM-In-The-Loop Conclusions

- LLM should be a selective escalation path, not the default resolver.
- Use LLM only for ambiguous rows or conflicts.
- The LLM should rank bounded candidates, not invent open-ended answers.
- Good LLM inputs include:
  - merchant
  - raw line text
  - price
  - candidate products from hosted cache
  - known merchant aliases
- Good LLM outputs include:
  - ranked candidate
  - confidence
  - unresolved when unsure
- User edits must always override delayed model updates.

## Streaming Review Model

- The review UI should stream rows as soon as parsing is available.
- Rows can independently move through states such as:
  - parsed
  - estimated
  - improving
  - resolved
  - needs review
- Slow convergence on a few rows must not block the entire review experience.

## Cost Policy For LLM Usage

- Gate LLM calls behind low-confidence thresholds.
- Only run the LLM on the ambiguous tail.
- Batch unresolved rows when sensible.
- Cache prior resolutions.
- Learn from user corrections so LLM usage declines over time.

## MVP Scope Decision

- OCR and barcode scanning are not required for MVP.
- If the goal is to validate pantry intelligence, ship first without scanning.
- If one intake accelerator is needed early, add barcode before receipt OCR.
- Recommended sequencing:
  1. manual entry and guided fast-add first
  2. barcode second
  3. receipt OCR third

## Fast-Add MVP Focus

Build a strong guided manual entry flow around canonical items and qualifiers.

Validate these capabilities first:

- substitutions
- freshness and use-soon logic
- recipe matching
- pantry review and edit UX

## Evaluation Dataset Meaning

Create a representative benchmark corpus before locking in parser or vendor choices.

Include:

- real grocery receipts
- barcode scans
- expected pantry outcomes

Measure:

- parser quality
- identity resolution quality
- warning rates
- review burden
- time to first reviewable screen

Use the cheapest parser that meets quality and review-burden thresholds on this dataset.

## Strategic Principle

- Buy commodity extraction.
- Own pantry intelligence.
- Be deterministic where possible.
- Be explicit about uncertainty where necessary.
- Use background convergence for the ambiguous tail.
