import Foundation

final class AIService {
    private let apiKey: String
    private let urlSession: URLSession
    private let telemetryReporter: any TelemetryReporting
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let model = "gpt-4o"

    init(
        apiKey: String = AppConfig.openAIAPIKey,
        urlSession: URLSession = .shared,
        telemetryReporter: any TelemetryReporting = AppTelemetryReporter()
    ) {
        self.apiKey = apiKey
        self.urlSession = urlSession
        self.telemetryReporter = telemetryReporter
    }

    // MARK: - System Prompt

    private static let systemPrompt = """
        You are a helpful kitchen and cooking assistant. Always return valid JSON when asked for structured data.

        IMPORTANT: You can ONLY help with food, cooking, recipes, ingredients, meal planning, and kitchen-related topics.

        If the user asks about anything unrelated to food or cooking — such as:
        - Programming, coding, or software (e.g., "hello world in python", "write me some code")
        - Homework, math problems, or academic questions
        - General knowledge unrelated to food
        - Entertainment, games, or other non-cooking topics

        You MUST reject the request by setting "rejected": true with:
        - "rejectionReason": a brief category like "programming_request", "off_topic", "homework", etc.
        - "rejectionMessage": a friendly message like "I'm your cooking assistant! I can only help with recipes, ingredients, and food-related questions. Try asking me about a dish you'd like to make!"
        - "recipe": null

        When the request IS about food/cooking, set "rejected": false with rejectionReason and rejectionMessage as null, and provide the full recipe.

        Be generous in interpreting food-related requests. "Python Cake" or "Death by Chocolate" are valid dessert names. Only reject clearly non-food requests.
        """

    // MARK: - Make It Healthier

