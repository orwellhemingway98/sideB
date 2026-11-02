import XCTest
@testable import Spindle

@MainActor
final class NowPlayingTests: XCTestCase {
    private var engine: FakeEngine!
    private var player: PodcastPlayer!
    private var media: FakeMediaCenter!
    private var haptics: FakeHaptics!
    private var nowPlaying: NowPlaying!
    private var episode: Episode!
    private var scheduled: [(delay: TimeInterval, run: @MainActor () -> Void)] = []
    private var time: TimeInterval = 0
    private var baseline = 0
    private var chaptersToLoad: [Chapter] = []

    override func setUp() async throws {
        let feed = URL(string: "https://example.com/feed")!
        let library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        let show = try await library.follow(feedURL: feed)
        episode = library.episodes(of: show)[0]
        engine = FakeEngine()
        engine.duration = 3120
        player = PodcastPlayer(engine: engine, library: library)
        media = FakeMediaCenter()
        haptics = FakeHaptics()
        scheduled = []
        time = 0
        chaptersToLoad = []
        baseline = 0
        nowPlaying = NowPlaying(player: player, media: media, haptics: haptics,
                                schedule: { [unowned self] delay, run in scheduled.append((delay, run)) },
                                now: { [unowned self] in time },
                                loadChapters: { [unowned self] _ in chaptersToLoad })
    }

    /// Opens the episode paused and brings the player to `position`.
    private func open(at position: TimeInterval) {
        player.open(episode, autoplay: false)
        engine.fireTime(position)
        player.seek(to: position)
        baseline = engine.seeks.count
    }

    private var newSeeks: [TimeInterval] { Array(engine.seeks.dropFirst(baseline)) }

    private func waitForChapters() async {
        for _ in 0..<100 where nowPlaying.chapters.isEmpty { await Task.yield() }
    }

