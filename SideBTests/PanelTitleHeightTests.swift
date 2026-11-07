import AppKit
import SwiftUI
import XCTest
@testable import SideB

/// The playback buttons stay put from song to song, so a click on Next can't miss because a title wrapped.
@MainActor
final class PanelTitleHeightTests: XCTestCase {
    private func panelHeight(title: String) async throws -> CGFloat {
        let library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [:]))
        let player = PodcastPlayer(engine: FakeEngine(), library: library)
        let spotify = FakeMusicSource(.spotify)
        spotify.stop()
        let remote = MusicRemote(sources: [spotify], every: { _, _ in NSObject() })
        let nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                    schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] }, music: remote)
        spotify.play(title, id: "s1", position: 30)
        await remote.refresh()
        XCTAssertEqual(nowPlaying.display?.title, title)
        let view = PanelView(nowPlaying: nowPlaying, library: library, artwork: ArtworkCache(), onLibrary: {})
        return NSHostingView(rootView: view).fittingSize.height
    }

    func testAOneLineTitleTakesTheSameHeightAsATwoLineOne() async throws {
        let oneLine = try await panelHeight(title: "Japan")
        let twoLines = try await panelHeight(title: "Chemtrails Over the Country Club")
        XCTAssertEqual(oneLine, twoLines)
    }

    func testATitleTooLongForTwoLinesTakesTheSameHeightToo() async throws {
        let twoLines = try await panelHeight(title: "Chemtrails Over the Country Club")
        let tooLong = try await panelHeight(title: "A Song With Quite a Long Name That Runs On Over Two Lines and Then Some More After That")
        XCTAssertEqual(twoLines, tooLong)
    }
}
