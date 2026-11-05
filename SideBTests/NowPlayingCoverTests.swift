import AppKit
import XCTest
@testable import SideB

/// The panel changes its cover and title together, once the new cover is in.
@MainActor
final class NowPlayingCoverTests: XCTestCase {
    func testTheTitleWaitsForTheCover() async throws {
        let feed = URL(string: "https://example.com/feed")!
        let library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        let episode = library.episodes(of: try await library.follow(feedURL: feed))[0]
        let player = PodcastPlayer(engine: FakeEngine(), library: library)
        let music = FakeMusicSource(.appleMusic)
        music.stop()
        let remote = MusicRemote(sources: [music], every: { _, _ in NSObject() })
        let nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                    schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] }, music: remote)

        player.open(episode, autoplay: false)
        XCTAssertTrue(nowPlaying.coverSettled, "a podcast's cover comes from the artwork cache")
        XCTAssertEqual(nowPlaying.coverIdentity, "episode:" + episode.guid)

        let gate = DispatchSemaphore(value: 0)
        music.artworkGate = gate
        music.play("One", id: "m1")
        await remote.refresh()
        XCTAssertEqual(nowPlaying.mode, .music)
        XCTAssertFalse(nowPlaying.coverSettled, "the song's cover is still loading")
        gate.signal()
        while !nowPlaying.coverSettled { await Task.yield() }
        XCTAssertEqual(nowPlaying.coverIdentity, "song:m1")
    }
}
