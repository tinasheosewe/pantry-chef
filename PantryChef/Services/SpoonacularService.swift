import Foundation

/// Client for the Spoonacular API — ingredient-based search, complex search, recipe details.
/// Rate-limited to 1 req/sec. Maps responses → local Recipe model.
actor SpoonacularService {

    static let shared = SpoonacularService()

    private let baseURL = "https://api.spoonacular.com"
    private let session: URLSession
    private var lastRequestTime: Date?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    // MARK: - Search by Ingredients

    struct IngredientSearchResult: Sendable {
        let spoonacularId: Int
        let title: String
        let imageURL: String?
        let usedIngredientCount: Int
        let missedIngredientCount: Int
        let missedIngredients: [String]
    }

    /// Search recipes by ingredients the user has.
    func searchByIngredients(
        ingredients: [String],
        number: Int = 20,
        ranking: Int = 1 // 1 = maximize used, 2 = minimize missing
    ) async throws -> [IngredientSearchResult] {
        let ingredientList = ingredients.joined(separator: ",+")
        let query = "ingredients=\(ingredientList)&number=\(number)&ranking=\(ranking)"
        let url = try buildURL(path: "/recipes/findByIngredients", query: query)
        let data = try await fetch(url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return json.compactMap { item in
            guard let id = item["id"] as? Int,
                  let title = item["title"] as? String else { return nil }
            let imageURL = item["image"] as? String
            let used = item["usedIngredientCount"] as? Int ?? 0
            let missed = item["missedIngredientCount"] as? Int ?? 0
            let missedIngs = (item["missedIngredients"] as? [[String: Any]])?.compactMap {
                $0["name"] as? String
            } ?? []
            return IngredientSearchResult(
                spoonacularId: id,
                title: title,
                imageURL: imageURL,
                usedIngredientCount: used,
                missedIngredientCount: missed,
                missedIngredients: missedIngs
            )
        }
    }

    // MARK: - Complex Search (filters)

    struct ComplexSearchParams {
        var query: String?
        var cuisine: CuisineType?
        var mealType: MealType?
        var diet: DietaryTag?
        var maxReadyTime: Int?
        var includeIngredients: [String]?
        var sort: String?           // e.g. "popularity", "healthiness", "time"
        var sortDirection: String?   // "asc" or "desc"
        var number: Int = 20
        var offset: Int = 0
    }

    struct ComplexSearchResult: Sendable {
        let spoonacularId: Int
        let title: String
        let imageURL: String?
        let readyInMinutes: Int?
    }

    func complexSearch(_ params: ComplexSearchParams) async throws -> (results: [ComplexSearchResult], totalResults: Int) {
        var queryParts: [String] = []
        if let q = params.query, !q.isEmpty { queryParts.append("query=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)") }
        if let cuisine = params.cuisine { queryParts.append("cuisine=\(cuisine.rawValue)") }
        if let mealType = params.mealType {
            let mapped = mapMealType(mealType)
            queryParts.append("type=\(mapped)")
        }
        if let diet = params.diet { queryParts.append("diet=\(mapDiet(diet))") }
        if let time = params.maxReadyTime { queryParts.append("maxReadyTime=\(time)") }
        if let ings = params.includeIngredients, !ings.isEmpty {
            queryParts.append("includeIngredients=\(ings.joined(separator: ",+"))")
        }
        if let sort = params.sort { queryParts.append("sort=\(sort)") }
        if let dir = params.sortDirection { queryParts.append("sortDirection=\(dir)") }
        queryParts.append("number=\(params.number)")
        queryParts.append("offset=\(params.offset)")
        queryParts.append("addRecipeInformation=true")
        queryParts.append("fillIngredients=true")

        let url = try buildURL(path: "/recipes/complexSearch", query: queryParts.joined(separator: "&"))
        let data = try await fetch(url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return ([], 0)
        }

        let total = json["totalResults"] as? Int ?? 0
        let items = results.compactMap { item -> ComplexSearchResult? in
            guard let id = item["id"] as? Int,
                  let title = item["title"] as? String else { return nil }
            return ComplexSearchResult(
                spoonacularId: id,
                title: title,
                imageURL: item["image"] as? String,
                readyInMinutes: item["readyInMinutes"] as? Int
            )
        }
        return (items, total)
    }

    /// Complex search that returns fully-mapped Recipe models in a single API call.
    /// Uses addRecipeInformation=true so no per-recipe detail calls are needed.
    func complexSearchWithRecipes(_ params: ComplexSearchParams) async throws -> (recipes: [Recipe], totalResults: Int) {
        var queryParts: [String] = []
        if let q = params.query, !q.isEmpty { queryParts.append("query=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)") }
        if let cuisine = params.cuisine { queryParts.append("cuisine=\(cuisine.rawValue)") }
        if let mealType = params.mealType {
            let mapped = mapMealType(mealType)
            queryParts.append("type=\(mapped)")
        }
        if let diet = params.diet { queryParts.append("diet=\(mapDiet(diet))") }
        if let time = params.maxReadyTime { queryParts.append("maxReadyTime=\(time)") }
        if let ings = params.includeIngredients, !ings.isEmpty {
            queryParts.append("includeIngredients=\(ings.joined(separator: ",+"))")
        }
        if let sort = params.sort { queryParts.append("sort=\(sort)") }
        if let dir = params.sortDirection { queryParts.append("sortDirection=\(dir)") }
        queryParts.append("number=\(params.number)")
        queryParts.append("offset=\(params.offset)")
        queryParts.append("addRecipeInformation=true")
        queryParts.append("addRecipeInstructions=true")
        queryParts.append("instructionsRequired=true")
        queryParts.append("fillIngredients=true")
        queryParts.append("addRecipeNutrition=true")

        let url = try buildURL(path: "/recipes/complexSearch", query: queryParts.joined(separator: "&"))
        let data = try await fetch(url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return ([], 0)
        }

        let total = json["totalResults"] as? Int ?? 0
        let recipes = results.compactMap { item -> Recipe? in
            guard let id = item["id"] as? Int else { return nil }
            return mapToRecipe(item, spoonacularId: id)
        }
        return (recipes, total)
    }

    // MARK: - Get Recipe Detail

    /// Fetch full recipe information and convert to local Recipe model.
    func getRecipeDetail(id: Int) async throws -> Recipe? {
        let url = try buildURL(path: "/recipes/\(id)/information", query: "includeNutrition=true")
        let data = try await fetch(url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return mapToRecipe(json, spoonacularId: id)
    }

    // MARK: - Mapping

    private func mapToRecipe(_ json: [String: Any], spoonacularId: Int) -> Recipe? {
        guard let title = json["title"] as? String else { return nil }

        let summary = (json["summary"] as? String)?.strippingHTML()
        let servings = json["servings"] as? Int ?? 4
        let readyMin = json["readyInMinutes"] as? Int
        let prepMin = json["preparationMinutes"] as? Int
        let cookMin = json["cookingMinutes"] as? Int

        // Ingredients
        let extIngredients = json["extendedIngredients"] as? [[String: Any]] ?? []
        let ingredients: [Ingredient] = extIngredients.compactMap { ing in
            guard let name = ing["name"] as? String else { return nil }
            let amount = ing["amount"] as? Double ?? 0
            let unitStr = ing["unit"] as? String
            let unit = parseSpoonUnit(unitStr)
            let aisle = ing["aisle"] as? String
            return Ingredient(
                name: name,
                quantity: amount,
                unit: unit,
                category: mapAisle(aisle),
                isOptional: false
            )
        }

        // Steps
        let analyzedSteps = json["analyzedInstructions"] as? [[String: Any]] ?? []
        var steps: [RecipeStep] = []
        if let firstSet = analyzedSteps.first,
           let stepList = firstSet["steps"] as? [[String: Any]] {
            steps = stepList.enumerated().compactMap { (idx, stepJson) -> RecipeStep? in
                guard let instruction = stepJson["step"] as? String, !instruction.isEmpty else { return nil }
                return RecipeStep(
                    stepNumber: idx + 1,
                    instruction: instruction,
                    timerMinutes: nil,
                    estimatedDurationSeconds: nil
                )
            }
        }

        // Difficulty estimation
        let difficulty: DifficultyLevel = {
            if steps.count <= 3 { return .beginner }
            if steps.count <= 6 { return .easy }
            if steps.count <= 10 { return .medium }
            if steps.count <= 15 { return .hard }
            return .expert
        }()

        // Dietary tags
        var tags: [DietaryTag] = []
        if json["vegetarian"] as? Bool == true { tags.append(.vegetarian) }
        if json["vegan"] as? Bool == true { tags.append(.vegan) }
        if json["glutenFree"] as? Bool == true { tags.append(.glutenFree) }
        if json["dairyFree"] as? Bool == true { tags.append(.dairyFree) }

        // Meal type
        let dishTypes = json["dishTypes"] as? [String] ?? []
        let mealType = mapDishTypes(dishTypes)

        // Cuisine
        let cuisines = json["cuisines"] as? [String] ?? []
        let cuisine = mapCuisines(cuisines)

        // Nutrition
        var nutrition: NutritionInfo?
        if let nutritionJson = json["nutrition"] as? [String: Any],
           let nutrients = nutritionJson["nutrients"] as? [[String: Any]] {
            let cal = nutrients.first { ($0["name"] as? String) == "Calories" }?["amount"] as? Double
            let protein = nutrients.first { ($0["name"] as? String) == "Protein" }?["amount"] as? Double
            let carbs = nutrients.first { ($0["name"] as? String) == "Carbohydrates" }?["amount"] as? Double
            let fat = nutrients.first { ($0["name"] as? String) == "Fat" }?["amount"] as? Double
            let fiber = nutrients.first { ($0["name"] as? String) == "Fiber" }?["amount"] as? Double
            let sugar = nutrients.first { ($0["name"] as? String) == "Sugar" }?["amount"] as? Double
            let sodium = nutrients.first { ($0["name"] as? String) == "Sodium" }?["amount"] as? Double
            if let cal {
                nutrition = NutritionInfo(
                    calories: Int(cal),
                    protein: protein ?? 0,
                    carbohydrates: carbs ?? 0,
                    fat: fat ?? 0,
                    fiber: fiber,
                    sugar: sugar,
                    sodium: sodium
                )
            }
        }

        return TrustedRecipeCanonicalizer.canonicalize(Recipe(
            title: title,
            description: summary,
            ingredients: ingredients,
            steps: steps,
            servings: servings,
            prepTimeMinutes: prepMin ?? (readyMin.map { max(0, $0 - (cookMin ?? 0)) }),
            cookTimeMinutes: cookMin ?? readyMin,
            difficulty: difficulty,
            dietaryTags: tags,
            mealType: mealType,
            cuisine: cuisine,
            source: .spoonacular(id: spoonacularId),
            nutrition: nutrition
        ))
    }

    // MARK: - Helpers

    private func buildURL(path: String, query: String) throws -> URL {
        let key = AppConfig.spoonacularAPIKey
        guard !AppConfig.isMissing(key) else {
            throw SpoonacularError.missingAPIKey
        }
        let urlString = "\(baseURL)\(path)?\(query)&apiKey=\(key)"
        guard let url = URL(string: urlString) else {
            throw SpoonacularError.invalidURL
        }
        return url
    }

    private func fetch(_ url: URL) async throws -> Data {
        // Simple rate limiting: 1 req/sec
        if let last = lastRequestTime {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < 1.0 {
                try await Task.sleep(nanoseconds: UInt64((1.0 - elapsed) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw SpoonacularError.networkError("Invalid response")
        }
        switch http.statusCode {
        case 200...299: return data
        case 402: throw SpoonacularError.quotaExceeded
        case 401: throw SpoonacularError.invalidAPIKey
        default: throw SpoonacularError.networkError("HTTP \(http.statusCode)")
        }
    }

    private func parseSpoonUnit(_ str: String?) -> MeasurementUnit? {
        MeasurementUnit.parse(str)
    }

    private func mapAisle(_ aisle: String?) -> FoodCategory {
        FoodCategory.infer(from: aisle)
    }

    private func mapMealType(_ type: MealType) -> String {
        switch type {
        case .breakfast: return "breakfast"
        case .lunch: return "main+course"
        case .dinner: return "main+course"
        case .snack: return "snack"
        case .dessert: return "dessert"
        }
    }

    private func mapDiet(_ tag: DietaryTag) -> String {
        switch tag {
        case .vegetarian: return "vegetarian"
        case .vegan: return "vegan"
        case .glutenFree: return "gluten+free"
        case .dairyFree: return "dairy+free"
        case .keto: return "ketogenic"
        case .paleo: return "paleo"
        default: return ""
        }
    }

    private func mapDishTypes(_ types: [String]) -> MealType? {
        for t in types {
            let lc = t.lowercased()
            if lc.contains("breakfast") || lc.contains("morning") { return .breakfast }
            if lc.contains("lunch") { return .lunch }
            if lc.contains("dinner") || lc.contains("main") { return .dinner }
            if lc.contains("dessert") { return .dessert }
            if lc.contains("snack") || lc.contains("appetizer") { return .snack }
        }
        return nil
    }

    private func mapCuisines(_ cuisines: [String]) -> CuisineType? {
        for c in cuisines {
            if let ct = CuisineType(rawValue: c) { return ct }
            // Fuzzy match
            let lc = c.lowercased()
            for cuisine in CuisineType.allCases where cuisine != .other {
                if lc.contains(cuisine.rawValue.lowercased()) { return cuisine }
            }
        }
        return nil
    }
}

// MARK: - Errors

enum SpoonacularError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidAPIKey
    case quotaExceeded
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Spoonacular API key not configured"
        case .invalidURL: return "Invalid request URL"
        case .invalidAPIKey: return "Invalid API key"
        case .quotaExceeded: return "API quota exceeded. Try again later."
        case .networkError(let msg): return "Network error: \(msg)"
        }
    }
}

// MARK: - String HTML Stripping

private extension String {
    func strippingHTML() -> String {
        // Use regex-only stripping to avoid UIKit/WebKit HTML parsing on background threads.
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
