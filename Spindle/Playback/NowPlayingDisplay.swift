import AppKit

/// What every view shows for whatever the dial is steering: a podcast episode or a song.
struct NowPlayingDisplay: Equatable {
    enum Kind: Equatable { case podcast, music }

    let kind: Kind
    let title: String
    /// The show for a podcast, the artist for a song.
    let subtitle: String
    /// Where a song plays, shown as a coloured mark; nil for a podcast.
    let source: MusicSourceID?
    /// "Apple Music" or "Spotify" for a song (the mark's tooltip and spoken name); nil for a podcast.
    var sourceLabel: String? { source?.displayName }
    /// A podcast's artwork; a song's comes as an image (`NowPlaying.musicArtwork`).
    let artworkURL: URL?
    /// Picks the fallback gradient when there's no artwork.
    let artworkSeed: String
    let duration: TimeInterval?
    let isPlaying: Bool
}

extension NowPlaying {
    /// Nil when nothing is open in the current mode.
    var display: NowPlayingDisplay? {
        switch mode {
        case .music:
            guard let track = music?.track else { return nil }
            return NowPlayingDisplay(kind: .music, title: track.title, subtitle: track.artist,
                                     source: track.source, artworkURL: nil,
                                     artworkSeed: track.album.isEmpty ? track.title : track.album,
                                     duration: track.duration > 0 ? track.duration : nil,
                                     isPlaying: music?.isPlaying ?? false)
        case .podcast:
            guard let episode = player.episode else { return nil }
            return NowPlayingDisplay(kind: .podcast, title: episode.title, subtitle: episode.show?.title ?? "",
                                     source: nil, artworkURL: episode.show?.artworkURL,
                                     artworkSeed: episode.show?.title ?? episode.title,
                                     duration: player.duration, isPlaying: player.isPlaying)
        }
    }

    /// The song's artwork in music mode.
    var musicArtwork: NSImage? {
        mode == .music ? music?.artwork : nil
    }
}
