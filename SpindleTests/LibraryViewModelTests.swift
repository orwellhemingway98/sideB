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
        XCTAssertEqual(model.linkMessage, "That link isn't a podcast feed.")
        XCTAssertNil(model.searchMessage)
        XCTAssertTrue(library.shows.isEmpty)
    }

    func testAddByLinkFollows() async {
        let (model, library) = makeModel(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        await model.addByLink("  https://example.com/feed \n")
        XCTAssertEqual(library.shows.count, 1)
        XCTAssertNil(model.linkMessage)
        XCTAssertEqual(model.selectedShow?.title, "The Long Quiet")
    }

    func testSearchFailureShowsMessage() async {
        let searchURL = DirectorySearch.url(for: "quiet")
        let json = #"{"results":[{"collectionName":"The Long Quiet","artistName":"A","feedUrl":"https://example.com/feed"}]}"#
        let fetcher = StubFetcher(responses: [searchURL: .success(json)])
        let (model, _) = makeModel(fetcher: fetcher)
        model.query = "quiet"
        await model.search()
        XCTAssertEqual(model.results.count, 1)
        XCTAssertNil(model.searchMessage)

        fetcher.set(searchURL, .failure(URLError(.notConnectedToInternet)))
        await model.search()
        XCTAssertEqual(model.searchMessage, "Search isn't available right now.")
        XCTAssertEqual(model.results, [])
        XCTAssertNil(model.linkMessage)
    }

    func testFollowFromResults() async {
        let (model, library) = makeModel(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        let result = DirectoryResult(title: "The Long Quiet", author: "", artworkURL: nil, feedURL: feed)
        await model.follow(result)
        XCTAssertEqual(library.shows.count, 1)
        XCTAssertNil(model.searchMessage)
        XCTAssertEqual(model.selectedShow?.title, "The Long Quiet")
    }

    func testFollowFromResultsFailureSaysSo() async {
        let (model, library) = makeModel(fetcher: StubFetcher(responses: [feed: .failure(URLError(.badServerResponse))]))
        let result = DirectoryResult(title: "The Long Quiet", author: "", artworkURL: nil, feedURL: feed)
        await model.follow(result)
        XCTAssertEqual(model.searchMessage, "Couldn't follow that show.")
        XCTAssertNil(model.linkMessage)
        XCTAssertTrue(library.shows.isEmpty)
        XCTAssertNil(model.selectedShow)
    }
    func testAddByLinkWhileOfflineSaysOffline() async {
        let (model, library) = makeModel(fetcher: StubFetcher(responses: [feed: .failure(URLError(.notConnectedToInternet))]))
        await model.addByLink("https://example.com/feed")
        XCTAssertEqual(model.linkMessage, "You're offline. Try again when you're connected.")
        XCTAssertNil(model.searchMessage)
        XCTAssertTrue(library.shows.isEmpty)
    }

    func testFollowFromResultsWhileOfflineSaysOffline() async {
        let (model, _) = makeModel(fetcher: StubFetcher(responses: [feed: .failure(URLError(.timedOut))]))
        let result = DirectoryResult(title: "The Long Quiet", author: "", artworkURL: nil, feedURL: feed)
        await model.follow(result)
        XCTAssertEqual(model.searchMessage, "You're offline. Try again when you're connected.")
        XCTAssertNil(model.linkMessage)
    }
}
