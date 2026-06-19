import XCTest
@testable import PantryChef

/// The persisted snapshot must round-trip exactly — every nested value type (the
/// StockItem.Measure / DatedEvent.Kind enums with associated values especially) has to
/// survive encode→decode, or a user's saved kitchen comes back wrong.
@MainActor
final class PantryPersistenceTests: XCTestCase {

    private func roundTrip(_ snap: PantrySnapshot) throws -> PantrySnapshot {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(PantrySnapshot.self, from: enc.encode(snap))
    }

    func testSeedKitchenRoundTrips() throws {
        let store = KitchenStore()
        let snap = PantrySnapshot(
            stock: store.stock, shoppingList: store.shoppingList, events: store.events,
            journal: store.journal, whispers: store.whispers, profile: store.profile,
            autoAdjust: store.autoAdjustDaysOnStorageChange, assumeSpiceRack: store.assumeSpiceRack)
        let back = try roundTrip(snap)
        XCTAssertEqual(back.stock.count, snap.stock.count)
        XCTAssertEqual(back.shoppingList, snap.shoppingList)
        XCTAssertEqual(back.events.count, snap.events.count)
        XCTAssertEqual(back.assumeSpiceRack, snap.assumeSpiceRack)
        // The associated-value enums + identities specifically (dates round to the
        // second through iso8601, which is fine — we don't assert exact Date equality).
        XCTAssertEqual(back.stock.map(\.id), snap.stock.map(\.id))
        XCTAssertEqual(back.stock.map(\.measure), snap.stock.map(\.measure))
        XCTAssertEqual(back.stock.map(\.category), snap.stock.map(\.category))
        XCTAssertEqual(back.events.map(\.id), snap.events.map(\.id))
    }

    func testExpiryReminderSettingSurvivesAndOldFilesDefaultOn() throws {
        var snap = PantrySnapshot(stock: [], shoppingList: [], events: [], journal: [],
                                  whispers: [], profile: DietaryProfile(), autoAdjust: true,
                                  assumeSpiceRack: true, expiryReminders: false)
        XCTAssertFalse(try roundTrip(snap).expiryReminders, "the reminder setting round-trips")

        // A snapshot written before the field existed (key absent) must still load,
        // defaulting reminders on rather than failing the whole read.
        snap.expiryReminders = true
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        var json = try JSONSerialization.jsonObject(with: enc.encode(snap)) as! [String: Any]
        json.removeValue(forKey: "expiryReminders")
        let data = try JSONSerialization.data(withJSONObject: json)
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let back = try dec.decode(PantrySnapshot.self, from: data)
        XCTAssertTrue(back.expiryReminders, "a missing key falls back to the default, not a decode failure")
    }

    func testAllMeasureCasesRoundTrip() throws {
        let plate = PlateComposition(categories: [.produce], seed: 1)
        let items = [
            StockItem(key: "a", name: "A", plate: plate, section: .have,
                      measure: .perishable(detail: "300 g", daysLeft: 4.5)),
            StockItem(key: "b", name: "B", plate: plate, section: .staples, measure: .staple(.runningLow)),
            StockItem(key: "c", name: "C", plate: plate, section: .made, measure: .made(detail: "frozen", portions: 3)),
        ]
        let snap = PantrySnapshot(stock: items, shoppingList: [], events: [], journal: [],
                                  whispers: [], profile: DietaryProfile(), autoAdjust: true, assumeSpiceRack: true)
        XCTAssertEqual(try roundTrip(snap).stock.map(\.measure), items.map(\.measure))
    }
}
