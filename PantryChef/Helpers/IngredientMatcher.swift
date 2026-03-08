import Foundation

/// High-performance, offline ingredient matching engine.
/// Replaces naive substring matching with normalized names, synonym dictionary,
/// category-aware fallback, quantity checking, and substitution integration.
enum IngredientMatcher {

    // MARK: - Public API

    /// Full pantry match including substitution lookup.
    static func match(recipe: Recipe, pantry: [PantryItem]) -> PantryMatchResult {
        let required = recipe.ingredients.filter { !$0.isOptional }
        var matched: [Ingredient] = []
        var missing: [Ingredient] = []

        for ingredient in required {
            if pantryContains(ingredient: ingredient, pantry: pantry) {
                matched.append(ingredient)
            } else {
                missing.append(ingredient)
            }
        }

        let matchPct = required.isEmpty ? 0 : Double(matched.count) / Double(required.count) * 100

        // Look up substitutions for missing ingredients
        let subRepo = SubstitutionRepository.shared
        var substitutable: [(ingredient: Ingredient, substitutions: [SubstitutionEntry])] = []

        for ingredient in missing {
            let subs = subRepo.substitutions(for: ingredient.name)
            // Only include subs the user actually has in their pantry
            let availableSubs = subs.filter { sub in
                pantry.contains { pantryItem in
                    namesMatch(pantryItem.name, sub.substitute)
                }
            }
            if !availableSubs.isEmpty {
                substitutable.append((ingredient: ingredient, substitutions: availableSubs))
            }
        }

        let subCount = substitutable.count
        let effectivePct = required.isEmpty ? 0 :
            Double(matched.count + subCount) / Double(required.count) * 100
        let canMakeWithSubs = missing.count == subCount && !missing.isEmpty

        return PantryMatchResult(
            recipe: recipe,
            matchedIngredients: matched,
            missingIngredients: missing,
            matchPercentage: matchPct,
            substitutableIngredients: substitutable,
            canMakeWithSubstitutions: canMakeWithSubs,
            effectiveMatchPercentage: effectivePct
        )
    }

    /// Quick check: does the pantry contain something matching this ingredient?
    static func pantryContains(ingredient: Ingredient, pantry: [PantryItem]) -> Bool {
        pantry.contains { item in
            namesMatch(item.name, ingredient.name)
        }
    }

    /// Normalized name comparison with synonym awareness.
    static func namesMatch(_ a: String, _ b: String) -> Bool {
        let na = normalize(a)
        let nb = normalize(b)

        // Direct match
        if na == nb { return true }

        // Containment (handles "chicken breast" matching "chicken")
        if na.contains(nb) || nb.contains(na) { return true }

        // Synonym check
        let synsA = synonymGroup(for: na)
        let synsB = synonymGroup(for: nb)
        if !synsA.isEmpty && synsA == synsB { return true }

        // Check if either normalized name matches any synonym of the other
        if synsA.contains(nb) || synsB.contains(na) { return true }

        // Token overlap for compound names: "bell pepper" vs "red bell pepper"
        let tokensA = Set(na.split(separator: " ").map(String.init))
        let tokensB = Set(nb.split(separator: " ").map(String.init))
        let overlap = tokensA.intersection(tokensB)
        // If the shorter name's tokens are fully contained in the longer
        let shorter = tokensA.count <= tokensB.count ? tokensA : tokensB
        if shorter.count >= 1 && overlap == shorter { return true }

        return false
    }

    // MARK: - Normalization

    /// Strips adjectives, plurals, and normalizes whitespace.
    static func normalize(_ name: String) -> String {
        var s = name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove common adjectives/modifiers
        for word in stripWords {
            s = s.replacingOccurrences(of: "\\b\(word)\\b", with: "", options: .regularExpression)
        }

        // Collapse whitespace
        s = s.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        // Simple depluralize (handles "onions" → "onion", "tomatoes" → "tomato")
        if s.hasSuffix("ies") {
            s = String(s.dropLast(3)) + "y"
        } else if s.hasSuffix("oes") {
            s = String(s.dropLast(2))
        } else if s.hasSuffix("es") && !s.hasSuffix("ses") {
            s = String(s.dropLast(2))
        } else if s.hasSuffix("s") && !s.hasSuffix("ss") {
            s = String(s.dropLast())
        }

        return s
    }

