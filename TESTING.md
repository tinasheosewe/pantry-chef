# Testing Playbook

## Canonical Quality Command

Run the full quality stack with the maintained CI wrapper:

```bash
bash Scripts/ci/run_quality.sh
```

That script is the source of truth for local validation. It currently:

- runs `xcodegen generate`
- auto-selects an available iPhone simulator
- runs `PantryChefTests` with code coverage enabled
- enforces the coverage floor against the unit-suite `.xcresult`
- runs `PantryChefUITests` separately

If you want to pin a simulator manually, set `SIMULATOR_NAME` before invoking the script.

## Direct Commands

Run the unit suite with coverage:

```bash
xcodebuild test \
  -project PantryChef.xcodeproj \
  -scheme PantryChef \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage YES \
  -only-testing:PantryChefTests
```

Run the UI smoke suite:

```bash
xcodebuild test \
  -project PantryChef.xcodeproj \
  -scheme PantryChef \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PantryChefUITests
```

If `iPhone 17` is unavailable on your machine, substitute any current iPhone simulator or let `run_quality.sh` choose one automatically.

## Current Test Surface

The main unit bundle currently covers:

- AI output validation
- multi-recipe scheduling
- recipe ingredient resolution
- storage integration and persistence flows
- realtime event and service behavior
- scenario baselines across core kitchen workflows
- performance baselines
- snapshot baselines
- telemetry formatting and forwarding

The UI bundle is still intentionally light. It is a smoke suite for launch and high-level navigation, not a full behavioral UI regression suite.

## Coverage Gate

The enforced line-coverage floor is currently 20% for the `PantryChef.app` target.

Run the gate directly against an `.xcresult` bundle:

```bash
python3 Scripts/ci/check_coverage.py .artifacts/test-results/unit.xcresult --target PantryChef.app --minimum 20
```

The threshold is intentionally conservative. Raise it only when the suite meaningfully expands.

## Performance Budgets

These budgets are enforced in tests and are meant to catch regressions without turning CI noisy:

- Recipe filtering over a 600-recipe fixture set: average runtime must stay below 250 ms.
- Pantry matching over 250 recipes x 8 ingredients against a 120-item pantry: average runtime must stay below 1100 ms.

If a budget starts failing on healthy code, inspect fixture drift or sampling methodology before weakening the threshold.

## Snapshot Baselines

Snapshot tests use deterministic image hashes for critical views.

When a deliberate UI change happens:

1. Run `ViewSnapshotBaselineTests`.
2. Capture the new hash values from the failure output.
3. Review the visual change, not just the hash delta.
4. Update the expected hashes in the test file only after confirming the new rendering is correct.

## Manual Release Checks

Run these before cutting a release or after broad refactors:

1. Cold launch and warm relaunch both reach the Today screen without crashes or stuck loading states.
2. Pantry: add, bulk-add, edit, search, and delete an item.
3. Recipes: search, favorite, activate what-can-I-make, open a detail screen, and scale servings.
4. Plan: add a recipe or prepared dish to the meal plan and generate the shopping list.
5. Shopping: confirm duplicate ingredients consolidate correctly and pantry-plan edits persist.
6. Cook mode: open a recipe, advance steps, start a timer, background the app, and resume.
7. Permissions: deny microphone and speech permissions and verify the app remains usable.
8. No-key mode: verify non-AI flows still work when `OPENAI_API_KEY` is unset.

## Reliability Notes

- Treat `bash Scripts/ci/run_quality.sh` as the canonical command. A single mixed `xcodebuild test` pass can still produce transient UI-test runner preflight issues even when the split bundles pass.
- If Xcode appears to run stale XCTest code after source changes, prefer a clean rebuild with `xcodebuild clean test`.
- When adding new Swift source files, regenerate the project with `xcodegen generate` before assuming the checked-in Xcode project will pick them up.

## Expansion Priorities

The highest-value areas for additional coverage remain:

1. Launch and crash safety around startup loading, AI decoding, and permission-gated flows.
2. Persistence integrity for SwiftData encode/decode edge cases and relationship hydration.
3. Kitchen workflows such as pantry matching, meal-plan-to-shopping generation, and prepared-dish lifecycle behavior.
4. AI contract validation for malformed or underspecified structured outputs.
5. UI flows beyond smoke coverage, especially intake, shopping review, and favorite/discover behavior.
