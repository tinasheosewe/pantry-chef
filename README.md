# Pantry Chef 🍳

A personal iOS kitchen management app powered by AI. Tells you what to buy, what you can cook, and how to substitute missing ingredients.

## Features

### Core
- **What to Buy** — Given a recipe + your pantry, generates a precise shopping list
- **What Can I Make** — Suggests recipes based on what's in your pantry (ranked by match %)
- **Smart Substitutions** — AI-powered ingredient substitution suggestions with confidence ratings

### Pantry Management
- Add items manually, by barcode scan (Open Food Facts), or receipt OCR
- Expiry date tracking with visual warnings
- Organized by food category with search & filters

### Recipes
- Full recipe management with difficulty ratings, nutrition, and dietary tags
- Import recipes from URLs or cookbook photos (OCR)
- Recipe scaling (adjust servings)
- Pantry match percentage on every recipe

### Cook Mode
- Full-screen step-by-step guided cooking
- Built-in timers per step
- Voice readout (Apple TTS) and voice commands ("next", "repeat", "start timer")
- Dark UI optimized for kitchen use

### Meal Planning
- Weekly calendar with breakfast/lunch/dinner slots
- Auto-generate shopping lists from your meal plan

### AI Assistant
- Floating chat button for natural language queries
- Quick actions: "What can I make?", "Use up expiring items", "Easy dinner ideas"
- Leftover transformer, healthier recipe suggestions

## Tech Stack

- **Platform**: iOS 17.0+, Swift 5.9, SwiftUI
- **Architecture**: MVVM with centralized AppState
- **Storage**: In-memory (with sample data preloaded). Supabase-ready service layer included for future cloud migration.
- **AI**: OpenAI GPT-4o
- **Speech**: Apple AVSpeechSynthesizer + SFSpeechRecognizer
- **OCR**: Apple Vision framework
- **Barcode**: Open Food Facts API

## Setup

### Prerequisites
- macOS with Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An [OpenAI](https://platform.openai.com) API key (optional — only needed for AI features)

### 1. Clone & Generate Project
```bash
cd PantryChef
xcodegen generate
open PantryChef.xcodeproj
```

### 2. Configure API Keys (optional)
Edit `PantryChef/Utils/AppConfig.swift` and replace the placeholder OpenAI key to enable AI features:
```swift
static let openAIAPIKey = "YOUR-OPENAI-API-KEY"
```

### 3. Build & Run
Select your target device/simulator in Xcode and hit ⌘R. The app launches with sample pantry items and recipes preloaded — no backend setup required.

### Future: Migrating to Supabase
The service layer (`StorageService.swift`) is designed for a seamless swap to cloud storage:
1. Add the `supabase-swift` package dependency back to `project.yml`
2. Replace the in-memory implementation with the Supabase client calls
3. Run `Supabase/migrations/001_initial_schema.sql` in your Supabase SQL Editor
4. Add your Supabase URL and anon key to `AppConfig.swift`

## Project Structure

```
PantryChef/
├── project.yml                    # XcodeGen project spec
├── PantryChef/
│   ├── App/
│   │   ├── PantryChefApp.swift    # App entry point
│   │   ├── AppState.swift         # Central state manager
│   │   └── ContentView.swift      # Tab bar + floating AI button
│   ├── Models/
│   │   ├── Enums.swift            # FoodCategory, Units, Tags, etc.
│   │   ├── PantryItem.swift       # Pantry item model
│   │   ├── Recipe.swift           # Recipe + Ingredient + Step models
│   │   ├── MealPlan.swift         # Meal plan entry model
│   │   ├── ShoppingItem.swift     # Shopping list item model
│   │   └── AIModels.swift         # AI response models
│   ├── Services/
│   │   ├── StorageService.swift   # In-memory storage (Supabase-ready)
│   │   ├── AIService.swift        # OpenAI API integration
│   │   ├── SpeechService.swift    # TTS + voice recognition
│   │   └── ScannerService.swift   # Barcode + receipt OCR
│   ├── ViewModels/
│   │   ├── HomeViewModel.swift
│   │   ├── PantryViewModel.swift
│   │   ├── RecipeViewModel.swift
│   │   ├── CookModeViewModel.swift
│   │   ├── MealPlanViewModel.swift
│   │   ├── ShoppingViewModel.swift
│   │   └── AIAssistantViewModel.swift
│   ├── Views/
│   │   ├── Common/Components.swift
│   │   ├── Home/HomeView.swift
│   │   ├── Pantry/PantryView.swift
│   │   ├── Recipes/RecipeListView.swift
│   │   ├── Recipes/RecipeDetailView.swift
│   │   ├── CookMode/CookModeView.swift
│   │   ├── MealPlan/MealPlanView.swift
│   │   ├── Shopping/ShoppingListView.swift
│   │   └── AI/AIAssistantView.swift
│   └── Utils/
│       ├── AppConfig.swift        # API keys & settings
│       └── Extensions.swift       # Date, String, View helpers
└── Supabase/
    └── migrations/
        └── 001_initial_schema.sql # Database schema
```

## Notes

- **In-Memory Storage** — Data resets on app relaunch. Supabase migration path included in `Supabase/migrations/`.
- **No Authentication** — Designed for personal use. Add Supabase Auth + RLS policies before sharing.
- **Light Mode Only** — Dark mode support planned for v2.
- **Barcode Scanner** — Uses the camera; requires a physical device (not simulator).
- **Voice Commands** — Requires microphone permission; works best in quiet environments.

## License

Personal project. Not licensed for distribution.
