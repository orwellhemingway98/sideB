import CryptoKit
import Foundation

/// Where downloaded episodes live: root/Episodes/<feed>/<episode>.<ext>, named by hashes so any
/// feed URL or guid makes a safe, stable file name.
enum EpisodeFiles {
    static func directory(root: URL) -> URL {
        root.appendingPathComponent("Episodes", isDirectory: true)
    }

    @MainActor
    static func destination(for episode: Episode, root: URL) -> URL {
        let feed = hash(episode.show?.feedURL.absoluteString ?? "unknown")
        let ext = episode.enclosureURL.pathExtension.isEmpty ? "mp3" : episode.enclosureURL.pathExtension.lowercased()
        return directory(root: root)
            .appendingPathComponent(feed, isDirectory: true)
            .appendingPathComponent(hash(episode.guid))
            .appendingPathExtension(ext)
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
