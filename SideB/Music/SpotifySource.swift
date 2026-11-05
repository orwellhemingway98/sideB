import Foundation

final class SpotifySource: AppleScriptMusicSource, MusicSource {
    let id = MusicSourceID.spotify
    var displayName: String { id.displayName }

    /// Reads albums and playlists once signed in; nil (no lists) in tests and previews.
    private let api: SpotifyWebAPI?

    init(api: SpotifyWebAPI? = nil) {
        self.api = api
        super.init(bundleIdentifier: "com.spotify.client", appName: "Spotify")
    }

    private static let snapshotScript = """
        set theSep to character id 31
        set theState to player state as string
        set theVolume to sound volume as string
        if theState is "stopped" then return theState & theSep & theVolume
        try
            set t to current track
            return theState & theSep & theVolume & theSep & (id of t) & theSep & (name of t) & theSep & (artist of t) & theSep & (album of t) & theSep & ((duration of t) as string) & theSep & ((player position) as string) & theSep & "" & theSep & ""
        on error
            return theState & theSep & theVolume
        end try
        """

    func snapshot() throws -> MusicSnapshot {
        let output = try tell(Self.snapshotScript).stringValue ?? ""
        guard let snapshot = ScriptOutputParser.parse(output, source: id, durationIsMilliseconds: true) else {
            throw MusicSourceError.scriptFailed("Unexpected output from Spotify")
        }
        return snapshot
    }

    func artwork() throws -> ArtworkRef {
        let url = try tell("return artwork url of current track").stringValue ?? ""
        return URL(string: url).map(ArtworkRef.url) ?? .none
    }

    func playPause() throws { try tell("playpause") }
    func pause() throws { try tell("pause") }
    func next() throws { try tell("next track") }
    func previous() throws { try tell("previous track") }
    func setPosition(_ seconds: Double) throws { try tell("set player position to \(String(format: "%.2f", max(0, seconds)))") }
    func setVolume(_ percent: Int) throws { try tell("set sound volume to \(min(100, max(0, percent)))") }

    // Spotify's scripting can't list albums or playlists; its Web API can, once signed in.
    func contextKey() throws -> String? { try api?.contextKey() }
    func context() throws -> MusicContext? { try api?.context() }

    /// Playing goes through the app, so it needs no Web API player access.
    func play(trackID: String, in context: MusicContext) throws {
        try tell(Self.playScript(trackID: trackID, contextID: context.id))
    }

    /// `contextID` is "album:<id>" or "playlist:<id>"; Spotify wants "spotify:album:<id>".
    static func playScript(trackID: String, contextID: String) -> String {
        "play track \"\(trackID)\" in context \"spotify:\(contextID)\""
    }
}
