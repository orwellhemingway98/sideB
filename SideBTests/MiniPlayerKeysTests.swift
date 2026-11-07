import AppKit
import XCTest
@testable import SideB

/// Once clicked, the mini player answers the panel's keys.
@MainActor
final class MiniPlayerKeysTests: XCTestCase {
    private var engine: FakeEngine!
    private var player: PodcastPlayer!
    private var nowPlaying: NowPlaying!
    private var list: ListModel!
    private var mini: MiniPlayerController!
    private var library: LibraryStore!
    private var opened = 0
    private var suite: String!

    override func setUp() async throws {
        let feed = URL(string: "https://example.com/feed")!
        library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        let episode = library.episodes(of: try await library.follow(feedURL: feed))[0]
        engine = FakeEngine()
        engine.duration = 3120
        player = PodcastPlayer(engine: engine, library: library)
        nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(), schedule: { _, _ in },
                                now: { 0 }, loadChapters: { _ in [] })
        player.open(episode, autoplay: false)
        engine.fireTime(100)
        list = ListModel(nowPlaying: nowPlaying, library: library)
        opened = 0
        suite = "sideb.tests.\(UUID().uuidString)"
        mini = MiniPlayerController(nowPlaying: nowPlaying, placement: MiniPlacement(defaults: UserDefaults(suiteName: suite)!),
                                    onPutBack: {}, onLibrary: { [unowned self] in self.opened += 1 }, list: list)
    }

    override func tearDown() {
        mini.putBack()
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    func testItCanTakeKeys() {
        XCTAssertTrue(mini.window.canBecomeKey)
        XCTAssertFalse(mini.window.canBecomeMain)
    }

    func testSpacePlaysAndPauses() {
        XCTAssertFalse(player.isPlaying)
        mini.press(.playPause)
        XCTAssertTrue(player.isPlaying)
    }

    func testTheArrowsSkip() {
        mini.press(.forward)
        XCTAssertEqual(engine.seeks.last, 130)
        mini.press(.back)
        XCTAssertEqual(engine.seeks.last, 115)
    }

    func testReturnTurnsTheCover() {
        mini.press(.turnCover)
        XCTAssertTrue(list.showsList)
    }

    func testCommandLOpensTheLibrary() {
        mini.press(.library)
        XCTAssertEqual(opened, 1)
    }

    func testEscapeTurnsTheCoverBackAndOtherwiseLeavesItUp() {
        mini.show()
        mini.press(.turnCover)
        mini.press(.escape)
        XCTAssertFalse(list.showsList)
        mini.press(.escape)
        XCTAssertTrue(mini.isShown)
    }

    func testARealKeyPressReachesIt() throws {
        mini.show()
        let space = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: mini.window.windowNumber, context: nil,
                                                   characters: " ", charactersIgnoringModifiers: " ",
                                                   isARepeat: false, keyCode: 49))
        NSApp.sendEvent(space)
        XCTAssertTrue(player.isPlaying)
    }

    func testAPutBackMiniPlayerStopsListening() throws {
        mini.show()
        mini.putBack()
        let space = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: mini.window.windowNumber, context: nil,
                                                   characters: " ", charactersIgnoringModifiers: " ",
                                                   isARepeat: false, keyCode: 49))
        NSApp.sendEvent(space)
        XCTAssertFalse(player.isPlaying)
    }

    func testNotesSitClearOfWhatsThere() {
        let rest = MiniPlayer.noteLift(hovering: false, showsList: false)
        let controls = MiniPlayer.noteLift(hovering: true, showsList: false)
        let back = MiniPlayer.noteLift(hovering: true, showsList: true)
        XCTAssertGreaterThan(controls, rest, "above the title and controls")
        XCTAssertGreaterThan(back, rest, "above the Cover pill")
        XCTAssertEqual(MiniPlayer.noteLift(hovering: false, showsList: true), back)
    }
}
