import AppKit
import SwiftUI
import XCTest
@testable import SideB

/// The notes under the playback buttons really show in the panel, only while there's something to say.
@MainActor
final class PanelNotesTests: XCTestCase {
    private var spotify: FakeMusicSource!
    private var remote: MusicRemote!
    private var library: LibraryStore!
    private var nowPlaying: NowPlaying!
    private var transport: FakeTransport!
    private var account: SpotifyAccount!

    override func setUp() async throws {
        library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [:]))
        let player = PodcastPlayer(engine: FakeEngine(), library: library)
        spotify = FakeMusicSource(.spotify)
        spotify.stop()
        remote = MusicRemote(sources: [spotify], every: { _, _ in NSObject() })
        nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] }, music: remote)
        transport = FakeTransport()
        let store = MemoryTokenStore()
        store.save(SpotifyTokens(accessToken: "A", refreshToken: "R", expiresAt: .distantFuture))
        let defaults = UserDefaults(suiteName: "PanelNotesTests")!
        defaults.removePersistentDomain(forName: "PanelNotesTests")
        account = SpotifyAccount(store: store, transport: transport, defaults: defaults,
                                 authenticate: { _ in throw CancellationError() })
        spotify.play("Japan", id: "s1")
        await remote.refresh()
    }

    private var height: CGFloat {
        let list = ListModel(nowPlaying: nowPlaying, library: library, spotify: account)
        let view = PanelView(nowPlaying: nowPlaying, library: library, artwork: ArtworkCache(), onLibrary: {}, list: list)
        return NSHostingView(rootView: view).fittingSize.height
    }

    func testAFailedCommandAddsANote() async {
        let before = height
        spotify.commandFailure = .scriptFailed("timed out")
        remote.next()
        await remote.lastCommand?.value
        XCTAssertGreaterThan(height, before)
    }

    func testANeededSignInAddsANote() async {
        let before = height
        transport.reply("/v1/me/player/play", .status(403, #"{"error":{"message":"Insufficient client scope"}}"#))
        let api = account.api
        _ = await Task.detached { api.play(trackURI: "spotify:track:T1", contextID: "album:AL1") }.value
        for _ in 0..<1000 where !account.needsNewSignIn { await Task.yield() }
        XCTAssertGreaterThan(height, before)
    }

    func testTheSignInNoteIsForSpotifyOnly() async {
        let appleMusic = FakeMusicSource(.appleMusic)
        let remote = MusicRemote(sources: [appleMusic], every: { _, _ in NSObject() })
        let player = PodcastPlayer(engine: FakeEngine(), library: library)
        let nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                    schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] }, music: remote)
        appleMusic.play("Chemtrails", id: "m1")
        await remote.refresh()
        func panelHeight() -> CGFloat {
            let list = ListModel(nowPlaying: nowPlaying, library: library, spotify: account)
            let view = PanelView(nowPlaying: nowPlaying, library: library, artwork: ArtworkCache(), onLibrary: {}, list: list)
            return NSHostingView(rootView: view).fittingSize.height
        }
        let before = panelHeight()
        transport.reply("/v1/me/player/play", .status(403, #"{"error":{"message":"Insufficient client scope"}}"#))
        let api = account.api
        _ = await Task.detached { api.play(trackURI: "spotify:track:T1", contextID: "album:AL1") }.value
        for _ in 0..<1000 where !account.needsNewSignIn { await Task.yield() }
        XCTAssertEqual(panelHeight(), before)
    }
}
