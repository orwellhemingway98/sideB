import XCTest
@testable import Spindle

@MainActor
final class MusicRemoteContextTests: XCTestCase {
    private var music: FakeMusicSource!
    private var remote: MusicRemote!

    private let album = MusicContext(kind: .album, id: "album:Night Roads|Northern Static", title: "Night Roads",
                                     tracks: [ContextTrack(id: "t1", disc: 1, number: 1, title: "Headlights",
                                                           artist: "Northern Static", duration: 221),
                                              ContextTrack(id: "t2", disc: 1, number: 2, title: "Blue Hour Drive",
                                                           artist: "Northern Static", duration: 239)],
                                     totalCount: 2)

    override func setUp() async throws {
        music = FakeMusicSource(.appleMusic)
        remote = MusicRemote(sources: [music], every: { _, _ in NSObject() })
        music.contextResult = .success(album)
        music.contextKeyValue = album.id
        music.play("Headlights", id: "t1")
        await remote.refresh()
    }

    func testContextIsReadOnceAndCached() async throws {
        let track = try XCTUnwrap(remote.track)
        let first = await remote.context(for: track)
        let second = await remote.context(for: track)
        XCTAssertEqual(first, album)
        XCTAssertEqual(second, album)
        XCTAssertEqual(music.contextCalls, 1)
    }

    func testAnotherTrackOnTheSameAlbumReusesIt() async throws {
        _ = await remote.context(for: try XCTUnwrap(remote.track))
        music.play("Blue Hour Drive", id: "t2")
        await remote.refresh()
        let context = await remote.context(for: try XCTUnwrap(remote.track))
        XCTAssertEqual(context?.id, album.id)
        XCTAssertEqual(music.contextCalls, 1, "a song already in a cached album doesn't read Music again")
    }

    func testReadFailureIsReported() async throws {
        music.contextResult = .failure(.scriptFailed("timeout"))
        let context = await remote.context(for: try XCTUnwrap(remote.track))
        XCTAssertNil(context)
        XCTAssertTrue(remote.contextFailed)
    }

    func testSpotifyHasNoContext() async throws {
        let spotify = FakeMusicSource(.spotify)
        let spotifyRemote = MusicRemote(sources: [spotify], every: { _, _ in NSObject() })
        spotify.play("Song", id: "s1")
        await spotifyRemote.refresh()
        let context = await spotifyRemote.context(for: try XCTUnwrap(spotifyRemote.track))
        XCTAssertNil(context)
        XCTAssertFalse(spotifyRemote.contextFailed)
    }

    func testPlayingARowGoesToTheSource() async {
        remote.play(contextTrack: album.tracks[1], in: album)
        await remote.lastCommand?.value
        XCTAssertEqual(music.playedInContext.map(\.trackID), ["t2"])
        XCTAssertEqual(music.playedInContext.map(\.contextID), [album.id])
    }

    // MARK: Review fixes

    func testCacheIsKeyedByThePlayingContext() async throws {
        let playlist = MusicContext(kind: .playlist, id: "playlist:FAV", title: "Favourites", tracks: album.tracks, totalCount: 2)
        music.contextKeyValue = playlist.id
        music.contextResult = .success(playlist)
        await remote.refresh()
        let first = await remote.context(for: try XCTUnwrap(remote.track))
        XCTAssertEqual(first?.id, "playlist:FAV")
        // The same song, now played from its album.
        music.contextKeyValue = album.id
        music.contextResult = .success(album)
        music.play("Headlights", id: "t1", position: 1)
        await remote.refresh()
        let second = await remote.context(for: try XCTUnwrap(remote.track))
        XCTAssertEqual(second?.id, album.id, "a song shared by two lists shows the one it's playing from")
    }

    func testRefreshReadsAgain() async throws {
        let track = try XCTUnwrap(remote.track)
        _ = await remote.context(for: track)
        _ = await remote.context(for: track, refresh: true)
        XCTAssertEqual(music.contextCalls, 2, "opening the list reads Music again, so playlist edits show")
    }

    func testOverlappingReadsAreShared() async throws {
        let track = try XCTUnwrap(remote.track)
        async let a = remote.context(for: track)
        async let b = remote.context(for: track)
        _ = await (a, b)
        XCTAssertEqual(music.contextCalls, 1)
    }

    func testCacheHitsDoNotAnnounceChanges() async throws {
        let track = try XCTUnwrap(remote.track)
        _ = await remote.context(for: track)
        var changes = 0
        let watch = remote.objectWillChange.sink { changes += 1 }
        _ = await remote.context(for: track)
        watch.cancel()
        XCTAssertEqual(changes, 0, "a cached read changes nothing, so it mustn't wake the list")
    }

    func testContextKindFollowsTheSong() async throws {
        XCTAssertEqual(remote.contextKind, .album)
        music.contextKeyValue = "playlist:FAV"
        music.play("Blue Hour Drive", id: "t2")
        await remote.refresh()
        while remote.contextKind != .playlist { await Task.yield() }
        XCTAssertEqual(remote.contextKind, .playlist)
    }
}
