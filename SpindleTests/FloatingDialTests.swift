import Combine
import XCTest
@testable import Spindle

@MainActor
final class FloatingDialTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "spindle.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    func testPlacementIsRemembered() {
        let placement = DialPlacement(defaults: defaults)
        XCTAssertFalse(placement.isPoppedOut)
        placement.isPoppedOut = true
        XCTAssertTrue(DialPlacement(defaults: defaults).isPoppedOut)
    }

    func testShowAndPutBack() async throws {
        let feed = URL(string: "https://example.com/feed")!
        let library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        let player = PodcastPlayer(engine: FakeEngine(), library: library)
        let nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                    schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] })
        let placement = DialPlacement(defaults: defaults)
        var putBack = 0
        let dial = FloatingDialController(nowPlaying: nowPlaying, placement: placement,
                                          onPutBack: { putBack += 1 }, onLibrary: {})
        XCTAssertFalse(dial.isShown)
        dial.show()
        XCTAssertTrue(dial.isShown)
        XCTAssertTrue(placement.isPoppedOut)
        dial.putBack()
        XCTAssertFalse(dial.isShown)
        XCTAssertFalse(placement.isPoppedOut)
        XCTAssertEqual(putBack, 1)
    }

    func testPoppingOutIsAnnounced() {
        // The panel's Pop out / Put back pill follows it.
        let placement = DialPlacement(defaults: defaults)
        var seen: [Bool] = []
        let watch = placement.$isPoppedOut.dropFirst().sink { seen.append($0) }
        placement.isPoppedOut = true
        placement.isPoppedOut = false
        watch.cancel()
        XCTAssertEqual(seen, [true, false])
    }

    func testTheFloatingWindowIsTheMiniPlayer() {
        let player = PodcastPlayer(engine: FakeEngine(), library: LibraryStore.inMemory(fetcher: StubFetcher(responses: [:])))
        let nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                    schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] })
        let mini = FloatingDialController(nowPlaying: nowPlaying, placement: DialPlacement(defaults: defaults),
                                          onPutBack: {}, onLibrary: {})
        XCTAssertEqual(mini.window.frame.size, MiniPlayer.size, "a capsule like the menu bar strip, grown")
        XCTAssertEqual(MiniPlayer.size, CGSize(width: 300, height: 56))
    }

    func testDraggingTheLineSeeksWhereThePointerIs() {
        XCTAssertEqual(MiniPlayer.fraction(atX: 50, width: 200), 0.25)
        XCTAssertEqual(MiniPlayer.fraction(atX: -10, width: 200), 0, "held at the start")
        XCTAssertEqual(MiniPlayer.fraction(atX: 260, width: 200), 1, "held at the end")
        XCTAssertEqual(MiniPlayer.fraction(atX: 10, width: 0), 0)
    }
}
