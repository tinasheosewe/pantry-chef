# Recipe pass: per-step cook times + validity flag

For your assigned slice of `recipes[start:end]` in `PantryChef/Resources/seed_recipes.json`,
emit `docs/recipe-pass/chunk-<start>.json`:

```json
{ "recipes": [
  { "name": "<exact>", "index": <int>, "count": <#steps>,
    "timeMinutes": <realistic total minutes, int>,
    "stepSeconds": [ <int per step, ALIGNED 1:1 to the steps array> ],
    "valid": <bool>, "issue": <"short reason" | null> }
] }
```

## Per-step seconds — use real cooking knowledge, NOT an even split
Estimate how long each step actually takes:
- chop/measure/whisk/prep: ~60–180s
- sauté / brown / fry / sear: ~240–600s
- simmer / braise / stew / reduce: ~900–2700s
- boil pasta / blanch: ~480–720s
- bake / roast: ~1200–3000s
- marinate / rest / chill / proof: realistic (can be long)
- season to taste / plate / garnish / serve: ~30–90s

Every step gets a POSITIVE integer. The sum should be in the right ballpark of an
attentive cook's active time; it's fine if it doesn't exactly equal `timeMinutes×60` —
use honest per-step times rather than forcing a total. Keep `timeMinutes` as-is unless it's
clearly wrong (then correct it).

## Validity
Set `valid: false` (with a short `issue`) when a recipe isn't a real, coherent dish — e.g.
fewer than ~3 substantive ingredients, or steps that don't actually make the named dish.
Do NOT rewrite; just flag (the integrator handles fixes).

Include EVERY recipe in your slice. Validate the JSON parses; `stepSeconds.count` must equal
the recipe's step count. Report counts + any `valid:false` recipes.
