import Foundation

final class AIService {
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
        - "steps": [{"stepNumber": number, "instruction": string, "timerMinutes": number or null}]
        - "servings": number
        - "prepTimeMinutes": number
        - "cookTimeMinutes": number
        - "difficulty": number (1-5, where 1 is easiest)
        - "dietaryTags": [string]
        - "calories": number (estimated per serving)
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
        - "steps": [{"stepNumber": number, "instruction": string, "timerMinutes": number or null}]
        - "servings": number
        - "prepTimeMinutes": number
        - "cookTimeMinutes": number
        - "difficulty": number (1-5)

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
        - "steps": [{"stepNumber": number, "instruction": string, "timerMinutes": number or null}]
        - "servings": number
        - "prepTimeMinutes": number
        - "cookTimeMinutes": number
        - "dietaryTags": [string]

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
        - "steps": [{"stepNumber": number, "instruction": string, "timerMinutes": number or null}]
        - "servings": number
        - "prepTimeMinutes": number (estimate if not stated)
        - "cookTimeMinutes": number (estimate if not stated)
        - "dietaryTags": [string] (infer from ingredients)

        Return ONLY the JSON object, no other text.
        """

        guard let response = await sendChatRequest(prompt: prompt) else { return nil }
        return parseImportResult(from: response)
    }

    // MARK: - General Chat

    func chat(message: String, context: String) async -> String {
        let prompt = """
        You are Pantry Chef, a friendly and knowledgeable AI kitchen assistant. You help with cooking questions, recipe suggestions, ingredient substitutions, and kitchen tips. Keep answers concise and practical. You focus on helping beginner cooks eat healthy.

        Context about the user's kitchen:
        \(context)

        User's question: \(message)
        """

        return await sendChatRequest(prompt: prompt) ?? "Sorry, I couldn't process that request. Please try again."
    }

    // MARK: - Networking

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

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        } catch {
            print("AI Service Error: \(error.localizedDescription)")
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

                let steps: [RecipeStep] = (dict["steps"]?.value as? [[String: Any]])?.compactMap { step in
                    guard let instruction = step["instruction"] as? String else { return nil }
                    let num = (step["stepNumber"] as? Int) ?? 1
                    let timer = step["timerMinutes"] as? Int
                    return RecipeStep(stepNumber: num, instruction: instruction, timerMinutes: timer)
                } ?? []

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
