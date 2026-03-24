import Foundation
import SwiftData

enum StorageSchema {
    static let currentVersion = 13
}

@Model
final class PantryItemRecord {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var name: String
    var categoryRawValue: String
    var quantity: Double?
    var unitRawValue: String?
    var expiryDate: Date?
    var dateAdded: Date
    var notes: String?
    var imageURL: String?
    var catalogItemID: String?
    var storageRawValue: String
    var freshnessSourceRawValue: String
    var quantityModeRawValue: String?

    @Relationship(deleteRule: .cascade, inverse: \PantryFacetRecord.pantryItem)
    var facetRecords: [PantryFacetRecord] = []

    init(from item: PantryItem) {
        id = item.id
        schemaVersion = StorageSchema.currentVersion
        name = item.name
        categoryRawValue = item.category.rawValue
        quantity = item.quantity
        unitRawValue = item.unit?.rawValue
        expiryDate = item.expiryDate
        dateAdded = item.dateAdded
        notes = item.notes
        imageURL = item.imageURL
        catalogItemID = item.catalogItemID
        storageRawValue = item.storage.rawValue
        freshnessSourceRawValue = item.freshnessSource.rawValue
        quantityModeRawValue = item.quantityMode.rawValue
        facetRecords = Self.makeFacetRecords(from: item.facets)
    }

    func update(from item: PantryItem, in context: ModelContext) {
        schemaVersion = StorageSchema.currentVersion
        name = item.name
        categoryRawValue = item.category.rawValue
        quantity = item.quantity
        unitRawValue = item.unit?.rawValue
        expiryDate = item.expiryDate
        dateAdded = item.dateAdded
        notes = item.notes
        imageURL = item.imageURL
        catalogItemID = item.catalogItemID
        storageRawValue = item.storage.rawValue
        freshnessSourceRawValue = item.freshnessSource.rawValue
        quantityModeRawValue = item.quantityMode.rawValue
        replaceFacetRecords(with: item.facets, in: context)
    }

    func toDomain() -> PantryItem {
        PantryItem(
            id: id,
            name: name,
            category: FoodCategory(rawValue: categoryRawValue) ?? .other,
            quantity: quantity,
            unit: unitRawValue.flatMap { MeasurementUnit(rawValue: $0) },
            expiryDate: expiryDate,
            dateAdded: dateAdded,
            notes: notes,
            imageURL: imageURL,
            catalogItemID: catalogItemID,
            facets: facetRecords
                .sorted { $0.sortIndex < $1.sortIndex }
                .compactMap { $0.toDomain() },
            storage: PantryStorage(rawValue: storageRawValue) ?? .pantry,
            freshnessSource: PantryFreshnessSource(rawValue: freshnessSourceRawValue) ?? PantryFreshnessSource.none,
            quantityMode: quantityModeRawValue.flatMap(PantryQuantityMode.init(rawValue:))
        )
    }

    private func replaceFacetRecords(with facets: [PantryFacetSelection], in context: ModelContext) {
        let existingRecords = facetRecords
        facetRecords = []
        for record in existingRecords {
            context.delete(record)
        }
        facetRecords = Self.makeFacetRecords(from: facets)
    }

    private static func makeFacetRecords(from facets: [PantryFacetSelection]) -> [PantryFacetRecord] {
        facets.enumerated().map { index, selection in
            PantryFacetRecord(selection: selection, sortIndex: index)
        }
    }
}

@Model
final class PantryFacetRecord {
    var id: UUID
    var schemaVersion: Int
    var sortIndex: Int
    var keyRawValue: String
    var value: String

    var pantryItem: PantryItemRecord?

    init(selection: PantryFacetSelection, sortIndex: Int) {
        id = UUID()
        schemaVersion = StorageSchema.currentVersion
        self.sortIndex = sortIndex
        keyRawValue = selection.key.rawValue
        value = selection.value
    }

    func toDomain() -> PantryFacetSelection? {
        guard let key = PantryFacetKey(rawValue: keyRawValue) else { return nil }
        return PantryFacetSelection(key: key, value: value)
    }
}

