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

    // MARK: Playing a row

    private static let playPath = "/v1/me/player/play"
    private static let list = MusicContext(kind: .album, id: "album:AL1", title: "Night Roads", tracks: [], totalCount: 0)

    /// A source for an app that doesn't exist. Its fallback stops at "is it running?" with `.notRunning`, so these
    /// tests see that it was tried while no script can ever reach the real Spotify.
    private func source(signedIn: Bool = true, transport: FakeTransport) -> SpotifySource {
        let store = MemoryTokenStore()
        if signedIn { store.save(SpotifyTokens(accessToken: "A", refreshToken: "R", expiresAt: .distantFuture)) }
        let client = SpotifyClient(clientID: { "abc" }, store: store, transport: transport)
        return SpotifySource(api: SpotifyWebAPI(client: client), bundleIdentifier: "invalid.sideb.tests.no-such-app")
    }

    func testARowPlaysThroughTheWebAPIAndSkipsTheScript() throws {
        let transport = FakeTransport()
        transport.reply(Self.playPath, .status(204))
        try source(transport: transport).play(trackID: "spotify:track:T1", in: Self.list)
        XCTAssertEqual(transport.requests(to: Self.playPath).count, 1)
    }

    func testARefusedRowFallsBackToTheScript() {
        let transport = FakeTransport()
        transport.reply(Self.playPath, .status(403))
        XCTAssertThrowsError(try source(transport: transport).play(trackID: "spotify:track:T1", in: Self.list)) {
            XCTAssertEqual($0 as? MusicSourceError, .notRunning)
        }
        XCTAssertEqual(transport.requests(to: Self.playPath).count, 1)
    }

    func testSignedOutARowGoesStraightToTheScript() {
        let transport = FakeTransport()
        XCTAssertThrowsError(try source(signedIn: false, transport: transport).play(trackID: "spotify:track:T1", in: Self.list)) {
            XCTAssertEqual($0 as? MusicSourceError, .notRunning)
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
}
