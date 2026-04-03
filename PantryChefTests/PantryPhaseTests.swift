import XCTest
@testable import PantryChef

// MARK: - Mock User Catalog Store

private final class MockUserCatalogStore: UserCatalogStoreProtocol {
    var savedUserItems: [PantryCatalogItemDefinition] = []
    var savedFacetExtensions: [String: [String: [String]]] = [:]
    var savedAliasExtensions: [String: [String]] = [:]
    var savedDefaultOverrides: [String: [String: String]] = [:]

    var saveUserItemsCallCount = 0
    var saveFacetExtensionsCallCount = 0
    var saveAliasExtensionsCallCount = 0
    var saveDefaultOverridesCallCount = 0

    func loadUserItems() -> [PantryCatalogItemDefinition] { savedUserItems }
    func saveUserItems(_ items: [PantryCatalogItemDefinition]) {
        savedUserItems = items
        saveUserItemsCallCount += 1
    }

    func loadFacetExtensions() -> [String: [String: [String]]] { savedFacetExtensions }
    func saveFacetExtensions(_ extensions: [String: [String: [String]]]) {
        savedFacetExtensions = extensions
        saveFacetExtensionsCallCount += 1
    }

    func loadAliasExtensions() -> [String: [String]] { savedAliasExtensions }
    func saveAliasExtensions(_ extensions: [String: [String]]) {
        savedAliasExtensions = extensions
        saveAliasExtensionsCallCount += 1
    }

    func loadDefaultOverrides() -> [String: [String: String]] { savedDefaultOverrides }
    func saveDefaultOverrides(_ overrides: [String: [String: String]]) {
        savedDefaultOverrides = overrides
        saveDefaultOverridesCallCount += 1
    }
}

// MARK: - Helpers

private func makeTestItem(
    id: String,
    name: String,
    category: FoodCategory = .other,
    facets: [PantryFacetDefinition] = [],
    isUserDefined: Bool = false
) -> PantryCatalogItemDefinition {
    PantryCatalogItemDefinition(
        id: id,
        name: name,
        category: category,
        defaultUnit: nil,
        defaultQuantity: nil,
        defaultStorage: .pantry,
        aliases: [],
        facets: facets,
        defaultSelections: [],
        substitutions: [],
        unitOverrides: [:],
        freshnessByStorage: [:],
        isUserDefined: isUserDefined
    )
}

private func resetCatalog(store: MockUserCatalogStore? = nil) {
    let s = store ?? MockUserCatalogStore()
    PantryCatalog.loadUserData(from: s)
}

// MARK: - B1: Frequency Tracker Tests

final class FrequencyTrackerTests: XCTestCase {
    private let testKey = "pantry.item.add.frequency"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func testRecordAdditionIncrementsCount() {
        XCTAssertEqual(PantryAddFrequencyTracker.frequency(for: "milk"), 0)
        PantryAddFrequencyTracker.recordAddition(catalogItemID: "milk")
        XCTAssertEqual(PantryAddFrequencyTracker.frequency(for: "milk"), 1)
        PantryAddFrequencyTracker.recordAddition(catalogItemID: "milk")
        XCTAssertEqual(PantryAddFrequencyTracker.frequency(for: "milk"), 2)
    }

    func testFrequencyIndependentPerItem() {
        PantryAddFrequencyTracker.recordAddition(catalogItemID: "egg")
        PantryAddFrequencyTracker.recordAddition(catalogItemID: "egg")
        PantryAddFrequencyTracker.recordAddition(catalogItemID: "rice")
        XCTAssertEqual(PantryAddFrequencyTracker.frequency(for: "egg"), 2)
        XCTAssertEqual(PantryAddFrequencyTracker.frequency(for: "rice"), 1)
        XCTAssertEqual(PantryAddFrequencyTracker.frequency(for: "butter"), 0)
    }

    func testFrequenciesReturnsFullDictionary() {
        PantryAddFrequencyTracker.recordAddition(catalogItemID: "a")
        PantryAddFrequencyTracker.recordAddition(catalogItemID: "b")
        let all = PantryAddFrequencyTracker.frequencies()
        XCTAssertEqual(all["a"], 1)
        XCTAssertEqual(all["b"], 1)
    }
}

// MARK: - B2: DefaultsToOnHand Tests

final class DefaultsToOnHandTests: XCTestCase {
    func testOnHandCategories() {
        let onHandCategories: [FoodCategory] = [.spices, .bakingSupplies, .condiments, .oils]
        for category in onHandCategories {
            XCTAssertTrue(category.defaultsToOnHand, "\(category) should default to on-hand")
        }
    }