@Model
final class PreparedDishRecord {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var name: String
    var mealTypesRaw: String
    var servingsRemaining: Int
    var storageRawValue: String
    var useByDate: Date?
    var dateAdded: Date
    // Kept only to avoid unnecessary schema churn for existing stores.
    var freshnessSourceRawValue: String
    var notes: String?
    var recipeID: UUID?
    var calories: Int?
    var protein: Double?
    var carbohydrates: Double?
    var fat: Double?
    var fiber: Double?
    var sugar: Double?
    var sodium: Double?

    init(from dish: PreparedDish) {
        id = dish.id
        schemaVersion = StorageSchema.currentVersion
        name = dish.name
        mealTypesRaw = dish.mealTypes.map(\.rawValue).joined(separator: "|")
        servingsRemaining = dish.servingsRemaining
        storageRawValue = dish.storage.rawValue
        useByDate = dish.useByDate
        dateAdded = dish.dateAdded
        freshnessSourceRawValue = ""
        notes = dish.notes
        recipeID = dish.recipeID
        calories = dish.nutrition?.calories
        protein = dish.nutrition?.protein
        carbohydrates = dish.nutrition?.carbohydrates
        fat = dish.nutrition?.fat
        fiber = dish.nutrition?.fiber
        sugar = dish.nutrition?.sugar
        sodium = dish.nutrition?.sodium
    }

    func update(from dish: PreparedDish) {
        schemaVersion = StorageSchema.currentVersion
        name = dish.name
        mealTypesRaw = dish.mealTypes.map(\.rawValue).joined(separator: "|")
        servingsRemaining = dish.servingsRemaining
        storageRawValue = dish.storage.rawValue
        useByDate = dish.useByDate
        dateAdded = dish.dateAdded
        freshnessSourceRawValue = ""
        notes = dish.notes
        recipeID = dish.recipeID
        calories = dish.nutrition?.calories
        protein = dish.nutrition?.protein
        carbohydrates = dish.nutrition?.carbohydrates
        fat = dish.nutrition?.fat
        fiber = dish.nutrition?.fiber
        sugar = dish.nutrition?.sugar
        sodium = dish.nutrition?.sodium
    }

    func toDomain() -> PreparedDish {
        let mealTypes = mealTypesRaw
            .split(separator: "|")
            .compactMap { MealType(rawValue: String($0)) }

        let nutrition: NutritionInfo?
        if let calories, let protein, let carbohydrates, let fat {
            nutrition = NutritionInfo(
                calories: calories,
                protein: protein,
                carbohydrates: carbohydrates,
                fat: fat,
                fiber: fiber,
                sugar: sugar,
                sodium: sodium
            )
        } else {
            nutrition = nil
        }

        return PreparedDish(
            id: id,
            name: name,
            mealTypes: mealTypes,
            servingsRemaining: servingsRemaining,
            storage: PantryStorage(rawValue: storageRawValue) ?? .refrigerated,
            useByDate: useByDate,
            dateAdded: dateAdded,
            notes: notes,
            recipeID: recipeID,
            nutrition: nutrition
        )
    }
}

@Model
final class PreparedDishHistoryRecord {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var payload: Data
    var sortDate: Date

    init(from item: PreparedDishHistoryItem) throws {
        id = item.id
        schemaVersion = StorageSchema.currentVersion
        sortDate = item.lastUsedAt
        payload = try JSONEncoder().encode(item)
    }

    func update(from item: PreparedDishHistoryItem) throws {
        schemaVersion = StorageSchema.currentVersion
        sortDate = item.lastUsedAt
        payload = try JSONEncoder().encode(item)
    }

    func toDomain() throws -> PreparedDishHistoryItem {
        try JSONDecoder().decode(PreparedDishHistoryItem.self, from: payload)
    }
}

@Model
final class RecipeRecord {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var title: String
    var recipeDescription: String?
    var servings: Int
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var difficultyRawValue: Int
    var mealTypeRawValue: String?
    var cuisineRawValue: String?
    var sourceKind: String
    var sourceExternalId: Int?
    var imageURL: String?
    var sourceURL: String?
    var isFavorite: Bool
    var dateAdded: Date
    var timesCooked: Int
    var rating: Int?
    var calories: Int?
    var protein: Double?
    var carbohydrates: Double?
    var fat: Double?
    var fiber: Double?
    var sugar: Double?
    var sodium: Double?
    var dietaryTagsRaw: String

