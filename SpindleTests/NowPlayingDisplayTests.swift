import XCTest
@testable import Spindle

@MainActor
final class NowPlayingDisplayTests: XCTestCase {
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
        nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] }, music: remote)
    }

    func testPodcastDisplay() {
        player.open(episode, autoplay: true)
        let display = nowPlaying.display
        XCTAssertEqual(display?.kind, .podcast)
        XCTAssertEqual(display?.title, episode.title)
        XCTAssertEqual(display?.subtitle, "The Long Quiet")
        XCTAssertNil(display?.sourceLabel)
        XCTAssertEqual(display?.duration, 3120)
        XCTAssertEqual(display?.isPlaying, true)
        XCTAssertNil(nowPlaying.musicArtwork)
    }

    func testMusicDisplay() async {
        spotify.play("Blue Hour Drive", id: "s1", duration: 240, artist: "Northern Static")
        await remote.refresh()
        let display = nowPlaying.display
        XCTAssertEqual(display?.kind, .music)
        XCTAssertEqual(display?.title, "Blue Hour Drive")
        XCTAssertEqual(display?.subtitle, "Northern Static")
        XCTAssertEqual(display?.sourceLabel, "Spotify")
        XCTAssertEqual(display?.duration, 240)
        XCTAssertEqual(display?.isPlaying, true)
    }

    func testNothingOpenIsNil() {
        XCTAssertNil(nowPlaying.display)
    }
}