    func testNonOnHandCategories() {
        let nonOnHand: [FoodCategory] = [.produce, .protein, .dairy, .grains, .pasta, .beverages, .snacks, .other]
        for category in nonOnHand {
            XCTAssertFalse(category.defaultsToOnHand, "\(category) should NOT default to on-hand")
        }
    }
}

// MARK: - B3: PantryIntakeRowDraft blankFor Tests

final class PantryIntakeRowDraftBlankForTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetCatalog()
    }

    func testBlankForSetsSelectedItemID() {
        let item = makeTestItem(id: "test-item", name: "Test Item")
        let draft = PantryIntakeRowDraft(blankFor: item)
        XCTAssertEqual(draft.selectedItemID, "test-item")
    }

    func testBlankForSetsIsCustomItemForUserDefined() {
        let userItem = makeTestItem(id: "user-custom", name: "Custom", isUserDefined: true)
        let draft = PantryIntakeRowDraft(blankFor: userItem)
        XCTAssertTrue(draft.isCustomItem)
    }

    func testBlankForCatalogItemNotCustom() {
        let catalogItem = makeTestItem(id: "catalog-item", name: "Catalog")
        let draft = PantryIntakeRowDraft(blankFor: catalogItem)
        XCTAssertFalse(draft.isCustomItem)
    }
}

// MARK: - B5: CustomIngredientDraft Tests

final class CustomIngredientDraftTests: XCTestCase {
    func testTitleCaseBasic() {
        XCTAssertEqual(CustomIngredientDraft.titleCase("hello world"), "Hello World")
    }

    func testTitleCaseSingleWord() {
        XCTAssertEqual(CustomIngredientDraft.titleCase("butter"), "Butter")
    }

    func testTitleCaseAlreadyTitleCase() {
        XCTAssertEqual(CustomIngredientDraft.titleCase("Olive Oil"), "Olive Oil")
    }

    func testTitleCaseMixedInput() {
        XCTAssertEqual(CustomIngredientDraft.titleCase("BROWN SUGAR"), "Brown Sugar")
    }

    func testBuildDefinitionAppliesTitleCase() {
        var draft = CustomIngredientDraft(name: "brown sugar")
        draft.category = .bakingSupplies
        let definition = draft.buildDefinition()
        XCTAssertEqual(definition.name, "Brown Sugar")
    }

    func testTitleCasedNameUsesSharedFormatter() {
        let draft = CustomIngredientDraft(name: "brown sugar")
        XCTAssertEqual(draft.titleCasedName, "Brown Sugar")
        XCTAssertEqual(CustomIngredientDraft.titleCase("brown sugar"), PantryCatalogItemDefinition.titleCase("brown sugar"))
    }

    func testBuildDefinitionGeneratesUserPrefixID() {
        let draft = CustomIngredientDraft(name: "My Special Ingredient")
        let definition = draft.buildDefinition()
        XCTAssertTrue(definition.id.hasPrefix("user-"), "ID should start with user- prefix")
    }

    func testBuildDefinitionIsUserDefined() {
        let draft = CustomIngredientDraft(name: "Test")
        let definition = draft.buildDefinition()
        XCTAssertTrue(definition.isUserDefined)
    }

    func testAddFacetOptionIgnoresDuplicates() {
        var draft = CustomIngredientDraft(name: "Test")
        draft.addFacetOption(.variant, value: "Red")
        draft.addFacetOption(.variant, value: "red")
        XCTAssertEqual(draft.facets[.variant]?.count, 1, "Case-insensitive duplicate should be rejected")
    }

    func testAddFacetOptionIgnoresEmpty() {
        var draft = CustomIngredientDraft(name: "Test")
        draft.addFacetOption(.variant, value: "  ")
        XCTAssertNil(draft.facets[.variant], "Empty/whitespace option should not be added")
    }

    func testRemoveFacetOptionRemovesKey() {
        var draft = CustomIngredientDraft(name: "Test")
        draft.addFacetOption(.form, value: "Diced")
        draft.removeFacetOption(.form, value: "Diced")
        XCTAssertNil(draft.facets[.form], "Key should be removed when last option is removed")
    }

    func testBuildDefinitionIncludesFacets() {
        var draft = CustomIngredientDraft(name: "Tomato")
        draft.addFacetOption(.form, value: "Diced")
        draft.addFacetOption(.form, value: "Crushed")
        draft.addFacetOption(.preservation, value: "Canned")
        let definition = draft.buildDefinition()
        XCTAssertEqual(definition.facets.count, 2)
        let formFacet = definition.facets.first(where: { $0.key == .form })
        XCTAssertEqual(formFacet?.options.count, 2)
    }

