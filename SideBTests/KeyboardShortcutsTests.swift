import XCTest
@testable import SideB

/// The keys can be found from the menu, and R resumes the podcast music interrupted.
@MainActor
final class KeyboardShortcutsTests: XCTestCase {
    private var engine: FakeEngine!
    private var player: PodcastPlayer!
    private var spotify: FakeMusicSource!
    private var remote: MusicRemote!
    private var nowPlaying: NowPlaying!
    private var episode: Episode!

    override func setUp() async throws {
        let feed = URL(string: "https://example.com/feed")!
        let library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        episode = library.episodes(of: try await library.follow(feedURL: feed))[0]
        engine = FakeEngine()
        engine.duration = 3120
        player = PodcastPlayer(engine: engine, library: library)
        spotify = FakeMusicSource(.spotify)
        spotify.stop()
        remote = MusicRemote(sources: [spotify], every: { _, _ in NSObject() })
        nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(), schedule: { _, _ in },
                                now: { 0 }, loadChapters: { _ in [] }, music: remote)
    }

    private func press(_ key: PanelKey) {
        key.perform(nowPlaying: nowPlaying, list: nil, turnCover: {}, library: {}, escape: {})
    }

    func testRIsTheResumeKey() {
        XCTAssertEqual(PanelKey(keyCode: 15, modifiers: []), .resume)
        XCTAssertNil(PanelKey(keyCode: 15, modifiers: .command), "⌘R stays with macOS")
    }

    func testRResumesThePodcastMusicInterrupted() async {
        player.open(episode, autoplay: true)
        engine.fireTime(600)
        spotify.play("Japan", id: "s1")
        await remote.refresh()
        XCTAssertNotNil(nowPlaying.pausedEpisode)
        press(.resume)
        await remote.lastCommand?.value
        XCTAssertEqual(nowPlaying.mode, .podcast)
        XCTAssertTrue(player.isPlaying)
    }

    func testWithNothingToResumeRDoesNothing() async {
        spotify.play("Japan", id: "s1")
        await remote.refresh()
        press(.resume)
        XCTAssertEqual(nowPlaying.mode, .music)
        XCTAssertTrue(spotify.commands.isEmpty)
    }

    func testTheListNamesEveryKey() {
        let text = KeyboardShortcuts.text
        for key in ["Space", "\u{2190}", "\u{2192}", "Return", "\u{2191}", "\u{2193}", "R", "\u{2318}L", "Esc"] {
            XCTAssertTrue(text.contains(key), "missing \(key)")
        }
    }
}
