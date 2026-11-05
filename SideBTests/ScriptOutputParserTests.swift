import XCTest
@testable import SideB

final class ScriptOutputParserTests: XCTestCase {
    private func j(_ fields: String...) -> String {
        fields.joined(separator: String(ScriptOutputParser.separator))
    }

    func testParsesPlayingMusicTrack() throws {
        let snap = try XCTUnwrap(ScriptOutputParser.parse(
            j("playing", "55", "ABC", "Song", "Artist", "Album", "245.5", "12.25", "3", "14"),
            source: .appleMusic, durationIsMilliseconds: false))
        XCTAssertEqual(snap.state, .playing)
        XCTAssertEqual(snap.volume, 55)
        let track = try XCTUnwrap(snap.track)
        XCTAssertEqual(track.trackID, "ABC")
        XCTAssertEqual(track.title, "Song")
        XCTAssertEqual(track.artist, "Artist")
        XCTAssertEqual(track.album, "Album")
        XCTAssertEqual(track.duration, 245.5)
        XCTAssertEqual(track.position, 12.25)
        XCTAssertEqual(track.index, 3)
        XCTAssertEqual(track.count, 14)
        XCTAssertEqual(track.source, .appleMusic)
    }

    func testSpotifyMillisecondsConverted() throws {
        let snap = try XCTUnwrap(ScriptOutputParser.parse(
            j("paused", "70", "spotify:track:1", "Song", "Artist", "Album", "245000", "3.5", "", ""),
            source: .spotify, durationIsMilliseconds: true))
        XCTAssertEqual(snap.track?.duration, 245.0)
        XCTAssertEqual(snap.track?.position, 3.5)
        XCTAssertEqual(snap.state, .paused)
    }

    func testStoppedHasNoTrack() throws {
        let snap = try XCTUnwrap(ScriptOutputParser.parse(j("stopped", "40"), source: .appleMusic, durationIsMilliseconds: false))
        XCTAssertEqual(snap.state, .stopped)
        XCTAssertNil(snap.track)
        XCTAssertEqual(snap.volume, 40)
    }

    func testOddMetadataSurvives() throws {
        let title = "Hey | \"Jude\" 🎸"
        let snap = try XCTUnwrap(ScriptOutputParser.parse(
            j("playing", "50", "X", title, "Ärtist, The", "", "100", "1", "", ""),
            source: .appleMusic, durationIsMilliseconds: false))
        XCTAssertEqual(snap.track?.title, title)
        XCTAssertEqual(snap.track?.artist, "Ärtist, The")
        XCTAssertEqual(snap.track?.album, "")
    }

    func testMissingValueBecomesEmpty() throws {
        let snap = try XCTUnwrap(ScriptOutputParser.parse(
            j("playing", "50", "X", "Ad", "missing value", "missing value", "missing value", "1", "", ""),
            source: .spotify, durationIsMilliseconds: true))
        XCTAssertEqual(snap.track?.artist, "")
        XCTAssertEqual(snap.track?.album, "")
        XCTAssertEqual(snap.track?.duration, 0)
    }

    func testMissingIndexAndCount() throws {
        let snap = try XCTUnwrap(ScriptOutputParser.parse(
            j("playing", "50", "X", "T", "A", "B", "100", "1", "", ""),
            source: .appleMusic, durationIsMilliseconds: false))
        XCTAssertNil(snap.track?.index)
        XCTAssertNil(snap.track?.count)
    }

    func testCommaDecimals() throws {
        let snap = try XCTUnwrap(ScriptOutputParser.parse(
            j("playing", "50", "X", "T", "A", "B", "245,5", "1,5", "", ""),
            source: .appleMusic, durationIsMilliseconds: false))
        XCTAssertEqual(snap.track?.duration, 245.5)
        XCTAssertEqual(snap.track?.position, 1.5)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(ScriptOutputParser.parse("", source: .appleMusic, durationIsMilliseconds: false))
        XCTAssertNil(ScriptOutputParser.parse("weird", source: .appleMusic, durationIsMilliseconds: false))
        XCTAssertNil(ScriptOutputParser.parse(j("playing", "50", "X"), source: .appleMusic, durationIsMilliseconds: false))
    }
}