    func testUnusedFacetKeysExcludesUsed() {
        var draft = CustomIngredientDraft(name: "Test")
        draft.addFacetOption(.variant, value: "A")
        draft.addFacetOption(.form, value: "B")
        let unused = draft.unusedFacetKeys
        XCTAssertFalse(unused.contains(.variant))
        XCTAssertFalse(unused.contains(.form))
        XCTAssertTrue(unused.contains(.preservation))
    }
}

// MARK: - B6: PantryCatalog CRUD Tests

final class PantryCatalogCRUDTests: XCTestCase {
    private var store: MockUserCatalogStore!

    override func setUp() {
        super.setUp()
        store = MockUserCatalogStore()
        resetCatalog(store: store)
    }

    override func tearDown() {
        resetCatalog()
        super.tearDown()
    }

    func testRegisterUserItemSuccess() {
        let item = makeTestItem(id: "user-zytoplasmx", name: "Zytoplasmx", isUserDefined: true)
        let result = PantryCatalog.registerUserItem(item)
        XCTAssertNoThrow(try result.get())
        XCTAssertNotNil(PantryCatalog.item(id: "user-zytoplasmx"))
        XCTAssertEqual(store.saveUserItemsCallCount, 1)
    }

    func testRegisterUserItemRejectsBadPrefix() {
        let item = makeTestItem(id: "no-prefix", name: "Bad", isUserDefined: true)
        let result = PantryCatalog.registerUserItem(item)
        if case .failure = result {
            // expected
        } else {
            XCTFail("Should reject items without user- prefix")
        }
    }

    func testRegisterUserItemRejectsDuplicateID() {
        let item1 = makeTestItem(id: "user-duptest", name: "DupTestAlpha", isUserDefined: true)
        let item2 = makeTestItem(id: "user-duptest", name: "DupTestBeta", isUserDefined: true)
        _ = PantryCatalog.registerUserItem(item1)
        let result = PantryCatalog.registerUserItem(item2)
        if case .failure = result {
            // expected — either idCollision or duplicateUserItem
        } else {
            XCTFail("Should reject duplicate ID")
        }
    }

    func testRegisterUserItemRejectsDuplicateName() {
        let item1 = makeTestItem(id: "user-thingalpha", name: "UniqueThingAlpha", isUserDefined: true)
        let item2 = makeTestItem(id: "user-thingbeta", name: "uniquethingalpha", isUserDefined: true)
        _ = PantryCatalog.registerUserItem(item1)
        let result = PantryCatalog.registerUserItem(item2)
        if case .failure = result {
            // expected — name collision
        } else {
            XCTFail("Should reject duplicate name (case-insensitive)")
        }
    }

    func testRemoveUserItem() {
        let item = makeTestItem(id: "user-remove-me", name: "Remove Me", isUserDefined: true)
        _ = PantryCatalog.registerUserItem(item)
        XCTAssertNotNil(PantryCatalog.item(id: "user-remove-me"))

        PantryCatalog.removeUserItem(id: "user-remove-me")
        XCTAssertNil(PantryCatalog.item(id: "user-remove-me"))
    }

    func testApplyMergeAddsFacetExtensions() {
        // Pick a known catalog item
        guard let existingItem = PantryCatalog.allItems.first(where: { !$0.isUserDefined }) else {
            XCTFail("No catalog items found")
            return
        }

        PantryCatalog.applyMerge(
            catalogItemID: existingItem.id,
            mergedFacets: [.variant: ["TestVariant"]],
            mergedAliases: ["test-alias"]
        )

        let updated = PantryCatalog.item(id: existingItem.id)
        let variantFacet = updated?.facets.first(where: { $0.key == .variant })
        XCTAssertTrue(variantFacet?.options.contains("TestVariant") ?? false)
        XCTAssertEqual(store.saveFacetExtensionsCallCount, 1)
    }

    func testResetExtensionsClearsModifications() {
        guard let existingItem = PantryCatalog.allItems.first(where: { !$0.isUserDefined }) else {
            XCTFail("No catalog items found")
            return
        }

        PantryCatalog.applyMerge(
            catalogItemID: existingItem.id,
            mergedFacets: [.form: ["Smashed"]],
            mergedAliases: ["smash-alias"]
        )
        XCTAssertNotNil(PantryCatalog.facetExtensions[existingItem.id])

        PantryCatalog.resetExtensions(catalogItemID: existingItem.id)
        XCTAssertNil(PantryCatalog.facetExtensions[existingItem.id])
        XCTAssertNil(PantryCatalog.aliasExtensions[existingItem.id])
    }