    // MARK: - Synonym Dictionary

    /// Returns the canonical synonym group for a normalized name, or empty set.
    static func synonymGroup(for normalizedName: String) -> Set<String> {
        if let group = synonymIndex[normalizedName] {
            return group
        }
        return []
    }

    // MARK: - Quantity Check

    /// Returns true if the pantry item has enough quantity for the ingredient.
    /// Returns true (optimistic) if quantities can't be compared.
    static func hasEnoughQuantity(pantryItem: PantryItem, ingredient: Ingredient) -> Bool {
        guard let pantryQty = pantryItem.quantity,
              let pantryUnit = pantryItem.unit,
              let ingredientUnit = ingredient.unit else {
            return true // Can't compare → assume yes
        }

        // Try to convert to common unit
        if let converted = UnitConverter.convert(pantryQty, from: pantryUnit, to: ingredientUnit) {
            return converted >= ingredient.quantity
        }

        // Same unit, direct compare
        if pantryUnit == ingredientUnit {
            return pantryQty >= ingredient.quantity
        }

        return true // Can't convert → assume yes
    }

    // MARK: - Private Data

    /// Common words to strip from ingredient names for matching.
    private static let stripWords: [String] = [
        "fresh", "dried", "frozen", "organic", "large", "small", "medium",
        "whole", "chopped", "diced", "minced", "sliced", "ground", "raw",
        "cooked", "boneless", "skinless", "extra", "virgin", "light",
        "heavy", "low-fat", "fat-free", "unsalted", "salted", "canned",
        "packed", "plain", "all-purpose", "self-rising", "unbleached",
        "fine", "coarse", "baby", "ripe", "firm", "soft", "thin", "thick",
    ]

    /// Synonym groups — sets of interchangeable ingredient names (normalized).
    private static let synonymGroups: [Set<String>] = [
        // Alliums
        ["green onion", "scallion", "spring onion"],
        ["shallot", "french shallot"],
        // Peppers
        ["bell pepper", "capsicum", "sweet pepper"],
        ["chili pepper", "chilli", "chile", "hot pepper"],
        ["jalapeno", "jalapeño"],
        // Herbs
        ["cilantro", "coriander", "coriander leaf"],
        ["parsley", "flat leaf parsley", "italian parsley"],
        // Starches
        ["cornstarch", "corn starch", "corn flour"],
        ["potato starch", "potato flour"],
        // Proteins
        ["chicken breast", "chicken"],
        ["ground beef", "beef mince", "minced beef"],
        ["ground turkey", "turkey mince"],
        ["shrimp", "prawn"],
        // Dairy
        ["heavy cream", "whipping cream", "double cream"],
        ["sour cream", "crème fraîche"],
        ["greek yogurt", "greek yoghurt", "strained yogurt"],
        // Grains
        ["all purpose flour", "plain flour", "ap flour", "flour"],
        ["bread flour", "strong flour"],
        // Oils
        ["olive oil", "extra virgin olive oil", "evoo"],
        ["vegetable oil", "canola oil", "neutral oil"],
        // Sauces
        ["soy sauce", "shoyu", "tamari"],
        ["fish sauce", "nam pla"],
        // Sweeteners
        ["sugar", "granulated sugar", "white sugar"],
        ["brown sugar", "dark brown sugar", "light brown sugar"],
        ["powdered sugar", "confectioner sugar", "icing sugar"],
        // Misc
        ["garbanzo", "chickpea"],
        ["eggplant", "aubergine"],
        ["zucchini", "courgette"],
        ["arugula", "rocket"],
        ["beet", "beetroot"],
        ["stock", "broth"],
        ["chicken stock", "chicken broth"],
        ["beef stock", "beef broth"],
        ["vegetable stock", "vegetable broth"],
        ["baking soda", "bicarbonate of soda", "bicarb"],
        ["baking powder", "raising agent"],
        ["cream cheese", "neufchatel"],
        ["egg", "egg whole"],
    ]

    /// Precomputed index: normalized name → its synonym group.
    private static let synonymIndex: [String: Set<String>] = {
        var idx: [String: Set<String>] = [:]
        for group in synonymGroups {
            for name in group {
                idx[name] = group
            }
        }
        return idx
    }()
}
