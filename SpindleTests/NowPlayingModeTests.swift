import XCTest
@testable import Spindle

/// Podcasts and music take turns: whichever was started most recently is in control.
@MainActor
final class NowPlayingModeTests: XCTestCase {
    private var engine: FakeEngine!
    private var player: PodcastPlayer!
    private var media: FakeMediaCenter!
    private var spotify: FakeMusicSource!
    private var remote: MusicRemote!
    private var nowPlaying: NowPlaying!
    private var episode: Episode!
    private var scheduled: [@MainActor () -> Void] = []

    override func setUp() async throws {
        let feed = URL(string: "https://example.com/feed")!
        let library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        episode = library.episodes(of: try await library.follow(feedURL: feed))[0]
        engine = FakeEngine()
        engine.duration = 3120
        player = PodcastPlayer(engine: engine, library: library)
        media = FakeMediaCenter()
        spotify = FakeMusicSource(.spotify)
        spotify.stop()
        remote = MusicRemote(sources: [spotify], every: { _, _ in NSObject() })
        scheduled = []
        nowPlaying = NowPlaying(player: player, media: media, haptics: FakeHaptics(),
                                schedule: { [unowned self] _, run in scheduled.append(run) },
                                now: { 0 }, loadChapters: { _ in [] }, music: remote)
    }

    private func startMusic(id: String = "s1", position: Double = 30) async {
        spotify.play("Blue Hour Drive", id: id, position: position)
        await remote.refresh()
    }

    func testMusicStartingPausesThePodcastAndKeepsItsPlace() async {
        player.open(episode, autoplay: true)
        engine.fireTime(600)
        await startMusic()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(episode.position, 600, "the podcast keeps its place")
        XCTAssertEqual(nowPlaying.mode, .music)
        XCTAssertEqual(media.published.last.map { $0 == nil }, true, "the music app publishes its own Now Playing")
    }

    func testStartingAPodcastPausesTheMusic() async {
        await startMusic()
        XCTAssertEqual(nowPlaying.mode, .music)
        nowPlaying.play(episode)
        await remote.lastCommand?.value
        XCTAssertEqual(spotify.commands, [.pause])
        XCTAssertEqual(nowPlaying.mode, .podcast)
    }

    func testTheDialScrubsTheSongInMusicMode() async {
        await startMusic(position: 30)
        nowPlaying.turn(degrees: 30)
        XCTAssertEqual(nowPlaying.scrubPosition, 40)
        XCTAssertEqual(nowPlaying.displayPosition, 40)
        scheduled.forEach { $0() }
        await remote.lastCommand?.value
        XCTAssertEqual(spotify.commands, [.setPosition(40)])
        XCTAssertNil(nowPlaying.scrubPosition)
    }

    func testToggleAndSkipControlTheMusic() async {
        await startMusic()
        nowPlaying.toggle(); await remote.lastCommand?.value
        nowPlaying.next(); await remote.lastCommand?.value
        nowPlaying.previous(); await remote.lastCommand?.value
        XCTAssertEqual(spotify.commands, [.playPause, .next, .previous])
        XCTAssertEqual(engine.playCount, 0, "the podcast is left alone")
    }

    func testBackAndForwardChangeTheSong() async {
        await startMusic()
        nowPlaying.forward(); await remote.lastCommand?.value
        nowPlaying.back(); await remote.lastCommand?.value
        XCTAssertEqual(spotify.commands, [.next, .previous])
    }

    func testMusicGoingAwayFallsBackToThePodcast() async {
        player.open(episode, autoplay: false)
        await startMusic()
        XCTAssertEqual(nowPlaying.mode, .music)
        spotify.running = false
        await remote.refresh()
        XCTAssertEqual(nowPlaying.mode, .podcast)
    }

    func testNewSongDropsAPendingScrub() async {
        await startMusic(id: "s1", position: 30)
        nowPlaying.turn(degrees: 30)
        spotify.play("Next Song", id: "s2", position: 0)
        await remote.refresh()
        XCTAssertNil(nowPlaying.scrubPosition)
        scheduled.forEach { $0() }
        await remote.lastCommand?.value
        XCTAssertEqual(spotify.commands, [], "the old scrub isn't applied to the new song")
    }

    func testNoMusicRemoteMeansPodcastOnly() {
        let plain = NowPlaying(player: player, media: media, haptics: FakeHaptics(),
                               schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] })
        XCTAssertEqual(plain.mode, .podcast)
        plain.next()   // no music: nothing happens
        XCTAssertEqual(plain.mode, .podcast)
    }

    // MARK: Final review fixes

    func testResumePodcastFromMusicMode() async {
        player.open(episode, autoplay: true)
        engine.fireTime(600)
        await startMusic()
        XCTAssertTrue(nowPlaying.pausedEpisode === episode, "music mode offers the paused podcast")
        nowPlaying.resumePodcast()
        await remote.lastCommand?.value
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(nowPlaying.mode, .podcast)
        XCTAssertEqual(spotify.commands, [.pause])
        XCTAssertNil(nowPlaying.pausedEpisode)
    }

    func testStartingAPodcastSoonAfterMusicPausesIt() async {
        spotify.play("Blue Hour Drive", id: "s1", state: .paused)
        await remote.refresh()                       // polled while paused
        spotify.play("Blue Hour Drive", id: "s1")    // the user presses play in Spotify; not polled yet
        nowPlaying.play(episode)
        await remote.lastCommand?.value
        XCTAssertEqual(spotify.commands, [.pause], "a podcast always pauses the music app it knows about")
    }

    func testZeroLengthSongsCannotBeScrubbed() async {
        spotify.play("Live Radio", id: "r1", position: 120, duration: 0)
        await remote.refresh()
        XCTAssertNil(nowPlaying.displayDuration)
        nowPlaying.turn(degrees: 30)
        nowPlaying.jump(to: 10)
        scheduled.forEach { $0() }
        await remote.lastCommand?.value
        XCTAssertNil(nowPlaying.scrubPosition)
        XCTAssertEqual(spotify.commands, [], "a live stream has no position to scrub to")
    }
}
