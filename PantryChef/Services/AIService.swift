import Foundation

final class AIService: AIServiceProtocol {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4o"

    init(apiKey: String = AppConfig.openAIAPIKey) {
        self.apiKey = apiKey
    }

    // MARK: - Core Feature 1: What to Buy

    func generateShoppingList(recipe: Recipe, pantry: [PantryItem]) async -> [ShoppingItem] {
        let pantryDescription = pantry.map { "\($0.name) (\($0.displayQuantity))" }.joined(separator: ", ")
        let ingredientList = recipe.ingredients.map { $0.displayText }.joined(separator: "\n")

        let prompt = """
        I want to cook: \(recipe.title)

        Required ingredients:
        \(ingredientList)

        I currently have in my pantry:
        \(pantryDescription)

        Return a JSON array of items I need to buy. Each item should have:
        - "name": string
        - "quantity": number (optional)
        - "unit": string (optional)
        - "category": string (one of: Dairy, Produce, Protein, Grains & Cereals, Spices & Herbs, Condiments & Sauces, Baking Supplies, Frozen Foods, Canned & Jarred, Beverages, Oils & Fats, Pasta & Noodles, Nuts & Seeds, Other)

        Only include items I genuinely need to buy. If I have an ingredient, skip it. Return ONLY the JSON array, no other text.
        """

        guard let response = await sendChatRequest(prompt: prompt) else { return [] }
        return parseShoppingItems(from: response)
    }

    // MARK: - Core Feature 2: What Can I Make

    func suggestRecipes(pantry: [PantryItem]) async -> [Recipe] {
        let pantryDescription = pantry.map { item in
            var desc = item.name
            if let qty = item.quantity, let unit = item.unit {
                desc += " (\(qty) \(unit.rawValue))"
            }
            if let days = item.daysUntilExpiry {
                desc += " [expires in \(days) days]"
            }
            return desc
        }.joined(separator: "\n")

        let prompt = """
        Based on these pantry ingredients, suggest 5 recipes I can make. Prioritize recipes that use ingredients expiring soon.

        My pantry:
        \(pantryDescription)

        Return a JSON array of recipes. Each recipe should have:
        - "title": string
        - "description": string (1-2 sentences)
        - "ingredients": [{"name": string, "quantity": number, "unit": string}]
        - "steps": [{"stepNumber": number, "instruction": string, "timerMinutes": number or null, "estimatedDurationSeconds": number, "tasks": [task]}]
        - "servings": number
        - "prepTimeMinutes": number
        - "cookTimeMinutes": number
        - "difficulty": number (1-5, where 1 is easiest)
        - "dietaryTags": [string]
        - "calories": number (estimated per serving)

        Each task object: {"taskIndex": number, "action": string, "ingredient": string or null, "durationSeconds": number, "type": "active" or "passive", "effort": "easy" or "medium" or "hard", "requiresEquipment": string or null, "dependsOn": [number]}
        "taskIndex" — a unique integer starting at 0, incrementing across ALL steps in the recipe (not per-step). The first task is 0, the second 1, etc.
        "dependsOn" — array of taskIndex values for tasks that MUST finish before this one can start. Use this to encode the real cooking workflow:
          • A task that uses the output of an earlier task must list that task (e.g., "sauté onion" depends on "dice onion").
          • Sequential pan/vessel use: if two cook tasks share the same pan, the later one depends on the earlier.
          • "plate"/"serve" usually depends on all cooking tasks.
          • Independent prep tasks (different ingredients, no shared vessel) have an empty dependsOn [].
        "effort" — how much active attention this task demands:
          • "easy" (1 pt) = occasional checking — boiling water, toasting bread, simmering, resting.
          • "medium" (2 pts) = periodic attention — sautéing, pan-frying, flipping.
          • "hard" (3 pts) = constant hands-on — stir-frying, tempering, making roux.
          The scheduler can run multiple tasks in parallel up to 3 effort points total.
        Valid actions: "cut_dice", "cut_mince", "cut_slice", "cut_chop", "cut_julienne", "cut_halve", "peel", "measure", "mix", "marinate", "season", "heat", "saute", "boil", "simmer", "fry_pan", "fry_deep", "fry_stir", "bake", "roast", "grill", "steam", "scramble", "plate", "garnish", "rest", "serve", "toss", or a custom string.
        Use "passive" for tasks that don't need hands (baking, boiling, resting). Use "active" otherwise.
        For estimatedDurationSeconds, provide the realistic wall-clock time for each step in seconds (including active work, waiting, and cooking). For example: "chop onion" ≈ 60, "boil water" ≈ 300, "bake for 30 minutes" = 1800.
        - "protein": number (grams per serving)
        - "carbohydrates": number (grams per serving)
        - "fat": number (grams per serving)

        Return ONLY the JSON array, no other text.
        """

        guard let response = await sendChatRequest(prompt: prompt) else { return [] }
        return parseRecipes(from: response)
    }

