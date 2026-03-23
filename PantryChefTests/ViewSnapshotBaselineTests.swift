import CryptoKit
import SwiftUI
import UIKit
import XCTest
@testable import PantryChef

@MainActor
final class ViewSnapshotBaselineTests: XCTestCase {
    func testPantryViewSnapshotHash() throws {
        let (appState, _, _) = makeTestAppState()
        appState.pantryItems = [
            PantryItem(name: "Milk", category: .dairy, quantity: 1, unit: .liter, expiryDate: nil),
            PantryItem(name: "Tomato", category: .produce, quantity: 3, unit: .whole, expiryDate: nil),
            PantryItem(name: "Rice", category: .grains, quantity: 1, unit: .kilogram, expiryDate: nil),
        ]

        let hash = try snapshotHash(of: PantryView(appState: appState), size: CGSize(width: 390, height: 844))
        XCTAssertEqual(hash, "94fc62ac38743855de53203e7e6cad7f5cbb95d6a1ecf2900910c2555361f665")
    }

    func testShoppingListViewSnapshotHash() throws {
        let (appState, _, _) = makeTestAppState()
        appState.shoppingItems = [
            ShoppingItem(name: "Bell Pepper", quantity: 2, unit: .whole, category: .produce),
            ShoppingItem(name: "Soy Sauce", quantity: 1, unit: .package, category: .condiments),
        ]

        let hash = try snapshotHash(of: ShoppingListView(appState: appState), size: CGSize(width: 390, height: 844))
        XCTAssertEqual(hash, "935914b38b4c6097357da4401c023b16ba9e9ef91e1511fd4242d4927f92dd8c")
    }

    func testRecipeDetailViewSnapshotHash() throws {
        let (appState, _, _) = makeTestAppState()
        appState.pantryItems = [
            PantryItem(name: "Chicken Breast", category: .protein, quantity: 2, unit: .piece, expiryDate: nil),
            PantryItem(name: "Rice", category: .grains, quantity: 1, unit: .cup, expiryDate: nil),
            PantryItem(name: "Spinach", category: .produce, quantity: 1, unit: .whole, expiryDate: nil),
        ]

        let recipe = makeRecipe(
            title: "Chicken Rice Bowl",
            ingredients: [
                Ingredient(name: "Chicken Breast", quantity: 1, unit: .piece, category: .protein),
                Ingredient(name: "Rice", quantity: 1, unit: .cup, category: .grains),
                Ingredient(name: "Spinach", quantity: 2, unit: .cup, category: .produce, isOptional: true),
            ],
            steps: [
                RecipeStep(stepNumber: 1, instruction: "Season the chicken and start the rice."),
                RecipeStep(stepNumber: 2, instruction: "Cook chicken until golden, then wilt the spinach into the pan."),
            ],
            prepTimeMinutes: 15,
            cookTimeMinutes: 20,
            difficulty: .medium,
            dietaryTags: [.highProtein, .glutenFree],
            mealType: .dinner,
            nutrition: NutritionInfo(calories: 540, protein: 38, carbohydrates: 44, fat: 18)
        )

        let hash = try snapshotHash(
            of: NavigationStack { RecipeDetailView(recipe: recipe).environment(appState) },
            size: CGSize(width: 390, height: 844)
        )
        XCTAssertEqual(hash, "4570ebd536089ec3754ee1ec8fc7663cce2dfaa7a749a0dc91b7d08a2b0a438d")
    }

    func testPreparedDishDetailViewSnapshotHash() throws {
        let (appState, _, _) = makeTestAppState()
        let recipe = makeRecipe(
            title: "Veggie Lasagna",
            ingredients: [
                Ingredient(name: "Lasagna Sheets", quantity: 8, unit: .piece, category: .grains),
                Ingredient(name: "Ricotta", quantity: 250, unit: .gram, category: .dairy),
                Ingredient(name: "Spinach", quantity: 2, unit: .cup, category: .produce),
            ],
            steps: [RecipeStep(stepNumber: 1, instruction: "Layer and bake.")],
            mealType: .dinner,
            nutrition: NutritionInfo(calories: 460, protein: 24, carbohydrates: 32, fat: 21)
        )
        appState.recipes = [recipe]
        appState.pantryItems = [
            PantryItem(name: "Ricotta", category: .dairy, quantity: 1, unit: .package, expiryDate: nil),
            PantryItem(name: "Spinach", category: .produce, quantity: 1, unit: .whole, expiryDate: nil),
        ]

        let dish = PreparedDish(
            name: "Weekend Lasagna",
            mealTypes: [.lunch, .dinner],
            servingsRemaining: 3,
            storage: .refrigerated,
            useByDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
            freshnessSource: .estimated,
            recipeID: recipe.id,
            nutrition: recipe.nutrition
        )
        appState.preparedDishes = [dish]

        let hash = try snapshotHash(
            of: NavigationStack { PreparedDishDetailView(dish: dish).environment(appState) },
            size: CGSize(width: 390, height: 844)
        )
        XCTAssertEqual(hash, "f5cef72a10a3c5436c39a0fcff7f36c25b66c34c63f2d2d64bfd66b892d4e36e")
    }

    private func snapshotHash<V: View>(of view: V, size: CGSize) throws -> String {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        let controller = UIHostingController(rootView: view.preferredColorScheme(.light))
        controller.view.frame = window.bounds
        controller.view.backgroundColor = .white
        window.rootViewController = controller
        window.makeKeyAndVisible()
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else {
            throw NSError(domain: "ViewSnapshotBaselineTests", code: 1)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
