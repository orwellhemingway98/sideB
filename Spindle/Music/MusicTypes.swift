import Foundation

enum MusicSourceID: String, CaseIterable {
    case appleMusic
    case spotify

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }

    /// The word after the dot under the title: the Mac app's own name for Apple Music.
    var shortName: String {
        switch self {
        case .appleMusic: return "Music"
        case .spotify: return "Spotify"
        }
    }

    /// The colour of the small dot that stands for the source beside the artist (our own mark, not a logo).
    var markHex: UInt32 {
        switch self {
        case .appleMusic: return 0xFA2D48
        case .spotify: return 0x1ED760
        }
    }
}

enum MusicPlayerState: Equatable {
    case playing, paused, stopped
}

/// The current track as reported by a music app. Times are in seconds.
struct MusicTrack: Equatable {
    var trackID: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var index: Int?
    var count: Int?
    var source: MusicSourceID
}

struct MusicSnapshot: Equatable {
    var state: MusicPlayerState
    var track: MusicTrack?
    var volume: Int
}

enum ArtworkRef: Equatable {
    case data(Data)
    case url(URL)
    case none
}


enum MusicSourceError: Error, Equatable {
    case permissionDenied
    case notRunning
    case scriptFailed(String)
}

/// A music app Spindle can control (copied from ClickWheel; volume is left to the keyboard). Methods are synchronous and may block,
/// so callers run them off the main thread.
protocol MusicSource: AnyObject {
    var id: MusicSourceID { get }
    var displayName: String { get }
    func isRunning() -> Bool
    func snapshot() throws -> MusicSnapshot
    func artwork() throws -> ArtworkRef
    func playPause() throws
    func pause() throws
    func next() throws
    func previous() throws
    func setPosition(_ seconds: Double) throws
    /// The app's own volume, 0...100.
    func setVolume(_ percent: Int) throws
    /// Which album or playlist the current song plays from ("playlist:<id>" / "album:<album>|<artist>"),
    /// cheaply, without reading its songs; nil when the app can't say.
    func contextKey() throws -> String?
    /// The album or playlist the current song plays from; nil when the app can't say.
    func context() throws -> MusicContext?
    /// Plays one song of a context, continuing through that context.
    func play(trackID: String, in context: MusicContext) throws
}

extension MusicSource {
    // Sources that can't list albums or playlists.
    func contextKey() throws -> String? { nil }
    func context() throws -> MusicContext? { nil }
    func play(trackID: String, in context: MusicContext) throws {}
}
