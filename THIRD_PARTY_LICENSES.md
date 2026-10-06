# Third-Party Components And Data Sources

What this repository takes from other people, under which terms, and where the data and images bundled with the app came from.

## Package dependency

- `sentry-cocoa`
  - Purpose: optional crash reporting and telemetry forwarding.
  - Integration: Swift Package Manager dependency declared in `PantryChef.xcodeproj` and pinned to 9.8.0 in `Package.resolved`. Not vendored; nothing from it is stored in this repository.
  - Runtime behavior: inactive unless `SENTRY_DSN` is configured.
  - License: MIT (Copyright (c) 2015 Sentry). See `LICENSE.md` in https://github.com/getsentry/sentry-cocoa.

## Adapted code

- `Fuse-Swift` (bitap algorithm)
  - Source: https://github.com/krisk/fuse-swift, 1.x sources (the files cited below exist at tag `1.4.0`).
  - Author: Kirollos Risk
  - License: MIT for the 1.x sources, reproduced below. The upstream repository's current default branch is licensed Apache-2.0.
  - Usage: the bitap (shift-or) fuzzy substring search algorithm was adapted
    from `Fuse/Classes/Fuse.swift` and `Fuse/Classes/FuseUtilities.swift` into
    `PantryChef/Services/BitapSearcher.swift`. The multi-property search,
    async dispatch, and highlight-range utilities were not used.
  - Local file: `PantryChef/Services/BitapSearcher.swift`

```text
The MIT License (MIT)

Copyright (c) 2017 Kirollos Risk

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Bundled fonts

- `Fraunces` (variable font, roman and italic)
  - Files: `PantryChef/Resources/Fonts/Fraunces.ttf`, `PantryChef/Resources/Fonts/Fraunces-Italic.ttf`
  - Copyright: Copyright 2020 The Fraunces Project Authors (github.com/undercasetype/Fraunces), as recorded in the font files.
  - License: SIL Open Font License, Version 1.1. The full text is in `PantryChef/Resources/Fonts/OFL.txt`, and the license statement is also embedded in the font files.
  - Usage: registered at launch by `PantryChef/UI/Foundation/FontLoader.swift` and used as the display typeface.

## Bundled data and images

Everything below was written or generated for this project, as the commit history records. No recipe site, cookbook or food database was copied into it.

- **Ingredient catalog** (`PantryChef/Resources/catalog.json`, `catalog.source.json`)
  - The first list of base ingredients (March and April 2026) was selected with the help of a frequency count of ingredient names in the RecipeNLG corpus, run locally, then triaged and extended with OpenAI's GPT-4.1. Aliases, facets, default units and shelf-life ranges were written with the same model under a JSON schema.
  - In May and June 2026 the list was restructured by the scripts in `Scripts/` (variants became child entries; density, allergens, dietary tags and default substitutions were derived by the rules in `Scripts/remodel/enrich.py`), then extended and corrected with per-category proposals written with Anthropic's Claude, kept under `docs/catalog-*` and applied by the scripts in `tools/`.
  - Shelf-life ranges were written by a language model. Densities and piece weights are constants in `Scripts/remodel/enrich.py`: common kitchen reference values, many of which match USDA standard reference figures (public domain). Treat all of them as estimates.
- **Recipes** (`PantryChef/Resources/seed_recipes.json`, drafts in `docs/recipe-seed/`)
  - The 188 recipes were written with Anthropic's Claude for this project in June 2026, in four batches, and then deduplicated, given per-step times and marked essential or optional per ingredient by later passes (`docs/recipe-pass/`, `docs/recipe-essentiality/`). The seven dishes defined in `KitchenStore.swift` were written in code for the sample kitchen.
- **Plate images** (`PantryChef/Resources/PlateArt/*.png`)
  - Generated with OpenAI's `gpt-image-1` from the art-direction prompt shared by `PlateRenderLibrary` and `tools/generate_plate_art.py`, then downscaled to 640 px and quantized.
- **App icon** (`PantryChef/Assets.xcassets/AppIcon.appiconset/AppIcon.png`)
  - Drawn by `tools/make_app_icon.swift`.

## Services called at run time

- **OpenAI API** (Chat Completions with `gpt-4o`, image generation with `gpt-image-1`): only when an API key is configured and the user starts one of the AI actions. Subject to OpenAI's terms for the key holder.
- **Open Food Facts API**: barcode lookups in `PantryChef/Services/ProductLookup.swift` read a product's name. No Open Food Facts data is stored in this repository or packaged into the app. The Open Food Facts database is available under the Open Database License (https://openfoodfacts.org); an app that shows its data to users is expected to credit it.

## Data used during development and not included

- **RecipeNLG** (Poznań University of Technology): used locally for ingredient-name frequency analysis (`Scripts/analyze_corpus_ingredients.py`). The dataset is licensed for non-commercial research and educational use. Neither the dataset nor the frequency tables computed from it are in this repository; the script writes its output to the git-ignored `Scripts/triage_output/`.
- **MISKG**, the Multimodal Ingredient Substitution Knowledge Graph (CC BY-NC 4.0, https://github.com/kanak8278/MISKG): for two weeks in March 2026 the app's substitution table was built from its substitution pairs. That table was replaced on 21 March 2026 by substitutions held in the catalog, and it is not in this repository. The scripts that processed it remain in the history (`Scripts/preprocess_miskg.py` and related files).
- **USDA FoodData Central** (Foundation Foods and SR Legacy; public domain, CC0 1.0): used in March 2026 experiments on parsing and grouping ingredient descriptions. The outputs of those experiments are in the history under `Scripts/recipe_ingredient_orchestrator/`; nothing derived from them is in the current app. Source: U.S. Department of Agriculture, Agricultural Research Service. FoodData Central. https://fdc.nal.usda.gov/.

## Earlier in the history

- `swift-realtime-openai` by Miguel Piedrafita (MIT) was vendored under `Vendor/swift-realtime-openai`, with its license file and a note of local changes, from 19 March to 19 June 2026 for the voice cook mode that was later removed.
- The Spoonacular recipe API was called at run time between 8 and 22 March 2026. No Spoonacular data is in this repository.

If additional third-party code, datasets or bundled assets are introduced later, record them here with their source, license, and shipping status.
