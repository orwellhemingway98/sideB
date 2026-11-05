import XCTest
@testable import SideB

final class ChapterLoaderTests: XCTestCase {
    func testDecodesPodcastChaptersJSON() throws {
        let json = #"{"version":"1.2.0","chapters":[{"startTime":750.5,"title":"Basement tapes"},{"startTime":0,"title":"Intro"},{"startTime":900}]}"#
        XCTAssertEqual(try ChapterLoader.decodeJSON(Data(json.utf8)), [Chapter(start: 0, title: "Intro"), Chapter(start: 750.5, title: "Basement tapes")])
    }

    func testJSONWinsOverInlineAndAudio() async {
        let got = await ChapterLoader.load(chaptersURL: URL(string: "https://x/c.json"), inline: [Chapter(start: 0, title: "inline")],
                                           audioChapters: { [Chapter(start: 0, title: "audio")] }, fetcher: StubFetcher(json: #"{"chapters":[{"startTime":0,"title":"json"}]}"#))
        XCTAssertEqual(got.map(\.title), ["json"])
    }

    func testFailingJSONFallsToInline() async {
        let got = await ChapterLoader.load(chaptersURL: URL(string: "https://x/c.json"), inline: [Chapter(start: 0, title: "inline")],
                                           audioChapters: { [] }, fetcher: StubFetcher(error: URLError(.notConnectedToInternet)))
        XCTAssertEqual(got.map(\.title), ["inline"])
    }

    func testFallsThroughToAudioFile() async {
        let got = await ChapterLoader.load(chaptersURL: nil, inline: [], audioChapters: { [Chapter(start: 0, title: "audio")] }, fetcher: StubFetcher(json: "{}"))
        XCTAssertEqual(got.map(\.title), ["audio"])
    }
}
