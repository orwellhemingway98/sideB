import AppKit
import SwiftUI
import XCTest
@testable import SideB

/// Real mouse events through a real window, so this covers the line's gesture and not just what it calls.
@MainActor
final class ProgressLineDragTests: XCTestCase {
    private var engine: FakeEngine!
    private var player: PodcastPlayer!
    private var nowPlaying: NowPlaying!
    private var window: NSWindow!
    private var baseline = 0
    private static let width: CGFloat = 240

    override func setUp() async throws {
        let feed = URL(string: "https://example.com/feed")!
        let library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        let episode = library.episodes(of: try await library.follow(feedURL: feed))[0]
        engine = FakeEngine()
        engine.duration = 1000
        player = PodcastPlayer(engine: engine, library: library)
        nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(), schedule: { _, _ in },
                                now: { 0 }, loadChapters: { _ in [] })
        player.open(episode, autoplay: false)
        engine.fireTime(100)
        player.seek(to: 100)
        baseline = engine.seeks.count
        let line = ProgressLine(nowPlaying: nowPlaying, host: .panel).frame(width: Self.width, height: 20)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 20), styleMask: .borderless,
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: line)
        window.orderFrontRegardless()
        try await settle()
    }

    override func tearDown() async throws {
        window.orderOut(nil)
        window = nil
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(150)) }

    private func send(_ type: NSEvent.EventType, x: CGFloat) async throws {
        let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 10), modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                                       pressure: type == .leftMouseUp ? 0 : 1)!
        window.sendEvent(event)
        try await settle()
    }

    private var newSeeks: [TimeInterval] { Array(engine.seeks.dropFirst(baseline)) }

    func testTheTimeFollowsTheDragAndOnlyLettingGoSeeks() async throws {
        try await send(.leftMouseDown, x: 24)
        try await send(.leftMouseDragged, x: 60)
        XCTAssertEqual(nowPlaying.displayPosition, 250, accuracy: 1)
        try await send(.leftMouseDragged, x: 120)
        XCTAssertEqual(nowPlaying.displayPosition, 500, accuracy: 1)
        XCTAssertTrue(newSeeks.isEmpty)
        try await send(.leftMouseUp, x: 120)
        XCTAssertEqual(newSeeks.count, 1)
        XCTAssertEqual(newSeeks.first ?? 0, 500, accuracy: 1)
        XCTAssertEqual(nowPlaying.displayPosition, 500, accuracy: 1)
    }

    func testThePanelClosingMidDragGoesBackToTheRealPlace() async throws {
        try await send(.leftMouseDown, x: 24)
        try await send(.leftMouseDragged, x: 120)
        XCTAssertEqual(nowPlaying.displayPosition, 500, accuracy: 1)
        NotificationCenter.default.post(name: PanelController.didClose, object: nil)
        window.orderOut(nil)
        try await settle()
        XCTAssertEqual(nowPlaying.displayPosition, 100)
        try await send(.leftMouseUp, x: 120)    // the mouse-up that comes after, on the closed panel
        XCTAssertEqual(nowPlaying.displayPosition, 100)
        XCTAssertTrue(newSeeks.isEmpty)
    }

    func testTheLineGoingAwayMidDragGoesBackToTheRealPlace() async throws {
        try await send(.leftMouseDown, x: 24)
        try await send(.leftMouseDragged, x: 120)
        window.contentView = nil
        try await settle()
        XCTAssertEqual(nowPlaying.displayPosition, 100)
        XCTAssertTrue(newSeeks.isEmpty)
    }

    func testAStrayClickDoesNothing() async throws {
        try await send(.leftMouseDown, x: 120)
        try await send(.leftMouseUp, x: 120)
        XCTAssertTrue(newSeeks.isEmpty)
        XCTAssertEqual(nowPlaying.displayPosition, 100)
    }
}