    // MARK: - Core Feature 3: Substitutions

    func suggestSubstitutions(recipe: Recipe, pantry: [PantryItem]) async -> [SubstitutionSuggestion] {
        let matchResult = recipe.pantryMatch(pantry: pantry)
        guard !matchResult.missingIngredients.isEmpty else { return [] }

        let missingList = matchResult.missingIngredients.map { $0.displayText }.joined(separator: "\n")
        let availableList = pantry.map { $0.name }.joined(separator: ", ")

        let prompt = """
        I'm making \(recipe.title) but I'm missing these ingredients:
        \(missingList)

        I have these ingredients available:
        \(availableList)

        Suggest substitutions using what I have. For each missing ingredient, return a JSON array of substitution objects:
        - "originalIngredient": string
        - "substituteName": string
        - "ratio": string (e.g., "1:1", "use half the amount")
        - "tasteImpact": string (how it changes the taste)
        - "textureImpact": string (how it changes the texture)
        - "nutritionImpact": string (calorie/macro differences)
        - "confidence": number (0.0 to 1.0, how good this substitution is)

        If no good substitution exists for an ingredient, still include it with confidence 0.0 and substituteName "No good substitute available".

        Return ONLY the JSON array, no other text.
        """

        guard let response = await sendChatRequest(prompt: prompt) else { return [] }
        return parseSubstitutions(from: response)
    }

    // MARK: - Make It Healthier

    func makeItHealthier(recipe: Recipe) async -> HealthierSuggestion? {
        let ingredientList = recipe.ingredients.map { $0.displayText }.joined(separator: "\n")

        let prompt = """
        Suggest ways to make this recipe healthier:

        Recipe: \(recipe.title)
        Ingredients:
        \(ingredientList)

        Return a JSON object with:
        - "suggestions": [{"change": string, "benefit": string}]
        - "estimatedCalorieReduction": number (estimated calories saved per serving)
        - "overallImpact": string (one sentence summary of health impact)

        Return ONLY the JSON object, no other text.
        """

        guard let response = await sendChatRequest(prompt: prompt) else { return nil }
        return parseHealthierSuggestion(from: response, recipeTitle: recipe.title)
    }

    // MARK: - Leftover Transformer