    func testLoadUserDataRestoresState() {
        let preloadStore = MockUserCatalogStore()
        let preItem = makeTestItem(id: "user-preloaded", name: "Preloaded", isUserDefined: true)
        preloadStore.savedUserItems = [preItem]
        preloadStore.savedFacetExtensions = ["some-id": ["variant": ["Red"]]]

        PantryCatalog.loadUserData(from: preloadStore)
        XCTAssertNotNil(PantryCatalog.item(id: "user-preloaded"))
        XCTAssertEqual(PantryCatalog.facetExtensions["some-id"]?["variant"], ["Red"])
    }
}

// MARK: - B7: Notification Tests

final class CatalogNotificationTests: XCTestCase {
    private var store: MockUserCatalogStore!

    override func setUp() {
        super.setUp()
        store = MockUserCatalogStore()
        resetCatalog(store: store)
    }

    override func tearDown() {
        resetCatalog()
        super.tearDown()
    }

    func testRegisterUserItemPostsNotification() {
        let expectation = expectation(forNotification: .pantryCatalogDidChange, object: nil)
        let item = makeTestItem(id: "user-notif", name: "Notif", isUserDefined: true)
        _ = PantryCatalog.registerUserItem(item)
        wait(for: [expectation], timeout: 1.0)
    }

    func testRemoveUserItemPostsNotification() {
        let item = makeTestItem(id: "user-notif-rm", name: "NotifRm", isUserDefined: true)
        _ = PantryCatalog.registerUserItem(item)

        let expectation = expectation(forNotification: .pantryCatalogDidChange, object: nil)
        PantryCatalog.removeUserItem(id: "user-notif-rm")
        wait(for: [expectation], timeout: 1.0)
    }

