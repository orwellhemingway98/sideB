import XCTest
@testable import Spindle

final class FeedParserTests: XCTestCase {
    func testParsesShowAndEpisodes() throws {
        let feed = try FeedParser.parse(Data(SampleFeeds.longQuiet.utf8))
        XCTAssertEqual(feed.title, "The Long Quiet")
        XCTAssertEqual(feed.author, "Field Studio")
        XCTAssertEqual(feed.artworkURL, URL(string: "https://example.com/art.jpg"))
        XCTAssertEqual(feed.episodes.count, 2)
        XCTAssertEqual(feed.episodes[0].title, "Ep. 112 — Rooms & Rooms")
        XCTAssertEqual(feed.episodes[0].duration, 3120)
        XCTAssertEqual(feed.episodes[0].enclosureURL, URL(string: "https://example.com/112.mp3"))
        XCTAssertEqual(feed.episodes[0].chaptersURL, URL(string: "https://example.com/112-chapters.json"))
    }

    func testInlinePodloveChapters() throws {
        let feed = try FeedParser.parse(Data(SampleFeeds.withPSC.utf8))
        XCTAssertEqual(feed.episodes[0].inlineChapters, [Chapter(start: 0, title: "Intro"), Chapter(start: 750.5, title: "Basement tapes")])
    }

    func testMissingGuidFallsBackToEnclosureURL() throws {
        let feed = try FeedParser.parse(Data(SampleFeeds.noGuid.utf8))
        XCTAssertEqual(feed.episodes[0].guid, "https://example.com/9.mp3")
    }

    func testItemWithoutEnclosureIsSkipped() throws {
        XCTAssertEqual(try FeedParser.parse(Data(SampleFeeds.oneWithoutEnclosure.utf8)).episodes.count, 1)
    }

    func testNotAFeedThrows() {
        XCTAssertThrowsError(try FeedParser.parse(Data("<html><body>hi</body></html>".utf8))) { XCTAssertEqual($0 as? FeedError, .notAFeed) }
    }
}
