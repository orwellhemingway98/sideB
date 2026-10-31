import XCTest
@testable import Spindle

@MainActor
final class DownloadManagerTests: XCTestCase {
    private let feedURL = URL(string: "https://example.com/feed")!
    private var root: URL!
    private var library: LibraryStore!
    private var session: FakeDownloadSession!
    private var episode: Episode!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("spindle-root-\(UUID().uuidString)")
        library = LibraryStore.inMemory(fetcher: StubFetcher(json: SampleFeeds.longQuiet))
        let show = try await library.follow(feedURL: feedURL)
        episode = library.episodes(of: show)[0]
        session = FakeDownloadSession()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func manager() -> DownloadManager {
        DownloadManager(library: library, session: session, root: root)
    }

    func testDownloadMovesTheFileAndMarksTheEpisode() throws {
        let downloads = manager()
        downloads.download(episode)
        XCTAssertEqual(session.requests.map(\.url), [episode.enclosureURL])
        session.requests[0].progress(0.5)
        XCTAssertEqual(downloads.state(of: episode), .downloading(0.5))
        session.requests[0].completion(.success(try FakeDownloadSession.temporaryFile()))
        let destination = EpisodeFiles.destination(for: episode, root: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(episode.localFile, destination)
        XCTAssertEqual(downloads.state(of: episode), .downloaded)
    }

    func testLocalFileIsSetOnlyWhenTheDownloadCompletes() {
        let downloads = manager()
        downloads.download(episode)
        session.requests[0].progress(0.9)
        XCTAssertNil(episode.localFile)
        let afterRelaunch = manager()
        XCTAssertEqual(afterRelaunch.state(of: episode), .none)
        XCTAssertNil(episode.localFile)
    }

    func testFailedDownloadCanBeRetried() {
        let downloads = manager()
        downloads.download(episode)
        session.requests[0].completion(.failure(URLError(.badServerResponse)))
        XCTAssertEqual(downloads.state(of: episode), .failed("Download failed. Try again."))
        XCTAssertNil(episode.localFile)
        downloads.download(episode)
        XCTAssertEqual(session.requests.count, 2, "a failed download can start again")
        XCTAssertEqual(downloads.state(of: episode), .downloading(0))
    }

    func testOfflineFailureSaysOffline() {
        let downloads = manager()
        downloads.download(episode)
        session.requests[0].completion(.failure(URLError(.notConnectedToInternet)))
        XCTAssertEqual(downloads.state(of: episode), .failed("You're offline."))
    }

    func testDownloadingTwiceStartsOnce() {
        let downloads = manager()
        downloads.download(episode)
        downloads.download(episode)
        XCTAssertEqual(session.requests.count, 1)
    }

    func testCancelStopsAndResets() {
        let downloads = manager()
        downloads.download(episode)
        downloads.cancel(episode)
        XCTAssertTrue(session.requests[0].cancelled)
        XCTAssertEqual(downloads.state(of: episode), .none)
        session.requests[0].completion(.failure(URLError(.cancelled)))
        XCTAssertEqual(downloads.state(of: episode), .none, "the cancelled task's late callback changes nothing")
    }

    func testRemoveDownloadDeletesTheFile() throws {
        let downloads = manager()
        downloads.download(episode)
        session.requests[0].completion(.success(try FakeDownloadSession.temporaryFile()))
        let file = try XCTUnwrap(episode.localFile)
        downloads.removeDownload(episode)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(episode.localFile)
        XCTAssertEqual(downloads.state(of: episode), .none)
    }

    func testDestinationIsStablePerFeedAndGuid() {
        let first = EpisodeFiles.destination(for: episode, root: root)
        XCTAssertEqual(first, EpisodeFiles.destination(for: episode, root: root))
        XCTAssertEqual(first.pathExtension, "mp3")
        XCTAssertTrue(first.path.hasPrefix(EpisodeFiles.directory(root: root).path))
        let other = library.episodes(of: episode.show!)[1]
        XCTAssertNotEqual(first, EpisodeFiles.destination(for: other, root: root))
    }

    func testHttpEnclosuresDownloadOverHttps() {
        episode.enclosureURL = URL(string: "http://media.example.com/112.mp3")!
        manager().download(episode)
        XCTAssertEqual(session.requests.first?.url, URL(string: "https://media.example.com/112.mp3")!)
    }
}
