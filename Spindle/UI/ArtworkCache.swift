import AppKit
import SwiftUI

/// Show artwork by URL, kept in memory. Each URL is fetched at most once.
@MainActor
final class ArtworkCache: ObservableObject {
    private let session: URLSession
    private var images: [URL: NSImage] = [:]
    private var requested: Set<URL> = []

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// The cached image, or nil while it loads (or when it can't be loaded). Publishes when it arrives.
    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        if let image = images[url] { return image }
        if requested.insert(url).inserted {
            Task { await load(url) }
        }
        return nil
    }

    private func load(_ url: URL) async {
        var request = URLRequest(url: url)
        request.setValue("Spindle/0.1", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: request), let image = NSImage(data: data) else { return }
        objectWillChange.send()
        images[url] = image
    }
}

/// Artwork in a rounded tile; a soft gradient drawn in code stands in until (or unless) the image loads.
struct ArtworkView: View {
    @ObservedObject var cache: ArtworkCache
    let url: URL?
    /// Picks the fallback gradient, so each show keeps its own colours.
    let seed: String
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if let image = cache.image(for: url) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                Self.fallback(for: seed)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
    }

    private static func fallback(for seed: String) -> some View {
        // A stable hash: String.hashValue changes from launch to launch.
        let sum = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let hue = Double(sum % 360) / 360
        return LinearGradient(
            colors: [Color(hue: hue, saturation: 0.45, brightness: 0.95),
                     Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.7)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
