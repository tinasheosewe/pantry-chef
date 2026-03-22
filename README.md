# PantryChef

PantryChef is an iOS cooking and kitchen-planning app built with SwiftUI. It combines pantry tracking, recipe management, meal planning, shopping generation, and AI-assisted cook mode in a local-first app.

## What The App Does

- Track pantry items with quantities, categories, and expiry-aware sorting.
- Manage personal recipes alongside bundled and discovered recipes.
- Filter recipes by pantry match, favorites, meal type, cuisine, difficulty, and dietary tags.
- Build meal plans and turn them into consolidated shopping lists.
- Run a guided cook mode with step navigation, timers, notifications, and resume support.
- Use OpenAI-backed helpers for shopping lists, recipe suggestions, healthier variants, leftovers, and conversational cook assistance.
- Search for discover recipes through Spoonacular when an API key is configured.

## Current Product Shape

This repository is currently centered on the manual-entry and local-persistence experience.

- Core app data is stored locally with SwiftData.
- The app boots with sample pantry items and recipes to make simulator testing easy.
- AI and network-backed features are optional and degrade gracefully when keys are not configured.
- Pantry intake OCR and barcode workflows are being researched, but they are not the primary shipped flow today.

## Stack

- Platform: iOS 17.0+
- Language: Swift 5.9
- UI: SwiftUI
- Project generation: XcodeGen
- Persistence: SwiftData
- AI: OpenAI Chat Completions plus OpenAI Realtime API
- External recipe discovery: Spoonacular
- Realtime voice transport: vendored swift-realtime-openai package in Vendor/

## Setup

### Prerequisites

- macOS with Xcode 15 or newer
- XcodeGen
- An OpenAI API key for AI features
- Optionally, a Spoonacular API key for discover search

Install XcodeGen if needed:

```bash
brew install xcodegen
```

### 1. Generate The Xcode Project

```bash
cd PantryChef
xcodegen generate
open PantryChef.xcodeproj
```

### 2. Configure Secrets

The project loads Config/Secrets.xcconfig, which includes Config/LocalSecrets.xcconfig for developer-local values.

Set these values in Config/LocalSecrets.xcconfig or in your environment:

- OPENAI_API_KEY
- SPOONACULAR_API_KEY

AppConfig reads environment variables first, then Info.plist values.

### 3. Build And Run

Open the PantryChef scheme in Xcode and run on an iOS 17 simulator or device.

On first launch, the app seeds local sample data so the main flows are usable without backend setup.

## Testing

Run the current quality gate:

```bash
bash Scripts/ci/run_quality.sh
```

This script runs unit tests and UI smoke tests separately, then applies the coverage gate.

See TESTING.md for:

- direct xcodebuild commands
- coverage enforcement
- performance budgets
- snapshot baseline workflow
- exploratory release checks

## Repository Map

```text
PantryChef/
├── project.yml
├── README.md
├── TESTING.md
├── Config/
│   ├── Secrets.xcconfig
│   └── LocalSecrets.xcconfig
├── Documentation/
│   ├── OCR_NOTES.md
│   └── PANTRY_INTAKE_NOTES.md
├── PantryChef/
│   ├── App/                # app entry, shared app state, root tab shell
│   ├── Helpers/            # ingredient and audio-related helpers
│   ├── Models/             # pantry, recipe, planning, AI, and intake models
│   ├── Resources/          # bundled seed data
│   ├── Services/           # storage, AI, realtime, notifications, discovery
│   ├── Utils/              # config, extensions, launch options
│   ├── ViewModels/         # feature state and presentation logic
│   └── Views/              # SwiftUI screens and shared components
├── PantryChefTests/
├── PantryChefUITests/
├── Scripts/
│   └── ci/
├── Supabase/
│   └── migrations/
└── Vendor/
    └── swift-realtime-openai/
```

## Notes

- The current storage path is local-first SwiftData, not Supabase.
- Supabase migrations are present for future backend work, but the app does not require a backend to run.
- Realtime cook mode requires microphone permission and an OpenAI key.
- Spoonacular-backed discovery requires SPOONACULAR_API_KEY.

## Related Docs

- TESTING.md
- Documentation/PANTRY_INTAKE_NOTES.md
- Documentation/OCR_NOTES.md

## License

Personal project. Not licensed for distribution.
