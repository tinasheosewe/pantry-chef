import Foundation

struct ShoppingItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var quantity: Double?
    var unit: MeasurementUnit?
    var category: FoodCategory
    var isChecked: Bool
    var recipeSource: String? // Which recipe needed this

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double? = nil,
        unit: MeasurementUnit? = nil,
        category: FoodCategory = .other,
        isChecked: Bool = false,
        recipeSource: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.isChecked = isChecked
        self.recipeSource = recipeSource
    }

    var displayText: String {
        var parts: [String] = []
        if let quantity {
            if quantity == quantity.rounded() {
                parts.append("\(Int(quantity))")
            } else {
                parts.append(String(format: "%.1f", quantity))
            }
        }
        if let unit {
            parts.append(unit.rawValue)
        }
        parts.append(name)
        return parts.joined(separator: " ")
    }

    static let samples: [ShoppingItem] = [
        ShoppingItem(name: "Bell Pepper", quantity: 2, unit: .whole, category: .produce),
        ShoppingItem(name: "Soy Sauce", quantity: 1, unit: .package, category: .condiments),
        ShoppingItem(name: "Bread", quantity: 1, unit: .package, category: .grains),
        ShoppingItem(name: "Butter", quantity: 250, unit: .gram, category: .dairy),
        ShoppingItem(name: "Tomatoes", quantity: 4, unit: .whole, category: .produce),
    ]
}
