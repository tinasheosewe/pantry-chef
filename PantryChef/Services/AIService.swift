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

        Only include items I genuinely need to buy. If I have an ingredient, skip it.
        """

        guard let response = await sendChatRequest(
            prompt: prompt,
            responseFormat: ["type": "json_schema", "json_schema": Self.shoppingListSchema]
        ) else { return [] }

        guard let data = response.data(using: .utf8) else { return [] }
        do {
            let raw = try JSONDecoder().decode(RawShoppingList.self, from: data)
            return raw.items.map { $0.toShoppingItem() }
        } catch {
            AppLog.warn("[AIService] Failed to decode shopping list: \(error)")
            return []
        }
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

        Return ONLY the JSON object with a "recipes" array.
        """

        guard let response = await sendChatRequest(
            prompt: prompt,
            responseFormat: ["type": "json_schema", "json_schema": Self.recipeArraySchema]
        ) else { return [] }

        guard let data = response.data(using: .utf8) else { return [] }
        do {
            let raw = try JSONDecoder().decode(RawRecipeArray.self, from: data)
            return raw.recipes.map { $0.toRecipe(source: .aiGenerated) }
        } catch {
            AppLog.warn("[AIService] Failed to decode suggested recipes: \(error)")
            return []
        }
    }

    // MARK: - Core Feature 3: Substitutions

    func suggestSubstitutions(recipe: Recipe, pantry: [PantryItem]) async -> [SubstitutionSuggestion] {
        let matchResult = recipe.pantryMatch(pantry: pantry)
        guard !matchResult.missingIngredients.isEmpty else { return [] }

        // Try local SubstitutionRepository first (pantry-aware ranking, top 3)
        var localSuggestions: [SubstitutionSuggestion] = []
        var unresolvedIngredients: [Ingredient] = []

        for ingredient in matchResult.missingIngredients {
            let subs = SubstitutionRepository.shared.substitutions(for: ingredient.name, pantry: pantry)
            let top3 = Array(subs.prefix(3))
            if top3.isEmpty {
                unresolvedIngredients.append(ingredient)
            } else {
                for sub in top3 {
                    let worstOrdinal: Int
                    if let taste = sub.tasteImpact, let texture = sub.textureImpact {
                        worstOrdinal = max(taste.ordinal, texture.ordinal)
                    } else {
                        worstOrdinal = 1 // default for unenriched
                    }
                    localSuggestions.append(SubstitutionSuggestion(
                        originalIngredient: ingredient.name,
                        substituteName: sub.substitute,
                        ratio: sub.ratio ?? "Ratio not available",
                        tasteImpact: sub.tasteImpact?.rawValue ?? "Unknown",
                        textureImpact: sub.textureImpact?.rawValue ?? "Unknown",
                        nutritionImpact: sub.nutritionImpact ?? "Similar",
                        confidence: sub.inPantry ? 0.95 : (sub.enriched ? (worstOrdinal == 0 ? 0.9 : worstOrdinal == 1 ? 0.75 : 0.55) : 0.5),
                        inPantry: sub.inPantry,
                        enriched: sub.enriched
                    ))
                }
            }
        }

        // If all resolved locally, skip AI
        if unresolvedIngredients.isEmpty {
            return localSuggestions
        }

        // AI fallback for unresolved ingredients only
        let missingList = unresolvedIngredients.map { $0.displayText }.joined(separator: "\n")
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
        """

        guard let response = await sendChatRequest(
            prompt: prompt,
            responseFormat: ["type": "json_schema", "json_schema": Self.substitutionsSchema]
        ) else { return localSuggestions }

        guard let data = response.data(using: .utf8) else { return localSuggestions }
        do {
            let raw = try JSONDecoder().decode(RawSubstitutionList.self, from: data)
            return localSuggestions + raw.substitutions.map { $0.toSubstitutionSuggestion() }
        } catch {
            AppLog.warn("[AIService] Failed to decode substitutions: \(error)")
            return localSuggestions
        }
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
        """

        guard let response = await sendChatRequest(
            prompt: prompt,
            responseFormat: ["type": "json_schema", "json_schema": Self.healthierSchema]
        ) else { return nil }

        guard let data = response.data(using: .utf8) else { return nil }
        do {
            let raw = try JSONDecoder().decode(RawHealthierResult.self, from: data)
            return raw.toHealthierSuggestion(recipeTitle: recipe.title)
        } catch {
            AppLog.warn("[AIService] Failed to decode healthier suggestion: \(error)")
            return nil
        }
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

        Return ONLY the JSON object with a "recipes" array.
        """

        guard let response = await sendChatRequest(
            prompt: prompt,
            responseFormat: ["type": "json_schema", "json_schema": Self.recipeArraySchema]
        ) else { return [] }

        guard let data = response.data(using: .utf8) else { return [] }
        do {
            let raw = try JSONDecoder().decode(RawRecipeArray.self, from: data)
            return raw.recipes.map { $0.toRecipe(source: .aiGenerated) }
        } catch {
            AppLog.warn("[AIService] Failed to decode leftover recipes: \(error)")
            return []
        }
    }

    // MARK: - Recipe URL Import

    func parseRecipeFromURL(_ url: String) async -> RecipeImportResult? {
        // Fetch the webpage HTML ourselves — the LLM cannot browse the internet
        guard let pageURL = URL(string: url) else { return nil }

        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 15
        // Desktop Chrome UA — many recipe sites block mobile UAs
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200...399).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            return nil
        }

        // 1) Try JSON-LD first — most recipe sites embed structured data
        if let ldText = extractRecipeFromJSONLD(html) {
            return await parseRecipeFromText(ldText)
        }

        // 2) Fall back to full-page text extraction
        let text = stripHTML(html)
        let trimmed = String(text.prefix(12_000))
        guard !trimmed.isEmpty else { return nil }

        return await parseRecipeFromText(trimmed)
    }

    /// Extract recipe info from JSON-LD `<script type="application/ld+json">` blocks.
    /// Most recipe websites embed structured Schema.org Recipe data this way.
    private func extractRecipeFromJSONLD(_ html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        for match in matches {
            guard let contentRange = Range(match.range(at: 1), in: html) else { continue }
            let jsonStr = String(html[contentRange])
            guard let data = jsonStr.data(using: .utf8) else { continue }

            guard let parsed = try? JSONSerialization.jsonObject(with: data) else { continue }

            // Find the Recipe object — could be top-level, in an array, or in @graph
            if let recipe = findRecipeObject(in: parsed) {
                return formatRecipeJSONLD(recipe)
            }
        }
        return nil
    }

    /// Recursively find a dict with `@type` == "Recipe" in parsed JSON-LD.
    private func findRecipeObject(in obj: Any) -> [String: Any]? {
        if let dict = obj as? [String: Any] {
            let typeValue = dict["@type"]
            let isRecipe: Bool
            if let typeStr = typeValue as? String {
                isRecipe = typeStr == "Recipe"
            } else if let typeArr = typeValue as? [String] {
                isRecipe = typeArr.contains("Recipe")
            } else {
                isRecipe = false
            }
            if isRecipe { return dict }

            // Check @graph
            if let graph = dict["@graph"] as? [Any] {
                for item in graph {
                    if let found = findRecipeObject(in: item) { return found }
                }
            }
        } else if let array = obj as? [Any] {
            for item in array {
                if let found = findRecipeObject(in: item) { return found }
            }
        }
        return nil
    }

    /// Convert a JSON-LD Recipe dict into clean text the LLM can parse.
    private func formatRecipeJSONLD(_ recipe: [String: Any]) -> String {
        var parts: [String] = []

        if let name = recipe["name"] as? String {
            parts.append(name)
        }
        if let desc = recipe["description"] as? String {
            parts.append(desc)
        }

        // Yield & servings
        if let yield_ = recipe["recipeYield"] {
            if let arr = yield_ as? [String], let first = arr.first {
                parts.append("Servings: \(first)")
            } else if let str = yield_ as? String {
                parts.append("Servings: \(str)")
            }
        }

        // Times
        if let prep = recipe["prepTime"] as? String { parts.append("Prep time: \(prep)") }
        if let cook = recipe["cookTime"] as? String { parts.append("Cook time: \(cook)") }
        if let total = recipe["totalTime"] as? String { parts.append("Total time: \(total)") }

        // Ingredients
        if let ingredients = recipe["recipeIngredient"] as? [String] {
            parts.append("\nIngredients:")
            for ing in ingredients {
                parts.append("- \(ing)")
            }
        }

        // Instructions
        if let instructions = recipe["recipeInstructions"] {
            parts.append("\nInstructions:")
            if let steps = instructions as? [[String: Any]] {
                for (i, step) in steps.enumerated() {
                    let text = step["text"] as? String ?? step["name"] as? String ?? ""
                    parts.append("\(i + 1). \(text)")
                }
            } else if let steps = instructions as? [String] {
                for (i, step) in steps.enumerated() {
                    parts.append("\(i + 1). \(step)")
                }
            } else if let text = instructions as? String {
                parts.append(text)
            }
        }

        // Dietary info / categories
        if let category = recipe["recipeCategory"] {
            if let arr = category as? [String] {
                parts.append("Category: \(arr.joined(separator: ", "))")
            } else if let str = category as? String {
                parts.append("Category: \(str)")
            }
        }
        if let cuisine = recipe["recipeCuisine"] {
            if let arr = cuisine as? [String] {
                parts.append("Cuisine: \(arr.joined(separator: ", "))")
            } else if let str = cuisine as? String {
                parts.append("Cuisine: \(str)")
            }
        }

        return parts.joined(separator: "\n")
    }

    /// Remove HTML tags, scripts, styles, and collapse whitespace.
    private func stripHTML(_ html: String) -> String {
        var result = html
        // Remove script and style blocks entirely
        let blockPatterns = ["<script[^>]*>[\\s\\S]*?</script>", "<style[^>]*>[\\s\\S]*?</style>"]
        for pattern in blockPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: " ")
            }
        }
        // Replace <br>, <p>, <div>, <li> with newlines for readability
        if let breakRegex = try? NSRegularExpression(pattern: "<(br|/p|/div|/li|/tr)[^>]*>", options: .caseInsensitive) {
            result = breakRegex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "\n")
        }
        // Strip remaining tags
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            result = tagRegex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: " ")
        }
        // Decode common HTML entities
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&frac12;", with: "1/2")
            .replacingOccurrences(of: "&frac14;", with: "1/4")
            .replacingOccurrences(of: "&frac34;", with: "3/4")
            .replacingOccurrences(of: "&deg;", with: "°")
        // Decode numeric entities (&#123; and &#x1F;)
        if let numericEntity = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);", options: []) {
            let matches = numericEntity.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let codeRange = Range(match.range(at: 1), in: result) else { continue }
                let codeStr = String(result[codeRange])
                let codePoint: UInt32?
                if codeStr.hasPrefix("x") || codeStr.hasPrefix("X") {
                    codePoint = UInt32(codeStr.dropFirst(), radix: 16)
                } else {
                    codePoint = UInt32(codeStr)
                }
                if let cp = codePoint, let scalar = Unicode.Scalar(cp) {
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        // Collapse whitespace
        result = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Recipe from Text / Photo / URL text

    // MARK: - Shared Schema Components

    private static let ingredientItemSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "name": ["type": "string"],
            "quantity": ["type": "number"],
            "unit": ["type": "string"],
            "category": ["type": "string"]
        ] as [String: Any],
        "required": ["name", "quantity", "unit", "category"],
        "additionalProperties": false
    ]

    private static let taskItemSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "taskIndex": ["type": "integer"],
            "action": ["type": "string"],
            "ingredient": ["type": ["string", "null"]],
            "durationSeconds": ["type": "integer"],
            "type": ["type": "string", "enum": ["active", "passive"]],
            "effort": ["type": "string", "enum": ["easy", "medium", "hard"]],
            "requiresEquipment": ["type": ["string", "null"]],
            "dependsOn": ["type": "array", "items": ["type": "integer"]]
        ] as [String: Any],
        "required": ["taskIndex", "action", "ingredient", "durationSeconds", "type", "effort", "requiresEquipment", "dependsOn"],
        "additionalProperties": false
    ]

    private static let stepItemSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "stepNumber": ["type": "integer"],
            "instruction": ["type": "string"],
            "timerMinutes": ["type": ["integer", "null"]],
            "estimatedDurationSeconds": ["type": ["integer", "null"]],
            "tasks": ["type": "array", "items": taskItemSchema]
        ] as [String: Any],
        "required": ["stepNumber", "instruction", "timerMinutes", "estimatedDurationSeconds", "tasks"],
        "additionalProperties": false
    ]

    /// Build recipe object schema properties and required keys.
    private static func recipeSchemaBody(includeFullDetails: Bool) -> [String: Any] {
        var properties: [String: Any] = [
            "title": ["type": "string"],
            "description": ["type": ["string", "null"]],
            "ingredients": ["type": "array", "items": ingredientItemSchema],
            "steps": ["type": "array", "items": stepItemSchema],
            "servings": ["type": ["integer", "null"]],
            "prepTimeMinutes": ["type": ["integer", "null"]],
            "cookTimeMinutes": ["type": ["integer", "null"]],
            "dietaryTags": ["type": "array", "items": ["type": "string"]]
        ]
        var required = ["title", "description", "ingredients", "steps", "servings", "prepTimeMinutes", "cookTimeMinutes", "dietaryTags"]

        if includeFullDetails {
            let extras: [String: Any] = [
                "difficulty": ["type": ["integer", "null"]],
                "mealType": ["type": ["string", "null"]],
                "cuisine": ["type": ["string", "null"]],
                "calories": ["type": ["integer", "null"]],
                "protein": ["type": ["number", "null"]],
                "carbohydrates": ["type": ["number", "null"]],
                "fat": ["type": ["number", "null"]],
                "fiber": ["type": ["number", "null"]],
                "sugar": ["type": ["number", "null"]],
                "sodium": ["type": ["number", "null"]]
            ]
            for (key, value) in extras { properties[key] = value }
            required += ["difficulty", "mealType", "cuisine", "calories", "protein", "carbohydrates", "fat", "fiber", "sugar", "sodium"]
        }

        return [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false
        ]
    }

    // MARK: - JSON Schemas for Structured Output

    /// Recipe import — basic fields only.
    private static let recipeImportSchema: [String: Any] = [
        "name": "recipe_import",
        "strict": true,
        "schema": recipeSchemaBody(includeFullDetails: false)
    ]

    /// Full recipe — includes difficulty, meal type, cuisine, nutrition.
    private static let fullRecipeSchema: [String: Any] = [
        "name": "full_recipe",
        "strict": true,
        "schema": recipeSchemaBody(includeFullDetails: true)
    ]

    /// Array of full recipes — for suggestRecipes, leftoverTransformer.
    private static let recipeArraySchema: [String: Any] = [
        "name": "recipe_array",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "recipes": ["type": "array", "items": recipeSchemaBody(includeFullDetails: true)] as [String: Any]
            ],
            "required": ["recipes"],
            "additionalProperties": false
        ] as [String: Any]
    ]

    /// Shopping list items.
    private static let shoppingListSchema: [String: Any] = [
        "name": "shopping_list",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"],
                            "quantity": ["type": ["number", "null"]],
                            "unit": ["type": ["string", "null"]],
                            "category": ["type": "string"]
                        ] as [String: Any],
                        "required": ["name", "quantity", "unit", "category"],
                        "additionalProperties": false
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "required": ["items"],
            "additionalProperties": false
        ] as [String: Any]
    ]

    /// Substitution suggestions.
    private static let substitutionsSchema: [String: Any] = [
        "name": "substitutions",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "substitutions": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "originalIngredient": ["type": "string"],
                            "substituteName": ["type": "string"],
                            "ratio": ["type": "string"],
                            "tasteImpact": ["type": "string"],
                            "textureImpact": ["type": "string"],
                            "nutritionImpact": ["type": "string"],
                            "confidence": ["type": "number"]
                        ] as [String: Any],
                        "required": ["originalIngredient", "substituteName", "ratio", "tasteImpact", "textureImpact", "nutritionImpact", "confidence"],
                        "additionalProperties": false
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "required": ["substitutions"],
            "additionalProperties": false
        ] as [String: Any]
    ]

    /// Healthier recipe suggestions.
    private static let healthierSchema: [String: Any] = [
        "name": "healthier_suggestion",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "suggestions": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "change": ["type": "string"],
                            "benefit": ["type": "string"]
                        ] as [String: Any],
                        "required": ["change", "benefit"],
                        "additionalProperties": false
                    ] as [String: Any]
                ] as [String: Any],
                "estimatedCalorieReduction": ["type": ["integer", "null"]],
                "overallImpact": ["type": "string"]
            ] as [String: Any],
            "required": ["suggestions", "estimatedCalorieReduction", "overallImpact"],
            "additionalProperties": false
        ] as [String: Any]
    ]

    /// Step duration estimates.
    private static let stepDurationsSchema: [String: Any] = [
        "name": "step_durations",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "durations": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "stepNumber": ["type": "integer"],
                            "estimatedDurationSeconds": ["type": "integer"]
                        ] as [String: Any],
                        "required": ["stepNumber", "estimatedDurationSeconds"],
                        "additionalProperties": false
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "required": ["durations"],
            "additionalProperties": false
        ] as [String: Any]
    ]

    /// Status messages array.
    private static let statusMessagesSchema: [String: Any] = [
        "name": "status_messages",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "messages": ["type": "array", "items": ["type": "string"]]
            ] as [String: Any],
            "required": ["messages"],
            "additionalProperties": false
        ] as [String: Any]
    ]

    func parseRecipeFromText(_ extractedText: String) async -> RecipeImportResult? {
        let prompt = """
        Parse the following text into a structured recipe. The text may come from a website, \
        a photo of a cookbook page, or pasted by the user. Extract the recipe details as accurately as possible.

        RULES:
        - "unit" must be one of: tsp, tbsp, cup, fl oz, ml, L, g, kg, oz, lb, piece, whole, slice, clove, bunch, can, pkg, pinch, splash, to taste
        - "category" must be one of: Dairy, Produce, Protein, Grains & Cereals, Spices & Herbs, Condiments & Sauces, Baking Supplies, Frozen Foods, Canned & Jarred, Beverages, Snacks, Oils & Fats, Pasta & Noodles, Nuts & Seeds, Other
        - "dietaryTags" values must be from: Vegetarian, Vegan, Gluten-Free, Dairy-Free, Nut-Free, Low Carb, High Protein, Keto, Paleo, Halal, Kosher
        - "taskIndex" must be a unique integer starting at 0, incrementing across ALL steps
        - "dependsOn" contains taskIndex values of prerequisite tasks
        - "estimatedDurationSeconds" is the realistic wall-clock time for each step
        - Estimate servings, prep/cook times if not stated

        Text:
        \(extractedText)
        """

        guard let response = await sendChatRequest(
            prompt: prompt,
            responseFormat: ["type": "json_schema", "json_schema": Self.recipeImportSchema]
        ) else { return nil }

        guard let data = response.data(using: .utf8) else { return nil }
        do {
            let raw = try JSONDecoder().decode(RawImportResult.self, from: data)
            return raw.toRecipeImportResult()
        } catch {
            AppLog.warn("[AIService] Failed to decode structured recipe: \(error)")
            return nil
        }
    }

    // MARK: - AI Recipe Generation

    /// Generate a complete recipe from a search query and user preferences.
    // MARK: - Status Messages (lightweight, fast)

    func generateStatusMessages(query: String, preferences: RecipeGenerationPreferences) async -> [String] {
        var context = "Dish: \(query)"
        if preferences.spiceLevel != .medium {
            context += ", Spice: \(preferences.spiceLevel.rawValue)"
        }
        if let time = preferences.maxTimeMinutes {
            context += ", Max time: \(time) min"
        }
        if !preferences.dietaryTags.isEmpty {
            context += ", Dietary: \(preferences.dietaryTags.map(\.rawValue).joined(separator: ", "))"
        }
        if preferences.usePantry {
            context += ", Using pantry ingredients"
        }
        if preferences.servings != 4 {
            context += ", Servings: \(preferences.servings)"
        }

        let prompt = """
        I'm about to generate a recipe for: \(context)

        While the user waits (~30 seconds), I want to show fun, specific status messages about what's happening.
        Generate exactly 8 short status messages (max 8 words each) that reference this SPECIFIC dish, its cuisine, \
        its cooking techniques, and the user's preferences. Make them feel like a real chef is working.

        Rules:
        - Each message must end with "…" (ellipsis)
        - Reference the actual dish, its ingredients, or techniques — NOT generic placeholders
        - Progress from research → ingredients → technique → cooking → finishing
        - Be playful and knowledgeable — show you know this dish
        - If there are dietary/spice/time constraints, weave 1-2 of them in naturally
        - Use standard sentence capitalization (capitalize first word only, not every word)

        Return ONLY a JSON object with a "messages" array of 8 strings. No explanation.
        """

        guard let response = await sendChatRequest(
            prompt: prompt,
            maxTokens: 300,
            responseFormat: ["type": "json_schema", "json_schema": Self.statusMessagesSchema]
        ) else {
            return Self.fallbackMessages(dish: query)
        }

        guard let data = response.data(using: .utf8) else {
            return Self.fallbackMessages(dish: query)
        }
        do {
            let raw = try JSONDecoder().decode(RawStatusMessages.self, from: data)
            return raw.messages.count >= 4 ? raw.messages : Self.fallbackMessages(dish: query)
        } catch {
            return Self.fallbackMessages(dish: query)
        }
    }

    private static func fallbackMessages(dish: String) -> [String] {
        [
            "Researching the best \(dish) recipes…",
            "Selecting the perfect ingredients…",
            "Working out the technique…",
            "Writing step-by-step instructions…",
            "Calculating nutrition info…",
            "Adding finishing touches…",
            "Your \(dish) is almost ready…",
        ]
    }

    // MARK: - Recipe Generation

    func generateRecipe(query: String, preferences: RecipeGenerationPreferences) async -> Recipe? {
        var contextLines: [String] = []
        contextLines.append("Create a recipe for: \(query)")
        contextLines.append("Servings: \(preferences.servings)")
        contextLines.append("Spice level: \(preferences.spiceLevel.rawValue)")

        if let maxTime = preferences.maxTimeMinutes {
            contextLines.append("Maximum total time: \(maxTime) minutes")
        }
        if !preferences.dietaryTags.isEmpty {
            contextLines.append("Dietary requirements: \(preferences.dietaryTags.map(\.rawValue).joined(separator: ", "))")
        }
        if preferences.usePantry, !preferences.pantryIngredients.isEmpty {
            contextLines.append("Adapt the recipe to use these available ingredients where possible: \(preferences.pantryIngredients.joined(separator: ", "))")
        }

        let context = contextLines.joined(separator: "\n")

        let prompt = """
        \(context)

        Create an authentic, well-tested recipe. Use realistic quantities, proper technique, \
        and accurate cooking times. The recipe should feel like it comes from an experienced \
        home cook, not a generic template.

        IMPORTANT: Use standard title capitalization for the recipe title (capitalize major words). \
        Use sentence case for ingredient names (lowercase unless a proper noun, e.g. "chicken breast" not "Chicken Breast"). \
        Use sentence case for step instructions.

        INGREDIENT QUALITY RULES:
        - Every ingredient name must be specific enough to purchase at a store (e.g. "chicken thigh" not "chicken", "basmati rice" not "rice").
        - Use the most natural unit for each ingredient type: weight (g, kg) for solids/meats, volume (ml, L, cup, tbsp) for liquids, "piece"/"whole" only for naturally countable items (eggs, onions, lemons).
        - Never use "piece" for meats, cheese, or ingredients sold by weight — use g or kg instead.
        - Prefer human-readable quantities: use "1 kg" not "1000 g", use "1 L" not "1000 ml", use "1.5 kg" not "1500 g".
        - Quantities must be realistic for the serving count — scale proportionally and sanity-check amounts.
        - For fats and oils, use volume (tbsp, cup, ml) not weight.
        - For spices and seasonings, use tsp, tbsp, or "pinch" — never grams for small amounts.

        Return a single JSON object with:
        - "title": string (specific and descriptive, e.g. "Hyderabadi Chicken Dum Biryani" not just "Chicken Biryani")
        - "description": string (2-3 sentences about the dish, its origin, and what makes it special)
        - "ingredients": [{"name": string, "quantity": number, "unit": string, "category": string}]
        - "steps": [{"stepNumber": number, "instruction": string, "timerMinutes": number or null, "estimatedDurationSeconds": number, "tasks": [task]}]
        - "servings": \(preferences.servings)
        - "prepTimeMinutes": number
        - "cookTimeMinutes": number
        - "difficulty": number (1-5)
        - "dietaryTags": [string] (from: Vegetarian, Vegan, Gluten-Free, Dairy-Free, Nut-Free, Low Carb, High Protein, Keto, Paleo, Halal, Kosher)
        - "mealType": string (one of: Breakfast, Lunch, Dinner, Snack, Dessert)
        - "cuisine": string (one of: Italian, Mexican, Chinese, Japanese, Indian, Thai, French, Mediterranean, American, Korean, Vietnamese, Greek, Middle Eastern, Ethiopian, Caribbean, Other)
        - "calories": number (per serving)
        - "protein": number (grams per serving)
        - "carbohydrates": number (grams per serving)
        - "fat": number (grams per serving)
        - "fiber": number (grams per serving)
        - "sugar": number (grams per serving)
        - "sodium": number (mg per serving)

        For unit, use: tsp, tbsp, cup, ml, L, g, kg, oz, lb, piece, whole, slice, clove, bunch, can, pinch, to taste.
        For category, use: Dairy, Produce, Protein, Grains & Cereals, Spices & Herbs, Condiments & Sauces, Baking Supplies, Oils & Fats, Other.

        Each task object: {"taskIndex": number, "action": string, "ingredient": string or null, "durationSeconds": number, "type": "active" or "passive", "effort": "easy" or "medium" or "hard", "requiresEquipment": string or null, "dependsOn": [number]}
        "taskIndex" — unique integer starting at 0, incrementing across ALL steps.
        "dependsOn" — taskIndex values of prerequisite tasks.
        "effort" — "easy" (occasional checking), "medium" (periodic attention), "hard" (constant hands-on).
        Valid actions: "cut_dice", "cut_mince", "cut_slice", "cut_chop", "peel", "measure", "mix", "marinate", "season", "heat", "saute", "boil", "simmer", "fry_pan", "fry_deep", "fry_stir", "bake", "roast", "grill", "steam", "plate", "garnish", "rest", "serve", "toss", or a custom string.

        Return ONLY the JSON object, no other text.
        """

        guard let response = await sendChatRequest(
            prompt: prompt,
            responseFormat: ["type": "json_schema", "json_schema": Self.fullRecipeSchema]
        ) else { return nil }

        guard let data = response.data(using: .utf8) else { return nil }
        do {
            let raw = try JSONDecoder().decode(RawFullRecipe.self, from: data)
            return raw.toRecipe(source: .aiGenerated)
        } catch {
            AppLog.warn("[AIService] Failed to parse generated recipe: \(error)")
            return nil
        }
    }

    // MARK: - Recipe Modification

    func modifyRecipe(_ recipe: Recipe, feedback: String, pantryIngredients: [String]) async -> Recipe? {
        let ingredientList = recipe.ingredients.map { ing in
            "\(ing.quantity) \(ing.unit?.rawValue ?? "") \(ing.name)"
        }.joined(separator: "\n")

        let stepList = recipe.steps.map { step in
            "Step \(step.stepNumber): \(step.instruction)"
        }.joined(separator: "\n")

        var contextLines: [String] = []
        contextLines.append("Current recipe: \(recipe.title)")
        if let desc = recipe.description { contextLines.append("Description: \(desc)") }
        contextLines.append("Servings: \(recipe.servings)")
        contextLines.append("\nIngredients:\n\(ingredientList)")
        contextLines.append("\nSteps:\n\(stepList)")
        if !pantryIngredients.isEmpty {
            contextLines.append("\nUser's pantry contains: \(pantryIngredients.joined(separator: ", "))")
        }
        contextLines.append("\nUser's modification request: \(feedback)")

        let context = contextLines.joined(separator: "\n")

        let prompt = """
        \(context)

        Modify this recipe according to the user's request. Keep the recipe's identity \
        and character intact — only change what the user asked for. If the user references \
        their pantry or available ingredients, use those. If they ask to make it spicier, \
        healthier, faster, etc., adjust accordingly.

        IMPORTANT: Use standard title capitalization for the recipe title. \
        Use sentence case for ingredient names (lowercase unless a proper noun). \
        Use sentence case for step instructions.

        INGREDIENT QUALITY RULES:
        - Every ingredient name must be specific enough to purchase at a store (e.g. "chicken thigh" not "chicken").
        - Use the most natural unit for each ingredient type: weight (g, kg) for solids/meats, volume (ml, L, cup, tbsp) for liquids, "piece"/"whole" only for naturally countable items (eggs, onions).
        - Never use "piece" for meats, cheese, or ingredients sold by weight.
        - Prefer human-readable quantities: "1 kg" not "1000 g", "1 L" not "1000 ml".
        - Quantities must be realistic for the serving count.
        - For fats and oils, use volume (tbsp, cup, ml) not weight.
        - For spices and seasonings, use tsp, tbsp, or "pinch" — never grams for small amounts.

        Return the COMPLETE modified recipe as a single JSON object with the same structure:
        - "title": string
        - "description": string (update to reflect changes)
        - "ingredients": [{"name": string, "quantity": number, "unit": string, "category": string}]
        - "steps": [{"stepNumber": number, "instruction": string, "timerMinutes": number or null, "estimatedDurationSeconds": number, "tasks": [task]}]
        - "servings": number
        - "prepTimeMinutes": number
        - "cookTimeMinutes": number
        - "difficulty": number (1-5)
        - "dietaryTags": [string]
        - "mealType": string
        - "cuisine": string
        - "calories": number (per serving)
        - "protein": number (grams per serving)
        - "carbohydrates": number (grams per serving)
        - "fat": number (grams per serving)
        - "fiber": number (grams per serving)
        - "sugar": number (grams per serving)
        - "sodium": number (mg per serving)

        For unit, use: tsp, tbsp, cup, ml, L, g, kg, oz, lb, piece, whole, slice, clove, bunch, can, pinch, to taste.
        For category, use: Dairy, Produce, Protein, Grains & Cereals, Spices & Herbs, Condiments & Sauces, Baking Supplies, Oils & Fats, Other.
        Each task object: {"taskIndex": number, "action": string, "ingredient": string or null, "durationSeconds": number, "type": "active" or "passive", "effort": "easy" or "medium" or "hard", "requiresEquipment": string or null, "dependsOn": [number]}

        Return ONLY the JSON object, no other text.
        """

        guard let response = await sendChatRequest(
            prompt: prompt,
            responseFormat: ["type": "json_schema", "json_schema": Self.fullRecipeSchema]
        ) else { return nil }

        guard let data = response.data(using: .utf8) else { return nil }
        do {
            let raw = try JSONDecoder().decode(RawFullRecipe.self, from: data)
            return raw.toRecipe(source: recipe.source, preserving: recipe)
        } catch {
            AppLog.warn("[AIService] Failed to parse modified recipe: \(error)")
            return nil
        }
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

        Return a JSON object with a "durations" array where each element is:
        {"stepNumber": number, "estimatedDurationSeconds": number}
        """

        guard let response = await sendChatRequest(
            prompt: prompt,
            responseFormat: ["type": "json_schema", "json_schema": Self.stepDurationsSchema]
        ) else { return steps }

        guard let data = response.data(using: .utf8) else { return steps }
        do {
            let raw = try JSONDecoder().decode(RawDurationList.self, from: data)
            var lookup: [Int: Int] = [:]
            for item in raw.durations {
                lookup[item.stepNumber] = item.estimatedDurationSeconds
            }
            return steps.map { step in
                var updated = step
                if updated.estimatedDurationSeconds == nil, let dur = lookup[step.stepNumber] {
                    updated.estimatedDurationSeconds = dur
                }
                return updated
            }
        } catch {
            AppLog.warn("[AIService] Failed to parse step durations: \(error)")
            return steps
        }
    }

    // MARK: - Networking (with retry)

    /// Maximum number of retry attempts for transient failures.
    private let maxRetries = 3

    /// Sends a prompt to OpenAI with automatic retry + exponential backoff.
    /// Retries on network errors and 5xx / 429 responses. Gives up on 4xx client errors.
    /// Pass `responseFormat` to enable structured output (e.g. json_schema).
    private func sendChatRequest(prompt: String, maxTokens: Int = 4096, responseFormat: [String: Any]? = nil) async -> String? {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !AppConfig.isMissing(apiKey) else {
            AppLog.info("[AIService] Missing OpenAI API key")
            return nil
        }

        guard let url = URL(string: baseURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a helpful kitchen and cooking assistant. Always return valid JSON when asked for structured data."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": maxTokens
        ]

        if let responseFormat {
            body["response_format"] = responseFormat
        }

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
                        AppLog.warn("[AIService] Received HTTP 200 with unexpected response shape")
                        return nil // valid 200 but unexpected shape — don't retry
                    }

                    // Rate limited or server error — retryable
                    if httpResponse.statusCode == 429 || httpResponse.statusCode >= 500 {
                        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                        AppLog.warn("[AIService] Retryable HTTP \(httpResponse.statusCode), attempt \(attempt)/\(maxRetries): \(body)")
                        if attempt < maxRetries {
                            let delay = Double(attempt) * 1.5 // 1.5s, 3s
                            try await Task.sleep(for: .seconds(delay))
                            continue
                        }
                        return nil
                    }

                    // 4xx client error (bad key, etc.) — not retryable
                    let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                    AppLog.error("[AIService] Non-retryable HTTP \(httpResponse.statusCode): \(body)")
                    return nil
                }
            } catch {
                // Network error — retry with backoff
                if attempt < maxRetries {
                    let delay = Double(attempt) * 1.5
                    try? await Task.sleep(for: .seconds(delay))
                    continue
                }
                AppLog.error("AI Service Error after \(maxRetries) attempts: \(error.localizedDescription)")
            }
        }

        return nil
    }

    // MARK: - Response Parsing (legacy — kept for edge cases)
}
