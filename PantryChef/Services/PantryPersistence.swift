import Foundation

/// The user-owned state that must survive relaunch (the audit's #1 gap: today the
/// whole kitchen evaporates on quit). The seed *library* is reloaded from the bundle;
/// only what the user actually changed — their pantry, list, plans, journal, profile,
/// and settings — is snapshotted. This is the local foundation; CloudKit sync +
/// household sharing layer on top of the same Codable shape later.
struct PantrySnapshot: Codable {
    var version = 1
    var stock: [StockItem]
    var shoppingList: [ShoppingEntry]
    var events: [DatedEvent]
    var journal: [JournalItem]
    var whispers: [DatedWhisper]
    var profile: DietaryProfile
    var autoAdjust: Bool
    var assumeSpiceRack: Bool
    var expiryReminders: Bool = true
}

extension PantrySnapshot {
    private enum CodingKeys: String, CodingKey {
        case version, stock, shoppingList, events, journal, whispers
        case profile, autoAdjust, assumeSpiceRack, expiryReminders
    }

    /// Tolerant decode so a snapshot written before a field existed still loads
    /// (newer keys fall back to their defaults rather than failing the whole read).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        stock = try c.decode([StockItem].self, forKey: .stock)
        shoppingList = try c.decodeIfPresent([ShoppingEntry].self, forKey: .shoppingList) ?? []
        events = try c.decode([DatedEvent].self, forKey: .events)
        journal = try c.decode([JournalItem].self, forKey: .journal)
        whispers = try c.decode([DatedWhisper].self, forKey: .whispers)
        profile = try c.decode(DietaryProfile.self, forKey: .profile)
        autoAdjust = try c.decode(Bool.self, forKey: .autoAdjust)
        assumeSpiceRack = try c.decode(Bool.self, forKey: .assumeSpiceRack)
        expiryReminders = try c.decodeIfPresent(Bool.self, forKey: .expiryReminders) ?? true
    }
}

/// Reads/writes the snapshot as JSON in Application Support. Pure I/O, no app state.
enum PantryPersistence {
    private static let filename = "pantry-state.json"

    private static var url: URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true) else { return nil }
        return dir.appendingPathComponent(filename)
    }

    static func load() -> PantrySnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PantrySnapshot.self, from: data)
    }

    static func save(_ snapshot: PantrySnapshot) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        // Atomic so an interrupted write can't corrupt the file.
        try? data.write(to: url, options: .atomic)
    }

    /// Test/onboarding affordance: forget everything and fall back to a fresh seed.
    static func clear() {
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}