    @Relationship(deleteRule: .cascade, inverse: \IngredientRecord.recipe)
    var ingredientRecords: [IngredientRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \RecipeStepRecord.recipe)
    var stepRecords: [RecipeStepRecord] = []

    init(from recipe: Recipe) throws {
        id = recipe.id
        schemaVersion = StorageSchema.currentVersion
        title = recipe.title
        recipeDescription = recipe.description
        servings = recipe.servings
        prepTimeMinutes = recipe.prepTimeMinutes
        cookTimeMinutes = recipe.cookTimeMinutes
        difficultyRawValue = recipe.difficulty.rawValue
        mealTypeRawValue = recipe.mealType?.rawValue
        cuisineRawValue = recipe.cuisine?.rawValue
        sourceKind = RecipeSourceCodec.kind(from: recipe.source)
        sourceExternalId = RecipeSourceCodec.externalId(from: recipe.source)
        imageURL = recipe.imageURL
        sourceURL = recipe.sourceURL
        isFavorite = recipe.isFavorite
        dateAdded = recipe.dateAdded
        timesCooked = recipe.timesCooked
        rating = recipe.rating
        calories = recipe.nutrition?.calories
        protein = recipe.nutrition?.protein
        carbohydrates = recipe.nutrition?.carbohydrates
        fat = recipe.nutrition?.fat
        fiber = recipe.nutrition?.fiber
        sugar = recipe.nutrition?.sugar
        sodium = recipe.nutrition?.sodium
        dietaryTagsRaw = recipe.dietaryTags.map(\.rawValue).joined(separator: "|")

        ingredientRecords = recipe.ingredients.enumerated().map { idx, ingredient in
            IngredientRecord(from: ingredient, sortIndex: idx)
        }
        stepRecords = try recipe.steps.enumerated().map { idx, step in
            try RecipeStepRecord(from: step, sortIndex: idx)
        }
    }

    func update(from recipe: Recipe) throws {
        schemaVersion = StorageSchema.currentVersion
        title = recipe.title
        recipeDescription = recipe.description
        servings = recipe.servings
        prepTimeMinutes = recipe.prepTimeMinutes
        cookTimeMinutes = recipe.cookTimeMinutes
        difficultyRawValue = recipe.difficulty.rawValue
        mealTypeRawValue = recipe.mealType?.rawValue
        cuisineRawValue = recipe.cuisine?.rawValue
        sourceKind = RecipeSourceCodec.kind(from: recipe.source)
        sourceExternalId = RecipeSourceCodec.externalId(from: recipe.source)
        imageURL = recipe.imageURL
        sourceURL = recipe.sourceURL
        isFavorite = recipe.isFavorite
        dateAdded = recipe.dateAdded
        timesCooked = recipe.timesCooked
        rating = recipe.rating
        calories = recipe.nutrition?.calories
        protein = recipe.nutrition?.protein
        carbohydrates = recipe.nutrition?.carbohydrates
        fat = recipe.nutrition?.fat
        fiber = recipe.nutrition?.fiber
        sugar = recipe.nutrition?.sugar
        sodium = recipe.nutrition?.sodium
        dietaryTagsRaw = recipe.dietaryTags.map(\.rawValue).joined(separator: "|")

        ingredientRecords = recipe.ingredients.enumerated().map { idx, ingredient in
            IngredientRecord(from: ingredient, sortIndex: idx)
        }
        stepRecords = try recipe.steps.enumerated().map { idx, step in
            try RecipeStepRecord(from: step, sortIndex: idx)
        }
    }

