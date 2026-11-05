import AppKit
import XCTest
@testable import SideB

final class SpotifySourceTests: XCTestCase {
    func testPlayingARowScriptsSpotifyWithItsList() {
        XCTAssertEqual(SpotifySource.playScript(trackID: "spotify:track:T1", contextID: "album:AL1"),
                       #"play track "spotify:track:T1" in context "spotify:album:AL1""#)
        XCTAssertEqual(SpotifySource.playScript(trackID: "spotify:track:T1", contextID: "playlist:PL1"),
                       #"play track "spotify:track:T1" in context "spotify:playlist:PL1""#)
    }

    func testThePlayScriptCompilesAgainstSpotify() throws {
        // Compiling (not running) catches a term Spotify's dictionary doesn't know, without launching it.
        let body = SpotifySource.playScript(trackID: "spotify:track:T1", contextID: "album:AL1")
        let source = AppleScriptMusicSource.wrapped(body, bundleIdentifier: "com.spotify.client")
        try XCTSkipUnless(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil,
                          "Spotify isn't installed")
        var error: NSDictionary?
        XCTAssertTrue(NSAppleScript(source: source)!.compileAndReturnError(&error), "\(error ?? [:])")
    }

    func testWithoutSignInThereIsNoList() throws {
        let source = SpotifySource()
        XCTAssertNil(try source.contextKey())
        XCTAssertNil(try source.context())
    }
}