    func testResetExtensionsPostsNotification() {
        guard let existing = PantryCatalog.allItems.first(where: { !$0.isUserDefined }) else {
            XCTFail("No catalog items")
            return
        }
        PantryCatalog.applyMerge(catalogItemID: existing.id, mergedFacets: [.form: ["X"]], mergedAliases: [])

        let expectation = expectation(forNotification: .pantryCatalogDidChange, object: nil)
        PantryCatalog.resetExtensions(catalogItemID: existing.id)
        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - B8: Title Case Round-Trip Tests

final class TitleCaseRoundTripTests: XCTestCase {
    private var store: MockUserCatalogStore!

    override func setUp() {
        super.setUp()
        store = MockUserCatalogStore()
        resetCatalog(store: store)
    }

    override func tearDown() {
        resetCatalog()
        super.tearDown()
    }

    func testRegisterAndRetrievePreservesTitleCase() {
        var draft = CustomIngredientDraft(name: "brown sugar")
        draft.category = .bakingSupplies
        let def = draft.buildDefinition()
        _ = PantryCatalog.registerUserItem(def)

        let retrieved = PantryCatalog.item(id: def.id)
        XCTAssertEqual(retrieved?.name, "Brown Sugar")
        XCTAssertEqual(retrieved?.titleCasedName, "Brown Sugar")
    }
}

// MARK: - B9: Scenario Tests (End-to-End Workflows)

final class CatalogScenarioTests: XCTestCase {
    private var store: MockUserCatalogStore!

    override func setUp() {
        super.setUp()
        store = MockUserCatalogStore()
        resetCatalog(store: store)
    }

    override func tearDown() {
        resetCatalog()
        super.tearDown()
    }

    func testCreateCustomItemEditAndDelete() {
        // Create
        var draft = CustomIngredientDraft(name: "homemade spice blend")
        draft.category = .spices
        draft.addFacetOption(.variant, value: "Smoky")
        let def = draft.buildDefinition()
        let createResult = PantryCatalog.registerUserItem(def)
        XCTAssertNoThrow(try createResult.get())
        XCTAssertEqual(PantryCatalog.item(id: def.id)?.name, "Homemade Spice Blend")

        // Edit: remove then re-register with updated facets
        PantryCatalog.removeUserItem(id: def.id)
        var editDraft = CustomIngredientDraft(name: "Homemade Spice Blend")
        editDraft.category = .spices
        editDraft.addFacetOption(.variant, value: "Smoky")
        editDraft.addFacetOption(.variant, value: "Sweet")
        let editDef = editDraft.buildDefinition()
        let editResult = PantryCatalog.registerUserItem(editDef)
        XCTAssertNoThrow(try editResult.get())

        let updated = PantryCatalog.item(id: editDef.id)
        let variants = updated?.facets.first(where: { $0.key == .variant })?.options
        XCTAssertEqual(variants?.count, 2)

        // Delete
        PantryCatalog.removeUserItem(id: editDef.id)
        XCTAssertNil(PantryCatalog.item(id: editDef.id))
    }

    func testExtendCatalogItemThenReset() {
        guard let catalogItem = PantryCatalog.allItems.first(where: { !$0.isUserDefined }) else {
            XCTFail("Need at least one catalog item")
            return
        }

        let originalFacetCount = catalogItem.facets.count

        // Extend with new facets
        PantryCatalog.applyMerge(
            catalogItemID: catalogItem.id,
            mergedFacets: [.texture: ["Crunchy", "Smooth"]],
            mergedAliases: ["alias-1"]
        )

        let extended = PantryCatalog.item(id: catalogItem.id)!
        let textureFacet = extended.facets.first(where: { $0.key == .texture })
        XCTAssertTrue(textureFacet?.options.contains("Crunchy") ?? false)

        // Reset
        PantryCatalog.resetExtensions(catalogItemID: catalogItem.id)
        let reset = PantryCatalog.item(id: catalogItem.id)!
        XCTAssertEqual(reset.facets.count, originalFacetCount)
    }

    func testApplyMergeIsAdditive() throws {
        guard let catalogItem = PantryCatalog.allItems.first(where: {
            !$0.isUserDefined && $0.facets.contains(where: { $0.key == .form })
        }) else {
            throw XCTSkip("No catalog item with .form facet found")
        }

        let originalFormOptions = catalogItem.facets.first(where: { $0.key == .form })!.options
        PantryCatalog.applyMerge(
            catalogItemID: catalogItem.id,
            mergedFacets: [.form: ["NewFormOption"]],
            mergedAliases: []
        )

        let updated = PantryCatalog.item(id: catalogItem.id)!
        let updatedFormOptions = updated.facets.first(where: { $0.key == .form })!.options
        // All original options must still be there
        for orig in originalFormOptions {
            XCTAssertTrue(updatedFormOptions.contains(orig), "Original option '\(orig)' must persist")
        }
        XCTAssertTrue(updatedFormOptions.contains("NewFormOption"), "New option must be added")

        // Cleanup
        PantryCatalog.resetExtensions(catalogItemID: catalogItem.id)
    }

    func testDuplicateUserItemRegistrationPreservesOriginal() {
        let item1 = makeTestItem(id: "user-original", name: "Original", category: .produce, isUserDefined: true)
        _ = PantryCatalog.registerUserItem(item1)

        let item2 = makeTestItem(id: "user-original", name: "Replacement", category: .dairy, isUserDefined: true)
        let result = PantryCatalog.registerUserItem(item2)

        if case .success = result {
            XCTFail("Should reject duplicate ID")
        }
        // Original is preserved
        XCTAssertEqual(PantryCatalog.item(id: "user-original")?.category, .produce)
    }
}

// MARK: - B10: Facet Migration Map Tests

final class FacetMigrationTests: XCTestCase {
    private var store: MockUserCatalogStore!

    override func setUp() {
        super.setUp()
        store = MockUserCatalogStore()
    }

    override func tearDown() {
        resetCatalog()
        super.tearDown()
    }

    func testOrphanedExtensionPreserved() {
        guard let catalogItem = PantryCatalog.allItems.first(where: { !$0.isUserDefined }) else {
            XCTFail("Need catalog items")
            return
        }

        // Inject an extension with an unrecognized facet key
        store.savedFacetExtensions = [catalogItem.id: ["nonexistent_key": ["ValueA", "ValueB"]]]
        PantryCatalog.loadUserData(from: store)

        // The unrecognized key should appear in orphanedExtensions
        let orphans = PantryCatalog.orphanedExtensions[catalogItem.id]
        XCTAssertNotNil(orphans, "Orphaned extensions should be preserved")
        XCTAssertEqual(orphans?["nonexistent_key"], ["ValueA", "ValueB"])
    }

    func testRecognizedExtensionNotOrphaned() {
        guard let catalogItem = PantryCatalog.allItems.first(where: { !$0.isUserDefined }) else {
            XCTFail("Need catalog items")
            return
        }

        // Inject an extension with a valid facet key
        store.savedFacetExtensions = [catalogItem.id: ["variant": ["TestVariant"]]]
        PantryCatalog.loadUserData(from: store)

        // Should NOT appear in orphaned
        let orphans = PantryCatalog.orphanedExtensions[catalogItem.id]
        XCTAssertNil(orphans, "Recognized key should not be orphaned")

        // Should appear on the item
        let item = PantryCatalog.item(id: catalogItem.id)
        let variantFacet = item?.facets.first(where: { $0.key == .variant })
        XCTAssertTrue(variantFacet?.options.contains("TestVariant") ?? false)
    }

    func testMixedRecognizedAndOrphanedExtensions() {
        guard let catalogItem = PantryCatalog.allItems.first(where: { !$0.isUserDefined }) else {
            XCTFail("Need catalog items")
            return
        }

        store.savedFacetExtensions = [
            catalogItem.id: [
                "form": ["NewForm"],
                "bogus_key": ["OrphanValue"]
            ]
        ]
        PantryCatalog.loadUserData(from: store)

        // Recognized key applied
        let item = PantryCatalog.item(id: catalogItem.id)
        let formFacet = item?.facets.first(where: { $0.key == .form })
        XCTAssertTrue(formFacet?.options.contains("NewForm") ?? false)

        // Unrecognized key orphaned
        let orphans = PantryCatalog.orphanedExtensions[catalogItem.id]
        XCTAssertEqual(orphans?["bogus_key"], ["OrphanValue"])
    }
}

// MARK: - B11: Frequency Sort Tests

@MainActor
final class FrequencySortTests: XCTestCase {
    private let freqKey = "pantry.item.add.frequency"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: freqKey)
        resetCatalog()
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: freqKey)
        super.tearDown()
    }

    func testBrowseModeFrequencyPrimarySort() throws {
        let preferenceStore = MockPantryItemPreferenceStore()
        let vm = PantryBulkAddViewModel(preferenceStore: preferenceStore)

        // Get two catalog items
        guard PantryCatalog.allItems.count >= 2 else {
            throw XCTSkip("Need at least 2 catalog items")
        }
        let itemA = PantryCatalog.allItems[0]
        let itemB = PantryCatalog.allItems[1]

        // Make itemB have higher frequency
        PantryAddFrequencyTracker.recordAddition(catalogItemID: itemB.id)
        PantryAddFrequencyTracker.recordAddition(catalogItemID: itemB.id)

        vm.catalogSearchText = ""
        vm.updateCatalogSearch()

        // itemB should appear before itemA in browse mode
        let idxA = vm.filteredCatalogItems.firstIndex(where: { $0.id == itemA.id })
        let idxB = vm.filteredCatalogItems.firstIndex(where: { $0.id == itemB.id })
        if let a = idxA, let b = idxB {
            XCTAssertLessThan(b, a, "Higher frequency item should appear first in browse mode")
        }
    }
}

