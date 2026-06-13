import SwiftUI
import Observation
import os

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
    /// unwired library can never spend. Plates can be requested before the store
    /// wires this (first launch races the view tree), so arrival re-sweeps.
    @ObservationIgnored var eligibility: (String) -> Bool = { _ in false } {
        didSet { sweep() }
    }

    /// Finished renders by dish slug — views read through `render(for:)` and
    /// re-render when a plate lands.
    private(set) var renders: [String: UIImage] = [:]

    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var failed: Set<String> = []
    @ObservationIgnored private var seen: [String: String] = [:]   // slug → display name
    @ObservationIgnored private var startedThisLaunch = 0

    private static let log = Logger(subsystem: "PantryChef", category: "PlateRender")

    /// The cached render if one is in memory. Pure read — safe in a view body.
    func render(for name: String) -> UIImage? { renders[Self.slug(name)] }

    /// Re-attempt every requested-but-unpainted plate. Called when the policy
    /// arrives and when the app foregrounds (the network may be back); failures
    /// are forgiven so nothing stays stuck until relaunch.
    func sweep() {
        failed.removeAll()
        for (key, name) in seen where renders[key] == nil && !inFlight.contains(key) {
            request(name)
        }
    }

    /// Ensure a render exists or is on its way: memory → disk → (one) paint call.
    /// The paint runs in the library's own unstructured task: a plate request must
    /// outlive the view that made it, or scrolling cancels paints mid-flight.
    func request(_ name: String) {
        let key = Self.slug(name)
        guard !key.isEmpty, renders[key] == nil,
              !inFlight.contains(key), !failed.contains(key) else { return }
        seen[key] = name
        inFlight.insert(key)
        Task { await self.fulfil(key: key, name: name) }
    }

    private func fulfil(key: String, name: String) async {
        defer { inFlight.remove(key) }

        if let cached = Self.loadCached(key) {
            renders[key] = cached
            return
        }
        // Seed dishes ship with their art in the bundle — instant and offline,
        // like a cookbook's printed plates. Only new dishes go to the painter.
        if let bundled = Self.loadBundled(key) {
            renders[key] = bundled
            return
        }
        guard eligibility(name) else {
            Self.log.debug("\(key): not eligible (policy not wired yet, or not a dish)")
            return
        }
        guard !AppConfig.isMissing(AppConfig.openAIAPIKey) else {
            Self.log.info("\(key): no OpenAI key in this build — emoji it is")
            return
        }
        guard startedThisLaunch < KitchenConfig.Render.maxNewPerLaunch else {
            Self.log.info("\(key): per-launch render cap reached")
            return
        }
        startedThisLaunch += 1
        Self.log.info("\(key): painting…")
        do {
            let png = try await Self.paint(name)
            guard let image = Self.downscaled(png, to: KitchenConfig.Render.cachedPixelSize) else {
                Self.log.error("\(key): paint returned undecodable image data")
                failed.insert(key)
                return
            }
            Self.store(image, key: key)
            Self.log.info("\(key): painted and cached")
            withAnimation(.easeInOut(duration: 0.5)) { renders[key] = image }
        } catch {
            Self.log.error("\(key): paint failed — \(error.localizedDescription)")
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
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw NSError(domain: "PlateRender", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
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
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .joined(separator: "-")
    }

    private nonisolated static func loadBundled(_ key: String) -> UIImage? {
        let url = Bundle.main.url(forResource: key, withExtension: "png")
            ?? Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "PlateArt")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
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