    func toDomain() throws -> Recipe {
        let source = RecipeSourceCodec.decode(kind: sourceKind, externalId: sourceExternalId)
        let sortedIngredients = ingredientRecords.sorted { $0.sortIndex < $1.sortIndex }
        let ingredients = sortedIngredients.map { $0.toDomain() }

        let sortedSteps = stepRecords.sorted { $0.sortIndex < $1.sortIndex }
        let steps = try sortedSteps.map { try $0.toDomain() }

        let tags = dietaryTagsRaw
            .split(separator: "|")
            .compactMap { DietaryTag(rawValue: String($0)) }

        let nutrition: NutritionInfo?
        if let calories, let protein, let carbohydrates, let fat {
            nutrition = NutritionInfo(
                calories: calories,
                protein: protein,
                carbohydrates: carbohydrates,
                fat: fat,
                fiber: fiber,
                sugar: sugar,
                sodium: sodium
            )
        } else {
            nutrition = nil
        }

        return Recipe(
            id: id,
            title: title,
            description: recipeDescription,
            ingredients: ingredients,
            steps: steps,
            servings: servings,
            prepTimeMinutes: prepTimeMinutes,
            cookTimeMinutes: cookTimeMinutes,
            difficulty: DifficultyLevel(rawValue: difficultyRawValue) ?? .easy,
            dietaryTags: tags,
            mealType: mealTypeRawValue.flatMap { MealType(rawValue: $0) },
            cuisine: cuisineRawValue.flatMap { CuisineType(rawValue: $0) },
            source: source,
            nutrition: nutrition,
            imageURL: imageURL,
            sourceURL: sourceURL,
            isFavorite: isFavorite,
            dateAdded: dateAdded,
            timesCooked: timesCooked,
            rating: rating
        )
    }
}

@Model
final class IngredientRecord {
    var id: UUID
    var schemaVersion: Int
    var sortIndex: Int
    var rawName: String
    var quantity: Double
    var unitRawValue: String?
    var categoryRawValue: String
    var isOptional: Bool
    var notes: String?
    var catalogItemID: String?

    @Relationship(deleteRule: .cascade, inverse: \IngredientFacetRecord.ingredient)
    var facetRecords: [IngredientFacetRecord] = []

    var recipe: RecipeRecord?

    init(from ingredient: Ingredient, sortIndex: Int) {
        id = ingredient.id
        schemaVersion = StorageSchema.currentVersion
        self.sortIndex = sortIndex
        rawName = ingredient.rawName
        quantity = ingredient.quantity
        unitRawValue = ingredient.unit?.rawValue
        categoryRawValue = ingredient.category.rawValue
        isOptional = ingredient.isOptional
        notes = ingredient.notes
        catalogItemID = ingredient.catalogItemID
        facetRecords = ingredient.facets.enumerated().map { index, facet in
            IngredientFacetRecord(selection: facet, sortIndex: index)
        }
    }

    func toDomain() -> Ingredient {
        Ingredient(
            id: id,
            name: rawName,
            quantity: quantity,
            unit: unitRawValue.flatMap { MeasurementUnit(rawValue: $0) },
            category: FoodCategory(rawValue: categoryRawValue) ?? .other,
            isOptional: isOptional,
            notes: notes,
            catalogItemID: catalogItemID,
            facets: facetRecords
                .sorted { $0.sortIndex < $1.sortIndex }
                .compactMap { $0.toDomain() }
        )
    }
}

@Model
final class IngredientFacetRecord {
    var id: UUID
    var schemaVersion: Int
    var sortIndex: Int
    var keyRawValue: String
    var value: String

    var ingredient: IngredientRecord?

    init(selection: PantryFacetSelection, sortIndex: Int) {
        id = UUID()
        schemaVersion = StorageSchema.currentVersion
        self.sortIndex = sortIndex
        keyRawValue = selection.key.rawValue
        value = selection.value
    }

    func toDomain() -> PantryFacetSelection? {
        guard let key = PantryFacetKey(rawValue: keyRawValue) else { return nil }
        return PantryFacetSelection(key: key, value: value)
    }
}

@Model
final class RecipeStepRecord {
    var id: UUID
    var schemaVersion: Int
    var sortIndex: Int
    var stepNumber: Int
    var instruction: String
    var timerMinutes: Int?
    var tip: String?
    var estimatedDurationSeconds: Int?

    @Relationship(deleteRule: .cascade, inverse: \StepTaskRecord.step)
    var taskRecords: [StepTaskRecord] = []

    var recipe: RecipeRecord?

    init(from step: RecipeStep, sortIndex: Int) throws {
        id = step.id
        schemaVersion = StorageSchema.currentVersion
        self.sortIndex = sortIndex
        stepNumber = step.stepNumber
        instruction = step.instruction
        timerMinutes = step.timerMinutes
        tip = step.tip
        estimatedDurationSeconds = step.estimatedDurationSeconds
        taskRecords = step.tasks.enumerated().map { idx, task in
            StepTaskRecord(from: task, sortIndex: idx)
        }
    }

