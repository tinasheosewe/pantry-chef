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

    /// The face for a single pantry / recipe ingredient: its specific emoji where
    /// one exists, else the emoji for its catalog category (spec: "specific emoji
    /// per ingredient where one exists, else per-category fallback").
    static func icon(for ingredient: String, category: FoodCategory?) -> String {
        face(for: ingredient, categories: category.map { [$0] } ?? [])
    }

    /// Ordered: more specific phrases before generic ones, because matching is a
    /// substring scan — the FIRST keyword the name contains wins. So collisions are
    /// resolved by placement: "eggplant" before "egg", "goat" before "oat",
    /// "sweet potato" before "potato", "popcorn"/"corned beef" before "corn",
    /// "butternut" before "butter". Covers dish names *and* bare ingredient names
    /// (pantry tiles, recipe lines), so a specific food almost always gets a
    /// specific face; the category fallback is the safety net under it.
    private static let keywordFaces: [(String, String)] = [
        // — composed dishes (name-level) —
        ("shakshuka", "🍳"), ("frittata", "🍳"), ("omelet", "🍳"), ("scrambled", "🍳"),
        ("ragù", "🍝"), ("ragu", "🍝"), ("bolognese", "🍝"), ("carbonara", "🍝"),
        ("lasagn", "🍝"), ("spaghetti", "🍝"), ("orzo", "🍝"), ("gnocchi", "🍝"),
        ("ramen", "🍜"), ("pho", "🍜"), ("udon", "🍜"), ("noodle", "🍜"),
        ("stir-fry", "🥘"), ("stir fry", "🥘"), ("paella", "🥘"), ("tagine", "🥘"),
        ("curry", "🍛"), ("dal", "🍛"), ("daal", "🍛"), ("biryani", "🍛"),
        ("risotto", "🍚"), ("fried rice", "🍚"), ("pilaf", "🍚"), ("jambalaya", "🍚"),
        ("stew", "🍲"), ("soup", "🍲"), ("chowder", "🍲"), ("minestrone", "🍲"),
        ("chili con", "🌶️"), ("shakshouka", "🍳"),
        ("taco", "🌮"), ("burrito", "🌯"), ("quesadilla", "🫓"), ("enchilada", "🌯"),
        ("nachos", "🧀"), ("fajita", "🌯"), ("pizza", "🍕"), ("calzone", "🍕"),
        ("burger", "🍔"), ("sandwich", "🥪"), ("panini", "🥪"), ("sub ", "🥪"),
        ("wrap", "🌯"), ("gyro", "🥙"), ("shawarma", "🥙"), ("falafel", "🧆"),
        ("dumpling", "🥟"), ("gyoza", "🥟"), ("potsticker", "🥟"), ("wonton", "🥟"),
        ("sushi", "🍣"), ("poke", "🍣"), ("ceviche", "🍤"),
        ("pancake", "🥞"), ("waffle", "🧇"), ("french toast", "🍞"), ("crepe", "🥞"),
        ("muffin", "🧁"), ("scone", "🧁"), ("cupcake", "🧁"),
        ("brownie", "🍫"), ("cookie", "🍪"), ("biscuit", "🍪"),
        ("cheesecake", "🍰"), ("cake", "🍰"), ("pie", "🥧"), ("quiche", "🥧"),
        ("tart", "🥧"), ("cobbler", "🥧"), ("crumble", "🥧"), ("pudding", "🍮"),
        ("parfait", "🍨"), ("smoothie bowl", "🥣"), ("oatmeal", "🥣"), ("porridge", "🥣"),
        ("granola", "🥣"), ("cereal", "🥣"), ("salad", "🥗"), ("slaw", "🥗"),
        ("skewer", "🍢"), ("kebab", "🍢"), ("kabob", "🍢"), ("meatball", "🍖"),
        ("girl dinner", "🧀"), ("charcuterie", "🧀"),
        // — proteins —
        ("salmon", "🍣"), ("tuna", "🐟"), ("cod", "🐟"), ("tilapia", "🐟"),
        ("mackerel", "🐟"), ("sardine", "🐟"), ("anchovy", "🐟"), ("trout", "🐟"),
        ("haddock", "🐟"), ("halibut", "🐟"), ("catfish", "🐟"), ("fish", "🐟"),
        ("shrimp", "🦐"), ("prawn", "🦐"), ("crab", "🦀"), ("lobster", "🦞"),
        ("oyster", "🦪"), ("clam", "🦪"), ("mussel", "🦪"), ("scallop", "🦪"),
        ("squid", "🦑"), ("calamari", "🦑"), ("octopus", "🐙"),
        ("bacon", "🥓"), ("sausage", "🌭"), ("hot dog", "🌭"), ("pepperoni", "🍕"),
        ("salami", "🥓"), ("prosciutto", "🥓"), ("chorizo", "🌭"), ("ham", "🍖"),
        ("corned beef", "🥩"), ("ground beef", "🥩"), ("steak", "🥩"), ("brisket", "🥩"),
        ("beef", "🥩"), ("lamb", "🍖"), ("mutton", "🍖"), ("goat", "🍖"),
        ("pork", "🥩"), ("chicken", "🍗"), ("turkey", "🦃"), ("duck", "🦆"),
        ("tofu", "⬜"), ("tempeh", "🟫"), ("seitan", "🟫"), ("egg", "🥚"),
        // — vegetables & produce —
        ("eggplant", "🍆"), ("aubergine", "🍆"), ("zucchini", "🥒"), ("courgette", "🥒"),
        ("cucumber", "🥒"), ("butternut", "🎃"), ("pumpkin", "🎃"), ("squash", "🎃"),
        ("sweet potato", "🍠"), ("yam", "🍠"), ("potato", "🥔"),
        ("popcorn", "🍿"), ("corned beef", "🥩"), ("corn", "🌽"),
        ("spinach", "🥬"), ("kale", "🥬"), ("lettuce", "🥬"), ("cabbage", "🥬"),
        ("chard", "🥬"), ("arugula", "🥬"), ("bok choy", "🥬"), ("greens", "🥬"),
        ("broccoli", "🥦"), ("cauliflower", "🥦"), ("brussels", "🥦"),
        ("carrot", "🥕"), ("beet", "🫜"), ("radish", "🫜"), ("turnip", "🫜"),
        ("bell pepper", "🫑"), ("jalapeño", "🌶️"), ("jalapeno", "🌶️"),
        ("chili pepper", "🌶️"), ("chilli", "🌶️"), ("chili", "🌶️"), ("cayenne", "🌶️"),
        ("peppercorn", "🧂"), ("black pepper", "🧂"), ("pepper", "🫑"),
        ("mushroom", "🍄"), ("onion", "🧅"), ("shallot", "🧅"), ("leek", "🧅"),
        ("scallion", "🧅"), ("garlic", "🧄"), ("ginger", "🫚"),
        ("tomato", "🍅"), ("avocado", "🥑"), ("asparagus", "🌿"),
        ("green bean", "🫛"), ("snap pea", "🫛"), ("snow pea", "🫛"), ("edamame", "🫛"),
        ("pea", "🫛"), ("olive", "🫒"),
        // — fruit —
        ("strawberr", "🍓"), ("blueberr", "🫐"), ("raspberr", "🫐"), ("blackberr", "🫐"),
        ("cranberr", "🫐"), ("berry", "🫐"), ("grape", "🍇"), ("cherry", "🍒"),
        ("peach", "🍑"), ("nectarine", "🍑"), ("apricot", "🍑"), ("plum", "🍑"),
        ("mango", "🥭"), ("pineapple", "🍍"), ("coconut", "🥥"), ("kiwi", "🥝"),
        ("watermelon", "🍉"), ("melon", "🍈"), ("cantaloupe", "🍈"),
        ("orange", "🍊"), ("tangerine", "🍊"), ("clementine", "🍊"), ("mandarin", "🍊"),
        ("grapefruit", "🍊"), ("lemon", "🍋"), ("lime", "🍋"),
        ("apple", "🍎"), ("pear", "🍐"), ("banana", "🍌"), ("plantain", "🍌"),
        ("pomegranate", "🍎"), ("fig", "🍇"), ("date", "🫐"), ("raisin", "🍇"),
        // — dairy & eggs —
        ("yogurt", "🥛"), ("yoghurt", "🥛"), ("buttermilk", "🥛"), ("cream", "🥛"),
        ("milk", "🥛"), ("mozzarella", "🧀"), ("parmesan", "🧀"), ("cheddar", "🧀"),
        ("feta", "🧀"), ("ricotta", "🧀"), ("brie", "🧀"), ("cheese", "🧀"),
        ("butternut", "🎃"), ("butter", "🧈"),
        // — pantry, grains, nuts, condiments —
        ("rice", "🍚"), ("quinoa", "🌾"), ("couscous", "🌾"), ("bulgur", "🌾"),
        ("barley", "🌾"), ("polenta", "🌽"), ("cornmeal", "🌽"), ("oat", "🌾"),
        ("flour", "🌾"), ("wheat", "🌾"), ("pasta", "🍝"), ("macaroni", "🍝"),
        ("bagel", "🥯"), ("croissant", "🥐"), ("baguette", "🥖"), ("pretzel", "🥨"),
        ("tortilla", "🫓"), ("naan", "🫓"), ("pita", "🫓"), ("flatbread", "🫓"),
        ("crackers", "🍘"), ("toast", "🍞"), ("bread", "🍞"),
        ("peanut butter", "🥜"), ("peanut", "🥜"), ("almond", "🌰"), ("walnut", "🌰"),
        ("cashew", "🌰"), ("pecan", "🌰"), ("pistachio", "🥜"), ("hazelnut", "🌰"),
        ("chestnut", "🌰"), ("sesame", "🌰"), ("sunflower seed", "🌻"), ("chia", "🌱"),
        ("chickpea", "🫘"), ("lentil", "🫘"), ("black bean", "🫘"), ("kidney bean", "🫘"),
        ("bean", "🫘"), ("miso", "🥣"), ("hummus", "🧆"), ("tahini", "🥣"),
        ("honey", "🍯"), ("maple", "🍯"), ("jam", "🍓"), ("jelly", "🍓"),
        ("ketchup", "🍅"), ("mustard", "🌭"), ("mayo", "🥚"), ("soy sauce", "🫙"),
        ("vinegar", "🫙"), ("salsa", "🍅"), ("pesto", "🌿"), ("sriracha", "🌶️"),
        ("hot sauce", "🌶️"), ("oil", "🫒"), ("salt", "🧂"), ("sugar", "🧂"),
        ("chocolate", "🍫"), ("cocoa", "🍫"), ("ice cream", "🍨"), ("candy", "🍬"),
        ("vanilla", "🌼"),
        // — herbs & spices —
        ("basil", "🌿"), ("parsley", "🌿"), ("cilantro", "🌿"), ("coriander", "🌿"),
        ("mint", "🌿"), ("rosemary", "🌿"), ("thyme", "🌿"), ("oregano", "🌿"),
        ("dill", "🌿"), ("sage", "🌿"), ("bay leaf", "🍃"),
        ("cinnamon", "🟤"), ("cumin", "🟤"), ("paprika", "🌶️"), ("turmeric", "🟡"),
        ("nutmeg", "🟤"), ("clove", "🟤"), ("cardamom", "🟤"), ("curry powder", "🍛"),
        // — drinks —
        ("smoothie", "🥤"), ("juice", "🧃"), ("soda", "🥤"), ("coffee", "☕"),
        ("espresso", "☕"), ("latte", "☕"), ("tea", "🍵"), ("matcha", "🍵"),
        ("beer", "🍺"), ("wine", "🍷"), ("cocktail", "🍸"), ("water", "💧"),
        ("bowl", "🥣")
    ]

    /// The emoji standing in for a whole FoodCategory — the pantry's category tiles
    /// and the per-ingredient fallback both read from here.
    static func categoryFace(_ category: FoodCategory) -> String {
        categoryFaces[category] ?? "🍽️"
    }

    private static let categoryFaces: [FoodCategory: String] = [
        .produce: "🥬", .protein: "🥩", .dairy: "🧀", .grains: "🌾", .pasta: "🍝",
        .legumes: "🫘", .nuts: "🥜", .oils: "🫒", .spices: "🌶️", .condiments: "🫙",
        .canned: "🥫", .bakingSupplies: "🧁", .breads: "🍞", .frozenFoods: "🧊",
        .beverages: "☕", .alcohol: "🍷", .snacks: "🍿", .other: "🍽️"
    ]
}
