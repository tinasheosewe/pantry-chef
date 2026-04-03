import Foundation

// MARK: - Protocol

protocol UserCatalogStoreProtocol: AnyObject {
    func loadUserItems() -> [PantryCatalogItemDefinition]
    func saveUserItems(_ items: [PantryCatalogItemDefinition])

    func loadFacetExtensions() -> [String: [String: [String]]]
    func saveFacetExtensions(_ extensions: [String: [String: [String]]])

    func loadAliasExtensions() -> [String: [String]]
    func saveAliasExtensions(_ extensions: [String: [String]])

    func loadDefaultOverrides() -> [String: [String: String]]
    func saveDefaultOverrides(_ overrides: [String: [String: String]])
}

// MARK: - UserDefaults Implementation

final class UserCatalogStore: UserCatalogStoreProtocol {
    private let userDefaults: UserDefaults
    private let itemsKey: String
    private let facetExtensionsKey: String
    private let aliasExtensionsKey: String
    private let defaultOverridesKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        itemsKey: String = "pantry.user.catalog.items",
        facetExtensionsKey: String = "pantry.user.facet.extensions",
        aliasExtensionsKey: String = "pantry.user.alias.extensions",
        defaultOverridesKey: String = "pantry.user.default.overrides"
    ) {
        self.userDefaults = userDefaults
        self.itemsKey = itemsKey
        self.facetExtensionsKey = facetExtensionsKey
        self.aliasExtensionsKey = aliasExtensionsKey
        self.defaultOverridesKey = defaultOverridesKey
    }

    func loadUserItems() -> [PantryCatalogItemDefinition] {
        guard let data = userDefaults.data(forKey: itemsKey) else { return [] }
        do {
            return try decoder.decode([PantryCatalogItemDefinition].self, from: data)
        } catch {
            AppLog.warn("[UserCatalogStore] Discarding unreadable user catalog items: \(error.localizedDescription)")
            userDefaults.removeObject(forKey: itemsKey)
            return []
        }
    }

    func saveUserItems(_ items: [PantryCatalogItemDefinition]) {
        guard !items.isEmpty else {
            userDefaults.removeObject(forKey: itemsKey)
            return
        }
        do {
            let data = try encoder.encode(items)
            userDefaults.set(data, forKey: itemsKey)
        } catch {
            AppLog.warn("[UserCatalogStore] Failed to persist user catalog items: \(error.localizedDescription)")
        }
    }

    func loadFacetExtensions() -> [String: [String: [String]]] {
        guard let data = userDefaults.data(forKey: facetExtensionsKey) else { return [:] }
        do {
            return try decoder.decode([String: [String: [String]]].self, from: data)
        } catch {
            AppLog.warn("[UserCatalogStore] Discarding unreadable facet extensions: \(error.localizedDescription)")
            userDefaults.removeObject(forKey: facetExtensionsKey)
            return [:]
        }
    }

    func saveFacetExtensions(_ extensions: [String: [String: [String]]]) {
        guard !extensions.isEmpty else {
            userDefaults.removeObject(forKey: facetExtensionsKey)
            return
        }
        do {
            let data = try encoder.encode(extensions)
            userDefaults.set(data, forKey: facetExtensionsKey)
        } catch {
            AppLog.warn("[UserCatalogStore] Failed to persist facet extensions: \(error.localizedDescription)")
        }
    }

    func loadAliasExtensions() -> [String: [String]] {
        guard let data = userDefaults.data(forKey: aliasExtensionsKey) else { return [:] }
        do {
            return try decoder.decode([String: [String]].self, from: data)
        } catch {
            AppLog.warn("[UserCatalogStore] Discarding unreadable alias extensions: \(error.localizedDescription)")
            userDefaults.removeObject(forKey: aliasExtensionsKey)
            return [:]
        }
    }

    func saveAliasExtensions(_ extensions: [String: [String]]) {
        guard !extensions.isEmpty else {
            userDefaults.removeObject(forKey: aliasExtensionsKey)
            return
        }
        do {
            let data = try encoder.encode(extensions)
            userDefaults.set(data, forKey: aliasExtensionsKey)
        } catch {
            AppLog.warn("[UserCatalogStore] Failed to persist alias extensions: \(error.localizedDescription)")
        }
    }

    func loadDefaultOverrides() -> [String: [String: String]] {
        guard let data = userDefaults.data(forKey: defaultOverridesKey) else { return [:] }
        do {
            return try decoder.decode([String: [String: String]].self, from: data)
        } catch {
            AppLog.warn("[UserCatalogStore] Discarding unreadable default overrides: \(error.localizedDescription)")
            userDefaults.removeObject(forKey: defaultOverridesKey)
            return [:]
        }
    }

    func saveDefaultOverrides(_ overrides: [String: [String: String]]) {
        guard !overrides.isEmpty else {
            userDefaults.removeObject(forKey: defaultOverridesKey)
            return
        }
        do {
            let data = try encoder.encode(overrides)
            userDefaults.set(data, forKey: defaultOverridesKey)
        } catch {
            AppLog.warn("[UserCatalogStore] Failed to persist default overrides: \(error.localizedDescription)")
        }
    }
}
