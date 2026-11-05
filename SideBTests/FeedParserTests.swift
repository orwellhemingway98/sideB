import XCTest
@testable import SideB

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

    func testLeadingWhitespaceAndBOMAreTolerated() throws {
        for prefix in ["\n  ", "\u{FEFF}", "\u{FEFF}\n "] {
            let feed = try FeedParser.parse(Data((prefix + SampleFeeds.longQuiet).utf8))
            XCTAssertEqual(feed.title, "The Long Quiet")
        }
    }

    private func firstPublished(_ pubDate: String) throws -> Date? {
        let xml = """
        <?xml version="1.0"?><rss version="2.0"><channel><title>T</title>
        <item><title>E</title><pubDate>\(pubDate)</pubDate><enclosure url="https://example.com/a.mp3"/></item>
        </channel></rss>
        """
        return try FeedParser.parse(Data(xml.utf8)).episodes[0].published
    }

    func testCommonDateVariantsParse() throws {
        let expected = Date(timeIntervalSince1970: 1_790_841_600)   // 2026-10-01 08:00:00 UTC
        XCTAssertEqual(try firstPublished("Thu, 01 Oct 2026 08:00:00 +0000"), expected)
        XCTAssertEqual(try firstPublished("01 Oct 2026 08:00:00 +0000"), expected)
        XCTAssertEqual(try firstPublished("Thu, 01 Oct 2026 08:00:00 GMT"), expected)
        XCTAssertEqual(try firstPublished("Thu, 01 Oct 2026 08:00 +0000"), expected)
        XCTAssertEqual(try firstPublished("Thu, 01 Oct 2026 08:00:00 EST"), expected.addingTimeInterval(5 * 3600))
        XCTAssertEqual(try firstPublished("Thu, 01 Oct 2026 08:00:00 PST"), expected.addingTimeInterval(8 * 3600))
        XCTAssertNil(try firstPublished("last Thursday"))
    }

    func testAttributeURLsAreTrimmed() throws {
        let xml = """
        <?xml version="1.0"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
        xmlns:podcast="https://podcastindex.org/namespace/1.0"><channel><title>T</title>
        <itunes:image href="  https://example.com/art.jpg
        "/><itunes:image/>
        <item><title>E</title><enclosure url=" https://example.com/a.mp3 "/>
        <podcast:chapters url="
        https://example.com/c.json "/></item></channel></rss>
        """
        let feed = try FeedParser.parse(Data(xml.utf8))
        XCTAssertEqual(feed.artworkURL, URL(string: "https://example.com/art.jpg"))
        XCTAssertEqual(feed.episodes[0].enclosureURL, URL(string: "https://example.com/a.mp3"))
        XCTAssertEqual(feed.episodes[0].chaptersURL, URL(string: "https://example.com/c.json"))
    }
}
