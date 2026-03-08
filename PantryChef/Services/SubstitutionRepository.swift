import Foundation

/// Loads and serves ingredient substitutions from the bundled JSON.
/// O(1) dictionary lookup — no AI calls needed for common ingredients.
final class SubstitutionRepository: @unchecked Sendable {

    static let shared = SubstitutionRepository()

    /// normalized ingredient name → array of substitution entries
    private var store: [String: [SubstitutionEntry]] = [:]

    private init() {
        loadBundledData()
    }

    // MARK: - Public API

    /// Look up substitutions for an ingredient name. Returns empty if none found.
    func substitutions(for ingredientName: String) -> [SubstitutionEntry] {
        let normalized = IngredientMatcher.normalize(ingredientName)
        if let direct = store[normalized] {
            return direct
        }
        // Try synonym group fallback
        let group = IngredientMatcher.synonymGroup(for: normalized)
        for syn in group {
            if let found = store[syn] {
                return found
            }
        }
        return []
    }

    /// Check if we have local substitutions for this ingredient.
    func hasSubstitutions(for ingredientName: String) -> Bool {
        !substitutions(for: ingredientName).isEmpty
    }

    /// All ingredient names we have substitutions for (normalized).
    var allIngredients: [String] {
        Array(store.keys).sorted()
    }

    // MARK: - Loading

    private func loadBundledData() {
        guard let url = Bundle.main.url(forResource: "substitutions", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            // Fallback: load from hardcoded path in development
            loadFallbackData()
            return
        }
        parseJSON(data)
    }

    private func parseJSON(_ data: Data) {
        struct JSONRoot: Decodable {
            let substitutions: [String: [JSONSub]]
        }

        struct JSONSub: Decodable {
            let substitute: String
            let ratio: String
            let tasteImpact: String
            let textureImpact: String
            let notes: String?
            let dietary: [String]
        }

        guard let root = try? JSONDecoder().decode(JSONRoot.self, from: data) else { return }

        for (ingredient, subs) in root.substitutions {
            let normalized = IngredientMatcher.normalize(ingredient)
            store[normalized] = subs.map { sub in
                SubstitutionEntry(
                    original: ingredient,
                    substitute: sub.substitute,
                    ratio: sub.ratio,
                    tasteImpact: parseImpact(sub.tasteImpact),
                    textureImpact: parseImpact(sub.textureImpact),
                    notes: sub.notes,
                    dietary: sub.dietary.compactMap { DietaryTag(rawValue: $0) }
                )
            }
        }
    }

    private func parseImpact(_ string: String) -> SubstitutionImpact {
        switch string.lowercased() {
        case "none": return .none
        case "slight": return .slight
        case "moderate": return .moderate
        case "significant": return .significant
        default: return .moderate
        }
    }

    /// Fallback with a few hardcoded entries for development/testing.
    private func loadFallbackData() {
        store = [
            "butter": [
                SubstitutionEntry(original: "butter", substitute: "coconut oil", ratio: "1:1", tasteImpact: .slight, textureImpact: .slight, notes: "Adds coconut flavor", dietary: [.vegan, .dairyFree]),
                SubstitutionEntry(original: "butter", substitute: "olive oil", ratio: "3/4 cup per 1 cup", tasteImpact: .moderate, textureImpact: .moderate, notes: "Best for savory dishes", dietary: [.vegan, .dairyFree]),
            ],
            "egg": [
                SubstitutionEntry(original: "egg", substitute: "flax egg", ratio: "1 tbsp flax + 3 tbsp water", tasteImpact: .slight, textureImpact: .moderate, notes: "Let sit 5 min", dietary: [.vegan]),
            ],
            "milk": [
                SubstitutionEntry(original: "milk", substitute: "oat milk", ratio: "1:1", tasteImpact: .slight, textureImpact: .slight, notes: "Creamy alternative", dietary: [.vegan, .dairyFree]),
            ],
            "soy sauce": [
                SubstitutionEntry(original: "soy sauce", substitute: "coconut aminos", ratio: "1:1", tasteImpact: .slight, textureImpact: .none, notes: "Less sodium", dietary: [.glutenFree]),
            ],
            "chicken breast": [
                SubstitutionEntry(original: "chicken breast", substitute: "tofu", ratio: "1:1 by weight", tasteImpact: .significant, textureImpact: .moderate, notes: "Press well, extra firm", dietary: [.vegan, .vegetarian]),
            ],
        ]
    }
}
