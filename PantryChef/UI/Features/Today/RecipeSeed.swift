import Foundation

/// Loads the bundled recipe dataset (`seed_recipes.json`, 197 recipes generated for
/// breadth) into `Dish`es — so the Today feed and its filters have real variety. Each
/// ingredient is resolved to a catalog id through the same `IntakePipeline` the editor
/// uses, so seeded recipes match readiness by identity (and `SeedDishCatalogTests`
/// guarantees every line finds a catalog home). Decoded + resolved once per process.
enum RecipeSeed {

    /// The on-disk shape (matches docs/recipe-seed/*.json). Decoupled from `Dish` so the
    /// dataset can carry browse metadata (cuisine/diet/…) the core model didn't need.
    private struct DTO: Decodable {
        let name: String
        let blurb: String?
        let cuisine: String?
        let mealType: String?
        let course: String?
        let diets: [String]?
        let methods: [String]?
        let timeMinutes: Int?
        let servings: Int?
        let plateCategories: [String]?
        let ingredients: [Ingredient]
        let steps: [String]

        struct Ingredient: Decodable {
            let name: String
            let amount: String?
            let category: String?
            let staple: Bool?
            /// Pre-baked catalog id (offline-resolved). When present the loader skips
            /// the expensive runtime resolution — keeps launch a pure decode.
            let catalogId: String?
        }
    }

    private struct Payload: Decodable { let recipes: [DTO] }

    /// FoodCategory keyed by its case name ("produce", "bakingSupplies"), the form the
    /// dataset uses — distinct from the enum's display rawValue ("Produce").
    private static let categoryByKey: [String: FoodCategory] =
        Dictionary(uniqueKeysWithValues: FoodCategory.allCases.map { ("\($0)", $0) })

    /// The seeded dishes, decoded + catalog-resolved once.
    static let all: [Dish] = load()

    private static func load() -> [Dish] {
        // Bundle.main first — it has the resource and is instant. Only fall back to the
        // exhaustive locator (which enumerates every loaded framework, ~hundreds of ms)
        // if that misses, so the seed load doesn't pay that cost on every cold launch.
        guard let url = Bundle.main.url(forResource: "seed_recipes", withExtension: "json")
                ?? AppBundleResourceLocator.url(forResource: "seed_recipes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            AppLog.error("[RecipeSeed] seed_recipes.json not found")
            return []
        }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            // Resolve each distinct ingredient name at most once — across 197 recipes
            // the same names (garlic, olive oil…) recur heavily, so memoizing turns
            // ~1,800 catalog lookups into ~350. Skipped entirely when ids are pre-baked.
            var idCache: [String: String?] = [:]
            func resolve(_ name: String) -> String? {
                let key = name.lowercased()
                if let hit = idCache[key] { return hit }
                let id = IntakePipeline.bestCatalogID(for: name)
                idCache[key] = id
                return id
            }
            return payload.recipes.map { dish(from: $0, resolve: resolve) }
        } catch {
            AppLog.error("[RecipeSeed] decode failed: \(error.localizedDescription)")
            return []
        }
    }

    private static func dish(from r: DTO, resolve: (String) -> String?) -> Dish {
        let cats = (r.plateCategories ?? []).compactMap { categoryByKey[$0] }
        let seed = UInt64(abs(r.name.hashValue) % 100_000)
        let lines = r.ingredients.map { ing -> RecipeLine in
            RecipeLine(key: ing.name.lowercased(),
                       amount: ing.amount,
                       name: ing.name.capitalizedFirst,
                       isStaple: ing.staple ?? false,
                       catalogItemID: ing.catalogId ?? resolve(ing.name))
        }
        return Dish(
            name: r.name,
            plate: PlateComposition(categories: cats, seed: seed),
            time: timeString(r.timeMinutes),
            servings: max(1, r.servings ?? 2),
            blurb: r.blurb,
            ingredients: lines,
            steps: r.steps.map { CookStep($0) },
            cuisine: r.cuisine,
            mealType: r.mealType,
            course: r.course,
            diets: r.diets ?? [],
            methods: r.methods ?? [])
    }

    /// "25 min" / "1 h 30" — the display form `Dish.minutes` parses back.
    private static func timeString(_ minutes: Int?) -> String {
        guard let m = minutes, m > 0 else { return "—" }
        if m < 60 { return "\(m) min" }
        let h = m / 60, rem = m % 60
        return rem == 0 ? "\(h) h" : "\(h) h \(rem)"
    }
}

private extension String {
    /// First letter upper-cased, the rest left as written ("baby spinach" → "Baby spinach").
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