    func toDomain() throws -> RecipeStep {
        let tasks = taskRecords
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { $0.toDomain() }

        return RecipeStep(
            id: id,
            stepNumber: stepNumber,
            instruction: instruction,
            timerMinutes: timerMinutes,
            tip: tip,
            estimatedDurationSeconds: estimatedDurationSeconds,
            tasks: tasks
        )
    }
}

@Model
final class StepTaskRecord {
    var id: UUID
    var schemaVersion: Int
    var sortIndex: Int
    var actionKind: String
    var actionParameter: String?
    var ingredient: String?
    var quantity: Double?
    var unit: String?
    var durationSeconds: Int
    var typeRawValue: String
    var requiresEquipment: String?
    var temperature: Int?
    var effortRawValue: Int
    var recipeId: UUID?
    var recipeName: String?
    var sourceStepNumber: Int?

    @Relationship(deleteRule: .cascade, inverse: \StepTaskDependencyRecord.task)
    var dependencyRecords: [StepTaskDependencyRecord] = []

    var step: RecipeStepRecord?

    init(from task: StepTask, sortIndex: Int) {
        let encodedAction = CookingActionCodec.encode(task.action)

        id = task.id
        schemaVersion = StorageSchema.currentVersion
        self.sortIndex = sortIndex
        actionKind = encodedAction.kind
        actionParameter = encodedAction.parameter
        ingredient = task.ingredient
        quantity = task.quantity
        unit = task.unit
        durationSeconds = task.durationSeconds
        typeRawValue = task.type.rawValue
        requiresEquipment = task.requiresEquipment
        temperature = task.temperature
        effortRawValue = task.effort.rawValue
        recipeId = task.recipeId
        recipeName = task.recipeName
        sourceStepNumber = task.sourceStepNumber
        dependencyRecords = task.dependsOn.enumerated().map { idx, dependency in
            StepTaskDependencyRecord(dependsOnTaskId: dependency, sortIndex: idx)
        }
    }

    func toDomain() -> StepTask {
        let dependencies = dependencyRecords
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { $0.dependsOnTaskId }

        return StepTask(
            id: id,
            action: CookingActionCodec.decode(kind: actionKind, parameter: actionParameter),
            ingredient: ingredient,
            quantity: quantity,
            unit: unit,
            durationSeconds: durationSeconds,
            type: TaskType(rawValue: typeRawValue) ?? .active,
            requiresEquipment: requiresEquipment,
            temperature: temperature,
            effort: EffortLevel(rawValue: effortRawValue) ?? .medium,
            dependsOn: dependencies,
            recipeId: recipeId,
            recipeName: recipeName,
            sourceStepNumber: sourceStepNumber
        )
    }
}

@Model
final class StepTaskDependencyRecord {
    var id: UUID
    var schemaVersion: Int
    var dependsOnTaskId: UUID
    var sortIndex: Int

    var task: StepTaskRecord?

    init(dependsOnTaskId: UUID, sortIndex: Int) {
        id = UUID()
        schemaVersion = StorageSchema.currentVersion
        self.dependsOnTaskId = dependsOnTaskId
        self.sortIndex = sortIndex
    }
}

@Model
final class MealPlanRecord {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var date: Date
    var mealTypeRawValue: String
    var recipeId: UUID?
    var preparedDishId: UUID?
    var customMealName: String?
    var plannedServings: Int?
    var eatenServings: Int?
    var notes: String?

    init(from entry: MealPlanEntry) {
        id = entry.id
        schemaVersion = StorageSchema.currentVersion
        date = entry.date
        mealTypeRawValue = entry.mealType.rawValue
        recipeId = entry.recipe?.id
        preparedDishId = entry.preparedDish?.id
        customMealName = entry.customMealName
        plannedServings = entry.plannedServings
        eatenServings = entry.eatenServings
        notes = entry.notes
    }

    func update(from entry: MealPlanEntry) {
        schemaVersion = StorageSchema.currentVersion
        date = entry.date
        mealTypeRawValue = entry.mealType.rawValue
        recipeId = entry.recipe?.id
        preparedDishId = entry.preparedDish?.id
        customMealName = entry.customMealName
        plannedServings = entry.plannedServings
        eatenServings = entry.eatenServings
        notes = entry.notes
    }

