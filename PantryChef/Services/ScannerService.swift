import AVFoundation
import UIKit
import Vision

final class BarcodeScannerService: NSObject, ObservableObject {
    @Published var scannedBarcode: String?
    @Published var isScanning = false

    // MARK: - Barcode Lookup (Open Food Facts API - free)

    func lookupBarcode(_ barcode: String) async -> BarcodeLookupResult? {
        let urlString = "https://world.openfoodfacts.org/api/v0/product/\(barcode).json"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? Int, status == 1,
                  let product = json["product"] as? [String: Any] else {
                return nil
            }

            let productName = (product["product_name"] as? String) ?? "Unknown Product"
            let brand = product["brands"] as? String
            let imageURL = product["image_url"] as? String

            // Infer category from Open Food Facts categories
            let categories = (product["categories"] as? String)?.lowercased() ?? ""
            let category = inferCategory(from: categories)

            return BarcodeLookupResult(
                barcode: barcode,
                productName: productName,
                brand: brand,
                category: category,
                imageURL: imageURL
            )
        } catch {
            print("Barcode lookup error: \(error.localizedDescription)")
            return nil
        }
    }

    private func inferCategory(from categories: String) -> FoodCategory {
        if categories.contains("dairy") || categories.contains("milk") || categories.contains("cheese") || categories.contains("yogurt") {
            return .dairy
        } else if categories.contains("meat") || categories.contains("chicken") || categories.contains("fish") || categories.contains("protein") {
            return .protein
        } else if categories.contains("fruit") || categories.contains("vegetable") || categories.contains("produce") {
            return .produce
        } else if categories.contains("grain") || categories.contains("cereal") || categories.contains("bread") || categories.contains("rice") {
            return .grains
        } else if categories.contains("spice") || categories.contains("herb") || categories.contains("seasoning") {
            return .spices
        } else if categories.contains("sauce") || categories.contains("condiment") || categories.contains("ketchup") || categories.contains("mustard") {
            return .condiments
        } else if categories.contains("oil") || categories.contains("butter") || categories.contains("margarine") {
            return .oils
        } else if categories.contains("frozen") {
            return .frozenFoods
        } else if categories.contains("canned") || categories.contains("preserved") {
            return .canned
        } else if categories.contains("beverage") || categories.contains("drink") || categories.contains("juice") {
            return .beverages
        } else if categories.contains("snack") || categories.contains("chip") || categories.contains("cracker") {
            return .snacks
        } else if categories.contains("pasta") || categories.contains("noodle") {
            return .pasta
        } else if categories.contains("nut") || categories.contains("seed") {
            return .nuts
        } else if categories.contains("baking") || categories.contains("flour") || categories.contains("sugar") {
            return .bakingSupplies
        }
        return .other
    }
}

// MARK: - Receipt Scanner (Vision OCR)

final class ReceiptScannerService: ObservableObject {
    @Published var isProcessing = false
    @Published var extractedItems: [String] = []

    func scanReceipt(image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let texts = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                // Filter for likely grocery items (heuristic: skip prices, totals, dates)
                let groceryItems = texts.filter { text in
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    // Skip lines that are just numbers (prices)
                    if Double(trimmed.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ".")) != nil {
                        return false
                    }
                    // Skip common receipt keywords
                    let skipWords = ["total", "subtotal", "tax", "change", "cash", "card", "visa",
                                     "mastercard", "receipt", "thank", "date", "time", "store"]
                    let lowered = trimmed.lowercased()
                    for word in skipWords {
                        if lowered.contains(word) { return false }
                    }
                    // Skip very short or very long lines
                    if trimmed.count < 3 || trimmed.count > 50 { return false }
                    return true
                }

                continuation.resume(returning: groceryItems)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}

// MARK: - Recipe Photo Scanner (Vision OCR)

final class RecipePhotoScannerService: ObservableObject {
    @Published var isProcessing = false

    func extractText(from image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let fullText = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                continuation.resume(returning: fullText.isEmpty ? nil : fullText)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
