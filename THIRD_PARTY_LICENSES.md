# Third-Party Dependencies And Data Notes

This repository currently uses a small number of third-party code dependencies, but it does not ship third-party pantry, substitution, receipt, or food-catalog datasets in the app bundle.

## Runtime And Source Dependencies

- `sentry-cocoa`
  - Purpose: optional crash reporting and telemetry forwarding.
  - Integration: Swift Package Manager dependency declared in `project.yml`.
  - Runtime behavior: inactive unless `SENTRY_DSN` is configured.

- `swift-realtime-openai`
  - Purpose: OpenAI Realtime API transport for conversational cook mode.
  - Integration: vendored package under `Vendor/swift-realtime-openai`.
  - Local modifications: documented in `Vendor/swift-realtime-openai/PantryChefForkNotes.md`.

## Bundled Data Status

- No third-party substitution dataset is bundled.
- No third-party grocery catalog, barcode database, receipt corpus, or OCR dataset is bundled.
- Research notes may reference external sources such as Open Food Facts or USDA FoodData Central, but those sources are not packaged into the current app build.

## License Sources

- Vendored realtime package license: `Vendor/swift-realtime-openai/LICENSE`
- Sentry license: see the upstream `getsentry/sentry-cocoa` repository for the package license shipped by Swift Package Manager

If additional third-party datasets or bundled assets are introduced later, record them here with their source, license, and shipping status.
