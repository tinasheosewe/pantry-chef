import Foundation

enum PantryAddFrequencyTracker {
    private static let key = "pantry.item.add.frequency"

    static func recordAddition(catalogItemID: String) {
        var freq = frequencies()
        freq[catalogItemID, default: 0] += 1
        UserDefaults.standard.set(freq, forKey: key)
    }

    static func frequency(for catalogItemID: String) -> Int {
        frequencies()[catalogItemID] ?? 0
    }

    static func frequencies() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
    }
}
