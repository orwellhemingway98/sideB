import Foundation

final class AppleMusicSource: AppleScriptMusicSource, MusicSource {
    let id = MusicSourceID.appleMusic
    var displayName: String { id.displayName }

    init() { super.init(bundleIdentifier: "com.apple.Music", appName: "Music") }

    private static let snapshotScript = """
        set theSep to character id 31
        set theState to player state as string
        set theVolume to sound volume as string
        if theState is "stopped" then return theState & theSep & theVolume
        try
            set t to current track
        on error
            return theState & theSep & theVolume
        end try
        set theIndex to ""
        set theCount to ""
        try
            set theIndex to (index of t) as string
            set theCount to (count of tracks of current playlist) as string
        end try
        return theState & theSep & theVolume & theSep & (persistent ID of t) & theSep & (name of t) & theSep & (artist of t) & theSep & (album of t) & theSep & ((duration of t) as string) & theSep & ((player position) as string) & theSep & theIndex & theSep & theCount
        """

    func snapshot() throws -> MusicSnapshot {
        let output = try tell(Self.snapshotScript).stringValue ?? ""
        guard let snapshot = ScriptOutputParser.parse(output, source: id, durationIsMilliseconds: false) else {
            throw MusicSourceError.scriptFailed("Unexpected output from Music")
        }
        return snapshot
    }

    func artwork() throws -> ArtworkRef {
        let result = try tell("""
            try
                return raw data of artwork 1 of current track
            on error
                return ""
            end try
            """)
        let data = result.data
        return data.isEmpty || result.descriptorType == typeUnicodeText ? .none : .data(data)
    }

    func playPause() throws { try tell("playpause") }
    func pause() throws { try tell("pause") }
    func next() throws { try tell("next track") }
    func previous() throws { try tell("previous track") }
    func setPosition(_ seconds: Double) throws { try tell("set player position to \(String(format: "%.2f", max(0, seconds)))") }
}
