import Foundation

/// A recipe handed from the share extension to the main app via the App Group. The
/// extension's job is to be *fast* — it just captures the shared URL or text and drops
/// it here, then the app does the (slow, network) AI import on its next launch and
/// clears the inbox. Keeping the AI work out of the memory-constrained extension is what
/// makes share-to-import reliable.
struct PendingRecipeImport: Codable, Equatable {
    enum Source: Codable, Equatable {
        case url(String)
        case text(String)
    }
    var source: Source
    var receivedAt: Date = Date()
}

/// The App Group-backed mailbox the extension writes to and the app drains.
enum SharedRecipeInbox {
    /// Must match the App Group entitlement on BOTH the app and the extension targets.
    static let appGroup = "group.com.tboya.pantrychef"
    private static let key = "pc.pendingRecipeImports"

    private static var store: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func add(_ item: PendingRecipeImport) {
        var items = all()
        items.append(item)
        write(items)
    }

    static func all() -> [PendingRecipeImport] {
        guard let data = store?.data(forKey: key),
              let items = try? JSONDecoder().decode([PendingRecipeImport].self, from: data) else { return [] }
        return items
    }

    /// Read and clear — the app calls this once on launch to drain pending imports.
    static func drain() -> [PendingRecipeImport] {
        let items = all()
        store?.removeObject(forKey: key)
        return items
    }

    static func clear() { store?.removeObject(forKey: key) }

    private static func write(_ items: [PendingRecipeImport]) {
        if let data = try? JSONEncoder().encode(items) { store?.set(data, forKey: key) }
    }
}
