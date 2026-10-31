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

    // MARK: Stage 2

    func testImportSummaryText() {
        XCTAssertEqual(LibraryViewModel.importSummaryText(ImportSummary(followed: 3, alreadyFollowed: 1, failed: 1)),
                       "Followed 3 shows \u{00B7} 1 already followed \u{00B7} 1 couldn't be added")
        XCTAssertEqual(LibraryViewModel.importSummaryText(ImportSummary(followed: 1)), "Followed 1 show")
        XCTAssertEqual(LibraryViewModel.importSummaryText(ImportSummary(alreadyFollowed: 2)), "2 already followed")
        XCTAssertEqual(LibraryViewModel.importSummaryText(ImportSummary()), "No shows found in that file.")
    }

    func testImportingNotOPMLSaysSo() async {
        let (model, library) = makeModel(fetcher: StubFetcher(responses: [:]))
        await model.importOPML(Data("<rss/>".utf8))
        XCTAssertEqual(model.importMessage, "That file isn't an OPML list of podcasts.")
        XCTAssertTrue(library.shows.isEmpty)
    }

    func testImportingFollowsShows() async {
        let other = URL(string: "https://example.com/other")!
        let fetcher = StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet), other: .success(SampleFeeds.withPSC)])
        let (model, library) = makeModel(fetcher: fetcher)
        let opml = #"<opml version="2.0"><body><outline xmlUrl="https://example.com/feed"/><outline xmlUrl="https://example.com/other"/></body></opml>"#
        await model.importOPML(Data(opml.utf8))
        XCTAssertEqual(library.shows.count, 2)
        XCTAssertEqual(model.importMessage, "Followed 2 shows")
    }

    func testFollowingSelectsTheShowSection() async {
        let (model, library) = makeModel(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuiet)]))
        XCTAssertEqual(model.section, .newEpisodes)
        await model.addByLink("https://example.com/feed")
        XCTAssertEqual(model.section, .show(library.shows[0].persistentModelID))
    }

    func testImportShowsProgressAndIgnoresASecondRequest() async {
        let gate = GateFetcher()
        let library = LibraryStore.inMemory(fetcher: gate)
        let player = PodcastPlayer(engine: FakeEngine(), library: library)
        let nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                    schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] })
        let model = LibraryViewModel(library: library, fetcher: gate, nowPlaying: nowPlaying)
        let opml = Data(#"<opml><body><outline xmlUrl="https://example.com/feed"/></body></opml>"#.utf8)
        let first = Task { await model.importOPML(opml) }
        while !gate.isWaiting { await Task.yield() }
        XCTAssertTrue(model.isImporting)
        await model.importOPML(opml)            // ignored while the first runs
        XCTAssertEqual(gate.requestCount, 1)
        gate.release(with: SampleFeeds.longQuiet)
        await first.value
        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.importMessage, "Followed 1 show")
    }
}

/// Holds the first request until the test releases it.
private final class GateFetcher: HTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Never>?
    private var count = 0
    var isWaiting: Bool { lock.withLock { continuation != nil } }
    var requestCount: Int { lock.withLock { count } }

    func data(from url: URL) async throws -> Data {
        await withCheckedContinuation { continuation in
            lock.withLock { count += 1; self.continuation = continuation }
        }
    }

    func release(with text: String) {
        lock.withLock { continuation }?.resume(returning: Data(text.utf8))
    }
}