    func leftoverTransformer(ingredients: [String]) async -> [Recipe] {
        let ingredientList = ingredients.joined(separator: ", ")

        let prompt = """
        I have these leftovers: \(ingredientList)

        Suggest 3 creative, easy recipes I can make with these leftovers. Prioritize beginner-friendly, quick recipes.

        Return a JSON array of recipes. Each recipe should have:
        - "title": string
        - "description": string (1-2 sentences)
        - "ingredients": [{"name": string, "quantity": number, "unit": string}]
        - "steps": [{"stepNumber": number, "instruction": string, "timerMinutes": number or null, "estimatedDurationSeconds": number, "tasks": [task]}]
        - "servings": number
        - "prepTimeMinutes": number
        - "cookTimeMinutes": number
        - "difficulty": number (1-5)

        Each task object: {"taskIndex": number, "action": string, "ingredient": string or null, "durationSeconds": number, "type": "active" or "passive", "effort": "easy" or "medium" or "hard", "requiresEquipment": string or null, "dependsOn": [number]}
        "taskIndex" — a unique integer starting at 0, incrementing across ALL steps in the recipe. The first task is 0, the second 1, etc.
        "dependsOn" — array of taskIndex values for tasks that MUST finish before this one can start:
          • A task that uses the output of an earlier task depends on it (e.g., "sauté onion" depends on "dice onion").
          • Sequential pan use: if cook tasks share a pan, the later depends on the earlier.
          • "plate"/"serve" depends on all cooking tasks. Independent prep tasks have empty dependsOn [].
        "effort" — "easy" (occasional checking), "medium" (periodic attention), "hard" (constant hands-on). Scheduler runs up to 3 effort points in parallel.
        Valid actions: "cut_dice", "cut_mince", "cut_slice", "cut_chop", "peel", "measure", "mix", "season", "heat", "saute", "boil", "simmer", "fry_pan", "fry_stir", "bake", "roast", "grill", "steam", "scramble", "plate", "garnish", "rest", "serve", "toss", or a custom string.
        For estimatedDurationSeconds, provide the realistic wall-clock time for each step in seconds (including active work, waiting, and cooking).

        Return ONLY the JSON array, no other text.
        """

        guard let response = await sendChatRequest(prompt: prompt) else { return [] }
        return parseRecipes(from: response)
    }

    // MARK: - Recipe URL Import

    func parseRecipeFromURL(_ url: String) async -> RecipeImportResult? {
        let prompt = """
        Fetch and parse the recipe from this URL: \(url)

        Return a JSON object with:
        - "title": string
        - "description": string
        - "ingredients": [{"name": string, "quantity": number, "unit": string, "category": string}]
        - "steps": [{"stepNumber": number, "instruction": string, "timerMinutes": number or null, "estimatedDurationSeconds": number, "tasks": [task]}]
        - "servings": number
        - "prepTimeMinutes": number
        - "cookTimeMinutes": number
        - "dietaryTags": [string]

        Each task object: {"taskIndex": number, "action": string, "ingredient": string or null, "durationSeconds": number, "type": "active" or "passive", "effort": "easy" or "medium" or "hard", "requiresEquipment": string or null, "dependsOn": [number]}
        "taskIndex" — unique integer starting at 0, incrementing across ALL steps. "dependsOn" — taskIndex values of prerequisite tasks. "effort" — "easy"/"medium"/"hard" attention level.
        For estimatedDurationSeconds, provide the realistic wall-clock time for each step in seconds.
        For category, use one of: Dairy, Produce, Protein, Grains & Cereals, Spices & Herbs, Condiments & Sauces, Baking Supplies, Oils & Fats, Other.
        For unit, use: tsp, tbsp, cup, ml, L, g, kg, oz, lb, piece, whole, slice, clove, bunch, can, pinch.

        Return ONLY the JSON object, no other text.
        """

        guard let response = await sendChatRequest(prompt: prompt) else { return nil }
        return parseImportResult(from: response)
    }

    // MARK: - Recipe from Photo (text extracted via Vision)

    func parseRecipeFromText(_ extractedText: String) async -> RecipeImportResult? {
        let prompt = """
        The following text was extracted from a photo of a recipe (e.g., cookbook page or recipe card). Parse it into a structured recipe.

        Extracted text:
        \(extractedText)

        Return a JSON object with:
        - "title": string
        - "description": string (brief summary, generate if not present)
        - "ingredients": [{"name": string, "quantity": number, "unit": string, "category": string}]
        - "steps": [{"stepNumber": number, "instruction": string, "timerMinutes": number or null, "estimatedDurationSeconds": number, "tasks": [task]}]
        - "servings": number
        - "prepTimeMinutes": number (estimate if not stated)
        - "cookTimeMinutes": number (estimate if not stated)
        - "dietaryTags": [string] (infer from ingredients)

        Each task object: {"taskIndex": number, "action": string, "ingredient": string or null, "durationSeconds": number, "type": "active" or "passive", "effort": "easy" or "medium" or "hard", "requiresEquipment": string or null, "dependsOn": [number]}
        "taskIndex" — unique integer starting at 0, incrementing across ALL steps. "dependsOn" — taskIndex values of prerequisite tasks. "effort" — "easy"/"medium"/"hard" attention level.
        For estimatedDurationSeconds, provide the realistic wall-clock time for each step in seconds.

        Return ONLY the JSON object, no other text.
        """

        guard let response = await sendChatRequest(prompt: prompt) else { return nil }
        return parseImportResult(from: response)
    }

