import XCTest
@testable import PantryChef

final class AIOutputValidatorTests: XCTestCase {
    func testValidRecipePassesValidation() {
        let recipe = Recipe(
            title: "Chicken soup",
            description: "A simple, comforting chicken soup for weeknights.",
            ingredients: [Ingredient(name: "chicken broth", quantity: 500, unit: .milliliter, category: .other)],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Heat the broth in a pot until steaming.", estimatedDurationSeconds: 300),
                RecipeStep(stepNumber: 2, instruction: "Serve the soup warm with cracked pepper.", estimatedDurationSeconds: 60),
            ]
        )

        XCTAssertTrue(AIOutputValidator.validate(recipe: recipe).isEmpty)
    }

    func testWrongLanguageIsFlagged() {
        let recipe = Recipe(
            title: "Sopa de pollo",
            description: "Una sopa reconfortante con pollo y verduras para la cena.",
            ingredients: [Ingredient(name: "pollo", quantity: 500, unit: .gram, category: .protein)],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Calienta el caldo en una olla grande.", estimatedDurationSeconds: 300),
                RecipeStep(stepNumber: 2, instruction: "Sirve la sopa caliente con hierbas frescas.", estimatedDurationSeconds: 60),
            ]
        )

        XCTAssertTrue(AIOutputValidator.validate(recipe: recipe).contains {
            if case .wrongLanguage = $0 { return true }
            return false
        })
    }

    func testNonSequentialStepsAreRejected() {
        let recipe = Recipe(
            title: "Soup",
            ingredients: [Ingredient(name: "water", quantity: 1, unit: .liter)],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Boil water.", estimatedDurationSeconds: 300),
                RecipeStep(stepNumber: 3, instruction: "Serve.", estimatedDurationSeconds: 60),
            ]
        )

        XCTAssertTrue(AIOutputValidator.validate(recipe: recipe).contains {
            if case .nonSequentialStepNumbers = $0 { return true }
            return false
        })
    }

    func testNegativeTimersAreRejected() {
        let recipe = Recipe(
            title: "Soup",
            ingredients: [Ingredient(name: "water", quantity: 1, unit: .liter)],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Boil water.", timerMinutes: -2, estimatedDurationSeconds: 120),
            ]
        )

        XCTAssertTrue(AIOutputValidator.validate(recipe: recipe).contains {
            if case .invalidTimer = $0 { return true }
            return false
        })
    }

    func testRawFullRecipeSanitizesInvalidTaskDurations() {
        let raw = RawFullRecipe(
            title: "Salted Greens",
            description: "Quick greens with seasoning.",
            ingredients: [
                RawIngredient(name: "spinach", quantity: 2, unit: "cup", category: "Produce"),
                RawIngredient(name: "salt", quantity: 1, unit: "tsp", category: "Spices & Herbs")
            ],
            steps: [
                RawStep(
                    stepNumber: 1,
                    instruction: "Toss the spinach with salt.",
                    timerMinutes: nil,
                    estimatedDurationSeconds: 120,
                    tasks: [
                        RawTask(
                            taskIndex: 1,
                            action: "mix",
                            ingredient: "spinach",
                            durationSeconds: 0,
                            type: "active",
                            effort: "easy",
                            requiresEquipment: nil,
                            dependsOn: []
                        )
                    ]
                )
            ],
            servings: 2,
            prepTimeMinutes: nil,
            cookTimeMinutes: nil,
            dietaryTags: nil,
            difficulty: 1,
            mealType: nil,
            cuisine: nil,
            calories: nil,
            protein: nil,
            carbohydrates: nil,
            fat: nil,
            fiber: nil,
            sugar: nil,
            sodium: nil
        )

        let recipe = raw.toRecipe()

        XCTAssertEqual(recipe.steps.first?.tasks.first?.durationSeconds, 120)
        XCTAssertTrue(AIOutputValidator.validate(recipe: recipe).isEmpty)
    }

    func testInvalidImportResultIsRejected() {
        let result = RecipeImportResult(
            title: "",
            description: nil,
            ingredients: [],
            steps: [],
            servings: nil,
            prepTimeMinutes: nil,
            cookTimeMinutes: nil,
            dietaryTags: nil,
            difficulty: nil,
            mealType: nil,
            cuisine: nil,
            nutrition: nil
        )

        let issues = AIOutputValidator.validate(importResult: result)
        XCTAssertTrue(issues.contains(.emptyTitle))
        XCTAssertTrue(issues.contains(.missingIngredients))
        XCTAssertTrue(issues.contains(.missingSteps))
    }
}
