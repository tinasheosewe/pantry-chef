import Foundation

/// What the household avoids — the one-time profile that filters and flags across
/// the app (spec §"what to add"). Allergen-based for now; dietary tags can join.
struct DietaryProfile: Equatable, Sendable {
    var avoided: Set<Allergen> = []

    var isEmpty: Bool { avoided.isEmpty }
}
