import Foundation

final class AppleMusicSource: AppleScriptMusicSource, MusicSource {
    let id = MusicSourceID.appleMusic
    var displayName: String { id.displayName }

    init() { super.init(bundleIdentifier: "com.apple.Music", appName: "Music") }

    static let snapshotScript = """
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

    // MARK: Album or playlist

    /// Spindle's own playlist, refilled to play an album from a chosen song (ClickWheel's approach).
    static let playlistName = "Spindle"
    private static let playlistIDKey = "spindlePlaylistID"

    /// Works out the current song's list: one of your playlists, or its album. The album's artist falls back to
    /// the song's artist when the album artist is empty, so untagged albums of the same name don't merge.
    /// Sets `usePlaylist`, `pl`, `alb`, `aa` and `useAlbumArtist`.
    private static let contextPrologue = """
        try
            set t to current track
        on error
            return ""
        end try
        set usePlaylist to false
        try
            set pl to current playlist
            if (class of pl is user playlist) and (special kind of pl is none) and (name of pl is not \(quoted(playlistName))) then set usePlaylist to true
        end try
        set alb to album of t
        set aa to album artist of t
        set useAlbumArtist to true
        if aa is "" then
            set aa to artist of t
            set useAlbumArtist to false
        end if
        """

    static let contextKeyScript = """
        with timeout of 5 seconds
        \(contextPrologue)
        if usePlaylist then return "playlist:" & (persistent ID of pl)
        if alb is "" then return ""
        return "album:" & alb & "|" & aa
        end timeout
        """

    /// Reads the list's songs a property at a time (a few Apple events, not one per field per song).
    static let contextScript = """
        with timeout of 10 seconds
        set fs to character id 31
        set rs to character id 30
        \(contextPrologue)
        if usePlaylist then
            set total to count of tracks of pl
            set head to "playlist" & fs & "playlist:" & (persistent ID of pl) & fs & (name of pl) & fs & (total as string)
            if total is 0 then return head
            set n to total
            if n > \(MusicContextParser.cap) then set n to \(MusicContextParser.cap)
            set trs to a reference to (tracks 1 thru n of pl)
        else
            if alb is "" then return ""
            if useAlbumArtist then
                set trs to a reference to (every track of library playlist 1 whose album is alb and album artist is aa)
            else
                set trs to a reference to (every track of library playlist 1 whose album is alb and artist is aa)
            end if
            set total to count of trs
            set head to "album" & fs & "album:" & alb & "|" & aa & fs & alb & fs & (total as string)
            if total is 0 then return head
            set n to total
            if n > \(MusicContextParser.cap) then set n to \(MusicContextParser.cap)
        end if
        -- Each list gets a t prefix: plain `names` or `artists` are Music terms and won't compile here.
        set tIDs to persistent ID of trs
        set tDiscs to disc number of trs
        set tNums to track number of trs
        set tNames to name of trs
        set tArtists to artist of trs
        set tDurs to duration of trs
        set out to {head}
        repeat with i from 1 to n
            set end of out to (item i of tIDs) & fs & ((item i of tDiscs) as string) & fs & ((item i of tNums) as string) & fs & (item i of tNames) & fs & (item i of tArtists) & fs & ((item i of tDurs) as string)
        end repeat
        set AppleScript's text item delimiters to rs
        set res to out as string
        set AppleScript's text item delimiters to ""
        return res
        end timeout
        """

    func contextKey() throws -> String? {
        let key = try tell(Self.contextKeyScript).stringValue ?? ""
        return key.isEmpty ? nil : key
    }

    func context() throws -> MusicContext? {
        MusicContextParser.parse(try tell(Self.contextScript).stringValue ?? "")
    }

    func play(trackID: String, in context: MusicContext) throws {
        switch context.kind {
        case .playlist:
            let playlistID = String(context.id.dropFirst("playlist:".count))
            try tell("""
                with timeout of 10 seconds
                play (first track of (first user playlist whose persistent ID is \(Self.quoted(playlistID))) whose persistent ID is \(Self.quoted(trackID)))
                end timeout
                """)
        case .album:
            let defaults = UserDefaults.standard
            let script = Self.queueScript(trackIDs: context.tracks.map(\.id), startID: trackID,
                                          knownPlaylistID: defaults.string(forKey: Self.playlistIDKey))
            if let id = try tell(script).stringValue, !id.isEmpty {
                defaults.set(id, forKey: Self.playlistIDKey)
            }
        }
    }

    /// Refills the "Spindle" playlist with the album and plays it from `startID`, so the album carries on
    /// after it (and ⏮ reaches the songs before). Copied from ClickWheel's AppleMusicScripts.queue.
    static func queueScript(trackIDs: [String], startID: String, knownPlaylistID: String?) -> String {
        let findKnown = knownPlaylistID.map {
            "try\nset q to first user playlist whose persistent ID is \(quoted($0))\nend try"
        } ?? ""
        let ids = "{" + trackIDs.map(quoted).joined(separator: ", ") + "}"
        return """
            with timeout of 10 seconds
            set q to missing value
            \(findKnown)
            if q is missing value then
                try
                    set q to first user playlist whose name is \(quoted(playlistName))
                end try
            end if
            if q is missing value then set q to make new user playlist with properties {name:\(quoted(playlistName))}
            if (count of tracks of q) > 0 then delete every track of q
            set src to library playlist 1
            repeat with tid in \(ids)
                try
                    duplicate (first track of src whose persistent ID is (contents of tid)) to q
                end try
            end repeat
            try
                play (first track of q whose persistent ID is \(quoted(startID)))
            on error
                play track 1 of q
            end try
            return persistent ID of q
            end timeout
            """
    }

    /// An AppleScript string literal (ClickWheel's AppleMusicScripts.quoted).
    static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
