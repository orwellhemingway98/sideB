import Combine
import XCTest
@testable import Spindle

@MainActor
final class LibraryStoreTests: XCTestCase {
    private let feedURL = URL(string: "https://example.com/feed")!

    private func makeStore(_ fetcher: StubFetcher, now: @escaping () -> Date = Date.init) -> LibraryStore {
        LibraryStore.inMemory(fetcher: fetcher, now: now)
    }

    func testFollowAddsShowWithEpisodesNewestFirst() async throws {
        let store = makeStore(StubFetcher(json: SampleFeeds.longQuiet))
        let show = try await store.follow(feedURL: feedURL)
        XCTAssertEqual(store.shows.count, 1)
        XCTAssertEqual(show.title, "The Long Quiet")
        XCTAssertEqual(store.episodes(of: show).map(\.title),
                       ["Ep. 112 — Rooms & Rooms", "Ep. 111 — The Attic"])
    }

    func testFollowingTheSameFeedTwiceKeepsOneShow() async throws {
        let store = makeStore(StubFetcher(json: SampleFeeds.longQuiet))
        let first = try await store.follow(feedURL: feedURL)
        let second = try await store.follow(feedURL: URL(string: "http://example.com/feed/")!)
        XCTAssertEqual(store.shows.count, 1)
        XCTAssertTrue(first === second)
        XCTAssertEqual(first.feedURL, feedURL)
    }

    func testFollowingSomethingThatIsNotAFeedThrows() async {
        let store = makeStore(StubFetcher(json: "<html>"))
        do {
            _ = try await store.follow(feedURL: feedURL)
            XCTFail("expected invalidFeed")
        } catch {
            XCTAssertEqual(error as? LibraryError, .invalidFeed)
        }
        XCTAssertTrue(store.shows.isEmpty)
    }

    func testRefreshAddsNewEpisodesAndKeepsPlaces() async throws {
        let stub = StubFetcher(responses: [feedURL: .success(SampleFeeds.longQuiet)])
        let store = makeStore(stub)
        let show = try await store.follow(feedURL: feedURL)
        let first = try XCTUnwrap(store.episodes(of: show).first)
        store.savePosition(600, of: first)
        stub.set(feedURL, .success(SampleFeeds.longQuietThreeItems))
        await store.refresh(show)
        let episodes = store.episodes(of: show)
        XCTAssertEqual(episodes.count, 3)
        XCTAssertEqual(episodes.first?.guid, "lq-113")
        let kept = try XCTUnwrap(episodes.first { $0.guid == first.guid })
        XCTAssertEqual(kept.position, 600)
    }

    func testFailedRefreshRecordsErrorOnceAndSuccessClearsIt() async throws {
        let stub = StubFetcher(responses: [feedURL: .success(SampleFeeds.longQuiet)])
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = makeStore(stub, now: { clock })
        let show = try await store.follow(feedURL: feedURL)

        stub.set(feedURL, .failure(URLError(.notConnectedToInternet)))
        await store.refresh(show)
        XCTAssertNotNil(show.lastError)
        let since = try XCTUnwrap(show.errorSince)

        clock = Date(timeIntervalSince1970: 2_000)
        await store.refresh(show)
        XCTAssertNotNil(show.lastError)
        XCTAssertEqual(show.errorSince, since)

        stub.set(feedURL, .success(SampleFeeds.longQuiet))
        await store.refresh(show)
        XCTAssertNil(show.lastError)
        XCTAssertNil(show.errorSince)
        XCTAssertEqual(show.lastUpdated, clock)
    }

    func testUpNextQueueOrder() async throws {
        let store = makeStore(StubFetcher(json: SampleFeeds.longQuiet))
        let show = try await store.follow(feedURL: feedURL)
        let eps = store.episodes(of: show)
        let a = eps[0], b = eps[1]
        store.enqueue(a); store.enqueue(b); store.enqueue(a)
        XCTAssertEqual(store.upNext.map(\.guid), [a.guid, b.guid])
        store.remove(fromUpNext: a)
        XCTAssertEqual(store.upNext.map(\.guid), [b.guid])
        XCTAssertEqual(store.popNext()?.guid, b.guid)
        XCTAssertNil(store.popNext())
    }

    func testMarkPlayedResetsPosition() async throws {
        let store = makeStore(StubFetcher(json: SampleFeeds.longQuiet))
        let show = try await store.follow(feedURL: feedURL)
        let ep = try XCTUnwrap(store.episodes(of: show).first)
        store.savePosition(321, of: ep)
        XCTAssertEqual(ep.position, 321)
        store.markPlayed(ep)
        XCTAssertTrue(ep.played)
        XCTAssertEqual(ep.position, 0)
    }

    func testMutationsNotifyObservers() async throws {
        let store = makeStore(StubFetcher(json: SampleFeeds.longQuiet))
        var count = 0
        let subscription = store.objectWillChange.sink { count += 1 }
        defer { subscription.cancel() }

        var before = count
        let show = try await store.follow(feedURL: feedURL)
        XCTAssertGreaterThan(count, before)

        let ep = try XCTUnwrap(store.episodes(of: show).first)
        before = count
        store.enqueue(ep)
        XCTAssertGreaterThan(count, before)

        before = count
        _ = store.popNext()
        XCTAssertGreaterThan(count, before)

        before = count
        store.savePosition(10, of: ep)
        XCTAssertGreaterThan(count, before)
    }

    func testLastEpisodeGUIDRoundTrips() {
        let store = makeStore(StubFetcher(json: SampleFeeds.longQuiet))
        XCTAssertNil(store.lastEpisodeGUID)
        store.lastEpisodeGUID = "lq-112"
        XCTAssertEqual(store.lastEpisodeGUID, "lq-112")
        let other = makeStore(StubFetcher(json: SampleFeeds.longQuiet))
        XCTAssertNil(other.lastEpisodeGUID)
    }
}
