import XCTest
@testable import PantryChef

@MainActor
final class RecipeIngredientResolutionTests: XCTestCase {
    func testBuiltinRecipesAreFullyMapped() {
        let sampleRecipes = Recipe.samples
        let bundledRecipes = RecipeRepository.shared.seedRecipes
        let allRecipes = sampleRecipes + bundledRecipes

        XCTAssertFalse(sampleRecipes.isEmpty)
        XCTAssertFalse(bundledRecipes.isEmpty)

        let unresolved = allRecipes.flatMap { recipe in
            recipe.ingredients.compactMap { ingredient -> String? in
                guard !ingredient.isResolved else { return nil }
                return "\(recipe.title): \(ingredient.rawName)"
            }
        }

        XCTAssertTrue(
            unresolved.isEmpty,
            "Unresolved builtin ingredients:\n\(unresolved.sorted().joined(separator: "\n"))"
        )
    }

    func testCandidateParserPrefersFacetSpecificAliasMatch() {
        let parser = IngredientCandidateParser()
        let ingredient = Ingredient(name: "Greek yogurt")

        let candidates = parser.candidates(for: ingredient)

        XCTAssertEqual(candidates.first?.catalogItemID, "yogurt")
        XCTAssertEqual(candidates.first?.facets, [.init(key: .variant, value: "greek")])
        XCTAssertEqual(candidates.first?.displayName, "Greek Yogurt")
    }

    func testCandidateParserUsesSharedSynonymExpansion() {
        let parser = IngredientCandidateParser()
        let ingredient = Ingredient(name: "plain flour")

        let candidates = parser.candidates(for: ingredient)

        XCTAssertEqual(candidates.first?.catalogItemID, "flour")
        XCTAssertEqual(candidates.first?.facets, [.init(key: .variant, value: "all-purpose")])
        XCTAssertEqual(candidates.first?.displayName, "All-purpose Flour")
        XCTAssertTrue(candidates.first?.rationale.contains("Synonym expansion") == true)
    }

    func testCandidateParserUsesFacetTemplatesForVariantPhrases() {
        let parser = IngredientCandidateParser()
        let ingredient = Ingredient(name: "jasmine rice")

        let candidates = parser.candidates(for: ingredient)

        XCTAssertEqual(candidates.first?.catalogItemID, "rice")
        XCTAssertEqual(candidates.first?.facets, [.init(key: .variant, value: "jasmine")])
        XCTAssertEqual(candidates.first?.displayName, "Jasmine Rice")
    }

    func testCandidateParserResolvesStructuredBeefCuts() {
        let parser = IngredientCandidateParser()
        let ingredient = Ingredient(name: "beef stew meat")

        let candidates = parser.candidates(for: ingredient)

        XCTAssertEqual(candidates.first?.catalogItemID, "beef")
        XCTAssertEqual(candidates.first?.facets, [.init(key: .variant, value: "stew")])
        XCTAssertEqual(candidates.first?.displayName, "Beef Stew")
    }

    func testCandidateParserFallsBackToGenericForUnknownSubtypeOnGenericParent() {
        let parser = IngredientCandidateParser()
        let ingredient = Ingredient(name: "beef cheeks")

        let candidates = parser.candidates(for: ingredient)

        XCTAssertEqual(candidates.first?.catalogItemID, "beef")
        XCTAssertEqual(candidates.first?.facets, [.init(key: .variant, value: "generic")])
        XCTAssertEqual(candidates.first?.displayName, "Generic Beef")
        XCTAssertTrue(candidates.first?.rationale.contains("subtype as generic") == true)
    }

    func testCandidateParserFallsBackToGenericForOpenEndedStaples() {
        let parser = IngredientCandidateParser()
        let ingredient = Ingredient(name: "pecorino cheese")

        let candidates = parser.candidates(for: ingredient)

        XCTAssertEqual(candidates.first?.catalogItemID, "cheese")
        XCTAssertEqual(candidates.first?.facets, [.init(key: .variant, value: "generic")])
    }