    // MARK: - Step Duration Estimation (legacy backfill)

    /// One-shot AI call to estimate step durations for recipes that lack them.
    /// Returns updated steps with `estimatedDurationSeconds` populated.
    func estimateStepDurations(for steps: [RecipeStep], recipeTitle: String) async -> [RecipeStep] {
        let stepDescriptions = steps.enumerated().map { idx, step in
            "Step \(step.stepNumber): \(step.instruction)" +
            (step.timerMinutes != nil ? " [Timer: \(step.timerMinutes!) min]" : "")
        }.joined(separator: "\n")

        let prompt = """
        For this recipe ("\(recipeTitle)"), estimate the realistic wall-clock duration \
        of each step in seconds. Include all active work, waiting, and cooking time.

        Steps:
        \(stepDescriptions)

        Return a JSON array where each element is:
        {"stepNumber": number, "estimatedDurationSeconds": number}

        Return ONLY the JSON array, no other text.
        """

        guard let response = await sendChatRequest(prompt: prompt) else { return steps }
        guard let data = extractJSON(from: response) else { return steps }

        do {
            let items = try JSONDecoder().decode([[String: Int]].self, from: data)
            var lookup: [Int: Int] = [:]
            for item in items {
                if let num = item["stepNumber"], let dur = item["estimatedDurationSeconds"] {
                    lookup[num] = dur
                }
            }
            return steps.map { step in
                var updated = step
                if updated.estimatedDurationSeconds == nil, let dur = lookup[step.stepNumber] {
                    updated.estimatedDurationSeconds = dur
                }
                return updated
            }
        } catch {
            print("[AIService] Failed to parse step durations: \(error)")
            return steps
        }
    }

    // MARK: - Networking (with retry)

    /// Maximum number of retry attempts for transient failures.
    private let maxRetries = 3

