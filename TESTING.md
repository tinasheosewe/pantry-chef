# Testing

## What exists

- `PantryChefTests`: 242 XCTest functions in 28 files. They run inside the app on a simulator and need no network and no API key. They cover the pure engines, the store, the mapping from an AI response to a `Dish`, telemetry formatting, and the bundled data (catalog invariants, recipe-to-catalog consistency, plate-art coverage).
- `PantryChefUITests`: two UI tests. `testLaunchAndNavigateSpaces` launches the app and visits the three spaces. `testOurActionIsOfferedInSafariShareSheet` drives Safari's share sheet to check that "Save to PantryChef" is offered; it needs network access to load `example.com` and is sensitive to changes in Safari's interface.

No scheme file is tracked. `PantryChef` is the scheme Xcode creates automatically for the app target, and its test action covers both test targets (`xcodebuild -list -project PantryChef.xcodeproj` shows it).

## Running the tests

From Xcode: open `PantryChef.xcodeproj`, choose the `PantryChef` scheme and an iPhone simulator, then Product > Test.

From the command line, substituting a simulator installed on your machine:

```bash
xcodebuild test \
  -project PantryChef.xcodeproj \
  -scheme PantryChef \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PantryChefTests
```

Use `-only-testing:PantryChefUITests` for the UI tests.

The first build resolves the `sentry-cocoa` package (pinned in `Package.resolved`), whose prebuilt frameworks take about 2 GB of disk.

## The quality script and CI

```bash
bash Scripts/ci/run_quality.sh
```

The script builds the checked-in project directly (nothing is generated) and:

- picks an available iPhone simulator on the newest iOS runtime the selected Xcode can target;
- runs `PantryChefTests` with code coverage into a fresh `.artifacts/DerivedData`, writing `.artifacts/test-results/unit.xcresult`;
- fails if line coverage of `PantryChef.app` is below the floor (see below);
- with `RUN_UI_TESTS=1`, runs `PantryChefUITests` afterwards.

It shuts down running simulators before each test run. Overrides: `SIMULATOR_ID` or `SIMULATOR_NAME`, `SCHEME`, `PROJECT`, `RESULTS_DIR`, `DERIVED_DATA_PATH`, `SOURCE_PACKAGES_DIR` (an existing SwiftPM checkout directory to reuse instead of downloading the packages again), `COVERAGE_TARGET`, `COVERAGE_MINIMUM`. Arguments given to the script are passed on to `xcodebuild`.

`.github/workflows/ios-quality.yml` runs the same script on a `macos-26` GitHub runner for every push to `main`, every pull request and on manual dispatch. It selects Xcode 26.3, the version the app is developed with, when the runner image carries it, and uploads the result bundle as an artifact. The UI tests are left out of CI because the share-sheet test depends on Safari's interface.

## Coverage gate

The floor is 18% line coverage of the `PantryChef.app` target, measured from the unit-test run. It is a ratchet against regressions, set just under the 19.1% measured in CI: the unit tests cover the engines, the store and the bundled data, while most lines of the app target are SwiftUI views. To apply it to an existing result bundle:

```bash
python3 Scripts/ci/check_coverage.py .artifacts/test-results/unit.xcresult --target PantryChef.app --minimum 18
```

The threshold is intentionally conservative. Raise it only when the suite meaningfully expands.

## Share extension check

```bash
tools/verify_share_extension.sh
```

Builds the app, installs it on the booted simulator (or the one named by `PC_SIM_UDID`), launches it, and checks with `pluginkit` that the system has registered the extension under the name "Save to PantryChef". It is the deterministic companion to the Safari UI test. Arguments are passed on to `xcodebuild`.

## Manual checks

Run these before a release or after a broad refactor:

1. Cold launch and relaunch: confirm both reach Today without a stuck loading screen. On a clean install, confirm onboarding appears and that "Explore a sample kitchen first" loads the demo kitchen.
2. Pantry: add an item from the + bar (try `300 g spinach, fridge`), edit it, move it between pantry, fridge and freezer, and remove another. Quit and relaunch, and confirm the changes are still there.
3. Shopping: add an item to the list, run a shop, check it off with an amount, and confirm it lands in stock.
4. Today: open a recipe, scale the servings, apply a substitution, add the missing ingredients to the list.
5. Cook mode: start a cook, start a step timer, background the app and wait for the notification, come back and finish. Confirm the dish appears under leftovers.
6. Cook together: select two dishes and check that the merged step list puts prep first.
7. Plan: plan a meal for tomorrow, move it to another part of the day, change its servings, remove it.
8. No-key mode: with `OPENAI_API_KEY` unset, confirm the import, generate, healthier and tweak actions report that they could not run and that everything else still works.
9. With a key: import a recipe from a link and from pasted text, and confirm both open in the editor for review.
10. On a device: scan a barcode, and share a recipe link from Safari to "Save to PantryChef".

## Notes

- If Xcode appears to run stale test code after source changes, run `xcodebuild clean test` with the same arguments.
- When adding Swift files, register them in the checked-in project, in Xcode or with `ruby tools/xcadd.rb <path>`.
