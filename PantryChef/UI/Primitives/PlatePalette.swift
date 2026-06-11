import Foundation

/// Maps ingredient families to natural food tones for the procedural plate. This is
/// the tier-0 category→palette mapping (spec §10): greens for produce, rust for
/// protein, cream for dairy, gold for grains. Pure data, exhaustive over the
/// category taxonomy so a new category can't be silently forgotten.
enum PlatePalette {

    /// The warm off-white ceramic every plate sits on — the studio constant that
    /// lets visually different dishes coexist without clashing.
    static let ceramic = RGBA(r: 0.937, g: 0.909, b: 0.855)

    static func tone(for category: FoodCategory) -> RGBA {
        switch category {
        case .produce:        return RGBA(r: 0.306, g: 0.424, b: 0.259) // leaf green
        case .protein:        return RGBA(r: 0.631, g: 0.275, b: 0.173) // seared rust
        case .dairy:          return RGBA(r: 0.910, g: 0.875, b: 0.784) // cream
        case .grains:         return RGBA(r: 0.780, g: 0.659, b: 0.420) // golden grain
        case .pasta:          return RGBA(r: 0.878, g: 0.784, b: 0.588) // pale wheat
        case .legumes:        return RGBA(r: 0.541, g: 0.478, b: 0.290) // olive
        case .nuts:           return RGBA(r: 0.651, g: 0.475, b: 0.290) // toasted tan
        case .oils:           return RGBA(r: 0.788, g: 0.635, b: 0.290) // golden oil
        case .spices:         return RGBA(r: 0.604, g: 0.353, b: 0.165) // deep ochre
        case .condiments:     return RGBA(r: 0.690, g: 0.416, b: 0.188) // amber
        case .canned:         return RGBA(r: 0.612, g: 0.322, b: 0.251) // muted tomato
        case .bakingSupplies: return RGBA(r: 0.902, g: 0.780, b: 0.761) // sugar blush
        case .breads:         return RGBA(r: 0.757, g: 0.604, b: 0.357) // crust
        case .frozenFoods:    return RGBA(r: 0.784, g: 0.816, b: 0.808) // cool pale
        case .beverages:      return RGBA(r: 0.710, g: 0.506, b: 0.290) // steeped amber
        case .alcohol:        return RGBA(r: 0.494, g: 0.231, b: 0.322) // burgundy
        case .snacks:         return RGBA(r: 0.804, g: 0.651, b: 0.369) // warm gold
        case .other:          return RGBA(r: 0.690, g: 0.643, b: 0.557) // neutral warm
        }
    }
}