    /// Sends a prompt to OpenAI with automatic retry + exponential backoff.
    /// Retries on network errors and 5xx / 429 responses. Gives up on 4xx client errors.
    private func sendChatRequest(prompt: String) async -> String? {
        guard let url = URL(string: baseURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a helpful kitchen and cooking assistant. Always return valid JSON when asked for structured data."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 4096
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    // Success
                    if httpResponse.statusCode == 200 {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = json["choices"] as? [[String: Any]],
                           let firstChoice = choices.first,
                           let message = firstChoice["message"] as? [String: Any],
                           let content = message["content"] as? String {
                            return content
                        }
                        return nil // valid 200 but unexpected shape — don't retry
                    }

                    // Rate limited or server error — retryable
                    if httpResponse.statusCode == 429 || httpResponse.statusCode >= 500 {
                        if attempt < maxRetries {
                            let delay = Double(attempt) * 1.5 // 1.5s, 3s
                            try await Task.sleep(for: .seconds(delay))
                            continue
                        }
                        return nil
                    }

                    // 4xx client error (bad key, etc.) — not retryable
                    return nil
                }
            } catch {
                // Network error — retry with backoff
                if attempt < maxRetries {
                    let delay = Double(attempt) * 1.5
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }
                print("AI Service Error after \(maxRetries) attempts: \(error.localizedDescription)")
            }
        }

        return nil
    }

    // MARK: - Response Parsing

    private func parseShoppingItems(from response: String) -> [ShoppingItem] {
        guard let data = extractJSON(from: response) else { return [] }
        do {
            let items = try JSONDecoder().decode([[String: AnyCodable]].self, from: data)
            return items.compactMap { dict in
                guard let name = dict["name"]?.value as? String else { return nil }
                let quantity = dict["quantity"]?.value as? Double
                let unitStr = dict["unit"]?.value as? String
                let categoryStr = dict["category"]?.value as? String
                let unit = MeasurementUnit.allCases.first { $0.rawValue == unitStr }
                let category = FoodCategory.allCases.first { $0.rawValue == categoryStr } ?? .other
                return ShoppingItem(name: name, quantity: quantity, unit: unit, category: category)
            }
        } catch {
            return []
        }
    }

    private func parseRecipes(from response: String) -> [Recipe] {
        guard let data = extractJSON(from: response) else { return [] }
        do {
            let items = try JSONDecoder().decode([[String: AnyCodable]].self, from: data)
            return items.compactMap { dict -> Recipe? in
                guard let title = dict["title"]?.value as? String else { return nil }
                let description = dict["description"]?.value as? String
                let servings = dict["servings"]?.value as? Int ?? 4
                let prepTime = dict["prepTimeMinutes"]?.value as? Int
                let cookTime = dict["cookTimeMinutes"]?.value as? Int
                let difficultyRaw = dict["difficulty"]?.value as? Int ?? 2
                let difficulty = DifficultyLevel(rawValue: difficultyRaw) ?? .easy

                let ingredients: [Ingredient] = (dict["ingredients"]?.value as? [[String: Any]])?.compactMap { ing in
                    guard let name = ing["name"] as? String else { return nil }
                    let qty = (ing["quantity"] as? Double) ?? (ing["quantity"] as? Int).map { Double($0) } ?? 1
                    let unitStr = ing["unit"] as? String
                    let unit = MeasurementUnit.allCases.first { $0.rawValue == unitStr }
                    return Ingredient(name: name, quantity: qty, unit: unit)
                } ?? []

                // --- Two-pass task parsing: create tasks, then resolve dependsOn indices → UUIDs ---
                // Pass 1: parse all tasks across all steps, assign stable UUIDs, record taskIndex → UUID
                var indexToUUID: [Int: UUID] = [:]
                var rawDepsMap: [UUID: [Int]] = [:]   // taskId → raw dependsOn indices

                var parsedSteps: [(instruction: String, num: Int, timer: Int?, estDuration: Int?, taskDicts: [[String: Any]])] = []
                if let stepDicts = dict["steps"]?.value as? [[String: Any]] {
                    for step in stepDicts {
                        guard let instruction = step["instruction"] as? String else { continue }
                        let num = (step["stepNumber"] as? Int) ?? 1
                        let timer = step["timerMinutes"] as? Int
                        let estDuration = step["estimatedDurationSeconds"] as? Int
                        let taskDicts = (step["tasks"] as? [[String: Any]]) ?? []
                        parsedSteps.append((instruction, num, timer, estDuration, taskDicts))

                        for taskDict in taskDicts {
                            let idx = taskDict["taskIndex"] as? Int
                            let taskId = UUID()
                            if let idx { indexToUUID[idx] = taskId }
                            let rawDeps = (taskDict["dependsOn"] as? [Int]) ?? []
                            rawDepsMap[taskId] = rawDeps
                        }
                    }
                }

                // Pass 2: build RecipeSteps with resolved dependsOn UUIDs
                var taskDictCursor = 0
                let allTaskDicts = parsedSteps.flatMap(\.taskDicts)
                let sortedIndices = allTaskDicts.compactMap { $0["taskIndex"] as? Int }.sorted()

                let steps: [RecipeStep] = parsedSteps.map { info in
                    let tasks: [StepTask] = info.taskDicts.compactMap { taskDict in
                        guard let actionStr = taskDict["action"] as? String else { return nil }
                        let action = Self.parseAction(actionStr)
                        let ingredient = taskDict["ingredient"] as? String
                        let duration = (taskDict["durationSeconds"] as? Int) ?? 60
                        let typeStr = taskDict["type"] as? String ?? "active"
                        let type: TaskType = typeStr == "passive" ? .passive : .active
                        let effortStr = taskDict["effort"] as? String ?? "medium"
                        let effort = EffortLevel(from: effortStr)
                        let equipment = taskDict["requiresEquipment"] as? String

                        let idx = taskDict["taskIndex"] as? Int
                        let taskId = idx.flatMap { indexToUUID[$0] } ?? UUID()
                        let rawDeps = rawDepsMap[taskId] ?? []
                        let resolvedDeps = rawDeps.compactMap { indexToUUID[$0] }

                        return StepTask(id: taskId, action: action, ingredient: ingredient, durationSeconds: duration, type: type, requiresEquipment: equipment, effort: effort, dependsOn: resolvedDeps)
                    }
                    return RecipeStep(stepNumber: info.num, instruction: info.instruction, timerMinutes: info.timer, estimatedDurationSeconds: info.estDuration, tasks: tasks)
                }

                var nutrition: NutritionInfo?
                if let cal = dict["calories"]?.value as? Int {
                    nutrition = NutritionInfo(
                        calories: cal,
                        protein: (dict["protein"]?.value as? Double) ?? 0,
                        carbohydrates: (dict["carbohydrates"]?.value as? Double) ?? 0,
                        fat: (dict["fat"]?.value as? Double) ?? 0
                    )
                }

                return Recipe(
                    title: title,
                    description: description,
                    ingredients: ingredients,
                    steps: steps,
                    servings: servings,
                    prepTimeMinutes: prepTime,
                    cookTimeMinutes: cookTime,
                    difficulty: difficulty,
                    nutrition: nutrition
                )
            }
        } catch {
            return []
        }
    }

    private func parseSubstitutions(from response: String) -> [SubstitutionSuggestion] {
        guard let data = extractJSON(from: response) else { return [] }
        do {
            return try JSONDecoder().decode([SubstitutionSuggestion].self, from: data)
        } catch {
            return []
        }
    }

    private func parseHealthierSuggestion(from response: String, recipeTitle: String) -> HealthierSuggestion? {
        guard let data = extractJSON(from: response) else { return nil }
        do {
            struct ParsedResponse: Codable {
                let suggestions: [HealthTweak]
                let estimatedCalorieReduction: Int?
                let overallImpact: String
            }
            let parsed = try JSONDecoder().decode(ParsedResponse.self, from: data)
            return HealthierSuggestion(
                originalRecipeTitle: recipeTitle,
                suggestions: parsed.suggestions,
                estimatedCalorieReduction: parsed.estimatedCalorieReduction,
                overallImpact: parsed.overallImpact
            )
        } catch {
            return nil
        }
    }

    private func parseImportResult(from response: String) -> RecipeImportResult? {
        guard let data = extractJSON(from: response) else { return nil }
        do {
            return try JSONDecoder().decode(RecipeImportResult.self, from: data)
        } catch {
            return nil
        }
    }

    private func extractJSON(from text: String) -> Data? {
        // Try to extract JSON from markdown code blocks or raw JSON
        var jsonString = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code block markers
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        return jsonString.data(using: .utf8)
    }
}