// MARK: - B12: Optional Overload Tests

@MainActor
final class StagedRowOverloadTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetCatalog()
    }

    func testUpdateStagedUnitAcceptsNil() throws {
        let preferenceStore = MockPantryItemPreferenceStore()
        let vm = PantryBulkAddViewModel(preferenceStore: preferenceStore)

        guard let item = PantryCatalog.allItems.first else {
            throw XCTSkip("No catalog items")
        }
        vm.addAnotherInstance(item)
        let draftID = vm.stagedRows[0].id

        // Set a unit first
        vm.updateStagedUnit(draftID: draftID, unit: .gram)
        XCTAssertEqual(vm.stagedRows[0].unit, .gram)

        // Clear it with nil
        vm.updateStagedUnit(draftID: draftID, unit: nil)
        XCTAssertNil(vm.stagedRows[0].unit)
    }

    func testUpdateStagedQuantityNilClearsText() throws {
        let preferenceStore = MockPantryItemPreferenceStore()
        let vm = PantryBulkAddViewModel(preferenceStore: preferenceStore)

        guard let item = PantryCatalog.allItems.first else {
            throw XCTSkip("No catalog items")
        }
        vm.addAnotherInstance(item)
        let draftID = vm.stagedRows[0].id

        // Set a quantity first
        vm.updateStagedQuantity(draftID: draftID, quantity: 5.0)
        XCTAssertFalse(vm.stagedRows[0].quantityText.isEmpty)

        // Clear it with nil
        vm.updateStagedQuantity(draftID: draftID, quantity: nil)
        XCTAssertTrue(vm.stagedRows[0].quantityText.isEmpty)
    }

    func testUpdateStagedQuantityStringVersion() throws {
        let preferenceStore = MockPantryItemPreferenceStore()
        let vm = PantryBulkAddViewModel(preferenceStore: preferenceStore)

        guard let item = PantryCatalog.allItems.first else {
            throw XCTSkip("No catalog items")
        }
        vm.addAnotherInstance(item)
        let draftID = vm.stagedRows[0].id

        vm.updateStagedQuantity(draftID: draftID, quantity: "3.5")
        XCTAssertEqual(vm.stagedRows[0].quantityText, "3.5")
    }
}

