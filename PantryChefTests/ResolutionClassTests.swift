import XCTest
@testable import PantryChef

/// Data-driven invariants for ingredient tracking-class derivation. Like the
/// catalog invariant suite, these compute over the *entire* loaded catalog so a
/// bad row is caught wherever it appears, and each test fails once with the full
/// list of violations.
final class ResolutionClassTests: XCTestCase {

    private var items: [PantryCatalogItemDefinition] { PantryCatalog.allItems }

    private func report(_ violations: [String], _ label: String, cap: Int = 40) {
        guard !violations.isEmpty else { return }
        let shown = violations.prefix(cap).joined(separator: "\n  ")
        let more = violations.count > cap ? "\n  …and \(violations.count - cap) more" : ""
        XCTFail("\(label): \(violations.count) violation(s)\n  \(shown)\(more)")
    }

    /// Every item classifies into one of the known classes without trapping.
    func testEveryItemClassifies() {
        let valid = Set(ResolutionClass.allCases)
        var violations: [String] = []
        for item in items where !valid.contains(item.resolutionClass) {
            violations.append("'\(item.name)' (\(item.id)) produced an unknown class")
        }
        report(violations, "Item failed to classify")
    }

    /// The classifier's defining rule: a long representative shelf life always
    /// means staple. Guards against a future change silently breaking the contract.
    func testLongShelfLifeImpliesStaple() {
        var violations: [String] = []
        for item in items {
            guard let days = ResolutionClassifier.representativeShelfLifeDays(item),
                  days >= KitchenConfig.Resolution.stapleMinShelfLifeDays else { continue }
            if item.resolutionClass != .staple {
                violations.append("'\(item.name)' (\(days)d) classified \(item.resolutionClass) — expected staple")
            }
        }
        report(violations, "Long-life item not a staple")
    }

    /// The converse contract: a staple is only ever justified by a long shelf life,
    /// or — absent any freshness data — a shelf-stable category. Catches an oil or
    /// spice that picked up an absurdly short shelf life in the data.
    func testStapleImpliesLongLifeOrStableCategory() {
        var violations: [String] = []
        for item in items where item.resolutionClass == .staple {
            let longLife = (ResolutionClassifier.representativeShelfLifeDays(item) ?? 0)
                >= KitchenConfig.Resolution.stapleMinShelfLifeDays
            let stableFallback = item.freshnessByStorage.isEmpty && item.category.isTypicallyShelfStable
            if !longLife && !stableFallback {
                violations.append("'\(item.name)' is a staple but neither long-lived nor a stable-category fallback")
            }
        }
        report(violations, "Unjustified staple")
    }

    /// All three classes are populated. A catalog-wide regression (e.g. freshness
    /// data wiped, collapsing everything into one class) trips this immediately.
    func testEachClassIsPopulated() {
        let counts = Dictionary(grouping: items, by: \.resolutionClass).mapValues(\.count)
        for klass in ResolutionClass.allCases {
            XCTAssertGreaterThan(counts[klass] ?? 0, 20,
                "Suspiciously few \(klass) items (\(counts[klass] ?? 0)) — possible data regression")
        }
    }

    // MARK: - Human-meaningful spot checks (guarded against catalog renames)

    private func resolveAny(_ candidates: [String]) -> PantryCatalogItemDefinition? {
        for name in candidates {
            if let item = PantryCatalog.resolveExact(name: name) { return item }
        }
        return nil
    }

    func testOliveOilIsAStaple() throws {
        guard let oil = resolveAny(["Olive oil", "Extra virgin olive oil", "Olive Oil"]) else {
            throw XCTSkip("No olive-oil item in catalog")
        }
        XCTAssertEqual(oil.resolutionClass, .staple)
    }

    func testFreshLeafyGreenIsPerishable() throws {
        guard let greens = resolveAny(["Baby spinach", "Spinach", "Arugula", "Romaine lettuce"]) else {
            throw XCTSkip("No leafy-green item in catalog")
        }
        XCTAssertEqual(greens.resolutionClass, .perishable)
    }

    func testEggsAreSemiCountable() throws {
        guard let egg = resolveAny(["Egg", "Eggs", "Large egg", "Chicken egg"]) else {
            throw XCTSkip("No egg item in catalog")
        }
        // Eggs are counted in pieces and don't last long enough to be a staple.
        XCTAssertEqual(egg.resolutionClass, .semiCountable)
    }
}
