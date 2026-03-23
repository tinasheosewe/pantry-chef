import Foundation
import SwiftData

final class PantryItemPreferenceStore: PantryItemPreferenceStoreProtocol {
    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard, storageKey: String = "pantry.item.default.preferences") {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func preference(for catalogItemID: String) -> PantryItemDefaultPreference? {
        loadPreferences()[catalogItemID]
    }

    func savePreference(_ preference: PantryItemDefaultPreference) {
        var preferences = loadPreferences()
        preferences[preference.catalogItemID] = preference
        persist(preferences)
    }

    func removePreference(for catalogItemID: String) {
        var preferences = loadPreferences()
        preferences.removeValue(forKey: catalogItemID)
        persist(preferences)
    }

    private func loadPreferences() -> [String: PantryItemDefaultPreference] {
        guard let data = userDefaults.data(forKey: storageKey) else { return [:] }

        do {
            return try decoder.decode([String: PantryItemDefaultPreference].self, from: data)
        } catch {
            AppLog.warn("[PantryItemPreferenceStore] Discarding unreadable pantry item default preferences: \(error.localizedDescription)")
            userDefaults.removeObject(forKey: storageKey)
            return [:]
        }
    }

    private func persist(_ preferences: [String: PantryItemDefaultPreference]) {
        guard !preferences.isEmpty else {
            userDefaults.removeObject(forKey: storageKey)
            return
        }

        do {
            let data = try encoder.encode(preferences)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            AppLog.warn("[PantryItemPreferenceStore] Failed to persist pantry item default preferences: \(error.localizedDescription)")
        }
    }
}

actor StorageService: StorageServiceProtocol {
    private static let storeFileName = "default.store"

    enum StorageError: LocalizedError {
        case containerInitializationFailed(Error)
        case recipeEncodingFailed(UUID)

        var errorDescription: String? {
            switch self {
            case .containerInitializationFailed(let error):
                return "Failed to initialize persistent store: \(error.localizedDescription)"
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
        self.init(isStoredInMemoryOnly: false, shouldBootstrap: true, resetPersistentStore: false)
    }

    init(isStoredInMemoryOnly: Bool, shouldBootstrap: Bool, resetPersistentStore: Bool) {
        let schema = Schema([
            PantryItemRecord.self,
            PantryFacetRecord.self,
            RecipeRecord.self,
            IngredientRecord.self,
            IngredientFacetRecord.self,
            RecipeStepRecord.self,
            StepTaskRecord.self,
            StepTaskDependencyRecord.self,
            MealPlanRecord.self,
            ShoppingItemRecord.self,
            ShoppingFacetRecord.self,
        ])
        self.shouldBootstrap = shouldBootstrap

        do {
            self.container = try Self.makeContainer(
                schema: schema,
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                resetPersistentStore: resetPersistentStore
            )
        } catch {
            preconditionFailure(StorageError.containerInitializationFailed(error).localizedDescription)
        }
    }

    private static func makeContainer(schema: Schema, isStoredInMemoryOnly: Bool, resetPersistentStore: Bool) throws -> ModelContainer {
        if isStoredInMemoryOnly {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        let storeURL = try persistentStoreURL()
        if resetPersistentStore {
            AppLog.warn("[StorageService] Resetting persistent store at launch because RESET_PERSISTENT_STORE was supplied")
            try destroyPersistentStore(at: storeURL)
        }
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            AppLog.warn("[StorageService] Failed to open persistent store with current schema. Resetting store and retrying: \(error.localizedDescription)")
            try destroyPersistentStore(at: storeURL)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
    }

    private static func persistentStoreURL() throws -> URL {
        let appSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupportDirectory.appendingPathComponent(storeFileName)
    }

    private static func destroyPersistentStore(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let urlsToRemove = [
            storeURL,
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal"),
        ]

        for url in urlsToRemove where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
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
            record.update(from: item, in: context)
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
        let recipes = decodeRecipes(from: records)
        return recipes.sorted { $0.dateAdded > $1.dateAdded }
    }

    func fetchStartupSnapshot() async throws -> StorageStartupSnapshot {
        try ensureBootstrapIfNeeded()

        let pantryRecords = try context.fetch(FetchDescriptor<PantryItemRecord>())
        let recipeRecords = try context.fetch(FetchDescriptor<RecipeRecord>())
        let mealPlanRecords = try context.fetch(FetchDescriptor<MealPlanRecord>())
        let shoppingRecords = try context.fetch(FetchDescriptor<ShoppingItemRecord>())

        let pantryItems = pantryRecords
            .map { $0.toDomain() }
            .sorted { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }

        let decodedRecipes = decodeRecipes(from: recipeRecords)
        let sortedRecipes = decodedRecipes.sorted { $0.dateAdded > $1.dateAdded }

        var recipeById: [UUID: Recipe] = [:]
        recipeById.reserveCapacity(decodedRecipes.count)
        for recipe in decodedRecipes {
            recipeById[recipe.id] = recipe
        }

        let mealPlan = mealPlanRecords
            .map { record in
                record.toDomain(recipe: record.recipeId.flatMap { recipeById[$0] })
            }
            .sorted { $0.date < $1.date }

        let shoppingItems = shoppingRecords
            .map { $0.toDomain() }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return StorageStartupSnapshot(
            pantryItems: pantryItems,
            recipes: sortedRecipes,
            mealPlan: mealPlan,
            shoppingItems: shoppingItems
        )
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
        let decodedRecipes = decodeRecipes(from: recipeRecords)

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
                record.update(from: item, in: context)
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

    private func decodeRecipes(from records: [RecipeRecord]) -> [Recipe] {
        var recipes: [Recipe] = []
        recipes.reserveCapacity(records.count)

        for record in records {
            do {
                recipes.append(try record.toDomain())
            } catch {
                AppLog.warn("[StorageService] Skipping corrupted recipe record \(record.id.uuidString): \(error.localizedDescription)")
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

struct StorageStartupSnapshot {
    let pantryItems: [PantryItem]
    let recipes: [Recipe]
    let mealPlan: [MealPlanEntry]
    let shoppingItems: [ShoppingItem]
}
