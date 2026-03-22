import Foundation

enum IngredientResolutionStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case resolved
    case ambiguous
    case unknown
}

struct IngredientResolutionCandidate: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let catalogItemID: String
    let facets: [PantryFacetSelection]
    let displayName: String
    let score: Double
    let rationale: String
    let supportedFacets: [PantryFacetDefinition]
}

struct IngredientResolutionDecision: Codable, Hashable, Sendable {
    let ingredientID: UUID
    let status: IngredientResolutionStatus
    let selectedCandidateID: String?
    let candidateIDs: [String]
    let confidence: Double
    let rationale: String
}

struct IngredientResolutionRequest: Codable, Hashable, Sendable {
    let ingredientID: UUID
    let rawName: String
    let quantity: Double
    let unit: MeasurementUnit?
    let category: FoodCategory
    let notes: String?
    let candidates: [IngredientResolutionCandidate]
}

struct ResolvedIngredientDraft: Identifiable, Hashable, Sendable {
    var ingredient: Ingredient
    var status: IngredientResolutionStatus
    var candidates: [IngredientResolutionCandidate]
    var selectedCandidateID: String?
    var confidence: Double
    var rationale: String

    var id: UUID { ingredient.id }

    init(
        ingredient: Ingredient,
        status: IngredientResolutionStatus,
        candidates: [IngredientResolutionCandidate] = [],
        selectedCandidateID: String? = nil,
        confidence: Double = 0,
        rationale: String = ""
    ) {
        self.ingredient = ingredient
        self.status = status
        self.candidates = candidates
        self.selectedCandidateID = selectedCandidateID
        self.confidence = confidence
        self.rationale = rationale
    }

    var requiresUserChoice: Bool {
        status == .ambiguous
    }

    var selectedCandidate: IngredientResolutionCandidate? {
        guard let selectedCandidateID else { return nil }
        return candidates.first { $0.id == selectedCandidateID }
    }

    var resolvedIngredient: Ingredient {
        guard let selectedCandidate else {
            return ingredient.unresolved()
        }
        return ingredient.resolved(to: selectedCandidate.catalogItemID, facets: selectedCandidate.facets)
    }

    mutating func applyDecision(_ decision: IngredientResolutionDecision) {
        status = decision.status
        selectedCandidateID = decision.selectedCandidateID
        confidence = decision.confidence
        rationale = decision.rationale
    }

    mutating func chooseCandidate(_ candidate: IngredientResolutionCandidate) {
        status = .resolved
        selectedCandidateID = candidate.id
        confidence = max(confidence, candidate.score)
        rationale = candidate.rationale
    }
}

struct RecipeResolutionDraft: Identifiable, Hashable, Sendable {
    var id: UUID
    var recipe: Recipe
    var ingredients: [ResolvedIngredientDraft]

    init(id: UUID = UUID(), recipe: Recipe, ingredients: [ResolvedIngredientDraft]) {
        self.id = id
        self.recipe = recipe
        self.ingredients = ingredients
    }

    var ambiguousIngredients: [ResolvedIngredientDraft] {
        ingredients.filter(\.requiresUserChoice)
    }

    var unknownIngredients: [ResolvedIngredientDraft] {
        ingredients.filter { $0.status == .unknown }
    }

    var isReadyToBuild: Bool {
        ambiguousIngredients.isEmpty
    }

    func builtRecipe() -> Recipe {
        var resolvedRecipe = recipe
        resolvedRecipe.ingredients = ingredients.map(\.resolvedIngredient)
        return resolvedRecipe
    }
}

enum TrustedRecipeCanonicalizer {
    private static let parser = IngredientCandidateParser(maxCandidates: 1)

    static func canonicalize(_ recipe: Recipe) -> Recipe {
        var canonicalRecipe = recipe
        canonicalRecipe.ingredients = recipe.ingredients.map(canonicalize)
        return canonicalRecipe
    }

    private static func canonicalize(_ ingredient: Ingredient) -> Ingredient {
        if ingredient.isResolved {
            return ingredient
        }

        if let candidate = parser.candidates(for: ingredient).first,
           candidate.score >= 0.9 {
            return ingredient.resolved(to: candidate.catalogItemID, facets: candidate.facets)
        }

        guard let item = PantryCatalog.resolveExact(name: ingredient.rawName) else {
            return ingredient
        }

        return ingredient.resolved(to: item.id, facets: item.defaultSelections)
    }
}