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

        stub.set(feedURL, .failure(URLError(.badServerResponse)))
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

    func testLastEpisodeRoundTripsWithItsShow() async throws {
        let otherURL = URL(string: "https://example.com/other-feed")!
        let stub = StubFetcher(responses: [feedURL: .success(SampleFeeds.longQuiet),
                                           otherURL: .success(SampleFeeds.longQuiet)])
        let store = makeStore(stub)
        let first = try await store.follow(feedURL: feedURL)
        let second = try await store.follow(feedURL: otherURL)
        XCTAssertNil(store.lastEpisode)
        // Both shows carry an episode with guid lq-112.
        let wanted = store.episodes(of: second)[0]
        XCTAssertEqual(wanted.guid, store.episodes(of: first)[0].guid)
        store.rememberLastEpisode(wanted)
        XCTAssertTrue(store.lastEpisode === wanted)
        let other = store.episodes(of: first)[0]
        store.rememberLastEpisode(other)
        XCTAssertTrue(store.lastEpisode === other)
        let fresh = makeStore(StubFetcher(json: SampleFeeds.longQuiet))
        XCTAssertNil(fresh.lastEpisode)
    }

    func testFollowingWhileOfflineSaysOffline() async {
        for code in [URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost] {
            let store = makeStore(StubFetcher(error: URLError(code)))
            do {
                _ = try await store.follow(feedURL: feedURL)
                XCTFail("expected offline for \(code)")
            } catch {
                XCTAssertEqual(error as? LibraryError, .offline, "\(code)")
            }
        }
        let store = makeStore(StubFetcher(error: URLError(.badServerResponse)))
        do {
            _ = try await store.follow(feedURL: feedURL)
            XCTFail("expected invalidFeed")
        } catch {
            XCTAssertEqual(error as? LibraryError, .invalidFeed)
        }
    }

    func testParsingHappensOffTheMainActor() async throws {
        let lock = NSLock()
        var onMain: [Bool] = []
        FeedParser.parseObserver = { value in lock.withLock { onMain.append(value) } }
        defer { FeedParser.parseObserver = nil }
        let store = makeStore(StubFetcher(json: SampleFeeds.longQuiet))
        _ = try await store.follow(feedURL: feedURL)
        await store.refreshAll()
        let seen = lock.withLock { onMain }
        XCTAssertEqual(seen.count, 2, "follow and refresh each parse once")
        XCTAssertEqual(seen, [false, false], "feeds are parsed off the main thread")
    }

    // MARK: Stage 2 queries

    private let pscURL = URL(string: "https://example.com/psc")!

    private func twoShows(now: @escaping () -> Date = Date.init) async throws -> LibraryStore {
        let stub = StubFetcher(responses: [feedURL: .success(SampleFeeds.longQuietThreeItems),
                                           pscURL: .success(SampleFeeds.withPSC)])
        let store = makeStore(stub, now: now)
        _ = try await store.follow(feedURL: feedURL)
        _ = try await store.follow(feedURL: pscURL)
        return store
    }

    func testNewEpisodesAreUnplayedAcrossShowsNewestFirst() async throws {
        let store = try await twoShows()
        let all = store.newEpisodes()
        XCTAssertEqual(all.map(\.guid), ["lq-113", "lq-112", "lq-111", "psc-1"], "dated first, newest first; undated last")
        store.markPlayed(all[0])
        XCTAssertEqual(store.newEpisodes().first?.guid, "lq-112")
        XCTAssertFalse(store.newEpisodes().contains { $0.played })
    }

    func testNewEpisodesRespectsTheLimit() async throws {
        let store = try await twoShows()
        XCTAssertEqual(store.newEpisodes(limit: 2).map(\.guid), ["lq-113", "lq-112"])
    }

    func testMarkPlayedRecordsWhenAndUnplayedClearsIt() async throws {
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try await twoShows(now: { when })
        let episode = store.newEpisodes()[0]
        XCTAssertNil(episode.playedAt)
        store.markPlayed(episode)
        XCTAssertEqual(episode.playedAt, when)
        store.markUnplayed(episode)
        XCTAssertNil(episode.playedAt)
    }

    func testDownloadedListsOnlyEpisodesWhoseFileExists() async throws {
        let store = try await twoShows()
        let episodes = store.newEpisodes()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("spindle-\(UUID().uuidString).mp3")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        episodes[1].localFile = file
        episodes[2].localFile = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).mp3")
        XCTAssertEqual(store.downloaded.map(\.guid), [episodes[1].guid])
    }

    func testMoveUpNextReorders() async throws {
        let store = try await twoShows()
        let e = store.newEpisodes()
        store.enqueue(e[0]); store.enqueue(e[1]); store.enqueue(e[2])
        store.moveUpNext(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(store.upNext.map(\.guid), [e[2].guid, e[0].guid, e[1].guid])
        store.moveUpNext(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(store.upNext.map(\.guid), [e[0].guid, e[1].guid, e[2].guid])
    }

    // MARK: Stage 2 review fixes

    func testOfflineRefreshLeavesShowsAlone() async throws {
        let stub = StubFetcher(responses: [feedURL: .success(SampleFeeds.longQuiet)])
        let store = makeStore(stub)
        let show = try await store.follow(feedURL: feedURL)
        stub.set(feedURL, .failure(URLError(.notConnectedToInternet)))
        await store.refreshAll()
        XCTAssertNil(show.lastError, "offline checks fail quietly")
        XCTAssertNil(show.errorSince)
    }

    func testRefreshSendsValidatorsAndSkipsUnchangedFeeds() async throws {
        let stub = StubFetcher(responses: [feedURL: .success(SampleFeeds.longQuiet)])
        stub.setValidators(feedURL, Validators(etag: "\"v1\"", lastModified: "Thu, 29 Oct 2026 08:00:00 GMT"))
        let clock = Date(timeIntervalSince1970: 1_800_000_000)
        var now = clock
        let store = makeStore(stub, now: { now })
        let show = try await store.follow(feedURL: feedURL)
        XCTAssertEqual(show.etag, "\"v1\"")
        stub.markNotModified(feedURL)
        stub.set(feedURL, .success(SampleFeeds.longQuietThreeItems))  // would add an episode if fetched in full
        now = clock.addingTimeInterval(3600)
        await store.refreshAll()
        XCTAssertEqual(stub.validatorsSeen.last, Validators(etag: "\"v1\"", lastModified: "Thu, 29 Oct 2026 08:00:00 GMT"))
        XCTAssertEqual(store.episodes(of: show).count, 2, "a 304 leaves the episodes as they were")
        XCTAssertEqual(show.lastUpdated, now)
        XCTAssertNil(show.lastError)
    }

    func testHttpFeedTriesHttpsFirst() async throws {
        let https = URL(string: "https://legacy.example.com/rss")!
        let stub = StubFetcher(responses: [https: .success(SampleFeeds.longQuiet)])
        let store = makeStore(stub)
        let show = try await store.follow(feedURL: URL(string: "http://legacy.example.com/rss")!)
        XCTAssertEqual(show.feedURL, https)
    }
}
