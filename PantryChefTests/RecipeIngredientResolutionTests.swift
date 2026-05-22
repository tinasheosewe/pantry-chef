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
                guard IngredientLexicon.lookupKey(ingredient.rawName) != "water" else { return nil }
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

    func testCandidateParserMatchesFacetTemplateRegardlessOfWordOrder() {
        let parser = IngredientCandidateParser()
        let ingredient = Ingredient(name: "garlic, minced")

        let candidates = parser.candidates(for: ingredient)

        XCTAssertEqual(candidates.first?.catalogItemID, "garlic")
        XCTAssertEqual(candidates.first?.facets, [.init(key: .form, value: "minced")])
        XCTAssertEqual(candidates.first?.displayName, "Minced Garlic")
    }

    func testCandidateParserResolvesStructuredBeefCuts() {
        let parser = IngredientCandidateParser()
        let ingredient = Ingredient(name: "beef stew meat")

        let candidates = parser.candidates(for: ingredient)

        XCTAssertEqual(candidates.first?.catalogItemID, "beef")
        XCTAssertEqual(candidates.first?.facets, [.init(key: .variant, value: "stew meat")])
        XCTAssertEqual(candidates.first?.displayName, "Stew Meat Beef")
    }

    func testCandidateParserFallsBackToGenericForUnknownSubtypeOnGenericParent() {
        let parser = IngredientCandidateParser()
        let ingredient = Ingredient(name: "beef cheeks")

        let candidates = parser.candidates(for: ingredient)

        XCTAssertEqual(candidates.first?.catalogItemID, "beef")
        XCTAssertEqual(candidates.first?.facets, [.init(key: .variant, value: "none")])
        XCTAssertEqual(candidates.first?.displayName, "Beef")
        XCTAssertTrue(candidates.first?.rationale.contains("subtype unspecified") == true)
    }

    func testCandidateParserFallsBackToGenericForOpenEndedStaples() {
        let parser = IngredientCandidateParser()
        let ingredient = Ingredient(name: "pecorino cheese")

        let candidates = parser.candidates(for: ingredient)

        XCTAssertEqual(candidates.first?.catalogItemID, "cheese")
        XCTAssertEqual(candidates.first?.facets, [.init(key: .variant, value: "none")])
    }

    func testCandidateParserReturnsResultsForQualifierPrefixedIngredients() {
        let parser = IngredientCandidateParser()
        let qualifiedNames = ["dried rosemary", "fresh basil", "frozen peas", "ground cumin"]

        for name in qualifiedNames {
            let ingredient = Ingredient(name: name)
            let candidates = parser.candidates(for: ingredient)

            XCTAssertFalse(
                candidates.isEmpty,
                "Expected candidates for '\(name)' but got none."
            )
        }
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

    func testResolverAutomaticallyResolvesObviousFacetSpecificIngredient() async {
        let ingredient = Ingredient(name: "garlic, minced")
        let recipe = makeRecipe(title: "Garlic Toast", ingredients: [ingredient])
        let parser = IngredientCandidateParser()
        let ai = MockAIService()
        let resolver = RecipeIngredientResolver(candidateParser: parser, aiService: ai)

        let draft = await resolver.resolve(recipe: recipe)
        let built = draft.builtRecipe()

        XCTAssertEqual(draft.ingredients.first?.status, .resolved)
        XCTAssertEqual(draft.ingredients.first?.selectedCandidate?.catalogItemID, "garlic")
        XCTAssertEqual(draft.ingredients.first?.selectedCandidate?.facets, [.init(key: .form, value: "minced")])
        XCTAssertEqual(built.ingredients.first?.catalogItemID, "garlic")
        XCTAssertEqual(built.ingredients.first?.facets, [.init(key: .form, value: "minced")])
    }

    func testChoosingCandidateDoesNotDismissAmbiguousDraftBeforeApply() {
        let candidates = [
            IngredientResolutionCandidate(
                id: "garlic|form=clove",
                catalogItemID: "garlic",
                facets: [.init(key: .form, value: "clove")],
                displayName: "Whole Garlic",
                score: 0.85,
                rationale: "Whole garlic candidate.",
                supportedFacets: []
            ),
            IngredientResolutionCandidate(
                id: "garlic|form=minced",
                catalogItemID: "garlic",
                facets: [.init(key: .form, value: "minced")],
                displayName: "Minced Garlic",
                score: 0.9,
                rationale: "Minced garlic candidate.",
                supportedFacets: []
            )
        ]
        var draft = ResolvedIngredientDraft(
            ingredient: Ingredient(name: "garlic"),
            status: .ambiguous,
            candidates: candidates,
            selectedCandidateID: nil,
            confidence: 0.9,
            rationale: "Multiple plausible matches."
        )

        draft.chooseCandidate(candidates[1])

        XCTAssertEqual(draft.status, .ambiguous)
        XCTAssertEqual(draft.selectedCandidateID, candidates[1].id)
        XCTAssertTrue(draft.requiresUserChoice)
        XCTAssertEqual(draft.resolvedIngredient.catalogItemID, "garlic")
        XCTAssertEqual(draft.resolvedIngredient.facets, [.init(key: .form, value: "minced")])
    }
}

final class PantryCatalogInheritanceTests: XCTestCase {
    func testAncestorsIncludeSelfAndParents() {
        let ancestors = PantryCatalog.ancestors(of: "beef-shank")
        XCTAssertTrue(ancestors.contains("beef-shank"))
        XCTAssertTrue(ancestors.contains("beef"))
    }

    func testDescendantsIncludeSelfAndChildren() {
        let descendants = PantryCatalog.descendants(of: "beef")
        XCTAssertTrue(descendants.contains("beef"))
        XCTAssertTrue(descendants.contains("beef-shank"))
    }

    func testMatchingCatalogItemIDsWithoutFacetsReturnsDescendants() {
        let matches = PantryCatalog.matchingCatalogItemIDs(for: "beef", facets: [])
        XCTAssertTrue(matches.contains("beef"))
        XCTAssertTrue(matches.contains("beef-shank"))
    }

    func testMatchingCatalogItemIDsNarrowToSubclass() {
        let matches = PantryCatalog.matchingCatalogItemIDs(
            for: "beef",
            facets: [.init(key: .variant, value: "beef shank")]
        )
        XCTAssertTrue(matches.contains("beef-shank"))
        XCTAssertFalse(matches.contains("beef"))
    }

    func testSubclassPantrySatisfiesGenericRecipeRequirement() {
        let ingredient = Ingredient(
            name: "beef",
            quantity: 1,
            unit: .pound,
            category: .protein,
            catalogItemID: "beef"
        )
        let pantry = [
            PantryItem(
                name: "Beef Shank",
                category: .protein,
                quantity: 1,
                unit: .pound,
                catalogItemID: "beef-shank"
            )
        ]

        XCTAssertTrue(IngredientMatcher.pantryContains(ingredient: ingredient, pantry: pantry))
    }
}

private final class StubIngredientCandidateParser: IngredientCandidateParserProtocol {
    var stubbedCandidates: [UUID: [IngredientResolutionCandidate]] = [:]

    func candidates(for ingredient: Ingredient) -> [IngredientResolutionCandidate] {
        stubbedCandidates[ingredient.id] ?? []
    }
}