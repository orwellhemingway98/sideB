import XCTest
@testable import SideB

final class SpotifyAuthTests: XCTestCase {
    func testChallengeMatchesTheRFC7636Example() {
        XCTAssertEqual(SpotifyAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testVerifierIsLongAndUnreserved() {
        let verifier = SpotifyAuth.makeVerifier()
        XCTAssertEqual(verifier.count, 64)
        XCTAssertTrue(verifier.allSatisfy { $0.isLetter || $0.isNumber || "-._~".contains($0) })
        XCTAssertNotEqual(verifier, SpotifyAuth.makeVerifier())
    }

    func testAuthorizeURL() throws {
        let url = SpotifyAuth.authorizeURL(clientID: "abc", challenge: "xyz", state: "s1")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "accounts.spotify.com")
        XCTAssertEqual(url.path, "/authorize")
        XCTAssertEqual(query["client_id"], "abc")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["redirect_uri"], "sideb://callback")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["code_challenge"], "xyz")
        XCTAssertEqual(query["state"], "s1")
        XCTAssertEqual(query["scope"], "user-read-currently-playing user-read-playback-state playlist-read-private playlist-read-collaborative")
    }

    func testCallbackGivesTheCode() throws {
        let code = try SpotifyAuth.code(from: URL(string: "sideb://callback?code=C0DE&state=s1")!, state: "s1")
        XCTAssertEqual(code, "C0DE")
    }

    func testCallbackWithAnotherStateIsRejected() {
        XCTAssertThrowsError(try SpotifyAuth.code(from: URL(string: "sideb://callback?code=C&state=evil")!, state: "s1")) {
            XCTAssertEqual($0 as? SpotifyAuth.CallbackError, .stateMismatch)
        }
    }

    func testDeniedCallback() {
        XCTAssertThrowsError(try SpotifyAuth.code(from: URL(string: "sideb://callback?error=access_denied&state=s1")!,
                                                  state: "s1")) {
            XCTAssertEqual($0 as? SpotifyAuth.CallbackError, .denied)
        }
    }

    func testTokenRequestIsAFormPost() throws {
        let request = SpotifyAuth.tokenRequest(code: "C 1", verifier: "v", clientID: "abc")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, SpotifyAuth.tokenURL)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertEqual(body, "grant_type=authorization_code&code=C%201&redirect_uri=sideb%3A%2F%2Fcallback&client_id=abc&code_verifier=v")
    }

    func testRefreshRequest() throws {
        let body = String(decoding: try XCTUnwrap(SpotifyAuth.refreshRequest(refreshToken: "r", clientID: "abc").httpBody),
                          as: UTF8.self)
        XCTAssertEqual(body, "grant_type=refresh_token&refresh_token=r&client_id=abc")
    }

    func testTokensDecode() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let json = #"{"access_token":"A","token_type":"Bearer","expires_in":3600,"refresh_token":"R","scope":"x"}"#
        let tokens = try SpotifyAuth.tokens(from: Data(json.utf8), previous: nil, now: now)
        XCTAssertEqual(tokens, SpotifyTokens(accessToken: "A", refreshToken: "R", expiresAt: now.addingTimeInterval(3600)))
    }

    func testRefreshWithoutANewRefreshTokenKeepsTheOldOne() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let old = SpotifyTokens(accessToken: "A", refreshToken: "R", expiresAt: now)
        let tokens = try SpotifyAuth.tokens(from: Data(#"{"access_token":"B","expires_in":60}"#.utf8), previous: old, now: now)
        XCTAssertEqual(tokens.refreshToken, "R")
        XCTAssertEqual(tokens.accessToken, "B")
    }
}

final class SpotifyClientIDTests: XCTestCase {
    func testOnlyA32CharacterHexIDIsAccepted() {
        XCTAssertEqual(SpotifyClientIDPrompt.validated("  64c3deef8969445ca15a174b9c116b21 \n"), "64c3deef8969445ca15a174b9c116b21")
        XCTAssertEqual(SpotifyClientIDPrompt.validated("64C3DEEF8969445CA15A174B9C116B21"), "64c3deef8969445ca15a174b9c116b21")
        XCTAssertNil(SpotifyClientIDPrompt.validated("mfelouro"), "a username isn't a Client ID")
        XCTAssertNil(SpotifyClientIDPrompt.validated("64c3deef8969445ca15a174b9c116b2"), "one character short")
        XCTAssertNil(SpotifyClientIDPrompt.validated("64c3deef8969445ca15a174b9c116b2z"))
        XCTAssertNil(SpotifyClientIDPrompt.validated(""))
    }
}

/// Spotify works as a remote with no sign-in; listing albums is the optional extra.
final class SpotifyIsOptionalTests: XCTestCase {
    func testSetupSaysItIsOptionalAndWhatItAdds() {
        XCTAssertTrue(SpotifyClientIDPrompt.explanation.hasPrefix("Optional."))
        XCTAssertTrue(SpotifyClientIDPrompt.explanation.contains("sideb://callback"))
        XCTAssertTrue(SpotifyClientIDPrompt.explanation.contains("Premium"))
    }

    func testTheButtonOnlySaysSignInOnceAClientIDIsSaved() {
        XCTAssertEqual(SpotifyClientIDPrompt.buttonTitle(hasClientID: false), "Set Up Album Lists\u{2026}")
        XCTAssertEqual(SpotifyClientIDPrompt.buttonTitle(hasClientID: true), "Sign in to Spotify")
    }
}
