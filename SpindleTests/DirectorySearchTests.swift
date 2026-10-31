import XCTest
@testable import Spindle

final class DirectorySearchTests: XCTestCase {
    func testTermIsPercentEscaped() {
        let url = DirectorySearch.url(for: "café crème")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "term" }?.value, "café crème")
        XCTAssertTrue(url.absoluteString.contains("term=caf%C3%A9%20cr%C3%A8me"))
    }

    func testQueryItemsComeInOrder() {
        let url = DirectorySearch.url(for: "tide")
        XCTAssertEqual(url.absoluteString, "https://itunes.apple.com/search?media=podcast&entity=podcast&limit=25&term=tide")
    }

    func testDecodesResultsAndDropsThoseWithoutFeeds() throws {
        let json = #"{"resultCount":2,"results":[{"collectionName":"Tidewater","artistName":"Salt Co","artworkUrl600":"https://e/a.jpg","feedUrl":"https://e/feed"},{"collectionName":"No Feed","artistName":"X"}]}"#
        XCTAssertEqual(try DirectorySearch.decode(Data(json.utf8)), [DirectoryResult(title: "Tidewater", author: "Salt Co", artworkURL: URL(string: "https://e/a.jpg"), feedURL: URL(string: "https://e/feed")!)])
    }

    func testDropsResultsWithoutNameAndDefaultsMissingAuthor() throws {
        let json = #"{"results":[{"feedUrl":"https://e/nameless"},{"collectionName":"Solo","feedUrl":"https://e/solo"}]}"#
        XCTAssertEqual(try DirectorySearch.decode(Data(json.utf8)), [DirectoryResult(title: "Solo", author: "", artworkURL: nil, feedURL: URL(string: "https://e/solo")!)])
    }

    func testMalformedResponseThrows() {
        XCTAssertThrowsError(try DirectorySearch.decode(Data("<html>".utf8)))
    }

    func testBlankTermSearchesNothing() async throws {
        let stub = StubFetcher(error: URLError(.badURL))
        let r = try await DirectorySearch.search("  ", fetcher: stub)
        XCTAssertEqual(r, [])
        XCTAssertTrue(stub.requested.isEmpty)
    }

    func testSearchFetchesTrimmedTermAndDecodes() async throws {
        let stub = StubFetcher(json: #"{"results":[{"collectionName":"Tidewater","artistName":"Salt Co","feedUrl":"https://e/feed"}]}"#)
        let r = try await DirectorySearch.search("  tide ", fetcher: stub)
        XCTAssertEqual(stub.requested, [DirectorySearch.url(for: "tide")])
        XCTAssertEqual(r.map(\.title), ["Tidewater"])
    }
}
