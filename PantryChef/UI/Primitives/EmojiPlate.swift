import Foundation

/// Picks the emoji "face" for a dish or ingredient — name keywords first (most
/// specific wins), then the dominant catalog category. Deterministic presentation
/// mapping, co-located like a palette. The AI-rendered plate (spec §10 tier 1)
/// replaces this face per-dish when generation is wired; this is the instant,
/// free, offline tier underneath it.
enum EmojiPlate {

    static func face(for name: String, categories: [FoodCategory] = []) -> String {
        let lowered = name.lowercased()
        for (keyword, emoji) in keywordFaces where lowered.contains(keyword) {
            return emoji
        }
        if let category = categories.first, let emoji = categoryFaces[category] {
            return emoji
        }
        return "🍽️"
    }

    /// Ordered: more specific phrases before generic ones.
    private static let keywordFaces: [(String, String)] = [
        ("shakshuka", "🍳"), ("frittata", "🍳"), ("omelet", "🍳"), ("egg", "🥚"),
        ("ragù", "🍝"), ("ragu", "🍝"), ("orzo", "🍝"), ("pasta", "🍝"), ("noodle", "🍜"),
        ("spaghetti", "🍝"), ("lasagn", "🍝"), ("mac and cheese", "🧀"),
        ("salmon", "🍣"), ("fish", "🐟"), ("shrimp", "🍤"), ("prawn", "🍤"), ("tuna", "🐟"),
        ("stir-fry", "🥘"), ("stir fry", "🥘"), ("curry", "🍛"), ("stew", "🍲"),
        ("soup", "🍜"), ("broth", "🍜"), ("chili", "🌶️"),
        ("salad", "🥗"), ("greens", "🥬"), ("spinach", "🥬"), ("kale", "🥬"),
        ("taco", "🌮"), ("burrito", "🌯"), ("pizza", "🍕"), ("burger", "🍔"),
        ("sandwich", "🥪"), ("toast", "🍞"), ("flatbread", "🫓"), ("bread", "🍞"),
        ("pancake", "🥞"), ("waffle", "🧇"), ("cake", "🍰"), ("cookie", "🍪"),
        ("rice", "🍚"), ("risotto", "🍚"), ("bowl", "🥣"),
        ("chicken", "🍗"), ("lamb", "🥩"), ("beef", "🥩"), ("steak", "🥩"), ("pork", "🥓"),
        ("roast", "🍖"), ("skewer", "🍢"), ("kebab", "🍢"),
        ("yogurt", "🥛"), ("milk", "🥛"), ("cheese", "🧀"), ("feta", "🧀"), ("butter", "🧈"),
        ("avocado", "🥑"), ("tomato", "🍅"), ("potato", "🥔"), ("corn", "🌽"),
        ("mushroom", "🍄"), ("onion", "🧅"), ("garlic", "🧄"), ("carrot", "🥕"),
        ("pepper", "🫑"), ("broccoli", "🥦"), ("cucumber", "🥒"), ("beet", "🫜"),
        ("lemon", "🍋"), ("apple", "🍎"), ("pear", "🍐"), ("berry", "🫐"), ("banana", "🍌"),
        ("olive", "🫒"), ("oil", "🫒"), ("flour", "🌾"), ("oat", "🌾"), ("bean", "🫘"),
        ("smoothie", "🥤"), ("coffee", "☕"), ("tea", "🍵"), ("wine", "🍷"),
        ("girl dinner", "🧀"), ("crackers", "🧀"), ("dumpling", "🥟"), ("sushi", "🍣"),
        ("pie", "🥧"), ("quiche", "🥧"), ("wrap", "🌯")
    ]

    private static let categoryFaces: [FoodCategory: String] = [
        .produce: "🥬", .protein: "🥩", .dairy: "🧀", .grains: "🌾", .pasta: "🍝",
        .legumes: "🫘", .nuts: "🥜", .oils: "🫒", .spices: "🌶️", .condiments: "🫙",
        .canned: "🥫", .bakingSupplies: "🧁", .breads: "🍞", .frozenFoods: "🧊",
        .beverages: "☕", .alcohol: "🍷", .snacks: "🍿", .other: "🍽️"
    ]
}