    func toDomain(recipe: Recipe?, preparedDish: PreparedDish?) -> MealPlanEntry {
        MealPlanEntry(
            id: id,
            date: date,
            mealType: MealType(rawValue: mealTypeRawValue) ?? .dinner,
            recipe: recipe,
            preparedDish: preparedDish,
            customMealName: customMealName,
            plannedServings: plannedServings,
            eatenServings: eatenServings,
            notes: notes
        )
    }
}

@Model
final class ShoppingItemRecord {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var name: String
    var quantity: Double?
    var unitRawValue: String?
    var categoryRawValue: String
    var isChecked: Bool
    var recipeSource: String?
    var catalogItemID: String?
    var pantryQuantity: Double?
    var pantryUnitRawValue: String?
    var pantryQuantityModeRawValue: String

    @Relationship(deleteRule: .cascade, inverse: \ShoppingFacetRecord.shoppingItem)
    var facetRecords: [ShoppingFacetRecord] = []

    init(from item: ShoppingItem) {
        id = item.id
        schemaVersion = StorageSchema.currentVersion
        name = item.name
        quantity = item.quantity
        unitRawValue = item.unit?.rawValue
        categoryRawValue = item.category.rawValue
        isChecked = item.isChecked
        recipeSource = item.recipeSource
        catalogItemID = item.catalogItemID
        pantryQuantity = item.pantryQuantity
        pantryUnitRawValue = item.pantryUnit?.rawValue
        pantryQuantityModeRawValue = item.pantryQuantityMode.rawValue
        facetRecords = Self.makeFacetRecords(from: item.facets)
    }

    func update(from item: ShoppingItem, in context: ModelContext) {
        schemaVersion = StorageSchema.currentVersion
        name = item.name
        quantity = item.quantity
        unitRawValue = item.unit?.rawValue
        categoryRawValue = item.category.rawValue
        isChecked = item.isChecked
        recipeSource = item.recipeSource
        catalogItemID = item.catalogItemID
        pantryQuantity = item.pantryQuantity
        pantryUnitRawValue = item.pantryUnit?.rawValue
        pantryQuantityModeRawValue = item.pantryQuantityMode.rawValue
        replaceFacetRecords(with: item.facets, in: context)
    }

    func toDomain() -> ShoppingItem {
        ShoppingItem(
            id: id,
            name: name,
            quantity: quantity,
            unit: unitRawValue.flatMap { MeasurementUnit(rawValue: $0) },
            category: FoodCategory(rawValue: categoryRawValue) ?? .other,
            isChecked: isChecked,
            recipeSource: recipeSource,
            catalogItemID: catalogItemID,
            facets: facetRecords
                .sorted { $0.sortIndex < $1.sortIndex }
                .compactMap { $0.toDomain() },
            pantryQuantity: pantryQuantity,
            pantryUnit: pantryUnitRawValue.flatMap { MeasurementUnit(rawValue: $0) },
            pantryQuantityMode: PantryQuantityMode(rawValue: pantryQuantityModeRawValue)
        )
    }

    private func replaceFacetRecords(with facets: [PantryFacetSelection], in context: ModelContext) {
        let existingRecords = facetRecords
        facetRecords = []
        for record in existingRecords {
            context.delete(record)
        }
        facetRecords = Self.makeFacetRecords(from: facets)
    }

    private static func makeFacetRecords(from facets: [PantryFacetSelection]) -> [ShoppingFacetRecord] {
        facets.enumerated().map { index, selection in
            ShoppingFacetRecord(selection: selection, sortIndex: index)
        }
    }
}

@Model
final class ShoppingFacetRecord {
    var id: UUID
    var schemaVersion: Int
    var sortIndex: Int
    var keyRawValue: String
    var value: String

    var shoppingItem: ShoppingItemRecord?

    init(selection: PantryFacetSelection, sortIndex: Int) {
        id = UUID()
        schemaVersion = StorageSchema.currentVersion
        self.sortIndex = sortIndex
        keyRawValue = selection.key.rawValue
        value = selection.value
    }

