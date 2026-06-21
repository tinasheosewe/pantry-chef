import Foundation

/// Resolve a scanned barcode to a product name via Open Food Facts — a free, open,
/// keyless food database. Deterministic (a lookup, not AI), so barcode pantry intake
/// stays a free-tier feature. The returned name then resolves through the same
/// `IntakePipeline` as everything else, so a scan lands as a first-class pantry item.
enum ProductLookup {
    struct Product: Equatable { let name: String }

    static func lookup(barcode: String) async -> Product? {
        let code = barcode.filter(\.isNumber)
        guard code.count >= 6,
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,product_name_en,generic_name,brands")
        else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        // Open Food Facts asks API clients to identify themselves.
        request.setValue("PantryChef/1.0 (iOS; pantry intake)", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int) == 1,
              let product = json["product"] as? [String: Any] else { return nil }

        // Prefer the plain product name; fall back to the English or generic name.
        let name = ["product_name", "product_name_en", "generic_name"]
            .compactMap { (product[$0] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let name, !name.isEmpty else { return nil }
        return Product(name: name)
    }
}
