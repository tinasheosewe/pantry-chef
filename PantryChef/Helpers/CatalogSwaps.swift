import Foundation

/// Substitution candidates for a catalog ingredient, in confidence order:
///
///   1. **curated** — the catalog's hand-picked `swaps` (highest confidence).
///   2. **sibling** — varieties sharing an immediate parent (another short pasta,
///      another spinach), excluding the identity lineage (those already *are* the
///      ingredient, so they're not "swaps"). Stays tight because the catalog only
///      parents true varieties — distinct ingredients are left orphaned.
///   3. **family** — items sharing the same trailing base word (almond milk ↔ milk,
///      the `*-sauce` family). The broad, noisier net.
///
/// Readiness counts only the confident tiers (curated + sibling) so "ready · N swaps"
/// stays trustworthy; the recipe chooser asks for all three so the cook can reach for
/// a family swap deliberately.
enum CatalogSwaps {
    enum Tier: Int, Comparable, Sendable {
        case curated = 0, sibling = 1, family = 2
        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    struct Candidate: Equatable, Sendable {
        let id: String
        let name: String
        let key: String
        let notes: String?
        let tier: Tier
    }

    /// Cap on family candidates, so a broad base word ("oil", "sauce") doesn't flood.
    private static let familyLimit = 6

    /// Ranked substitutes for an ingredient. `includeFamily` adds the broad same-base
    /// tier (off for readiness, on for the chooser).
    static func candidates(forItemID id: String, includeFamily: Bool = true) -> [Candidate] {
        guard let item = PantryCatalog.itemsByID[id] else { return [] }
        var seen: Set<String> = [id]
        var out: [Candidate] = []

        func add(_ subID: String, notes: String?, tier: Tier) {
            guard subID != id, seen.insert(subID).inserted,
                  let sub = PantryCatalog.itemsByID[subID] else { return }
            out.append(Candidate(id: subID, name: sub.name,
                                 key: IngredientLexicon.lookupKey(sub.name), notes: notes, tier: tier))
        }

        // 1) curated
        for s in item.swaps { add(s.substituteItemID, notes: s.notes, tier: .curated) }

        // Identity lineage already satisfies the requirement — never a "swap".
        let lineage = PantryCatalog.ancestors(of: id).union(PantryCatalog.descendants(of: id))

        // 2) siblings — other children of this item's immediate parents
        for parent in item.parentIds {
            for child in PantryCatalog.children(of: parent).sorted() where !lineage.contains(child) {
                add(child, notes: "similar", tier: .sibling)
            }
        }

        // 3) family — items sharing the trailing base word
        if includeFamily {
            var added = 0
            for famID in familyIndex[familyKey(of: item.name)] ?? [] where !lineage.contains(famID) {
                let before = out.count
                add(famID, notes: "similar", tier: .family)
                if out.count > before { added += 1; if added >= familyLimit { break } }
            }
        }
        return out
    }

    /// The trailing noun of a name — "almond milk" → "milk", "spinach" → "spinach".
    static func familyKey(of name: String) -> String {
        name.lowercased().split(whereSeparator: { $0 == " " }).map(String.init).last ?? name.lowercased()
    }

    /// Item ids grouped by the trailing base word of their name, built once.
    private static let familyIndex: [String: [String]] = {
        var idx: [String: [String]] = [:]
        for item in PantryCatalog.itemsByID.values {
            idx[familyKey(of: item.name), default: []].append(item.id)
        }
        for key in idx.keys { idx[key]?.sort() }
        return idx
    }()
}
