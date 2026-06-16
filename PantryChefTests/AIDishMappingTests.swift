import XCTest
@testable import PantryChef

/// The AI boundary maps a parsed recipe straight to a Dish (no legacy Recipe
/// detour), preserving the original's identity. The JSON→RawFullRecipe decode is
/// unchanged; this verifies the new post-decode mapping.
final class AIDishMappingTests: XCTestCase {

    private func decode(_ json: String) throws -> RawFullRecipe {
        try JSONDecoder().decode(RawFullRecipe.self, from: Data(json.utf8))
    }

    func testMapsRawRecipeToDishPreservingIdentity() throws {
        let raw = try decode("""
        {"title":"Lighter orzo","description":"sweeter, lighter",
         "ingredients":[{"name":"Baby spinach","quantity":300,"unit":"g","category":"Produce"},
                        {"name":"Lemon","quantity":1,"unit":"whole","category":"Produce"}],
         "steps":[{"stepNumber":1,"instruction":"Cook the orzo","timerMinutes":9,"estimatedDurationSeconds":540,"tasks":[]}],
         "servings":2,"prepTimeMinutes":5,"cookTimeMinutes":20}
        """)
        let original = Dish(name: "Spinach & feta orzo",
                            plate: .init(categories: [.pasta], seed: 1),
                            time: "25 min", isFavorite: true, servings: 2,
                            ingredients: [], steps: [])
        let dish = raw.toDish(preserving: original)

        XCTAssertEqual(dish.id, original.id)            // identity preserved
        XCTAssertEqual(dish.plate, original.plate)      // plate preserved
        XCTAssertTrue(dish.isFavorite)                  // favorite preserved
        XCTAssertEqual(dish.name, "Lighter orzo")
        XCTAssertEqual(dish.servings, 2)
        XCTAssertEqual(dish.time, "25 min")             // 5 + 20
        XCTAssertEqual(dish.blurb, "sweeter, lighter")
        XCTAssertEqual(dish.ingredients.first?.name, "Baby spinach")
        XCTAssertEqual(dish.ingredients.first?.amount, "300 g")
        XCTAssertEqual(dish.steps.first?.timerSeconds, 540)   // 9 min × 60
    }

    func testMapsStepPhaseAttentionAndIngredientFromTasks() throws {
        let raw = try decode("""
        {"title":"Tagged","description":null,
         "ingredients":[{"name":"Onion","quantity":1,"unit":"whole","category":"Produce"}],
         "steps":[
           {"stepNumber":1,"instruction":"Dice the onion","timerMinutes":null,"estimatedDurationSeconds":60,
            "tasks":[{"taskIndex":0,"action":"dice","ingredient":"onion","durationSeconds":60,"type":"active","phase":"prep","effort":"easy","requiresEquipment":null,"dependsOn":[]}]},
           {"stepNumber":2,"instruction":"Simmer the sauce","timerMinutes":30,"estimatedDurationSeconds":1800,
            "tasks":[{"taskIndex":0,"action":"simmer","ingredient":"tomato","durationSeconds":1800,"type":"passive","phase":"cook","effort":"easy","requiresEquipment":null,"dependsOn":[]}]}
         ],
         "servings":2,"prepTimeMinutes":5,"cookTimeMinutes":30}
        """)
        let original = Dish(name: "X", plate: .init(categories: [.produce], seed: 1),
                            time: "30 min", servings: 2, ingredients: [], steps: [])
        let dish = raw.toDish(preserving: original)

        XCTAssertEqual(dish.steps[0].phase, .prep)
        XCTAssertEqual(dish.steps[0].attention, .active)
        XCTAssertEqual(dish.steps[0].ingredient, "onion")
        XCTAssertEqual(dish.steps[1].phase, .cook)
        XCTAssertEqual(dish.steps[1].attention, .passive)
    }

    /// A step spanning prep + cook tasks takes the most-advanced phase (cook), so it
    /// is never front-loaded as if it were pure prep.
    func testStepPhaseTakesMostAdvancedTask() throws {
        let raw = try decode("""
        {"title":"Mixed","description":null,
         "ingredients":[{"name":"Garlic","quantity":1,"unit":"clove","category":"Produce"}],
         "steps":[
           {"stepNumber":1,"instruction":"Mince garlic, then fry it off","timerMinutes":null,"estimatedDurationSeconds":120,
            "tasks":[{"taskIndex":0,"action":"mince","ingredient":"garlic","durationSeconds":30,"type":"active","phase":"prep","effort":"easy","requiresEquipment":null,"dependsOn":[]},
                     {"taskIndex":1,"action":"fry","ingredient":"garlic","durationSeconds":90,"type":"active","phase":"cook","effort":"easy","requiresEquipment":null,"dependsOn":[0]}]}
         ],
         "servings":1,"prepTimeMinutes":null,"cookTimeMinutes":null}
        """)
        let original = Dish(name: "Y", plate: .init(categories: [.produce], seed: 3),
                            time: "5 min", servings: 1, ingredients: [], steps: [])
        let dish = raw.toDish(preserving: original)
        XCTAssertEqual(dish.steps[0].phase, .cook)
    }

    func testFallsBackToOriginalTimeWhenNoDurations() throws {
        let raw = try decode("""
        {"title":"X","description":null,
         "ingredients":[{"name":"Egg","quantity":2,"unit":"whole","category":"Protein"}],
         "steps":[{"stepNumber":1,"instruction":"Beat","timerMinutes":null,"estimatedDurationSeconds":null,"tasks":[]}],
         "servings":1,"prepTimeMinutes":null,"cookTimeMinutes":null}
        """)
        let original = Dish(name: "Eggs", plate: .init(categories: [.protein], seed: 2),
                            time: "10 min", servings: 1, ingredients: [], steps: [])
        let dish = raw.toDish(preserving: original)
        XCTAssertEqual(dish.time, "10 min")             // kept original when AI gave none
        XCTAssertNil(dish.steps.first?.timerSeconds)
    }
}
