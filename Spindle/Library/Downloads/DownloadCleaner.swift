import Foundation

/// Removes downloads a week after their episode was played, never the one playing now.
enum DownloadCleaner {
    static let keepAfterPlayed: TimeInterval = 7 * 24 * 3600

    @MainActor
    static func purge(_ episodes: [Episode], now: Date, excluding current: Episode?, remove: (Episode) -> Void) {
        let cutoff = now.addingTimeInterval(-keepAfterPlayed)
        for episode in episodes where episode !== current {
            guard episode.played, episode.localFile != nil,
                  let playedAt = episode.playedAt, playedAt <= cutoff else { continue }
            remove(episode)
        }
    }
}
