import SwiftUI
import Observation

/// Tier-1 plate art (spec §10): each dish gets one AI-painted plate in the app's
/// single art direction, rendered once and cached on disk forever. The emoji plate
/// (tier 0) stays the instant face — shown until a render lands, and wherever
/// rendering is impossible (no key, offline, spend cap reached). *Which* names
/// deserve a render is policy owned by the store via `eligibility`; this type is
/// mechanism only and spends nothing until wired.
@MainActor
@Observable
final class PlateRenderLibrary {
    static let shared = PlateRenderLibrary()

    /// Policy seam: dishes render, raw stock items don't. Defaults to nobody so an
    /// unwired library can never spend.
    @ObservationIgnored var eligibility: (String) -> Bool = { _ in false }

    /// Finished renders by dish slug — views read through `render(for:)` and
    /// re-render when a plate lands.
    private(set) var renders: [String: UIImage] = [:]

    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var failed: Set<String> = []
    @ObservationIgnored private var startedThisLaunch = 0

    /// The cached render if one is in memory. Pure read — safe in a view body.
    func render(for name: String) -> UIImage? { renders[Self.slug(name)] }

    /// Ensure a render exists or is on its way: memory → disk → (one) paint call.
    func request(_ name: String) async {
        let key = Self.slug(name)
        guard !key.isEmpty, renders[key] == nil,
              !inFlight.contains(key), !failed.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        if let cached = Self.loadCached(key) {
            renders[key] = cached
            return
        }
        guard eligibility(name),
              !AppConfig.isMissing(AppConfig.openAIAPIKey),
              startedThisLaunch < KitchenConfig.Render.maxNewPerLaunch else { return }
        startedThisLaunch += 1
        do {
            let png = try await Self.paint(name)
            guard let image = Self.downscaled(png, to: KitchenConfig.Render.cachedPixelSize) else {
                failed.insert(key)
                return
            }
            Self.store(image, key: key)
            withAnimation(.easeInOut(duration: 0.5)) { renders[key] = image }
        } catch {
            failed.insert(key)
        }
    }

    // MARK: Art direction

    /// The single style every plate is painted in, so a growing library still
    /// reads as one printed book. Transparent ground makes the result a drop-in
    /// face for any theme.
    private nonisolated static func prompt(for name: String) -> String {
        """
        A single round white ceramic plate of \(name), hand-painted gouache \
        cookbook illustration: muted natural colours, fine deep-green ink \
        outlines, and a thin green double ring on the plate rim. Viewed from \
        directly above, perfectly centred, isolated on a fully transparent \
        background — nothing outside the circular plate, no text.
        """
    }

    // MARK: Painting

    private struct ImageResponse: Decodable {
        struct Item: Decodable { let b64_json: String }
        let data: [Item]
    }

    private nonisolated static func paint(_ name: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        request.httpMethod = "POST"
        request.timeoutInterval = KitchenConfig.Render.timeoutSeconds
        request.setValue("Bearer \(AppConfig.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": KitchenConfig.Render.model,
            "prompt": prompt(for: name),
            "size": "1024x1024",
            "quality": KitchenConfig.Render.quality,
            "background": "transparent",
            "output_format": "png"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let b64 = try JSONDecoder().decode(ImageResponse.self, from: data).data.first?.b64_json,
              let png = Data(base64Encoded: b64) else {
            throw URLError(.cannotDecodeContentData)
        }
        return png
    }

    // MARK: Cache

    nonisolated static func slug(_ name: String) -> String {
        name.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .joined(separator: "-")
    }

    private nonisolated static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PlateRenders", isDirectory: true)
    }

    private nonisolated static func cacheURL(_ key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).png")
    }

    private nonisolated static func loadCached(_ key: String) -> UIImage? {
        guard let data = try? Data(contentsOf: cacheURL(key)) else { return nil }
        return UIImage(data: data)
    }

    private nonisolated static func store(_ image: UIImage, key: String) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? image.pngData()?.write(to: cacheURL(key))
    }

    /// Renders arrive at 1024 px but display at ~100 pt; downscaling before caching
    /// keeps a whole library of plates cheap on disk and in memory.
    private nonisolated static func downscaled(_ data: Data, to maxSide: CGFloat) -> UIImage? {
        guard let source = UIImage(data: data) else { return nil }
        let longest = max(source.size.width, source.size.height)
        guard longest > maxSide else { return source }
        let scale = maxSide / longest
        let target = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
