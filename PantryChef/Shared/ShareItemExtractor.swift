import Foundation
import UniformTypeIdentifiers

/// Pulls a recipe candidate out of what the OS share sheet handed us — a URL (a recipe
/// link from Safari / Instagram) preferred, else plain text (a pasted recipe). Pure and
/// dependency-free so it's unit-testable with synthetic `NSExtensionItem`s, no share
/// sheet required.
enum ShareItemExtractor {

    static func extract(from items: [NSExtensionItem]) async -> PendingRecipeImport? {
        let providers = items.flatMap { $0.attachments ?? [] }

        // A URL is the strong signal — import the page where the recipe lives.
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            if let url = await loadURL(provider) {
                return PendingRecipeImport(source: .url(url.absoluteString))
            }
        }
        // Otherwise a shared text blob (some apps share a URL only as text, too).
        for provider in providers where provider.canLoadObject(ofClass: String.self) {
            if let text = await loadText(provider) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // A bare link shared as text → treat it as a URL import.
                if let url = soleURL(in: trimmed) { return PendingRecipeImport(source: .url(url)) }
                if !trimmed.isEmpty { return PendingRecipeImport(source: .text(trimmed)) }
            }
        }
        return nil
    }

    /// A single http(s) URL on its own (shared as text) — else nil.
    static func soleURL(in text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(where: \.isWhitespace),
              t.hasPrefix("http://") || t.hasPrefix("https://"),
              URL(string: t) != nil else { return nil }
        return t
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                cont.resume(returning: object)
            }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: String.self) { object, _ in
                cont.resume(returning: object)
            }
        }
    }
}
