# Testing Playbook

## Quality Commands

Generate the project and run the full quality stack with split unit/UI phases:

```bash
bash Scripts/ci/run_quality.sh
```

Run just the unit suite with coverage:

```bash
xcodebuild test \
  -project PantryChef.xcodeproj \
  -scheme PantryChef \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage YES \
  -only-testing:PantryChefTests
```

Run just the UI smoke suite:

```bash
xcodebuild test \
  -project PantryChef.xcodeproj \
  -scheme PantryChef \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PantryChefUITests
```

## Coverage Gate

The current enforced line-coverage floor is 20% for the PantryChef app target.

Use the gate directly against an `.xcresult` bundle:

```bash
python3 Scripts/ci/check_coverage.py .artifacts/test-results/unit.xcresult --target PantryChef.app --minimum 20
```

The threshold is deliberately conservative for the first baseline. Raise it as the suite expands.

## Performance Budgets

These budgets are enforced in tests and are intended to catch regressions without making CI noisy.

- Recipe filtering over a 600-recipe fixture set: average runtime must stay below 250 ms
- Pantry matching over 250 recipes x 8 ingredients against a 120-item pantry: average runtime must stay below 1100 ms

If these budgets begin failing on healthy code, adjust the fixture size or sampling method first. Do not weaken the threshold without understanding the regression.

## Snapshot Baselines

Snapshot tests currently use deterministic image hashes for critical screens.

When intentional UI changes happen:

1. Run `ViewSnapshotBaselineTests`
2. Capture the new hash values from the failure output
3. Update the expected hashes in the snapshot test file
4. Review the visual change before accepting the new baseline

## Prioritized Fix-By-Test Backlog

1. Launch and crash safety
   Focus on any path that can terminate the app: AI decoding, persistence decoding, startup data loading, and permission-gated flows.
2. Persistence integrity
   Add regression coverage for SwiftData decode/encode edge cases, especially nested step-task dependencies and meal plan reconstruction.
3. Core kitchen workflows
   Keep expanding scenario coverage for pantry search, recipe search, what-can-I-make ranking/filtering, and meal-plan-to-shopping generation.
4. AI contracts
   Extend validator coverage around malformed structured outputs, language mismatches, empty sections, and timer/task sanity.
5. High-value UI flows
   Grow UI smoke coverage from navigation checks into add-item, favorite-recipe, and shopping generation happy paths.
6. Device-dependent features
   Add targeted checks for receipt scanning, speech, and notifications where simulator-safe seams exist.

## Exploratory Checkpoints

Run these manually before cutting a release or after large refactors:

1. Cold launch and warm relaunch both reach Home without error banners or crashes.
2. Pantry: add, search, edit, and delete an item.
3. Recipes: search, toggle favorite, activate what-can-I-make, and open a detail screen.
4. Meal plan: add a recipe to the plan and generate the shopping list.
5. Shopping: confirm generated missing ingredients are sensible and duplicates are collapsed.
6. Cook mode: open a recipe, advance steps, start a timer, background the app, and return.
7. Permissions: deny camera, mic, and speech permissions and verify fallback behavior remains usable.
8. Offline and no-key mode: verify non-AI and non-network features still work without blocking the UI.

## Reliability Notes

`xcodebuild test` against the full mixed scheme can intermittently fail with a UI test runner preflight busy error even when unit and UI bundles both pass independently. Until that is eliminated, treat `bash Scripts/ci/run_quality.sh` as the canonical quality command because it runs the two bundles separately.
