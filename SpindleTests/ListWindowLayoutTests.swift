import AppKit
import XCTest
@testable import Spindle

/// Opens the real panel and list windows, the way a click on the cover does, and lets AppKit lay them out.
@MainActor
final class ListWindowLayoutTests: XCTestCase {
    private var library: LibraryStore!
    private var player: PodcastPlayer!
    private var nowPlaying: NowPlaying!
    private var statusItem: NSStatusItem!

    override func setUp() async throws {
        let feed = URL(string: "https://example.com/feed")!
        library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuietThreeItems)]))
        let show = try await library.follow(feedURL: feed)
        player = PodcastPlayer(engine: FakeEngine(), library: library)
        let music = FakeMusicSource(.appleMusic)
        music.stop()
        nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] },
                                music: MusicRemote(sources: [music], every: { _, _ in NSObject() }))
        player.open(library.episodes(of: show)[0], autoplay: false)
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
    }

    override func tearDown() async throws {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testOpeningTheListFromTheCoverLaysOutCleanly() throws {
        let model = ListModel(nowPlaying: nowPlaying, library: library)
        let list = ListWindowController(model: model, nowPlaying: nowPlaying)
        var panel: DialPanelController!
        panel = DialPanelController(nowPlaying: nowPlaying, library: library, artwork: ArtworkCache(), onLibrary: {},
                                    onCover: { list.toggle(below: panel.window) }, list: model)
        panel.show(below: try XCTUnwrap(statusItem.button))
        spin(0.3)
        let before = panel.window.frame

        list.toggle(below: panel.window)
        // The droplet's spring runs inside a window of fixed size: SwiftUI must not resize the window to follow
        // it (each resize asked for another layout pass mid-layout, until AppKit gave up and threw).
        for _ in 0..<15 {
            spin(0.1)
            XCTAssertEqual(list.frame.width, ListPlacement.width)
        }

        XCTAssertTrue(list.isShown)
        XCTAssertEqual(panel.window.frame, before, "opening the list leaves the panel where it was")
        list.toggle(below: panel.window)
        spin(0.6)
        panel.close()
    }
}
