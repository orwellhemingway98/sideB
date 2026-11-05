import Combine
import XCTest
@testable import SideB

@MainActor
final class MiniPlayerTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "sideb.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    func testPlacementIsRemembered() {
        let placement = MiniPlacement(defaults: defaults)
        XCTAssertFalse(placement.isPoppedOut)
        placement.isPoppedOut = true
        XCTAssertTrue(MiniPlacement(defaults: defaults).isPoppedOut)
    }

    func testShowAndPutBack() async throws {
        let feed = URL(string: "https://example.com/feed")!
        let library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        let player = PodcastPlayer(engine: FakeEngine(), library: library)
        let nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                    schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] })
        let placement = MiniPlacement(defaults: defaults)
        var putBack = 0
        let mini = MiniPlayerController(nowPlaying: nowPlaying, placement: placement,
                                          onPutBack: { putBack += 1 }, onLibrary: {})
        XCTAssertFalse(mini.isShown)
        mini.show()
        XCTAssertTrue(mini.isShown)
        XCTAssertTrue(placement.isPoppedOut)
        mini.putBack()
        XCTAssertFalse(mini.isShown)
        XCTAssertFalse(placement.isPoppedOut)
        XCTAssertEqual(putBack, 1)
    }

    func testPoppingOutIsAnnounced() {
        // The panel's Pop out / Put back pill follows it.
        let placement = MiniPlacement(defaults: defaults)
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
        let mini = MiniPlayerController(nowPlaying: nowPlaying, placement: MiniPlacement(defaults: defaults),
                                          onPutBack: {}, onLibrary: {})
        let m = MiniPlayerController.shadowMargin
        XCTAssertEqual(mini.window.frame.size, CGSize(width: MiniPlayer.size.width + m.left + m.right,
                                                      height: MiniPlayer.size.height + m.top + m.bottom),
                       "the cover's frame plus clear room round it, so the glass's own shadow fades out")
        XCTAssertFalse(mini.window.hasShadow, "no window shadow tracing the square window, as in the panel")
        XCTAssertEqual(MiniPlayer.size, CGSize(width: 260, height: 260), "the panel's 240 pt cover in a 10 pt glass frame")
        XCTAssertEqual(MiniPlayer.cornerRadius, PanelView.coverCornerRadius + MiniPlayer.frameWidth,
                       "parallel corners: the cover's plus the frame")
    }

    func testAClickFlipsAndAMoveDrags() {
        let start = NSPoint(x: 100, y: 100)
        XCTAssertFalse(MiniPlayer.isDrag(from: start, to: start))
        XCTAssertFalse(MiniPlayer.isDrag(from: start, to: NSPoint(x: 102, y: 101)), "a slightly shaky click still flips")
        XCTAssertTrue(MiniPlayer.isDrag(from: start, to: NSPoint(x: 105, y: 100)))
        XCTAssertTrue(MiniPlayer.isDrag(from: start, to: NSPoint(x: 100, y: 95)))
    }

    func testClosingThePanelLeavesTheMiniPlayersCoverTurned() {
        // Each has its own flip; clicking the mini player closes the panel, and mustn't turn its own cover back.
        let library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [:]))
        let player = PodcastPlayer(engine: FakeEngine(), library: library)
        let nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                    schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] })
        let panelList = ListModel(nowPlaying: nowPlaying, library: library)
        let miniList = ListModel(nowPlaying: nowPlaying, library: library)
        let panelController = ListController(model: panelList, nowPlaying: nowPlaying)
        let miniController = ListController(model: miniList, nowPlaying: nowPlaying, followsPanel: false)
        panelList.showsList = true
        miniList.showsList = true
        NotificationCenter.default.post(name: PanelController.didClose, object: nil)
        XCTAssertFalse(panelController.isShown)
        XCTAssertTrue(miniController.isShown)
    }

    func testRightClickingAnywhereOnTheMiniPlayerOffersItsMenu() {
        let menu = MiniPlayer.menu(onPutBack: {}, onLibrary: {})
        XCTAssertEqual(menu.items.map { $0.title }, ["Put Back", "Open Library\u{2026}", "", "Quit sideB"])
        XCTAssertTrue(menu.items[2].isSeparatorItem)
    }
}