    func testTrustedCanonicalizerUsesBestCandidateIdentity() {
        let recipe = makeRecipe(
            title: "Parfait",
            ingredients: [Ingredient(name: "Greek yogurt")]
        )

        let canonicalized = TrustedRecipeCanonicalizer.canonicalize(recipe)

        XCTAssertEqual(canonicalized.ingredients.first?.catalogItemID, "yogurt")
        XCTAssertEqual(canonicalized.ingredients.first?.facets, [.init(key: .variant, value: "greek")])
        XCTAssertEqual(canonicalized.ingredients.first?.displayName, "Greek Yogurt")
    }

    func testResolverRejectsOutOfDomainAIDecision() async {
        let ingredient = Ingredient(name: "milk")
        let recipe = makeRecipe(title: "Test", ingredients: [ingredient])
        let parser = StubIngredientCandidateParser()
        let ai = MockAIService()
        let candidates = [
            IngredientResolutionCandidate(
                id: "milk|variant=whole",
                catalogItemID: "milk",
                facets: [.init(key: .variant, value: "whole")],
                displayName: "Whole Milk",
                score: 0.92,
                rationale: "Exact variant match.",
                supportedFacets: []
            ),
            IngredientResolutionCandidate(
                id: "milk|variant=skim",
                catalogItemID: "milk",
                facets: [.init(key: .variant, value: "skim")],
                displayName: "Skim Milk",
                score: 0.84,
                rationale: "Alternative milk variant.",
                supportedFacets: []
            )
        ]
        parser.stubbedCandidates[ingredient.id] = candidates
        ai.ingredientResolutionDecisionsToReturn = [
            IngredientResolutionDecision(
                ingredientID: ingredient.id,
                status: .resolved,
                selectedCandidateID: "milk|variant=oat",
                candidateIDs: ["milk|variant=oat"],
                confidence: 0.99,
                rationale: "AI picked a candidate outside the supplied set."
            )
        ]
        let resolver = RecipeIngredientResolver(candidateParser: parser, aiService: ai)

        let draft = await resolver.resolve(recipe: recipe)

        XCTAssertEqual(ai.resolveIngredientsCallCount, 1)
        XCTAssertEqual(draft.ingredients.first?.status, .ambiguous)
        XCTAssertNil(draft.ingredients.first?.selectedCandidateID)
        XCTAssertEqual(draft.ingredients.first?.candidates, candidates)
    }

    func testResolverAllowsUnknownIngredientsToPassThrough() async {
        let ingredient = Ingredient(name: "dragonfruit powder")
        let recipe = makeRecipe(title: "Smoothie", ingredients: [ingredient])
        let parser = StubIngredientCandidateParser()
        let ai = MockAIService()
        ai.ingredientResolutionDecisionsToReturn = [
            IngredientResolutionDecision(
                ingredientID: ingredient.id,
                status: .unknown,
                selectedCandidateID: nil,
                candidateIDs: [],
                confidence: 0.32,
                rationale: "No catalog match supplied."
            )
        ]
        let resolver = RecipeIngredientResolver(candidateParser: parser, aiService: ai)

        let draft = await resolver.resolve(recipe: recipe)
        let built = draft.builtRecipe()

        XCTAssertEqual(draft.ingredients.first?.status, .unknown)
        XCTAssertNil(built.ingredients.first?.catalogItemID)
        XCTAssertEqual(built.ingredients.first?.rawName, "dragonfruit powder")
    }
}

private final class StubIngredientCandidateParser: IngredientCandidateParserProtocol {
    var stubbedCandidates: [UUID: [IngredientResolutionCandidate]] = [:]

    func candidates(for ingredient: Ingredient) -> [IngredientResolutionCandidate] {
        stubbedCandidates[ingredient.id] ?? []
    }
}