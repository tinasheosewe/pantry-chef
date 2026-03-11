import Foundation
import SwiftData

actor StorageService: StorageServiceProtocol {
    enum StorageError: LocalizedError {
        case containerInitializationFailed(Error)
        case corruptedRecipeRecord(UUID)
        case recipeEncodingFailed(UUID)

        var errorDescription: String? {
            switch self {
            case .containerInitializationFailed(let error):
                return "Failed to initialize persistent store: \(error.localizedDescription)"
            case .corruptedRecipeRecord(let id):
                return "Corrupted recipe record: \(id.uuidString)"
            case .recipeEncodingFailed(let id):
                return "Failed to encode recipe for persistence: \(id.uuidString)"
            }
        }
    }

    private let container: ModelContainer
    private let shouldBootstrap: Bool
    private var didBootstrap = false

    private lazy var context: ModelContext = {
        ModelContext(container)
    }()

    init() {
        self.init(isStoredInMemoryOnly: false, shouldBootstrap: true)
    }

    init(isStoredInMemoryOnly: Bool, shouldBootstrap: Bool) {
        do {
            let schema = Schema([
                PantryItemRecord.self,
                RecipeRecord.self,
                IngredientRecord.self,
                RecipeStepRecord.self,
                StepTaskRecord.self,
                StepTaskDependencyRecord.self,
                MealPlanRecord.self,
                ShoppingItemRecord.self,
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isStoredInMemoryOnly)
            self.container = try ModelContainer(for: schema, configurations: [configuration])
            self.shouldBootstrap = shouldBootstrap
        } catch {
            preconditionFailure(StorageError.containerInitializationFailed(error).localizedDescription)
        }
    }

    func fetchPantryItems() async throws -> [PantryItem] {
        try ensureBootstrapIfNeeded()
        let records = try context.fetch(FetchDescriptor<PantryItemRecord>())
        return records
            .map { $0.toDomain() }
            .sorted { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }
    }

    func addPantryItem(_ item: PantryItem) async throws -> PantryItem {
        try ensureBootstrapIfNeeded()
        context.insert(PantryItemRecord(from: item))
        try saveContext()
        return item
    }

    func updatePantryItem(_ item: PantryItem) async throws -> PantryItem {
        try ensureBootstrapIfNeeded()
        if let record = try fetchPantryRecord(id: item.id) {
            record.update(from: item)
            try saveContext()
        }
        return item
    }

    func deletePantryItem(_ item: PantryItem) async throws {
        try ensureBootstrapIfNeeded()
        if let record = try fetchPantryRecord(id: item.id) {
            context.delete(record)
            try saveContext()
        }
    }

    func fetchRecipes() async throws -> [Recipe] {
        try ensureBootstrapIfNeeded()
        let records = try context.fetch(FetchDescriptor<RecipeRecord>())
        let recipes = try decodeRecipes(from: records)
        return recipes.sorted { $0.dateAdded > $1.dateAdded }
    }

    func addRecipe(_ recipe: Recipe) async throws -> Recipe {
        try ensureBootstrapIfNeeded()
        do {
            context.insert(try RecipeRecord(from: recipe))
        } catch {
            throw StorageError.recipeEncodingFailed(recipe.id)
        }
        try saveContext()
        return recipe
    }

    func updateRecipe(_ recipe: Recipe) async throws -> Recipe {
        try ensureBootstrapIfNeeded()
        if let record = try fetchRecipeRecord(id: recipe.id) {
            do {
                try record.update(from: recipe)
            } catch {
                throw StorageError.recipeEncodingFailed(recipe.id)
            }
        } else {
            do {
                context.insert(try RecipeRecord(from: recipe))
            } catch {
                throw StorageError.recipeEncodingFailed(recipe.id)
            }
        }
        try saveContext()
        return recipe
    }

    func deleteRecipe(_ recipe: Recipe) async throws {
        try ensureBootstrapIfNeeded()
        if let record = try fetchRecipeRecord(id: recipe.id) {
            context.delete(record)
            try saveContext()
        }
    }

    func fetchMealPlan() async throws -> [MealPlanEntry] {
        try ensureBootstrapIfNeeded()
        let records = try context.fetch(FetchDescriptor<MealPlanRecord>())
        let recipeRecords = try context.fetch(FetchDescriptor<RecipeRecord>())
        let decodedRecipes = try decodeRecipes(from: recipeRecords)

        var recipeById: [UUID: Recipe] = [:]
        recipeById.reserveCapacity(decodedRecipes.count)
        for recipe in decodedRecipes {
            recipeById[recipe.id] = recipe
        }

        return records
            .map { record in
                record.toDomain(recipe: record.recipeId.flatMap { recipeById[$0] })
            }
            .sorted { $0.date < $1.date }
    }

    func addMealPlanEntry(_ entry: MealPlanEntry) async throws -> MealPlanEntry {
        try ensureBootstrapIfNeeded()
        context.insert(MealPlanRecord(from: entry))
        try saveContext()
        return entry
    }

    func updateMealPlanEntry(_ entry: MealPlanEntry) async throws -> MealPlanEntry {
        try ensureBootstrapIfNeeded()
        if let record = try fetchMealPlanRecord(id: entry.id) {
            record.update(from: entry)
            try saveContext()
        }
        return entry
    }

    func deleteMealPlanEntry(_ entry: MealPlanEntry) async throws {
        try ensureBootstrapIfNeeded()
        if let record = try fetchMealPlanRecord(id: entry.id) {
            context.delete(record)
            try saveContext()
        }
    }

    func fetchShoppingItems() async throws -> [ShoppingItem] {
        try ensureBootstrapIfNeeded()
        let records = try context.fetch(FetchDescriptor<ShoppingItemRecord>())
        return records
            .map { $0.toDomain() }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func saveShoppingItems(_ items: [ShoppingItem]) async throws {
        try ensureBootstrapIfNeeded()
        let existing = try context.fetch(FetchDescriptor<ShoppingItemRecord>())
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let incomingIds = Set(items.map { $0.id })

        for item in items {
            if let record = existingById[item.id] {
                record.update(from: item)
            } else {
                context.insert(ShoppingItemRecord(from: item))
            }
        }

        for record in existing where !incomingIds.contains(record.id) {
            context.delete(record)
        }

        try saveContext()
    }

    private func ensureBootstrapIfNeeded() throws {
        guard shouldBootstrap, !didBootstrap else { return }
        try bootstrapIfNeeded()
        didBootstrap = true
    }

    private func bootstrapIfNeeded() throws {
        let pantryCount = try context.fetchCount(FetchDescriptor<PantryItemRecord>())
        let recipeCount = try context.fetchCount(FetchDescriptor<RecipeRecord>())

        if pantryCount > 0 || recipeCount > 0 {
            return
        }

        for item in PantryItem.samples {
            context.insert(PantryItemRecord(from: item))
        }

        for recipe in Recipe.samples {
            context.insert(try RecipeRecord(from: recipe))
        }

        if context.hasChanges {
            try context.save()
        }
    }

    private func fetchPantryRecord(id: UUID) throws -> PantryItemRecord? {
        var descriptor = FetchDescriptor<PantryItemRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchRecipeRecord(id: UUID) throws -> RecipeRecord? {
        var descriptor = FetchDescriptor<RecipeRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchMealPlanRecord(id: UUID) throws -> MealPlanRecord? {
        var descriptor = FetchDescriptor<MealPlanRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func decodeRecipes(from records: [RecipeRecord]) throws -> [Recipe] {
        var recipes: [Recipe] = []
        recipes.reserveCapacity(records.count)

        for record in records {
            do {
                recipes.append(try record.toDomain())
            } catch {
                throw StorageError.corruptedRecipeRecord(record.id)
            }
        }
        return recipes
    }

    private func saveContext() throws {
        if context.hasChanges {
            try context.save()
        }
    }
}