    func toDomain() -> PantryFacetSelection? {
        guard let key = PantryFacetKey(rawValue: keyRawValue) else { return nil }
        return PantryFacetSelection(key: key, value: value)
    }
}

@Model
final class CookQueueRecord {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var payload: Data
    var updatedAt: Date

    init(from queue: CookQueue) throws {
        id = queue.id
        schemaVersion = StorageSchema.currentVersion
        updatedAt = queue.updatedAt
        payload = try JSONEncoder().encode(queue)
    }

    func update(from queue: CookQueue) throws {
        schemaVersion = StorageSchema.currentVersion
        updatedAt = queue.updatedAt
        payload = try JSONEncoder().encode(queue)
    }

    func toDomain() throws -> CookQueue {
        try JSONDecoder().decode(CookQueue.self, from: payload)
    }
}

enum RecipeSourceCodec {
    static func kind(from source: RecipeSource) -> String {
        switch source {
        case .user: return "user"
        case .bundled: return "bundled"
        case .imported: return "imported"
        case .aiGenerated: return "aiGenerated"
        }
    }

    static func externalId(from source: RecipeSource) -> Int? {
        return nil
    }

    static func decode(kind: String, externalId: Int?) -> RecipeSource {
        _ = externalId
        switch kind {
        case "user": return .user
        case "bundled": return .bundled
        case "imported": return .imported
        case "aiGenerated": return .aiGenerated
        default: return .user
        }
    }
}

enum CookingActionCodec {
    struct EncodedAction {
        let kind: String
        let parameter: String?
    }

    static func encode(_ action: CookingAction) -> EncodedAction {
        switch action {
        case .cut(let style): return EncodedAction(kind: "cut", parameter: style.rawValue)
        case .peel: return EncodedAction(kind: "peel", parameter: nil)
        case .measure: return EncodedAction(kind: "measure", parameter: nil)
        case .mix: return EncodedAction(kind: "mix", parameter: nil)
        case .marinate: return EncodedAction(kind: "marinate", parameter: nil)
        case .season: return EncodedAction(kind: "season", parameter: nil)
        case .heat: return EncodedAction(kind: "heat", parameter: nil)
        case .saute: return EncodedAction(kind: "saute", parameter: nil)
        case .boil: return EncodedAction(kind: "boil", parameter: nil)
        case .simmer: return EncodedAction(kind: "simmer", parameter: nil)
        case .fry(let style): return EncodedAction(kind: "fry", parameter: style.rawValue)
        case .bake: return EncodedAction(kind: "bake", parameter: nil)
        case .roast: return EncodedAction(kind: "roast", parameter: nil)
        case .grill: return EncodedAction(kind: "grill", parameter: nil)
        case .steam: return EncodedAction(kind: "steam", parameter: nil)
        case .scramble: return EncodedAction(kind: "scramble", parameter: nil)
        case .plate: return EncodedAction(kind: "plate", parameter: nil)
        case .garnish: return EncodedAction(kind: "garnish", parameter: nil)
        case .rest: return EncodedAction(kind: "rest", parameter: nil)
        case .serve: return EncodedAction(kind: "serve", parameter: nil)
        case .toss: return EncodedAction(kind: "toss", parameter: nil)
        case .other(let value): return EncodedAction(kind: "other", parameter: value)
        }
    }

    static func decode(kind: String, parameter: String?) -> CookingAction {
        switch kind {
        case "cut":
            if let parameter, let style = CookingAction.CutStyle(rawValue: parameter) {
                return .cut(style)
            }
            return .other("cut")
        case "peel": return .peel
        case "measure": return .measure
        case "mix": return .mix
        case "marinate": return .marinate
        case "season": return .season
        case "heat": return .heat
        case "saute": return .saute
        case "boil": return .boil
        case "simmer": return .simmer
        case "fry":
            if let parameter, let style = CookingAction.FryStyle(rawValue: parameter) {
                return .fry(style)
            }
            return .other("fry")
        case "bake": return .bake
        case "roast": return .roast
        case "grill": return .grill
        case "steam": return .steam
        case "scramble": return .scramble
        case "plate": return .plate
        case "garnish": return .garnish
        case "rest": return .rest
        case "serve": return .serve
        case "toss": return .toss
        case "other": return .other(parameter ?? "other")
        default: return .other(parameter ?? kind)
        }
    }
}
