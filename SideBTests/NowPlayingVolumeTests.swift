import XCTest
@testable import SideB

/// Holding Option while scrolling changes the volume instead of the place.
@MainActor
final class NowPlayingVolumeTests: XCTestCase {
    private var engine: FakeEngine!
    private var player: PodcastPlayer!
    private var haptics: FakeHaptics!
    private var spotify: FakeMusicSource!
    private var remote: MusicRemote!
    private var nowPlaying: NowPlaying!
    private var episode: Episode!
    private var scheduled: [(delay: TimeInterval, run: @MainActor () -> Void)] = []
    private var option = true

    override func setUp() async throws {
        let feed = URL(string: "https://example.com/feed")!
        let library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        episode = library.episodes(of: try await library.follow(feedURL: feed))[0]
        engine = FakeEngine()
        engine.duration = 3120
        player = PodcastPlayer(engine: engine, library: library)
        haptics = FakeHaptics()
        spotify = FakeMusicSource(.spotify)
        spotify.stop()
        remote = MusicRemote(sources: [spotify], every: { _, _ in NSObject() })
        scheduled = []
        option = true
        nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: haptics,
                                schedule: { [unowned self] delay, run in scheduled.append((delay, run)) },
                                now: { 0 }, loadChapters: { _ in [] }, music: remote,
                                optionHeld: { [unowned self] in option })
    }

    private func runScheduled(delay: TimeInterval) {
        let due = scheduled.filter { $0.delay == delay }
        scheduled.removeAll { $0.delay == delay }
        due.forEach { $0.run() }
    }

    func testOptionTurnChangesThePodcastVolumeNotThePlace() {
        player.open(episode, autoplay: false)
        let seeks = engine.seeks.count
        nowPlaying.turn(degrees: -10 * NowPlaying.degreesPerPercent)
        XCTAssertEqual(nowPlaying.volumeShown, 90)
        XCTAssertEqual(player.volume, 90)
        XCTAssertEqual(engine.volume, 0.9, accuracy: 0.001)
        XCTAssertNil(nowPlaying.scrubPosition)
        XCTAssertEqual(engine.seeks.count, seeks, "no scrub")
        XCTAssertEqual(haptics.performed, [.tick], "a tick for passing 90")
    }

    func testSmallTurnsAddUp() {
        player.open(episode, autoplay: false)
        nowPlaying.turn(degrees: -0.6 * NowPlaying.degreesPerPercent)
        nowPlaying.turn(degrees: -0.6 * NowPlaying.degreesPerPercent)
        XCTAssertEqual(player.volume, 99)
        XCTAssertTrue(haptics.performed.isEmpty)
    }

    func testTheEndsStopFirmly() {
        player.open(episode, autoplay: false)
        nowPlaying.turn(degrees: 5 * NowPlaying.degreesPerPercent)
        XCTAssertEqual(player.volume, 100, "already at the top")
        XCTAssertTrue(haptics.performed.isEmpty)
        nowPlaying.turn(degrees: -150 * NowPlaying.degreesPerPercent)
        XCTAssertEqual(player.volume, 0)
        XCTAssertEqual(haptics.performed.last, .chapter, "a firmer stop at 0")
    }

    func testTheVolumeShowsForASecondAfterTurning() {
        player.open(episode, autoplay: false)
        nowPlaying.turn(degrees: -20 * NowPlaying.degreesPerPercent)
        nowPlaying.turn(degrees: -20 * NowPlaying.degreesPerPercent)
        XCTAssertEqual(scheduled.filter { $0.delay == NowPlaying.volumeShownFor }.count, 2)
        runScheduled(delay: NowPlaying.volumeShownFor)
        XCTAssertNil(nowPlaying.volumeShown, "the latest turn's timer hides it; the older one does nothing")
        XCTAssertEqual(player.volume, 60)
    }

    func testWithoutOptionTurningStillScrubs() {
        option = false
        player.open(episode, autoplay: false)
        nowPlaying.turn(degrees: 30)
        XCTAssertNotNil(nowPlaying.scrubPosition)
        XCTAssertNil(nowPlaying.volumeShown)
        XCTAssertEqual(player.volume, 100)
    }

    func testOptionTurnSetsTheMusicAppsVolumeOnceItSettles() async {
        spotify.play("Blue Hour Drive", id: "s1")
        await remote.refresh()
        XCTAssertEqual(nowPlaying.mode, .music)
        XCTAssertEqual(remote.volume, 50)
        nowPlaying.turn(degrees: 5 * NowPlaying.degreesPerPercent)
        nowPlaying.turn(degrees: 5 * NowPlaying.degreesPerPercent)
        XCTAssertEqual(nowPlaying.volumeShown, 60)
        XCTAssertTrue(spotify.commands.isEmpty, "not one script per tick")
        runScheduled(delay: NowPlaying.commitDelay)
        await remote.lastCommand?.value
        XCTAssertEqual(spotify.commands, [.setVolume(60)])
        XCTAssertEqual(remote.volume, 60)
        XCTAssertEqual(player.volume, 100, "the podcast's own volume is untouched")
    }

    func testAPollStillReportingTheOldVolumeIsIgnoredForAMoment() async {
        spotify.play("Blue Hour Drive", id: "s1")
        await remote.refresh()
        spotify.ignoresVolume = true
        remote.setVolume(70)
        XCTAssertEqual(remote.volume, 70)
        await remote.refresh()
        XCTAssertEqual(remote.volume, 70, "Spotify can take a poll to catch up")
    }
}
