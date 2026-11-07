import AppKit
import SwiftUI
import XCTest
@testable import SideB

/// Up Next is the podcast queue, so it belongs under a podcast. Under a song it would read as what plays next.
@MainActor
final class PanelUpNextTests: XCTestCase {
    private var library: LibraryStore!
    private var nowPlaying: NowPlaying!
    private var player: PodcastPlayer!
    private var spotify: FakeMusicSource!
    private var remote: MusicRemote!
    private var episodes: [Episode] = []

    override func setUp() async throws {
        let feed = URL(string: "https://example.com/feed")!
        library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        episodes = library.episodes(of: try await library.follow(feedURL: feed))
        player = PodcastPlayer(engine: FakeEngine(), library: library)
        spotify = FakeMusicSource(.spotify)
        spotify.stop()
        remote = MusicRemote(sources: [spotify], every: { _, _ in NSObject() })
        nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] }, music: remote)
    }

    private var height: CGFloat {
        let view = PanelView(nowPlaying: nowPlaying, library: library, artwork: ArtworkCache(), onLibrary: {})
        return NSHostingView(rootView: view).fittingSize.height
    }

    func testAPodcastShowsItsQueue() {
        player.open(episodes[0], autoplay: false)
        let before = height
        library.enqueue(episodes[1])
        XCTAssertGreaterThan(height, before)
    }

    func testASongDoesNotShowThePodcastQueue() async {
        spotify.play("Japan", id: "s1")
        await remote.refresh()
        XCTAssertEqual(nowPlaying.mode, .music)
        let before = height
        library.enqueue(episodes[1])
        XCTAssertEqual(height, before)
    }
}
