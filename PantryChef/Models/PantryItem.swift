import Foundation

struct PantryItem: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var category: FoodCategory
    var quantity: Double?
    var unit: MeasurementUnit?
    var expiryDate: Date?
    var dateAdded: Date
    var barcode: String?
    var notes: String?
    var imageURL: String?

    init(
        id: UUID = UUID(),
        name: String,
        category: FoodCategory = .other,
        quantity: Double? = nil,
        unit: MeasurementUnit? = nil,
        expiryDate: Date? = nil,
        dateAdded: Date = Date(),
        barcode: String? = nil,
        notes: String? = nil,
        imageURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.expiryDate = expiryDate
        self.dateAdded = dateAdded
        self.barcode = barcode
        self.notes = notes
        self.imageURL = imageURL
    }

    var expiryStatus: ExpiryStatus {
        guard let expiryDate else { return .fresh }
        let now = Date()
        if expiryDate < now {
            return .expired
        }
        let threeDaysFromNow = Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now
        if expiryDate <= threeDaysFromNow {
            return .expiringSoon
        }
        return .fresh
    }

    var daysUntilExpiry: Int? {
        guard let expiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiryDate).day
    }

    var displayQuantity: String {
        guard let quantity else { return "" }
        let unitStr = unit?.rawValue ?? ""
        if quantity == quantity.rounded() {
            return "\(Int(quantity)) \(unitStr)"
        }
        return String(format: "%.1f %@", quantity, unitStr)
    }

    // MARK: - Sample Data
    static let samples: [PantryItem] = [
        PantryItem(name: "Milk", category: .dairy, quantity: 1, unit: .liter,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 2, to: Date())),
        PantryItem(name: "Chicken Breast", category: .protein, quantity: 500, unit: .gram,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())),
        PantryItem(name: "Onions", category: .produce, quantity: 3, unit: .whole,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 14, to: Date())),
        PantryItem(name: "Garlic", category: .produce, quantity: 1, unit: .whole,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 21, to: Date())),
        PantryItem(name: "Olive Oil", category: .oils, quantity: 500, unit: .milliliter),
        PantryItem(name: "Salt", category: .spices, quantity: 1, unit: .package),
        PantryItem(name: "Black Pepper", category: .spices, quantity: 1, unit: .package),
        PantryItem(name: "Rice", category: .grains, quantity: 2, unit: .kilogram),
        PantryItem(name: "Eggs", category: .dairy, quantity: 6, unit: .piece,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 5, to: Date())),
        PantryItem(name: "Avocado", category: .produce, quantity: 2, unit: .whole,
                   expiryDate: Calendar.current.date(byAdding: .day, value: 2, to: Date())),
    ]
}