// MARK: - B13: Fold Candidate Guard Tests

final class FoldCandidateGuardTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetCatalog()
    }

    func testSearchResultBelowThresholdNotAFoldCandidate() {
        // Search for something that won't match well
        let results = CatalogSearchEngine.search("xyznonexistent")
        // If there are results at all, none should have score >= 0.5
        for result in results {
            if result.score < 0.5 {
                // This is correct — a result below 0.5 should not be used as fold candidate
                // The view's checkFoldCandidate guards against this
                break
            }
        }
        // If no results, that's also fine — no fold candidate possible
        XCTAssertTrue(results.isEmpty || results[0].score < 0.5,
                       "Nonsensical query should not produce high-score matches")
    }

    func testUserDefinedItemNotAFoldCandidate() {
        // Register a user item then search for it
        let store = MockUserCatalogStore()
        resetCatalog(store: store)

        let item = makeTestItem(id: "user-fold-test", name: "FoldTestUniqueXYZ", isUserDefined: true)
        _ = PantryCatalog.registerUserItem(item)

        let results = CatalogSearchEngine.search("FoldTestUniqueXYZ")
        if let top = results.first, top.score >= 0.5 {
            XCTAssertTrue(top.item.isUserDefined,
                          "Top match for user-defined item should be user-defined")
            // The view's checkFoldCandidate skips user-defined items
        }
    }
}

// MARK: - B14: Catalog Extension Save Tests

final class CatalogExtensionSaveTests: XCTestCase {
    private var store: MockUserCatalogStore!

    override func setUp() {
        super.setUp()
        store = MockUserCatalogStore()
        resetCatalog(store: store)
    }

    override func tearDown() {
        resetCatalog()
        super.tearDown()
    }

    func testApplyMergeDoesNotCallSaveUserItems() {
        guard let catalogItem = PantryCatalog.allItems.first(where: { !$0.isUserDefined }) else {
            XCTFail("Need catalog items")
            return
        }

        let beforeCount = store.saveUserItemsCallCount
        PantryCatalog.applyMerge(
            catalogItemID: catalogItem.id,
            mergedFacets: [.variant: ["ExtTest"]],
            mergedAliases: []
        )
        XCTAssertEqual(store.saveUserItemsCallCount, beforeCount,
                       "applyMerge should not save user items — it only saves extensions")
        XCTAssertGreaterThan(store.saveFacetExtensionsCallCount, 0,
                             "applyMerge should save facet extensions")

        PantryCatalog.resetExtensions(catalogItemID: catalogItem.id)
    }

    func testApplyMergeAdditiveNeverRemoves() throws {
        guard let catalogItem = PantryCatalog.allItems.first(where: {
            !$0.isUserDefined && !$0.facets.isEmpty
        }) else {
            throw XCTSkip("No catalog item with facets")
        }

        let originalItem = catalogItem
        PantryCatalog.applyMerge(
            catalogItemID: catalogItem.id,
            mergedFacets: [.variant: ["AddedVariant"]],
            mergedAliases: ["added-alias"]
        )

        let updated = PantryCatalog.item(id: catalogItem.id)!
        // All original facets should still exist
        for facet in originalItem.facets {
            let updatedFacet = updated.facets.first(where: { $0.key == facet.key })
            XCTAssertNotNil(updatedFacet, "Facet \(facet.key) should not be removed")
            for option in facet.options {
                XCTAssertTrue(updatedFacet!.options.contains(option),
                              "Original option '\(option)' for \(facet.key) must persist")
            }
        }

        PantryCatalog.resetExtensions(catalogItemID: catalogItem.id)
    }
}

// MARK: - B15: Navigation State Clearing Tests

@MainActor
final class NavigationStateClearingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetCatalog()
    }

    func testSearchTextChangeClearsHighlightAndExpanded() {
        let preferenceStore = MockPantryItemPreferenceStore()
        let vm = PantryBulkAddViewModel(preferenceStore: preferenceStore)

        vm.highlightedItemID = "some-id"
        vm.expandedItemIDs = ["a", "b"]

        // Trigger navigation change through public API
        vm.onCatalogSearchTextChanged()

        XCTAssertNil(vm.highlightedItemID, "Highlight should be cleared on navigation change")
        XCTAssertTrue(vm.expandedItemIDs.isEmpty, "Expanded IDs should be cleared on navigation change")
    }
}

// MARK: - B16: Additional Edge Cases

final class CatalogEdgeCaseTests: XCTestCase {
    private var store: MockUserCatalogStore!

