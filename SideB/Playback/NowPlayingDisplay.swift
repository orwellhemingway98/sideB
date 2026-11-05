import AppKit

/// What every view shows for whatever sideB is steering: a podcast episode or a song.
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

    /// Whose cover is up: the song whose artwork has loaded (or turned out to have none), or the episode.
    var coverIdentity: String? {
        switch mode {
        case .music: return music?.artworkTrackID.map { "song:" + $0 }
        case .podcast: return player.episode.map { "episode:" + $0.guid }
        }
    }

    /// False while a new song's cover is still loading: the panel keeps the last song's cover and title until
    /// then, so they change together.
    var coverSettled: Bool {
        mode == .podcast || music?.track == nil || music?.artworkTrackID == music?.track?.trackID
    }

    /// The song's artwork in music mode.
    var musicArtwork: NSImage? {
        mode == .music ? music?.artwork : nil
    }
}
