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
        XCTAssertEqual(hash, "2bb657eeaa12e9413e4fcacf1f00cd1f9e64aae5df5c533307d75437f9a4b48b")
    }

    func testShoppingListViewSnapshotHash() throws {
        let (appState, _, _) = makeTestAppState()
        appState.shoppingItems = [
            ShoppingItem(name: "Bell Pepper", quantity: 2, unit: .whole, category: .produce),
            ShoppingItem(name: "Soy Sauce", quantity: 1, unit: .package, category: .condiments),
        ]

        let hash = try snapshotHash(of: ShoppingListView(appState: appState), size: CGSize(width: 390, height: 844))
        XCTAssertEqual(hash, "83a65665b4789080e6df3d205b442cba68b4c48bab13239cfe24dd00f1cd52a0")
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
        XCTAssertEqual(hash, "0db72c8b0496f802ec3862b1bc66cef56bd0b7159975147f0f34bb11ba6a4d65")
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
            recipeID: recipe.id,
            nutrition: recipe.nutrition
        )
        appState.preparedDishes = [dish]

        let hash = try snapshotHash(
            of: NavigationStack { PreparedDishDetailView(dish: dish).environment(appState) },
            size: CGSize(width: 390, height: 844)
        )
        XCTAssertEqual(hash, "9e1b95c061005be37b968fe2aee89ba9c3484f3eff5e88a2a25d21183e682a2c")
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
