import Foundation

/// Converts volume measures to mass using the catalog's density enrichment
/// (`gramsPerCup`) — so "1 cup flour" can read "≈ 120 g" (spec §"what to add").
/// Pure; reuses the intake parser's quantity/unit vocabularies, no regex.
enum UnitConversion {

    /// Grams for a quantity in a volume unit, given the ingredient's density.
    static func grams(qty: Double, unit: MeasurementUnit, item: PantryCatalogItemDefinition) -> Double? {
        guard let perCup = item.gramsPerCup else { return nil }
        switch unit {
        case .cup: return qty * perCup
        case .tablespoon: return qty * perCup / 16   // 16 tbsp per cup
        case .teaspoon: return qty * perCup / 48      // 48 tsp per cup
        default: return nil                            // already mass, or not volumetric
        }
    }

    /// A "≈ N g" hint for a recipe line, when it's a volume measure of a
    /// density-known ingredient. Nil otherwise (no false precision).
    static func gramHint(for line: RecipeLine) -> String? {
        guard let amount = line.amount,
              let (qty, unit) = parseAmount(amount),
              let item = PantryCatalog.resolveExact(name: line.key),
              let grams = grams(qty: qty, unit: unit, item: item) else { return nil }
        return "≈ \(Int(grams.rounded())) g"
    }

    /// Splits "1 cup" / "2 tbsp" into quantity + unit, reusing the parser's lexicons.
    static func parseAmount(_ amount: String) -> (Double, MeasurementUnit)? {
        let tokens = amount.split(separator: " ").map { String($0).lowercased() }
        guard let first = tokens.first, let qty = IntakeParser.quantity(first) else { return nil }
        guard let unitToken = tokens.dropFirst().first,
              let unit = MeasurementUnit.parse(unitToken) ?? IntakeParser.containerUnits[unitToken] else { return nil }
        return (qty, unit)
    }
}