    override func setUp() {
        super.setUp()
        store = MockUserCatalogStore()
        resetCatalog(store: store)
    }

    override func tearDown() {
        resetCatalog()
        super.tearDown()
    }

    func testResetExtensionsForItemWithNoExtensionsIsNoOp() {
        guard let catalogItem = PantryCatalog.allItems.first(where: { !$0.isUserDefined }) else {
            XCTFail("Need catalog items")
            return
        }
        // Should not crash or error
        PantryCatalog.resetExtensions(catalogItemID: catalogItem.id)
        XCTAssertNil(PantryCatalog.facetExtensions[catalogItem.id])
    }

    func testRemoveNonexistentUserItemIsNoOp() {
        let countBefore = PantryCatalog.userItems.count
        PantryCatalog.removeUserItem(id: "user-does-not-exist")
        XCTAssertEqual(PantryCatalog.userItems.count, countBefore)
    }

    func testAllItemsIncludesBothBundleAndUser() {
        let userItem = makeTestItem(id: "user-mixed", name: "MixedTest", isUserDefined: true)
        _ = PantryCatalog.registerUserItem(userItem)

        let allIDs = Set(PantryCatalog.allItems.map(\.id))
        XCTAssertTrue(allIDs.contains("user-mixed"), "allItems should include user items")
        // Should also contain at least some bundle items
        XCTAssertGreaterThan(PantryCatalog.allItems.filter({ !$0.isUserDefined }).count, 0,
                             "allItems should include bundle items")
    }

    func testApplyMergeDuplicateOptionNotAdded() throws {
        guard let catalogItem = PantryCatalog.allItems.first(where: {
            !$0.isUserDefined && $0.facets.contains(where: { $0.key == .form && !$0.options.isEmpty })
        }) else {
            throw XCTSkip("No catalog item with form options")
        }

        let existingOption = catalogItem.facets.first(where: { $0.key == .form })!.options[0]
        let optionCountBefore = catalogItem.facets.first(where: { $0.key == .form })!.options.count

        PantryCatalog.applyMerge(
            catalogItemID: catalogItem.id,
            mergedFacets: [.form: [existingOption]],
            mergedAliases: []
        )

        let updated = PantryCatalog.item(id: catalogItem.id)!
        let optionCountAfter = updated.facets.first(where: { $0.key == .form })!.options.count
        XCTAssertEqual(optionCountAfter, optionCountBefore,
                       "Duplicate option should not be added again")

        PantryCatalog.resetExtensions(catalogItemID: catalogItem.id)
    }
}

// MARK: - B17: Ingredient Catalog Settings Search Tests

final class IngredientCatalogSettingsSearchTests: XCTestCase {
    func testCatalogSearchUsesSharedSearchResultsForAliasQueries() {
        let steak = makeTestItem(id: "steak", name: "steak", category: .protein)
        let unrelated = makeTestItem(id: "chicken", name: "chicken", category: .protein)

        let results = IngredientCatalogSettingsSupport.filteredCatalogItems(
            searchText: "ribeye",
            allItems: [unrelated, steak],
            search: { query in
                XCTAssertEqual(query, "ribeye")
                return [
                    CatalogSearchResult(
                        id: "steak:variant-ribeye",
                        catalogItemID: steak.id,
                        facets: [PantryFacetSelection(key: .variant, value: "ribeye")],
                        displayName: "Ribeye Steak",
                        score: 1,
                        item: steak
                    )
                ]
            }
        )

        XCTAssertEqual(results.map(\.id), ["steak"])
        XCTAssertEqual(results.first?.titleCasedName, "Steak")
    }

    func testCatalogSearchDeduplicatesMultipleFacetResultsForSameBaseItem() {
        let steak = makeTestItem(id: "steak", name: "steak", category: .protein)

        let results = IngredientCatalogSettingsSupport.filteredCatalogItems(
            searchText: "steak",
            allItems: [steak],
            search: { _ in
                [
                    CatalogSearchResult(
                        id: "steak:variant-ribeye",
                        catalogItemID: steak.id,
                        facets: [PantryFacetSelection(key: .variant, value: "ribeye")],
                        displayName: "Ribeye Steak",
                        score: 1,
                        item: steak
                    ),
                    CatalogSearchResult(
                        id: "steak:variant-sirloin",
                        catalogItemID: steak.id,
                        facets: [PantryFacetSelection(key: .variant, value: "sirloin")],
                        displayName: "Sirloin Steak",
                        score: 0.9,
                        item: steak
                    )
                ]
            }
        )

        XCTAssertEqual(results.map(\.id), ["steak"])
    }
}
