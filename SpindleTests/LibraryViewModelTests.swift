import XCTest
@testable import Spindle

@MainActor
final class LibraryViewModelTests: XCTestCase {
    private let feed = URL(string: "https://example.com/feed")!

    private func makeModel(fetcher: StubFetcher) -> (LibraryViewModel, LibraryStore) {
        let library = LibraryStore.inMemory(fetcher: fetcher)
        let player = PodcastPlayer(engine: FakeEngine(), library: library)
        let nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                    schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] })
        return (LibraryViewModel(library: library, fetcher: fetcher, nowPlaying: nowPlaying), library)
    }

    func testAddByLinkRejectsNonsense() async {
        let (model, library) = makeModel(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        await model.addByLink("not a url")
        XCTAssertEqual(model.message, "That link isn't a podcast feed.")
        XCTAssertTrue(library.shows.isEmpty)
    }

    func testAddByLinkFollows() async {
        let (model, library) = makeModel(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        await model.addByLink("  https://example.com/feed \n")
        XCTAssertEqual(library.shows.count, 1)
        XCTAssertNil(model.message)
        XCTAssertEqual(model.selectedShow?.title, "The Long Quiet")
    }

    func testSearchFailureShowsMessage() async {
        let (model, _) = makeModel(fetcher: StubFetcher(error: URLError(.notConnectedToInternet)))
        model.query = "quiet"
        await model.search()
        XCTAssertEqual(model.message, "Search isn't available right now.")
        XCTAssertEqual(model.results, [])
    }

    func testFollowFromResults() async {
        let (model, library) = makeModel(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        let result = DirectoryResult(title: "The Long Quiet", author: "", artworkURL: nil, feedURL: feed)
        await model.follow(result)
        XCTAssertEqual(library.shows.count, 1)
        XCTAssertNil(model.message)
        XCTAssertEqual(model.selectedShow?.title, "The Long Quiet")
    }
}