// MARK: - AnyCodable Helper

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int: try container.encode(intValue)
        case let doubleValue as Double: try container.encode(doubleValue)
        case let stringValue as String: try container.encode(stringValue)
        case let boolValue as Bool: try container.encode(boolValue)
        default: try container.encodeNil()
        }
    }
}

// MARK: - Action String Parsing Helper
extension AIService {
    /// Parse an action string from AI response into a CookingAction.
    static func parseAction(_ str: String) -> CookingAction {
        let lower = str.lowercased().trimmingCharacters(in: .whitespaces)
        switch lower {
        case "cut_dice": return .cut(.dice)
        case "cut_mince": return .cut(.mince)
        case "cut_slice": return .cut(.slice)
        case "cut_chop": return .cut(.chop)
        case "cut_julienne": return .cut(.julienne)
        case "cut_halve": return .cut(.halve)
        case "cut_rough": return .cut(.rough)
        case "peel": return .peel
        case "measure": return .measure
        case "mix": return .mix
        case "marinate": return .marinate
        case "season": return .season
        case "heat": return .heat
        case "saute", "sauté": return .saute
        case "boil": return .boil
        case "simmer": return .simmer
        case "fry_pan": return .fry(.pan)
        case "fry_deep": return .fry(.deep)
        case "fry_stir": return .fry(.stir)
        case "bake": return .bake
        case "roast": return .roast
        case "grill": return .grill
        case "steam": return .steam
        case "scramble": return .scramble
        case "plate": return .plate
        case "garnish": return .garnish
        case "rest": return .rest
        case "serve": return .serve
        case "toss": return .toss
        default: return .other(str)
        }
    }
}
