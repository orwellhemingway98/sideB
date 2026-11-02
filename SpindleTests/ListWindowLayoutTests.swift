import AppKit
import SwiftUI
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

    /// Runs async work from a synchronous test, keeping the run loop (and so the windows) going meanwhile.
    private func wait(_ work: @escaping @MainActor () async -> Void) {
        var done = false
        Task { await work(); done = true }
        let deadline = Date().addingTimeInterval(5)
        while !done, Date() < deadline { spin(0.02) }
        XCTAssertTrue(done, "timed out")
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
        // The list is a popover the panel's width; it opens without disturbing the panel.
        for _ in 0..<15 {
            spin(0.1)
            XCTAssertEqual(list.contentSize.width, ListPlacement.width)
        }
        let popoverWindow = try XCTUnwrap(list.window)
        XCTAssertFalse(PanelClickPolicy.closesPanel(clickWindow: popoverWindow, panel: panel.window, anchor: nil,
                                                    children: panel.window.childWindows ?? []),
                       "clicks in the list don't close the panel")

        XCTAssertTrue(list.isShown)
        XCTAssertEqual(panel.window.frame, before, "opening the list leaves the panel where it was")
        list.toggle(below: panel.window)
        spin(0.6)
        panel.close()
    }

    func testSigningInToSpotifyKeepsTheListOpen() throws {
        let spotify = FakeMusicSource(.spotify)
        spotify.contextResult = .success(MusicContext(kind: .album, id: "album:AL1", title: "Night Roads",
                                                      tracks: [ContextTrack(id: "spotify:track:T1", disc: 1, number: 1,
                                                                            title: "Headlights", artist: "Northern Static",
                                                                            duration: 200)], totalCount: 1))
        spotify.contextKeyValue = "album:AL1"
        spotify.play("Headlights", id: "spotify:track:T1")
        let remote = MusicRemote(sources: [spotify], every: { _, _ in NSObject() })
        let nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                    schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] }, music: remote)
        wait { await remote.refresh() }
        XCTAssertEqual(nowPlaying.mode, .music)
        let transport = FakeTransport()
        transport.reply("/api/token", json: #"{"access_token":"A","expires_in":3600,"refresh_token":"R"}"#)
        let defaults = UserDefaults(suiteName: "ListWindowLayoutTests")!
        let account = SpotifyAccount(store: MemoryTokenStore(), transport: transport, defaults: defaults,
                                     authenticate: { url in
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "state" }?.value ?? ""
            return URL(string: "spindle://callback?code=C&state=\(state)")!
        })
        let model = ListModel(nowPlaying: nowPlaying, library: library, spotify: account)
        let list = ListWindowController(model: model, nowPlaying: nowPlaying)
        let panel = DialPanelController(nowPlaying: nowPlaying, library: library, artwork: ArtworkCache(), onLibrary: {},
                                        onCover: {}, list: model)
        panel.show(below: try XCTUnwrap(statusItem.button))
        spin(0.3)
        let parent = panel.window
        list.toggle(below: parent)
        spin(0.6)
        XCTAssertTrue(list.isShown, "the popover opened")
        guard case .spotify = model.content else { return XCTFail("got \(model.content)") }

        wait { await account.signIn(clientID: "abc") }
        spin(1.0)
        guard case .music(let context, _) = model.content else { return XCTFail("got \(model.content)") }
        XCTAssertEqual(context.title, "Night Roads")
        XCTAssertTrue(list.isShown, "the list stays open and fills in")

        account.signOut()
        spin(1.0)
        guard case .spotify = model.content else { return XCTFail("got \(model.content)") }
        XCTAssertTrue(list.isShown)
        list.toggle(below: parent)
        spin(0.6)
        panel.close()
    }

    func testTheTallestPanelFitsA1280By800Screen() {
        // A podcast with a full Up Next is the tallest the panel gets.
        for episode in library.episodes(of: library.shows[0]) { library.enqueue(episode) }
        XCTAssertEqual(library.upNext.count, 3)
        let view = NSHostingView(rootView: DialPanelView(nowPlaying: nowPlaying, library: library, artwork: ArtworkCache(),
                                                         onLibrary: {}, onPopOut: {}, onCover: {}))
        // 800 pt, less a 33 pt menu bar and the 6 pt gap, leaves 761 pt; keep a margin for the Dock.
        XCTAssertLessThanOrEqual(view.fittingSize.height, 720)
    }

    func testThePanelStaysCompact() {
        // The times, skip buttons and footer live in the disc and the cover's corners, not rows of their own.
        let view = NSHostingView(rootView: DialPanelView(nowPlaying: nowPlaying, library: library, artwork: ArtworkCache(),
                                                         onLibrary: {}, onPopOut: {}, onCover: {}))
        XCTAssertLessThanOrEqual(view.fittingSize.height, 530)
    }

    func testTheDiscHasRoomForItsHalo() {
        // The halo reaches 5 pt past the disc on each side; the panel reserves it plus breathing room,
        // so the artist line and the pills sit 22 pt from the halo's edge.
        XCTAssertEqual(DialGeometry.haloSide, DialGeometry.discSize + 10)
        XCTAssertEqual(DialPanelView.rowSpacing + DialPanelView.discBreathing, 22)
        let view = NSHostingView(rootView: DialPanelView(nowPlaying: nowPlaying, library: library, artwork: ArtworkCache(),
                                                         onLibrary: {}, onPopOut: {}, onCover: {}))
        XCTAssertGreaterThanOrEqual(view.fittingSize.height, 500, "roomier than the 479 pt it was")
    }
}

@MainActor
final class DiscTimesTests: XCTestCase {
    func testEveryTimeFitsInTheLowerCornersAtFullSize() {
        // Both times always use the same font size: no shrinking for long episodes.
        let longest = TimeFormat.remaining(9 * 3600 + 59 * 60 + 59)
        XCTAssertEqual(longest, "\u{2212}9:59:59")
        let width = (longest as NSString).size(withAttributes: [.font: DialPanelView.timeFont]).width
        XCTAssertLessThanOrEqual(width, DialPanelView.timeColumnWidth, "fits where the disc curves away")
        XCTAssertGreaterThan(DialPanelView.timeColumnWidth, 60)
    }
}

@MainActor
final class PanelProportionsTests: XCTestCase {
    func testTheCoverCornersRunParallelWithThePanels() {
        // Concentric corners: the inner radius is the outer one less the gap between them.
        XCTAssertEqual(DialPanelView.coverCornerRadius, DialPanelView.panelCornerRadius - DialPanelView.panelPadding)
        XCTAssertEqual(DialPanelView.coverCornerRadius, 14)
    }

    func testTheTitleLeadsTheArtistLine() {
        XCTAssertEqual(DialPanelView.titleSize, 16)
        XCTAssertEqual(DialPanelView.subtitleSize, 12)
    }
}
