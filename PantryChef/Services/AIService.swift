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

        // Try local SubstitutionRepository first
        var localSuggestions: [SubstitutionSuggestion] = []
        var unresolvedIngredients: [Ingredient] = []

        for ingredient in matchResult.missingIngredients {
            let subs = SubstitutionRepository.shared.substitutions(for: ingredient.name)
            if let best = subs.first {
                let worstImpact = max(best.tasteImpact.ordinal, best.textureImpact.ordinal)
                localSuggestions.append(SubstitutionSuggestion(
                    originalIngredient: ingredient.name,
                    substituteName: best.substitute,
                    ratio: best.ratio,
                    tasteImpact: best.tasteImpact.rawValue,
                    textureImpact: best.textureImpact.rawValue,
                    nutritionImpact: "Similar",
                    confidence: worstImpact == 0 ? 0.95 : worstImpact == 1 ? 0.8 : 0.6
                ))
            } else {
                unresolvedIngredients.append(ingredient)
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

        Return ONLY the JSON array, no other text.
        """

        guard let response = await sendChatRequest(prompt: prompt) else { return localSuggestions }
        return localSuggestions + parseSubstitutions(from: response)
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

    /// JSON schema for OpenAI structured output — guarantees the response shape.
    private static let recipeImportSchema: [String: Any] = [
        "name": "recipe_import",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "description": ["type": ["string", "null"]],
                "ingredients": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"],
                            "quantity": ["type": "number"],
                            "unit": ["type": "string"],
                            "category": ["type": "string"]
                        ],
                        "required": ["name", "quantity", "unit", "category"],
                        "additionalProperties": false
                    ]
                ],
                "steps": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "stepNumber": ["type": "integer"],
                            "instruction": ["type": "string"],
                            "timerMinutes": ["type": ["integer", "null"]],
                            "estimatedDurationSeconds": ["type": ["integer", "null"]],
                            "tasks": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "taskIndex": ["type": "integer"],
                                        "action": ["type": "string"],
                                        "ingredient": ["type": ["string", "null"]],
                                        "durationSeconds": ["type": "integer"],
                                        "type": ["type": "string", "enum": ["active", "passive"]],
                                        "effort": ["type": "string", "enum": ["easy", "medium", "hard"]],
                                        "requiresEquipment": ["type": ["string", "null"]],
                                        "dependsOn": [
                                            "type": "array",
                                            "items": ["type": "integer"]
                                        ]
                                    ],
                                    "required": ["taskIndex", "action", "ingredient", "durationSeconds", "type", "effort", "requiresEquipment", "dependsOn"],
                                    "additionalProperties": false
                                ]
                            ]
                        ],
                        "required": ["stepNumber", "instruction", "timerMinutes", "estimatedDurationSeconds", "tasks"],
                        "additionalProperties": false
                    ]
                ],
                "servings": ["type": ["integer", "null"]],
                "prepTimeMinutes": ["type": ["integer", "null"]],
                "cookTimeMinutes": ["type": ["integer", "null"]],
                "dietaryTags": [
                    "type": "array",
                    "items": ["type": "string"]
                ]
            ],
            "required": ["title", "description", "ingredients", "steps", "servings", "prepTimeMinutes", "cookTimeMinutes", "dietaryTags"],
            "additionalProperties": false
        ] as [String : Any]
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
            print("[AIService] Failed to decode structured recipe: \(error)")
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

        Return ONLY a JSON array of 8 strings. No explanation.
        """

        guard let response = await sendChatRequest(prompt: prompt, maxTokens: 300) else {
            return Self.fallbackMessages(dish: query)
        }

        if let data = extractJSON(from: response),
           let messages = try? JSONDecoder().decode([String].self, from: data),
           messages.count >= 4 {
            return messages
        }

        return Self.fallbackMessages(dish: query)
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

        guard let response = await sendChatRequest(prompt: prompt) else { return nil }

        // Parse the single recipe from the response
        guard let data = extractJSON(from: response) else { return nil }
        do {
            let dict = try JSONDecoder().decode([String: AnyCodable].self, from: data)
            guard let title = dict["title"]?.value as? String else { return nil }
            let description = dict["description"]?.value as? String
            let servings = dict["servings"]?.value as? Int ?? preferences.servings
            let prepTime = dict["prepTimeMinutes"]?.value as? Int
            let cookTime = dict["cookTimeMinutes"]?.value as? Int
            let difficultyRaw = dict["difficulty"]?.value as? Int ?? 2
            let difficulty = DifficultyLevel(rawValue: difficultyRaw) ?? .easy

            let ingredients: [Ingredient] = (dict["ingredients"]?.value as? [[String: Any]])?.compactMap { ing in
                guard let name = ing["name"] as? String else { return nil }
                let qty = (ing["quantity"] as? Double) ?? (ing["quantity"] as? Int).map { Double($0) } ?? 1
                let unitStr = ing["unit"] as? String
                let unit = MeasurementUnit.allCases.first { $0.rawValue == unitStr }
                let categoryStr = ing["category"] as? String
                let category = FoodCategory.allCases.first { $0.rawValue == categoryStr }
                return Ingredient(name: name, quantity: qty, unit: unit, category: category ?? .other)
            } ?? []

            // Parse steps with tasks (same two-pass approach as parseRecipes)
            var indexToUUID: [Int: UUID] = [:]
            var rawDepsMap: [UUID: [Int]] = [:]

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
                        rawDepsMap[taskId] = (taskDict["dependsOn"] as? [Int]) ?? []
                    }
                }
            }

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

            // Dietary tags
            let tagStrings = dict["dietaryTags"]?.value as? [String] ?? []
            let dietaryTags = tagStrings.compactMap { DietaryTag(rawValue: $0) }

            // Meal type & cuisine
            let mealTypeStr = dict["mealType"]?.value as? String
            let mealType = mealTypeStr.flatMap { MealType(rawValue: $0) }
            let cuisineStr = dict["cuisine"]?.value as? String
            let cuisine = cuisineStr.flatMap { CuisineType(rawValue: $0) }

            // Nutrition
            let nutrition = parseNutrition(from: dict)

            return Recipe(
                title: title,
                description: description,
                ingredients: ingredients,
                steps: steps,
                servings: servings,
                prepTimeMinutes: prepTime,
                cookTimeMinutes: cookTime,
                difficulty: difficulty,
                dietaryTags: dietaryTags,
                mealType: mealType,
                cuisine: cuisine,
                source: .aiGenerated,
                nutrition: nutrition
            )
        } catch {
            print("[AIService] Failed to parse generated recipe: \(error)")
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

        guard let response = await sendChatRequest(prompt: prompt) else { return nil }
        guard let data = extractJSON(from: response) else { return nil }

        do {
            let dict = try JSONDecoder().decode([String: AnyCodable].self, from: data)
            guard let title = dict["title"]?.value as? String else { return nil }
            let description = dict["description"]?.value as? String
            let servings = dict["servings"]?.value as? Int ?? recipe.servings
            let prepTime = dict["prepTimeMinutes"]?.value as? Int
            let cookTime = dict["cookTimeMinutes"]?.value as? Int
            let difficultyRaw = dict["difficulty"]?.value as? Int ?? 2
            let difficulty = DifficultyLevel(rawValue: difficultyRaw) ?? .easy

            let ingredients: [Ingredient] = (dict["ingredients"]?.value as? [[String: Any]])?.compactMap { ing in
                guard let name = ing["name"] as? String else { return nil }
                let qty = (ing["quantity"] as? Double) ?? (ing["quantity"] as? Int).map { Double($0) } ?? 1
                let unitStr = ing["unit"] as? String
                let unit = MeasurementUnit.allCases.first { $0.rawValue == unitStr }
                let categoryStr = ing["category"] as? String
                let category = FoodCategory.allCases.first { $0.rawValue == categoryStr }
                return Ingredient(name: name, quantity: qty, unit: unit, category: category ?? .other)
            } ?? []

            var indexToUUID: [Int: UUID] = [:]
            var rawDepsMap: [UUID: [Int]] = [:]
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
                        rawDepsMap[taskId] = (taskDict["dependsOn"] as? [Int]) ?? []
                    }
                }
            }

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

            let tagStrings = dict["dietaryTags"]?.value as? [String] ?? []
            let dietaryTags = tagStrings.compactMap { DietaryTag(rawValue: $0) }
            let mealTypeStr = dict["mealType"]?.value as? String
            let mealType = mealTypeStr.flatMap { MealType(rawValue: $0) }
            let cuisineStr = dict["cuisine"]?.value as? String
            let cuisine = cuisineStr.flatMap { CuisineType(rawValue: $0) }

            let nutrition = parseNutrition(from: dict)

            // Preserve original recipe's identity
            return Recipe(
                id: recipe.id,
                title: title,
                description: description,
                ingredients: ingredients,
                steps: steps,
                servings: servings,
                prepTimeMinutes: prepTime,
                cookTimeMinutes: cookTime,
                difficulty: difficulty,
                dietaryTags: dietaryTags,
                mealType: mealType,
                cuisine: cuisine,
                source: recipe.source,
                nutrition: nutrition,
                imageURL: recipe.imageURL,
                sourceURL: recipe.sourceURL,
                isFavorite: recipe.isFavorite,
                dateAdded: recipe.dateAdded,
                timesCooked: recipe.timesCooked,
                rating: recipe.rating
            )
        } catch {
            print("[AIService] Failed to parse modified recipe: \(error)")
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
    /// Pass `responseFormat` to enable structured output (e.g. json_schema).
    private func sendChatRequest(prompt: String, maxTokens: Int = 4096, responseFormat: [String: Any]? = nil) async -> String? {
        guard let url = URL(string: baseURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

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

                let nutrition = parseNutrition(from: dict)

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

    /// Safely extract a Double from an AnyCodable value that might be Int or Double.
    private func asDouble(_ anyCodable: AnyCodable?) -> Double? {
        guard let val = anyCodable?.value else { return nil }
        if let d = val as? Double { return d }
        if let i = val as? Int { return Double(i) }
        return nil
    }

    /// Safely extract an Int from an AnyCodable value that might be Int or Double.
    private func asInt(_ anyCodable: AnyCodable?) -> Int? {
        guard let val = anyCodable?.value else { return nil }
        if let i = val as? Int { return i }
        if let d = val as? Double { return Int(d) }
        return nil
    }

    /// Parse nutrition info from a decoded response dictionary.
    private func parseNutrition(from dict: [String: AnyCodable]) -> NutritionInfo? {
        guard let cal = asInt(dict["calories"]) else { return nil }
        return NutritionInfo(
            calories: cal,
            protein: asDouble(dict["protein"]) ?? 0,
            carbohydrates: asDouble(dict["carbohydrates"]) ?? 0,
            fat: asDouble(dict["fat"]) ?? 0,
            fiber: asDouble(dict["fiber"]),
            sugar: asDouble(dict["sugar"]),
            sodium: asDouble(dict["sodium"])
        )
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