    func makeItHealthier(dish: Dish) async -> HealthierSuggestion? {
        let ingredientList = dish.ingredients.map(\.display).joined(separator: "\n")

        let prompt = """
        Suggest ways to make this recipe healthier:

        Recipe: \(dish.name)
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
            return raw.toHealthierSuggestion(recipeTitle: dish.name)
        } catch {
            AppLog.warn("[AIService] Failed to decode healthier suggestion: \(error)")
            return nil
        }
    }

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
    /// When `allNullable` is true, the entire recipe can be null (for rejection responses).
    private static func recipeSchemaBody(includeFullDetails: Bool, allNullable: Bool = false) -> [String: Any] {
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

        let objectSchema: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false
        ]

        if allNullable {
            return ["anyOf": [objectSchema, ["type": "null"]]] as [String: Any]
        }
        return objectSchema
    }

    // MARK: - JSON Schemas for Structured Output

    /// Recipe import — same metadata completeness as full recipes so onboarding stays populated.
    private static let fullRecipeSchema: [String: Any] = [
        "name": "full_recipe",
        "strict": true,
        "schema": recipeSchemaBody(includeFullDetails: true)
    ]

    /// Recipe or rejection — allows AI to reject off-topic queries.
    private static let recipeOrRejectionSchema: [String: Any] = [
        "name": "recipe_or_rejection",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "rejected": ["type": "boolean"],
                "rejectionReason": ["type": ["string", "null"]],
                "rejectionMessage": ["type": ["string", "null"]],
                "recipe": recipeSchemaBody(includeFullDetails: true, allNullable: true)
            ] as [String: Any],
            "required": ["rejected", "rejectionReason", "rejectionMessage", "recipe"],
            "additionalProperties": false
        ] as [String: Any]
    ]

    /// Array of full recipes — for suggestRecipes, leftoverTransformer.
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
    private static let ingredientDefinitionSchema: [String: Any] = [
        "name": "ingredient_definition",
        "strict": true,
        "schema": [
            "type": "object",
            "properties": [
                "category": [
                    "type": "string",
                    "enum": FoodCategory.allCases.map(\.rawValue)
                ] as [String: Any],
                "defaultStorage": [
                    "type": "string",
                    "enum": PantryStorage.allCases.map(\.rawValue)
                ] as [String: Any],
                "defaultUnit": [
                    "type": ["string", "null"],
                    "enum": [NSNull()] + MeasurementUnit.allCases.map(\.rawValue) as [Any]
                ] as [String: Any],
                "facets": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "key": [
                                "type": "string",
                                "enum": PantryFacetKey.allCases.map(\.rawValue)
                            ] as [String: Any],
                            "options": [
                                "type": "array",
                                "items": ["type": "string"]
                            ] as [String: Any]
                        ] as [String: Any],
                        "required": ["key", "options"],
                        "additionalProperties": false
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "required": ["category", "defaultStorage", "defaultUnit", "facets"],
            "additionalProperties": false
        ] as [String: Any]
    ]

    // MARK: - Ingredient Definition Generation

    func generateIngredientDefinition(name: String) async -> AIIngredientDefinition? {
        let prompt = """
        You are a food ingredient expert. Given the name of a food ingredient, generate a structured definition for a pantry catalog.

        Ingredient name: "\(name)"

        Return a JSON object with:
        - "category": the food category (e.g. "Produce", "Protein", "Dairy & Eggs")
        - "defaultStorage": how this ingredient is typically stored ("Pantry", "Refrigerated", or "Frozen")
        - "defaultUnit": the most common measurement unit for purchasing this ingredient, or null if "piece" is most natural
        - "facets": an array of attribute dimensions. Each facet has:
          - "key": one of "color", "variant", "grade", "fat", "form", "preparation", "preservation", "processing", "texture", "medium"
          - "options": an array of common values for that facet

        Facet key descriptions:
        - "color": visible color (e.g. red, green, white, black)
        - "variant": named sub-type / cultivar / style / flavor / regional kind (e.g. for pasta: penne, fusilli; for barbecue sauce: carolina, memphis; for apple: fuji, gala)
        - "grade": intensity / strength / diet grade (e.g. mild, sharp, extra sharp, hot, light, reduced sodium, extra virgin, concentrated)
        - "fat": dairy fat level (e.g. skim, 1%, 2%, whole, low fat)
        - "form": physical / market form (e.g. ground, whole, powder, liquid, fillet, steak, paste)
        - "preparation": knife / prep state (e.g. sliced, diced, chopped, peeled, deveined, trimmed)
        - "preservation": how it's kept (e.g. fresh, canned, dried, frozen, pickled, cured)
        - "processing": treatment / cooking (e.g. raw, roasted, smoked, blanched, fermented, marinated)
        - "texture": texture characteristics (e.g. creamy, crunchy, smooth, chunky, firm)
        - "medium": packing / cooking liquid (e.g. in water, in oil, in brine, in syrup)

        Only include facets that genuinely apply to this ingredient. Most ingredients have 2-4 relevant facets.
        Each facet should have 2-8 common options. Be practical — include options a home cook would actually use.
        """

        guard let response = await sendChatRequest(
            prompt: prompt,
            maxTokens: 1024,
            responseFormat: ["type": "json_schema", "json_schema": Self.ingredientDefinitionSchema]
        ) else { return nil }

        guard let data = response.data(using: .utf8) else { return nil }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

            guard let categoryRaw = json["category"] as? String,
                  let category = FoodCategory(rawValue: categoryRaw),
                  let storageRaw = json["defaultStorage"] as? String,
                  let storage = PantryStorage(rawValue: storageRaw) else {
                AppLog.warn("[AIService] Failed to parse ingredient definition: missing required fields")
                return nil
            }

            let defaultUnit: MeasurementUnit?
            if let unitRaw = json["defaultUnit"] as? String {
                defaultUnit = MeasurementUnit(rawValue: unitRaw)
            } else {
                defaultUnit = nil
            }

            var facets: [PantryFacetKey: [String]] = [:]
            if let facetArray = json["facets"] as? [[String: Any]] {
                for facetObj in facetArray {
                    guard let keyRaw = facetObj["key"] as? String,
                          let key = PantryFacetKey(rawValue: keyRaw),
                          let options = facetObj["options"] as? [String],
                          !options.isEmpty else { continue }
                    facets[key] = options
                }
            }

            return AIIngredientDefinition(
                category: category,
                defaultStorage: storage,
                defaultUnit: defaultUnit,
                facets: facets
            )
        } catch {
            AppLog.warn("[AIService] Failed to decode ingredient definition: \(error)")
            return nil
        }
    }

    // MARK: - Recipe Modification

    func modifyRecipe(_ dish: Dish, feedback: String, pantryIngredients: [String]) async -> Dish? {
        let ingredientList = dish.ingredients.map(\.display).joined(separator: "\n")

        let stepList = dish.steps.enumerated().map { index, step in
            "Step \(index + 1): \(step.instruction)"
        }.joined(separator: "\n")

        var contextLines: [String] = []
        contextLines.append("Current recipe: \(dish.name)")
        if let blurb = dish.blurb { contextLines.append("Description: \(blurb)") }
        contextLines.append("Servings: \(dish.servings)")
        contextLines.append("\nIngredients:\n\(ingredientList)")
        contextLines.append("\nSteps:\n\(stepList)")
        if !pantryIngredients.isEmpty {
            contextLines.append("\nUser's pantry contains: \(pantryIngredients.joined(separator: ", "))")
        }
        contextLines.append("\nUser's modification request: \(feedback)")

        let context = contextLines.joined(separator: "\n")

        let prompt = """
        \(context)

        If the modification request is NOT about food or cooking (e.g., asking you to write code, do homework, etc.), reject it with "rejected": true.

        Otherwise, modify this recipe according to the user's request. Keep the recipe's identity \
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

        Return a JSON object with these fields:
        - "rejected": boolean (true if off-topic request, false if valid modification)
        - "rejectionReason": string or null (e.g. "off_topic" — only if rejected)
        - "rejectionMessage": string or null (friendly message — only if rejected)
        - "recipe": object or null (the full modified recipe if not rejected, null if rejected)

        If not rejected, the recipe object should contain:
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

        For unit, use: tsp, tbsp, cup, ml, L, g, kg, oz, lb, piece, whole, loaf, slice, clove, bunch, can, pinch, to taste.
        For category, use: Dairy, Produce, Protein, Grains & Cereals, Spices & Herbs, Condiments & Sauces, Baking Supplies, Oils & Fats, Other.
        Each task object: {"taskIndex": number, "action": string, "ingredient": string or null, "durationSeconds": number, "type": "active" or "passive", "effort": "easy" or "medium" or "hard", "requiresEquipment": string or null, "dependsOn": [number]}

        Return ONLY the JSON object, no other text.
        """

        guard let response = await sendChatRequest(
            prompt: prompt,
            responseFormat: ["type": "json_schema", "json_schema": Self.recipeOrRejectionSchema]
        ) else { return nil }

        guard let data = response.data(using: .utf8) else { return nil }
        do {
            let raw = try JSONDecoder().decode(RawRecipeOrRejection.self, from: data)
            if raw.rejected {
                telemetryReporter.record(TelemetryEvent(
                    name: "ai.modification.rejected.offtopic",
                    severity: .info,
                    metadata: ["reason": raw.rejectionReason ?? "unknown"]
                ))
                return nil
            }
            guard let rawRecipe = raw.recipe, !rawRecipe.ingredients.isEmpty, !rawRecipe.steps.isEmpty else {
                AppLog.warn("[AIService] Modified recipe missing ingredients/steps")
                return nil
            }
            return rawRecipe.toDish(preserving: dish)
        } catch {
            AppLog.warn("[AIService] Failed to parse modified recipe: \(error)")
            return nil
        }
    }

    // MARK: - Networking (with retry)

    /// Maximum number of retry attempts for transient failures.
    private let maxRetries = AppConfig.aiMaxRetries

    /// Sends a prompt to OpenAI with automatic retry + exponential backoff.
    /// Retries on network errors and 5xx / 429 responses. Gives up on 4xx client errors.
    /// Pass `responseFormat` to enable structured output (e.g. json_schema).
    private func sendChatRequest(prompt: String, maxTokens: Int = 4096, responseFormat: [String: Any]? = nil) async -> String? {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !AppConfig.isMissing(apiKey) else {
            AppLog.info("[AIService] Missing OpenAI API key")
                        telemetryReporter.record(TelemetryEvent(name: "ai.request.skipped", severity: .warning, metadata: ["reason": "missing_api_key"]))
            return nil
        }

        guard let url = URL(string: baseURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AppConfig.aiChatTimeoutSeconds
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": maxTokens
        ]

        if let responseFormat {
            body["response_format"] = responseFormat
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = await performDataRequest(
            operation: "chat_completion",
            request: request,
            successStatusCodes: [200]
        ) else {
            return nil
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        AppLog.warn("[AIService] Received HTTP 200 with unexpected response shape")
        telemetryReporter.record(TelemetryEvent(
            name: "ai.request.invalid_response_shape",
            severity: .warning,
            metadata: ["operation": "chat_completion"]
        ))

        return nil
    }

    private func performDataRequest(
        operation: String,
        request: URLRequest,
        successStatusCodes: Set<Int>
    ) async -> (Data, HTTPURLResponse)? {
        let requestID = UUID().uuidString

        for attempt in 1...maxRetries {
            if Task.isCancelled {
                telemetryReporter.record(TelemetryEvent(
                    name: "ai.request.cancelled",
                    severity: .info,
                    metadata: [
                        "operation": operation,
                        "request_id": requestID,
                        "attempt": String(attempt)
                    ]
                ))
                return nil
            }

            let startedAt = Date()

            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    telemetryReporter.record(TelemetryEvent(
                        name: "ai.request.invalid_response",
                        severity: .error,
                        metadata: [
                            "operation": operation,
                            "request_id": requestID,
                            "attempt": String(attempt)
                        ]
                    ))
                    return nil
                }

                let durationMs = String(Int(Date().timeIntervalSince(startedAt) * 1000))
                let statusCode = httpResponse.statusCode

                if successStatusCodes.contains(statusCode) {
                    telemetryReporter.record(TelemetryEvent(
                        name: "ai.request.completed",
                        severity: attempt == 1 ? .debug : .info,
                        metadata: [
                            "operation": operation,
                            "request_id": requestID,
                            "attempt": String(attempt),
                            "status_code": String(statusCode),
                            "duration_ms": durationMs
                        ]
                    ))
                    return (data, httpResponse)
                }

                let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                let isRetryable = statusCode == 429 || statusCode >= 500

                telemetryReporter.record(TelemetryEvent(
                    name: isRetryable ? "ai.request.retryable_http_error" : "ai.request.http_error",
                    severity: isRetryable ? .warning : .error,
                    metadata: [
                        "operation": operation,
                        "request_id": requestID,
                        "attempt": String(attempt),
                        "status_code": String(statusCode),
                        "duration_ms": durationMs,
                        "body_preview": String(bodyPreview.prefix(200))
                    ]
                ))

                guard isRetryable, attempt < maxRetries else {
                    return nil
                }
            } catch {
                let durationMs = String(Int(Date().timeIntervalSince(startedAt) * 1000))
                telemetryReporter.record(TelemetryEvent(
                    name: attempt < maxRetries ? "ai.request.retryable_transport_error" : "ai.request.transport_error",
                    severity: attempt < maxRetries ? .warning : .error,
                    metadata: [
                        "operation": operation,
                        "request_id": requestID,
                        "attempt": String(attempt),
                        "duration_ms": durationMs,
                        "error": error.localizedDescription
                    ]
                ))

                guard attempt < maxRetries else {
                    AppLog.error("AI Service Error after \(maxRetries) attempts: \(error.localizedDescription)")
                    return nil
                }
            }

            let delaySeconds = Double(attempt) * AppConfig.aiBackoffMultiplier
            telemetryReporter.record(TelemetryEvent(
                name: "ai.request.backoff",
                severity: .info,
                metadata: [
                    "operation": operation,
                    "request_id": requestID,
                    "attempt": String(attempt),
                    "delay_seconds": String(format: "%.2f", delaySeconds)
                ]
            ))
            try? await Task.sleep(for: .seconds(delaySeconds))
        }

        return nil
    }

}
