import XCTest
@testable import Spindle

@MainActor
final class PodcastPlayerTests: XCTestCase {
    private var engine: FakeEngine!
    private var library: LibraryStore!
    private var player: PodcastPlayer!
    private var a: Episode!
    private var b: Episode!
    private var c: Episode!
    private var d: Episode!

    override func setUp() async throws {
        let feed = URL(string: "https://example.com/feed")!
        let other = URL(string: "https://example.com/other")!
        let fetcher = StubFetcher(responses: [feed: .success(SampleFeeds.longQuietThreeItems),
                                              other: .success(SampleFeeds.withPSC)])
        library = LibraryStore.inMemory(fetcher: fetcher)
        let show = try await library.follow(feedURL: feed)
        let episodes = library.episodes(of: show)
        a = episodes[0]
        b = episodes[1]
        c = episodes[2]
        d = library.episodes(of: try await library.follow(feedURL: other))[0]
        engine = FakeEngine()
        player = PodcastPlayer(engine: engine, library: library)
    }

    func testOpenResumesThreeSecondsEarly() {
        a.position = 600
        player.open(a, autoplay: false)
        XCTAssertEqual(engine.loads.last?.time, 597)
        XCTAssertEqual(engine.loads.last?.url, a.playableURL)
        XCTAssertEqual(engine.playCount, 0)
    }

    func testSavesEveryFiveSecondsWhilePlaying() {
        player.open(a, autoplay: true)
        engine.fireTime(1); engine.fireTime(3)
        XCTAssertEqual(a.position, 0)
        engine.fireTime(6)
        XCTAssertEqual(a.position, 6)
    }

    func testPauseSavesImmediately() {
        player.open(a, autoplay: true)
        engine.fireTime(602)
        player.pause()
        XCTAssertEqual(a.position, 602)
    }

    func testSwitchingEpisodeSavesTheOldOne() {
        player.open(a, autoplay: true)
        engine.fireTime(900)
        player.open(b, autoplay: true)
        XCTAssertEqual(a.position, 900)
        XCTAssertEqual(player.episode?.guid, b.guid)
    }

    func testFinishingMarksPlayedAndPlaysNext() {
        library.enqueue(b)
        player.open(a, autoplay: true)
        let plays = engine.playCount
        engine.fireEnd()
        XCTAssertTrue(a.played)
        XCTAssertEqual(a.position, 0)
        XCTAssertEqual(player.episode?.guid, b.guid)
        XCTAssertEqual(engine.playCount, plays + 1)
    }

    func testOfflineKeepsPlaceAndSaysSo() {
        player.open(a, autoplay: true)
        engine.fireFailure(URLError(.notConnectedToInternet))
        XCTAssertEqual(player.failure, "Offline")
        XCTAssertEqual(player.episode?.guid, a.guid)
    }

    func testDeadLinkSkipsToNext() {
        library.enqueue(b)
        player.open(a, autoplay: true)
        engine.fireFailure(URLError(.fileDoesNotExist))
        XCTAssertEqual(player.failure, "Unavailable")
        XCTAssertEqual(player.episode?.guid, b.guid)
        engine.fireTime(1)
        XCTAssertNil(player.failure)
    }

    func testPlayAfterOfflineReloadsAtTheSavedPlace() {
        player.open(a, autoplay: true)
        engine.fireTime(700)
        engine.fireFailure(URLError(.notConnectedToInternet))
        player.play()
        XCTAssertEqual(engine.loads.last?.time, 697)
        XCTAssertEqual(engine.loads.count, 2)
        XCTAssertNil(player.failure)
    }

    func testCycleRateSetsEngineRate() {
        player.open(a, autoplay: false)
        player.cycleRate(); player.cycleRate()
        XCTAssertEqual(engine.rate, 1.5)
        XCTAssertEqual(player.rate, 1.5)
    }

    func testDuplicateFailureSkipsOnlyOnce() {
        library.enqueue(b); library.enqueue(c)
        player.open(a, autoplay: true)
        engine.fireFailure(URLError(.fileDoesNotExist), ofLoad: 0)
        engine.fireFailure(URLError(.fileDoesNotExist), ofLoad: 0)  // the same dead item reporting twice
        XCTAssertEqual(player.episode?.guid, b.guid)
        XCTAssertEqual(library.upNext.count, 1)
    }

    func testReplayAfterFinishingTracksAndSaves() {
        player.open(a, autoplay: true)
        engine.fireEnd()
        player.play()
        engine.fireTime(10)
        XCTAssertEqual(player.position, 10)
        player.pause()
        XCTAssertEqual(a.position, 10)
    }

    func testReplayedEpisodeResumesWhereItWasPaused() {
        a.played = true
        a.position = 1200
        player.open(a, autoplay: false)
        XCTAssertEqual(engine.loads.last?.time, 1197)
    }

