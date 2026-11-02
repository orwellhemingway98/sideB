import XCTest
@testable import Spindle

final class SpotifyWebAPITests: XCTestCase {
    private var transport: FakeTransport!
    private var store: MemoryTokenStore!
    private var api: SpotifyWebAPI!

    private static let playingPath = "/v1/me/player/currently-playing"

    override func setUp() {
        transport = FakeTransport()
        store = MemoryTokenStore()
        store.save(SpotifyTokens(accessToken: "A", refreshToken: "R", expiresAt: .distantFuture))
        api = SpotifyWebAPI(client: SpotifyClient(clientID: { "abc" }, store: store, transport: transport))
    }

    private func playing(context: String?, album: String = "AL1", track: String = "T1", type: String = "track") {
        let contextJSON = context.map { uri -> String in
            let kind = uri.split(separator: ":")[1]
            return #"{"type":"\#(kind)","uri":"\#(uri)"}"#
        } ?? "null"
        let item = type == "episode"
            ? #"{"type":"episode","uri":"spotify:episode:E1","name":"Talk"}"#
            : #"{"type":"track","uri":"spotify:track:\#(track)","name":"Headlights","album":{"id":"\#(album)","name":"Night Roads"}}"#
        transport.reply(Self.playingPath, json: #"{"context":\#(contextJSON),"is_playing":true,"item":\#(item)}"#)
    }

    private static func track(_ id: String, _ name: String, disc: Int = 1, number: Int, local: Bool = false) -> String {
        #"{"type":"track","uri":"spotify:track:\#(id)","name":"\#(name)","disc_number":\#(disc),"track_number":\#(number),"duration_ms":200500,"artists":[{"name":"Northern Static"},{"name":"Guest"}],"is_local":\#(local)}"#
    }

    private func album(id: String = "AL1") {
        transport.reply("/v1/albums/\(id)", json: #"""
            {"id":"\#(id)","name":"Night Roads","tracks":{"items":[\#(Self.track("T2", "Blue Hour Drive", number: 2)),\#(Self.track("T1", "Headlights", number: 1))],
             "next":"https://api.spotify.com/v1/albums/\#(id)/tracks?offset=2&limit=50","total":3}}
            """#)
        transport.reply("/v1/albums/\(id)/tracks", json: #"""
            {"items":[\#(Self.track("T3", "Coda", disc: 2, number: 1))],"next":null,"total":3}
            """#)
    }

    // MARK: Which list

    func testNotSignedInAsksNothing() throws {
        store.clear()
        let api = SpotifyWebAPI(client: SpotifyClient(clientID: { "abc" }, store: store, transport: transport))
        XCTAssertNil(try api.contextKey())
        XCTAssertNil(try api.context())
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAlbumContextKey() throws {
        playing(context: "spotify:album:AL1")
        XCTAssertEqual(try api.contextKey(), "album:AL1")
    }

    func testPlaylistContextKey() throws {
        playing(context: "spotify:playlist:PL1")
        XCTAssertEqual(try api.contextKey(), "playlist:PL1")
    }

    func testOtherContextsUseTheSongsAlbum() throws {
        for context in ["spotify:artist:AR1", "spotify:collection:tracks", nil] {
            playing(context: context, album: "AL9")
            XCTAssertEqual(try api.contextKey(), "album:AL9", "context \(context ?? "none")")
        }
    }

    func testNothingPlaying() throws {
        transport.reply(Self.playingPath, .status(204))
        XCTAssertNil(try api.contextKey())
        XCTAssertNil(try api.context())
    }

    func testAnEpisodeHasNoList() throws {
        playing(context: nil, type: "episode")
        XCTAssertNil(try api.contextKey())
    }

    // MARK: Albums

    func testAlbumReadsEveryPageInOrder() throws {
        playing(context: "spotify:album:AL1")
        album()
        let context = try XCTUnwrap(try api.context())
        XCTAssertEqual(context.kind, .album)
        XCTAssertEqual(context.id, "album:AL1")
        XCTAssertEqual(context.title, "Night Roads")
        XCTAssertEqual(context.totalCount, 3)
        XCTAssertEqual(context.tracks.map(\.title), ["Headlights", "Blue Hour Drive", "Coda"])
        XCTAssertEqual(context.tracks[0], ContextTrack(id: "spotify:track:T1", disc: 1, number: 1, title: "Headlights",
                                                       artist: "Northern Static, Guest", duration: 200.5))
    }

    // MARK: Playlists

    func testOwnPlaylistReadsItsSongs() throws {
        playing(context: "spotify:playlist:PL1", track: "T5")
        transport.reply("/v1/playlists/PL1", json: #"""
            {"id":"PL1","name":"Favourites","items":{"items":[
               {"item":\#(Self.track("T5", "Five", number: 7))},
               {"item":null},
               {"item":{"type":"episode","uri":"spotify:episode:E1","name":"Talk"}},
               {"item":\#(Self.track("L1", "Local", number: 1, local: true)),"is_local":true}],
             "next":"https://api.spotify.com/v1/playlists/PL1/items?offset=4&limit=100","total":5}}
            """#)
        transport.reply("/v1/playlists/PL1/items", json: #"{"items":[{"item":\#(Self.track("T6", "Six", number: 3))}],"next":null,"total":5}"#)
        let context = try XCTUnwrap(try api.context())
        XCTAssertEqual(context.kind, .playlist)
        XCTAssertEqual(context.id, "playlist:PL1")
        XCTAssertEqual(context.title, "Favourites")
        XCTAssertEqual(context.tracks.map(\.title), ["Five", "Six"], "nulls, episodes and local files are skipped")
        XCTAssertEqual(context.tracks.map(\.number), [1, 2], "playlist rows are numbered by position")
        XCTAssertEqual(transport.requests(to: "/v1/playlists/PL1").first?.url?.query, "market=from_token")
    }

    func testPlaylistStopsAtTheCap() throws {
        playing(context: "spotify:playlist:PL1")
        let page = (0..<100).map { #"{"item":\#(Self.track("P\($0)", "Song \($0)", number: 1))}"# }.joined(separator: ",")
        transport.reply("/v1/playlists/PL1", json: #"{"id":"PL1","name":"Huge","items":{"items":[\#(page)],"next":"https://api.spotify.com/v1/playlists/PL1/items?offset=100","total":900}}"#)
        transport.reply("/v1/playlists/PL1/items", json: #"{"items":[\#(page)],"next":"https://api.spotify.com/v1/playlists/PL1/items?offset=200","total":900}"#)
        let context = try XCTUnwrap(try api.context())
        XCTAssertEqual(context.tracks.count, MusicContextParser.cap)
        XCTAssertEqual(context.totalCount, 900)
        XCTAssertEqual(transport.requests(to: "/v1/playlists/PL1/items").count, 4)
    }

    func testSomeoneElsesPlaylistShowsTheAlbumAndIsRemembered() throws {
        playing(context: "spotify:playlist:PL2")
        transport.reply("/v1/playlists/PL2", json: #"{"id":"PL2","name":"Top Hits"}"#)
        album()
        let context = try XCTUnwrap(try api.context())
        XCTAssertEqual(context.id, "album:AL1")
        XCTAssertEqual(try api.contextKey(), "album:AL1", "the cover's hint follows what the list shows")
    }

    func testAForbiddenPlaylistShowsTheAlbum() throws {
        playing(context: "spotify:playlist:PL3")
        transport.reply("/v1/playlists/PL3", .status(403))
        album()
        XCTAssertEqual(try api.context()?.id, "album:AL1")
    }

    func testOtherErrorsAreThrown() {
        playing(context: "spotify:album:AL1")
        transport.reply("/v1/albums/AL1", .status(500))
        XCTAssertThrowsError(try api.context())
    }

    func testAnExpiredLoginReadsNothing() throws {
        store.save(SpotifyTokens(accessToken: "A", refreshToken: "R", expiresAt: .distantPast))
        transport.reply("/api/token", .status(400))
        XCTAssertNil(try api.context())
    }
}
