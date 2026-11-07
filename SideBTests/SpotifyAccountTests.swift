import XCTest
@testable import SideB

@MainActor
final class SpotifyAccountTests: XCTestCase {
    private var transport: FakeTransport!
    private var store: MemoryTokenStore!
    private var defaults: UserDefaults!
    private var opened: [URL] = []

    override func setUp() {
        transport = FakeTransport()
        store = MemoryTokenStore()
        defaults = UserDefaults(suiteName: "SpotifyAccountTests")!
        defaults.removePersistentDomain(forName: "SpotifyAccountTests")
        opened = []
    }

    /// An account whose sign-in page answers with `reply(state)`.
    private func account(reply: @escaping (String) throws -> URL) -> SpotifyAccount {
        SpotifyAccount(store: store, transport: transport, defaults: defaults, authenticate: { [unowned self] url in
            self.opened.append(url)
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "state" }?.value ?? ""
            return try reply(state)
        })
    }

    func testSignInRemembersTheClientIDAndTheLogin() async throws {
        transport.reply("/api/token", json: #"{"access_token":"A","expires_in":3600,"refresh_token":"R"}"#)
        let account = account { URL(string: "sideb://callback?code=C&state=\($0)")! }
        XCTAssertFalse(account.isSignedIn)
        await account.signIn(clientID: "  abc123 ")
        XCTAssertTrue(account.isSignedIn)
        XCTAssertNil(account.notice)
        XCTAssertEqual(account.clientID, "abc123")
        XCTAssertEqual(store.load()?.accessToken, "A")
        let body = String(decoding: try XCTUnwrap(transport.requests(to: "/api/token").first?.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("client_id=abc123"))
        XCTAssertTrue(body.contains("code=C"))
    }

    func testCancellingLeavesNoNotice() async {
        let account = account { _ in throw CancellationError() }
        await account.signIn(clientID: "abc")
        XCTAssertFalse(account.isSignedIn)
        XCTAssertNil(account.notice)
        XCTAssertFalse(account.isSigningIn)
    }

    func testAFailedExchangeSaysSo() async {
        transport.reply("/api/token", .status(400))
        let account = account { URL(string: "sideb://callback?code=C&state=\($0)")! }
        await account.signIn(clientID: "abc")
        XCTAssertFalse(account.isSignedIn)
        XCTAssertEqual(account.notice, "Couldn't sign in to Spotify.")
    }

    func testAForgedCallbackIsRefused() async {
        let account = account { _ in URL(string: "sideb://callback?code=C&state=other")! }
        await account.signIn(clientID: "abc")
        XCTAssertFalse(account.isSignedIn)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAnEmptyClientIDDoesNothing() async {
        let account = account { _ in XCTFail("no page"); throw CancellationError() }
        await account.signIn(clientID: "   ")
        XCTAssertTrue(opened.isEmpty)
    }

    func testAnExpiredLoginShowsTheNotice() async throws {
        store.save(SpotifyTokens(accessToken: "A", refreshToken: "R", expiresAt: .distantPast))
        defaults.set("abc", forKey: SpotifyAccount.clientIDKey)
        transport.reply("/api/token", .status(400))
        let account = account { _ in throw CancellationError() }
        XCTAssertTrue(account.isSignedIn)
        let api = account.api
        _ = try await Task.detached { try api.context() }.value
        while account.isSignedIn { await Task.yield() }
        XCTAssertEqual(account.notice, "Spotify sign-in expired.")
    }

    func testSignOut() {
        store.save(SpotifyTokens(accessToken: "A", refreshToken: "R", expiresAt: .distantFuture))
        let account = account { _ in throw CancellationError() }
        account.signOut()
        XCTAssertFalse(account.isSignedIn)
        XCTAssertNil(account.notice)
        XCTAssertNil(store.load())
    }

    // MARK: A sign-in from before the permission

    private static let playPath = "/v1/me/player/play"
    private static let scopeRefusal = #"{"error":{"status":403,"message":"Insufficient client scope"}}"#

    private func signedInAccount() -> SpotifyAccount {
        store.save(SpotifyTokens(accessToken: "A", refreshToken: "R", expiresAt: .distantFuture))
        return account { state in URL(string: "sideb://callback?code=C&state=\(state)")! }
    }

    private func clickARow(_ account: SpotifyAccount) async {
        let api = account.api
        _ = await Task.detached { api.play(trackURI: "spotify:track:T1", contextID: "album:AL1") }.value
    }

    func testAScopeRefusalAsksForANewSignIn() async {
        transport.reply(Self.playPath, .status(403, Self.scopeRefusal))
        let account = signedInAccount()
        XCTAssertFalse(account.needsNewSignIn)
        await clickARow(account)
        for _ in 0..<1000 where !account.needsNewSignIn { await Task.yield() }
        XCTAssertTrue(account.needsNewSignIn)
    }

    func testOtherRefusalsDoNotAsk() async {
        transport.reply(Self.playPath, .status(404))
        let account = signedInAccount()
        await clickARow(account)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(account.needsNewSignIn)
    }

    func testANewSignInClearsTheRequest() async {
        transport.reply(Self.playPath, .status(403, Self.scopeRefusal))
        transport.reply("/api/token", json: #"{"access_token":"B","expires_in":3600,"refresh_token":"R2"}"#)
        let account = signedInAccount()
        await clickARow(account)
        for _ in 0..<1000 where !account.needsNewSignIn { await Task.yield() }
        await account.signIn(clientID: "abc")
        XCTAssertFalse(account.needsNewSignIn)
    }

    func testSigningOutClearsTheRequest() async {
        transport.reply(Self.playPath, .status(403, Self.scopeRefusal))
        let account = signedInAccount()
        await clickARow(account)
        for _ in 0..<1000 where !account.needsNewSignIn { await Task.yield() }
        account.signOut()
        XCTAssertFalse(account.needsNewSignIn)
    }
}