    func testUnavailableWithNothingQueuedRetriesOnPlay() {
        player.open(a, autoplay: true)
        engine.fireTime(700)
        engine.fireFailure(URLError(.fileDoesNotExist))
        XCTAssertEqual(player.failure, "Unavailable")
        XCTAssertFalse(player.isPlaying)
        player.play()
        XCTAssertEqual(engine.loads.last?.time, 697)
        XCTAssertEqual(engine.loads.count, 2)
        XCTAssertNil(player.failure)
        XCTAssertTrue(player.isPlaying)
    }

    func testConsecutiveDeadLinksSkipEach() {
        library.enqueue(b); library.enqueue(c); library.enqueue(d)
        player.open(a, autoplay: true)
        engine.fireFailure(URLError(.fileDoesNotExist))
        engine.fireFailure(URLError(.fileDoesNotExist))
        XCTAssertEqual(player.episode?.guid, c.guid)
    }

    func testRepeatOfflineFailureIsHandledOnce() {
        player.open(a, autoplay: true)
        engine.fireTime(700)
        engine.fireFailure(URLError(.notConnectedToInternet))
        engine.fireFailure(URLError(.notConnectedToInternet))
        XCTAssertEqual(engine.pauseCount, 1)
        XCTAssertEqual(player.failure, "Offline")
    }

    func testEarlyZeroTickDoesNotOverwriteResumePoint() {
        a.position = 600
        player.open(a, autoplay: true)
        XCTAssertEqual(engine.loads.last?.time, 597)
        engine.fireTime(0.5)
        player.pause()
        XCTAssertEqual(a.position, 600)
        engine.fireTime(597.5)
        engine.fireTime(603)
        XCTAssertEqual(player.position, 603)
    }
    // MARK: Final review fixes

    func testPlayingAQueuedEpisodeRemovesItFromUpNext() {
        library.enqueue(a); library.enqueue(b)
        player.open(a, autoplay: true)
        XCTAssertEqual(library.upNext.map(\.guid), [b.guid])
        engine.fireEnd()
        XCTAssertEqual(player.episode?.guid, b.guid)
        XCTAssertTrue(library.upNext.isEmpty)
    }

    func testLoadingWithoutListeningKeepsTheSavedPlace() {
        a.position = 600
        player.open(a, autoplay: false)
        engine.fireTime(597)   // the resume seek landing
        player.saveNow()
        XCTAssertEqual(a.position, 600)
        player.open(b, autoplay: false)   // switching away doesn't save it either
        XCTAssertEqual(a.position, 600)

        player.open(a, autoplay: true)
        engine.fireTime(597)
        engine.fireTime(610)
        player.saveNow()
        XCTAssertEqual(a.position, 610)
    }

    func testAnExplicitSeekCountsAsProgress() {
        a.position = 600
        player.open(a, autoplay: false)
        player.seek(to: 597)
        XCTAssertEqual(a.position, 597)
    }

    func testLastThirtySecondsMarksPlayedButKeepsPlaying() {
        engine.duration = 3600
        library.enqueue(b)
        player.open(a, autoplay: true)
        let pauses = engine.pauseCount
        engine.fireTime(3580)
        XCTAssertTrue(a.played)
        XCTAssertEqual(a.position, 0)
        XCTAssertEqual(engine.pauseCount, pauses)
        XCTAssertEqual(player.episode?.guid, a.guid)
        XCTAssertTrue(player.isPlaying)
        engine.fireTime(3590)
        player.pause()   // pausing inside the window keeps it played, at 0
        XCTAssertTrue(a.played)
        XCTAssertEqual(a.position, 0)
        player.play()
        engine.fireEnd()
        XCTAssertEqual(player.episode?.guid, b.guid)
        XCTAssertTrue(library.upNext.isEmpty)
    }

    func testSwitchingInsideTheLastThirtySecondsKeepsItPlayed() {
        engine.duration = 3600
        player.open(a, autoplay: true)
        engine.fireTime(3580)
        player.open(b, autoplay: true)
        XCTAssertTrue(a.played)
        XCTAssertEqual(a.position, 0)
    }

    func testSeekingBackOutOfTheEndUnmarksPlayed() {
        engine.duration = 3600
        player.open(a, autoplay: true)
        engine.fireTime(3580)
        XCTAssertTrue(a.played)
        player.seek(to: 3590)   // still inside the window
        XCTAssertTrue(a.played)
        XCTAssertEqual(a.position, 0)
        player.seek(to: 3000)
        XCTAssertFalse(a.played)
        XCTAssertEqual(a.position, 3000)
        engine.fireTime(3006)
        XCTAssertEqual(a.position, 3006)   // normal saving again
    }

    func testEnqueuingThePlayingEpisodeIsIgnored() {
        player.open(a, autoplay: true)
        player.enqueue(a)
        player.enqueue(b)
        XCTAssertEqual(library.upNext.map(\.guid), [b.guid])
        engine.fireEnd()
        XCTAssertEqual(player.episode?.guid, b.guid)
    }

    func testOpeningRemembersShowAndEpisode() {
        player.open(d, autoplay: false)
        XCTAssertTrue(library.lastEpisode === d)
    }
}
