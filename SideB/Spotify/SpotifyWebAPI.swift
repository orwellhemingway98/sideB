import Foundation

/// What Spotify says is playing: the list it plays from and the song's album.
struct SpotifyPlaying: Equatable {
    var contextType: String?
    var contextID: String?
    var albumID: String?
}

/// Reads Spotify's JSON into `MusicContext`. Pure, so it can be tested on canned replies.
enum SpotifyContextParser {
    struct Artist: Decodable { let name: String }

    struct Track: Decodable {
        let type: String?
        let uri: String?
        let name: String?
        let disc_number: Int?
        let track_number: Int?
        let duration_ms: Double?
        let artists: [Artist]?
        let is_local: Bool?
        let album: AlbumRef?

        struct AlbumRef: Decodable { let id: String? }
    }

    struct Page<Item: Decodable>: Decodable {
        let items: [Item]
        let next: String?
        let total: Int?
    }

    /// Spotify's docs name the song `item` since February 2026 and `track` before; either is read.
    struct PlaylistEntry: Decodable {
        let item: Track?
        let track: Track?
        let is_local: Bool?

        var song: Track? { item ?? track }
    }

    struct Album: Decodable {
        let name: String
        let tracks: Page<Track>
    }

    /// `items` is only there for playlists the user owns or collaborates on.
    struct Playlist: Decodable {
        let name: String
        let items: Page<PlaylistEntry>?
    }

    private struct Playing: Decodable {
        struct Context: Decodable { let type: String?; let uri: String? }
        let context: Context?
        let item: Track?
    }

    static func playing(from data: Data) throws -> SpotifyPlaying {
        let reply = try JSONDecoder().decode(Playing.self, from: data)
        return SpotifyPlaying(contextType: reply.context?.type, contextID: reply.context?.uri.map(id(fromURI:)),
                              albumID: reply.item?.type == "track" ? reply.item?.album?.id : nil)
    }

    /// "album:<id>" or "playlist:<id>". Anything sideB can't list (another user's playlist, Liked Songs,
    /// an artist, radio) is the song's album; an episode has none.
    static func contextKey(_ playing: SpotifyPlaying, unreadable: Set<String>) -> String? {
        if let id = playing.contextID {
            if playing.contextType == "album" { return "album:" + id }
            if playing.contextType == "playlist", !unreadable.contains(id) { return "playlist:" + id }
        }
        return playing.albumID.map { "album:" + $0 }
    }

    /// A playable song as a row; local files, episodes and missing items have none.
    static func row(_ track: Track?, number: Int? = nil) -> ContextTrack? {
        guard let track, track.type ?? "track" == "track", track.is_local != true,
              let uri = track.uri, uri.hasPrefix("spotify:track:") else { return nil }
        return ContextTrack(id: uri, disc: track.disc_number ?? 1, number: number ?? track.track_number ?? 0,
                            title: track.name ?? "", artist: (track.artists ?? []).map(\.name).joined(separator: ", "),
                            duration: (track.duration_ms ?? 0) / 1000)
    }

    static func id(fromURI uri: String) -> String {
        String(uri.split(separator: ":").last ?? "")
    }
}

/// The Web API calls behind a Spotify song's list. Every call is skipped while signed out, and a login Spotify
/// refuses reads as nothing (the list then offers to sign in again).
final class SpotifyWebAPI: @unchecked Sendable {
    private static let base = "https://api.spotify.com/v1"

    private let client: SpotifyClient
    private let lock = NSLock()
    /// Playlists Spotify won't list for this user: shown as the song's album from then on.
    private var unreadable: Set<String> = []

    init(client: SpotifyClient) { self.client = client }

    var isSignedIn: Bool { client.isSignedIn }

    func contextKey() throws -> String? {
        try signedIn {
            guard let playing = try currentlyPlaying() else { return nil }
            return SpotifyContextParser.contextKey(playing, unreadable: lock.withLock { unreadable })
        }
    }

