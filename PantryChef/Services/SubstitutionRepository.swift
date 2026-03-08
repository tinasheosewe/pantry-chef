import Foundation

/// Loads and serves ingredient substitutions from the bundled JSON.
///
/// Data sources (merged at build time by `Scripts/preprocess_miskg.py`):
/// - **Hand-curated**: 60 common ingredients with full metadata (ratio, impact, notes, dietary tags)
/// - **MISKG**: ~2,800 ingredients filtered from 80 K pairs, nutrition-ranked, no detailed metadata
///
/// Entries tagged `enriched == true` have ratio / impact data.
/// Entries tagged `enriched == false` are MISKG-sourced (substitute name + nutritionImpact only).
///
/// **License**: MISKG data is CC BY-NC 4.0.
/// TODO: Replace with commercially-licensed data before monetization.
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

    /// Return substitutions, sorted so pantry-available items come first.
    func substitutions(for ingredientName: String, pantry: [PantryItem]) -> [SubstitutionEntry] {
        let pantryNames = Set(pantry.map { IngredientMatcher.normalize($0.name) })
        var results = substitutions(for: ingredientName)
        for i in results.indices {
            results[i].inPantry = pantryNames.contains(IngredientMatcher.normalize(results[i].substitute))
        }
        results.sort { lhs, rhs in
            if lhs.inPantry != rhs.inPantry { return lhs.inPantry }
            if lhs.enriched != rhs.enriched { return lhs.enriched }
            return false
        }
        return results
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
            let ratio: String?
            let tasteImpact: String?
            let textureImpact: String?
            let nutritionImpact: String?
            let notes: String?
            let dietary: [String]?
            let enriched: Bool?
        }

        guard let root = try? JSONDecoder().decode(JSONRoot.self, from: data) else { return }

        for (ingredient, subs) in root.substitutions {
            let normalized = IngredientMatcher.normalize(ingredient)
            store[normalized] = subs.map { sub in
                SubstitutionEntry(
                    original: ingredient,
                    substitute: sub.substitute,
                    ratio: sub.ratio,
                    tasteImpact: sub.tasteImpact.flatMap { parseImpact($0) },
                    textureImpact: sub.textureImpact.flatMap { parseImpact($0) },
                    nutritionImpact: sub.nutritionImpact,
                    notes: sub.notes,
                    dietary: sub.dietary?.compactMap { DietaryTag(rawValue: $0) },
                    enriched: sub.enriched ?? true
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
                SubstitutionEntry(original: "butter", substitute: "coconut oil", ratio: "1:1", tasteImpact: .slight, textureImpact: .slight, nutritionImpact: "Similar", notes: "Adds coconut flavor", dietary: [.vegan, .dairyFree], enriched: true),
                SubstitutionEntry(original: "butter", substitute: "olive oil", ratio: "3/4 cup per 1 cup", tasteImpact: .moderate, textureImpact: .moderate, nutritionImpact: "Similar", notes: "Best for savory dishes", dietary: [.vegan, .dairyFree], enriched: true),
            ],
            "egg": [
                SubstitutionEntry(original: "egg", substitute: "flax egg", ratio: "1 tbsp flax + 3 tbsp water", tasteImpact: .slight, textureImpact: .moderate, nutritionImpact: "Lower protein", notes: "Let sit 5 min", dietary: [.vegan], enriched: true),
            ],
            "milk": [
                SubstitutionEntry(original: "milk", substitute: "oat milk", ratio: "1:1", tasteImpact: .slight, textureImpact: .slight, nutritionImpact: "Similar", notes: "Creamy alternative", dietary: [.vegan, .dairyFree], enriched: true),
            ],
            "soy sauce": [
                SubstitutionEntry(original: "soy sauce", substitute: "coconut aminos", ratio: "1:1", tasteImpact: .slight, textureImpact: .none, nutritionImpact: "Lower sodium", notes: "Less sodium", dietary: [.glutenFree], enriched: true),
            ],
            "chicken breast": [
                SubstitutionEntry(original: "chicken breast", substitute: "tofu", ratio: "1:1 by weight", tasteImpact: .significant, textureImpact: .moderate, nutritionImpact: "Lower fat, higher fiber", notes: "Press well, extra firm", dietary: [.vegan, .vegetarian], enriched: true),
            ],
        ]
    }
}