    func testTurningPreviewsThenCommitsAfterQuiet() {
        open(at: 600)
        nowPlaying.turn(degrees: 30)
        XCTAssertEqual(nowPlaying.scrubPosition, 610)
        XCTAssertEqual(nowPlaying.displayPosition, 610)
        XCTAssertTrue(newSeeks.isEmpty)
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled[0].delay, 0.15)
        scheduled[0].run()
        XCTAssertEqual(newSeeks, [610])
        XCTAssertNil(nowPlaying.scrubPosition)
    }

    func testANewTurnPostponesTheCommit() {
        open(at: 600)
        nowPlaying.turn(degrees: 30)
        nowPlaying.turn(degrees: 30)
        let summed = nowPlaying.scrubPosition!
        XCTAssertGreaterThan(summed, 610)
        scheduled[0].run()
        XCTAssertTrue(newSeeks.isEmpty)
        scheduled[1].run()
        XCTAssertEqual(newSeeks, [summed])
    }

    func testTicksAndChaptersReachTheHaptics() async {
        chaptersToLoad = [Chapter(start: 22, title: "Basement tapes")]
        open(at: 14)
        await waitForChapters()
        XCTAssertEqual(nowPlaying.chapters.count, 1)
        time = 0
        nowPlaying.turn(degrees: 54)   // 14 -> 41, crosses 15, 22 (chapter), 30
        XCTAssertEqual(haptics.performed, [.chapter])
        time = 0.04
        nowPlaying.turn(degrees: 15)   // -> ~50.6, crosses 45 only
        XCTAssertEqual(haptics.performed, [.chapter, .tick])
    }

    func testJumpCommitsImmediately() {
        open(at: 600)
        nowPlaying.jump(to: 1200)
        XCTAssertEqual(newSeeks, [1200])
        XCTAssertTrue(scheduled.isEmpty)
        XCTAssertNil(nowPlaying.scrubPosition)
    }

    func testCurrentChapter() async {
        chaptersToLoad = [Chapter(start: 0, title: "Intro"), Chapter(start: 750, title: "Tapes")]
        open(at: 800)
        await waitForChapters()
        XCTAssertEqual(nowPlaying.currentChapter?.title, "Tapes")
    }

    func testMediaCommandsDriveThePlayer() {
        open(at: 600)
        media.onCommand?(.skip(-15))
        XCTAssertEqual(engine.seeks.last, 585)
        XCTAssertFalse(player.isPlaying)
        media.onCommand?(.toggle)
        XCTAssertTrue(player.isPlaying)
        media.onCommand?(.toggle)
        XCTAssertFalse(player.isPlaying)
    }

    func testPublishesNowPlaying() {
        nowPlaying.play(episode)
        XCTAssertEqual(media.published.last??.title, "Ep. 112 — Rooms & Rooms")
        XCTAssertEqual(media.published.last??.isPlaying, true)
        nowPlaying.toggle()
        XCTAssertEqual(media.published.last??.isPlaying, false)
    }

    func testSkipDuringScrubWins() {
        open(at: 600)
        nowPlaying.turn(degrees: 30)
        XCTAssertEqual(nowPlaying.scrubPosition, 610)
        nowPlaying.skip(by: -15)
        XCTAssertEqual(newSeeks, [595])
        XCTAssertNil(nowPlaying.scrubPosition)
        scheduled[0].run()
        XCTAssertEqual(newSeeks, [595])
    }

    func testBackAndForwardSkipThePodcast() {
        open(at: 600)
        nowPlaying.back()
        nowPlaying.forward()
        XCTAssertEqual(newSeeks, [585, 615], "back 15 s, then forward 30 s")
    }

    func testSkipStartsFromTheScrubPosition() {
        open(at: 600)
        nowPlaying.turn(degrees: 30)
        nowPlaying.skip(by: 30)
        XCTAssertEqual(newSeeks, [640])
    }

    func testNothingOpenPublishesNil() {
        nowPlaying.play(episode)
        nowPlaying.episodeChanged(nil)
        guard case .some(let last) = media.published.last else { return XCTFail("nothing published") }
        XCTAssertNil(last)
    }

    func testUnsupportedRateIsIgnored() {
        open(at: 600)
        let published = media.published.count
        media.onCommand?(.rate(1.3))
        XCTAssertEqual(player.rate, 1)
        XCTAssertEqual(engine.rate, 1)
        XCTAssertEqual(media.published.count, published)
        media.onCommand?(.rate(1.5))
        XCTAssertEqual(player.rate, 1.5)
    }

    func testHapticsAreRateLimitedAcrossTurns() {
        open(at: 12)
        time = 0
        nowPlaying.turn(degrees: 15)   // 12 -> 17, crosses 15
        XCTAssertEqual(haptics.performed, [.tick])
        time = 0.02
        nowPlaying.turn(degrees: 60)   // fast: still crosses ticks, but 20 ms is too soon
        XCTAssertEqual(haptics.performed, [.tick])
        XCTAssertGreaterThan(nowPlaying.scrubPosition!, 37)   // the dial remembers the first turn's speed
    }
    // MARK: Final review fixes

    func testTogglingCommitsAPendingScrub() {
        open(at: 600)
        nowPlaying.turn(degrees: 30)
        XCTAssertEqual(nowPlaying.scrubPosition, 610)
        let plays = engine.playCount
        nowPlaying.toggle()
        XCTAssertEqual(newSeeks, [610])
        XCTAssertEqual(player.position, 610)
        XCTAssertEqual(engine.playCount, plays + 1)
        XCTAssertNil(nowPlaying.scrubPosition)
        scheduled[0].run()
        XCTAssertEqual(newSeeks, [610])
    }

    func testPlayingAnEpisodeCommitsAPendingScrubFirst() {
        open(at: 600)
        nowPlaying.turn(degrees: 30)
        nowPlaying.play(episode)
        XCTAssertEqual(newSeeks, [610])
        XCTAssertEqual(episode.position, 610)
        scheduled[0].run()
        XCTAssertEqual(newSeeks, [610])
    }

    func testFlushScrubOnQuitSavesTheScrubbedPlace() {
        open(at: 600)
        nowPlaying.turn(degrees: 30)
        nowPlaying.flushScrub()
        player.saveNow()
        XCTAssertEqual(episode.position, 610)
        XCTAssertNil(nowPlaying.scrubPosition)
        scheduled[0].run()
        XCTAssertEqual(newSeeks, [610])
    }

    func testDurationIsRepublishedWhenTheStreamReportsIt() {
        engine.duration = nil
        episode.duration = nil
        nowPlaying.play(episode)
        XCTAssertNil(media.published.last??.duration)
        engine.duration = 1800
        engine.fireTime(1)
        XCTAssertEqual(media.published.last??.duration, 1800)
        let count = media.published.count
        engine.fireTime(2)
        XCTAssertEqual(media.published.count, count)   // only when it first becomes known
    }
}