    func context() throws -> MusicContext? {
        try signedIn {
            guard let playing = try currentlyPlaying(),
                  let key = SpotifyContextParser.contextKey(playing, unreadable: lock.withLock { unreadable }) else {
                return nil
            }
            let id = String(key.drop { $0 != ":" }.dropFirst())
            if key.hasPrefix("playlist:") {
                if let playlist = try playlist(id) { return playlist }
                lock.withLock { _ = unreadable.insert(id) }
                guard let albumID = playing.albumID else { return nil }
                return try album(albumID)
            }
            return try album(id)
        }
    }

    // MARK: - Private

    private func signedIn<T>(_ read: () throws -> T?) throws -> T? {
        guard client.isSignedIn else { return nil }
        do { return try read() }
        catch SpotifyError.notSignedIn, SpotifyError.expired { return nil }
    }

    private func currentlyPlaying() throws -> SpotifyPlaying? {
        guard let data = try client.get(URL(string: Self.base + "/me/player/currently-playing")!) else { return nil }
        return try decode { try SpotifyContextParser.playing(from: data) }
    }

    private func album(_ id: String) throws -> MusicContext? {
        guard let data = try client.get(URL(string: "\(Self.base)/albums/\(id)")!) else { return nil }
        let album = try decode { try JSONDecoder().decode(SpotifyContextParser.Album.self, from: data) }
        var tracks = album.tracks.items.compactMap { SpotifyContextParser.row($0) }
        var next = album.tracks.next
        while let url = next.flatMap(URL.init(string:)), tracks.count < MusicContextParser.cap,
              let data = try client.get(url) {
            let page = try decode { try JSONDecoder().decode(SpotifyContextParser.Page<SpotifyContextParser.Track>.self, from: data) }
            tracks += page.items.compactMap { SpotifyContextParser.row($0) }
            next = page.next
        }
        tracks.sort { ($0.disc, $0.number) < ($1.disc, $1.number) }
        return MusicContext(kind: .album, id: "album:" + id, title: album.name,
                            tracks: Array(tracks.prefix(MusicContextParser.cap)),
                            totalCount: max(album.tracks.total ?? tracks.count, min(tracks.count, MusicContextParser.cap)))
    }

    /// Nil when Spotify won't list this playlist's songs for this user.
    private func playlist(_ id: String) throws -> MusicContext? {
        let data: Data?
        do { data = try client.get(URL(string: "\(Self.base)/playlists/\(id)?market=from_token")!) }
        catch SpotifyError.http(let code) where code == 403 || code == 404 { return nil }
        guard let data else { return nil }
        let playlist = try decode { try JSONDecoder().decode(SpotifyContextParser.Playlist.self, from: data) }
        guard let first = playlist.items else { return nil }
        var entries = first.items
        var next = first.next
        while let url = next.flatMap(URL.init(string:)), entries.count < MusicContextParser.cap,
              let data = try client.get(url) {
            let page = try decode {
                try JSONDecoder().decode(SpotifyContextParser.Page<SpotifyContextParser.PlaylistEntry>.self, from: data)
            }
            entries += page.items
            next = page.next
        }
        let songs = entries.filter { $0.is_local != true }.map(\.song)
        let tracks = songs.compactMap { SpotifyContextParser.row($0, number: 0) }.prefix(MusicContextParser.cap)
            .enumerated().map { index, track in
                ContextTrack(id: track.id, disc: track.disc, number: index + 1, title: track.title,
                             artist: track.artist, duration: track.duration)
            }
        return MusicContext(kind: .playlist, id: "playlist:" + id, title: playlist.name, tracks: tracks,
                            totalCount: max(first.total ?? tracks.count, tracks.count))
    }

    private func decode<T>(_ read: () throws -> T) throws -> T {
        do { return try read() }
        catch { throw MusicSourceError.scriptFailed("Unexpected reply from Spotify") }
    }
}
