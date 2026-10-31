import XCTest
@testable import Spindle

@MainActor
final class OPMLImporterTests: XCTestCase {
    private let a = URL(string: "https://example.com/a")!
    private let b = URL(string: "https://example.com/b")!
    private let c = URL(string: "https://example.com/c")!

    func testNestedDuplicateAndInvalidOutlines() throws {
        let opml = """

        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>My podcasts</title></head>
          <body>
            <outline text="Folder">
              <outline type="rss" text="A" xmlUrl="https://example.com/a"/>
            </outline>
            <outline type="rss" text="A again" xmlUrl="https://example.com/a"/>
            <outline type="rss" text="Not a web feed" xmlUrl="ftp://example.com/x"/>
            <outline type="rss" text="B" xmlURL=" https://example.com/b "/>
            <outline text="No feed here"/>
          </body>
        </opml>
        """
        XCTAssertEqual(try OPMLImporter.feedURLs(from: Data(opml.utf8)), [a, b])
    }

    func testNotOPMLThrows() {
        XCTAssertThrowsError(try OPMLImporter.feedURLs(from: Data("<rss version=\"2.0\"/>".utf8))) {
            XCTAssertEqual($0 as? OPMLError, .notOPML)
        }
        XCTAssertThrowsError(try OPMLImporter.feedURLs(from: Data("garbage".utf8))) {
            XCTAssertEqual($0 as? OPMLError, .notOPML)
        }
    }

    func testImportCountsFollowedExistingAndFailed() async throws {
        let stub = StubFetcher(responses: [a: .success(SampleFeeds.longQuiet),
                                           b: .success(SampleFeeds.withPSC),
                                           c: .success("<html>")])
        let library = LibraryStore.inMemory(fetcher: stub)
        _ = try await library.follow(feedURL: a)
        let summary = await library.importFeeds([a, b, c])
        XCTAssertEqual(summary, ImportSummary(followed: 1, alreadyFollowed: 1, failed: 1))
        XCTAssertEqual(library.shows.count, 2)
    }
}
