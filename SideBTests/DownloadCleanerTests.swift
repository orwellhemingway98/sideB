import XCTest
@testable import SideB

@MainActor
final class DownloadCleanerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 3600
    private var episodes: [Episode] = []
    private var library: LibraryStore!

    override func setUp() async throws {
        library = LibraryStore.inMemory(fetcher: StubFetcher(json: SampleFeeds.longQuietThreeItems))
        let show = try await library.follow(feedURL: URL(string: "https://example.com/feed")!)
        episodes = library.episodes(of: show)
        for episode in episodes { episode.localFile = URL(fileURLWithPath: "/tmp/\(episode.guid).mp3") }
    }

    private func played(_ episode: Episode, daysAgo: Double) {
        episode.played = true
        episode.playedAt = now.addingTimeInterval(-daysAgo * day)
    }

    private func purge(excluding current: Episode? = nil) -> [String] {
        var removed: [String] = []
        DownloadCleaner.purge(episodes, now: now, excluding: current) { removed.append($0.guid) }
        return removed
    }

    func testRemovesDownloadsPlayedMoreThanSevenDaysAgo() {
        played(episodes[0], daysAgo: 8)
        played(episodes[1], daysAgo: 6)
        XCTAssertEqual(purge(), [episodes[0].guid], "6 days ago is kept, and unplayed episodes are kept")
    }

    func testCleanupSkipsTheEpisodePlayingNow() {
        played(episodes[0], daysAgo: 30)
        XCTAssertEqual(purge(excluding: episodes[0]), [])
    }

    func testExactlySevenDaysIsRemoved() {
        played(episodes[0], daysAgo: 7)
        XCTAssertEqual(purge(), [episodes[0].guid])
    }

    func testEpisodesWithoutADownloadAreLeftAlone() {
        played(episodes[0], daysAgo: 30)
        episodes[0].localFile = nil
        XCTAssertEqual(purge(), [])
    }
}
