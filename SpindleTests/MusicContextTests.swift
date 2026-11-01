import XCTest
@testable import Spindle

final class MusicContextTests: XCTestCase {
    private let fs = "\u{1F}", rs = "\u{1E}"

    private func output(_ header: [String], _ rows: [[String]]) -> String {
        ([header] + rows).map { $0.joined(separator: fs) }.joined(separator: rs)
    }

    private func row(_ id: String, disc: Int, number: Int, _ title: String) -> [String] {
        [id, String(disc), String(number), title, "Northern Static", "200.5"]
    }

    func testParsesAnAlbumInDiscAndTrackOrder() throws {
        let text = output(["album", "album:Night Roads|Northern Static", "Night Roads", "3"],
                          [row("c", disc: 2, number: 1, "Static"), row("b", disc: 1, number: 2, "Blue Hour Drive"),
                           row("a", disc: 1, number: 1, "Headlights")])
        let context = try XCTUnwrap(MusicContextParser.parse(text))
        XCTAssertEqual(context.kind, .album)
        XCTAssertEqual(context.id, "album:Night Roads|Northern Static")
        XCTAssertEqual(context.title, "Night Roads")
        XCTAssertEqual(context.tracks.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(context.tracks[1], ContextTrack(id: "b", disc: 1, number: 2, title: "Blue Hour Drive",
                                                       artist: "Northern Static", duration: 200.5))
        XCTAssertEqual(context.totalCount, 3)
    }

    func testParsesAPlaylistInItsOwnOrder() throws {
        let text = output(["playlist", "playlist:ABC", "Road Trip", "3"],
                          [row("c", disc: 2, number: 1, "C"), row("a", disc: 1, number: 1, "A"), row("b", disc: 1, number: 2, "B")])
        let context = try XCTUnwrap(MusicContextParser.parse(text))
        XCTAssertEqual(context.kind, .playlist)
        XCTAssertEqual(context.tracks.map(\.id), ["c", "a", "b"])
    }

    func testEmptyOutputIsNil() throws {
        XCTAssertNil(MusicContextParser.parse(""))
        XCTAssertNil(MusicContextParser.parse("garbage"))
        let headerOnly = try XCTUnwrap(MusicContextParser.parse(output(["album", "album:X|Y", "X", "0"], [])))
        XCTAssertEqual(headerOnly.tracks, [])
    }

    func testFieldsMayContainOddCharacters() throws {
        let title = "\"Café\", Rock & Roll, 50% <live>"
        let text = output(["playlist", "playlist:1", title, "1"], [row("a", disc: 0, number: 0, title)])
        let context = try XCTUnwrap(MusicContextParser.parse(text))
        XCTAssertEqual(context.title, title)
        XCTAssertEqual(context.tracks.first?.title, title)
    }

    func testLongContextsAreCappedAt500() throws {
        let rows = (0..<600).map { row("t\($0)", disc: 1, number: $0 + 1, "Song \($0)") }
        let context = try XCTUnwrap(MusicContextParser.parse(output(["playlist", "playlist:big", "Everything", "5000"], rows)))
        XCTAssertEqual(context.tracks.count, 500)
        XCTAssertEqual(context.totalCount, 5000)
    }
}
