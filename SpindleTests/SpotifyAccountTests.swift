import XCTest
@testable import Spindle

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
        let account = account { URL(string: "spindle://callback?code=C&state=\($0)")! }
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
        let account = account { URL(string: "spindle://callback?code=C&state=\($0)")! }
        await account.signIn(clientID: "abc")
        XCTAssertFalse(account.isSignedIn)
        XCTAssertEqual(account.notice, "Couldn't sign in to Spotify.")
    }

    func testAForgedCallbackIsRefused() async {
        let account = account { _ in URL(string: "spindle://callback?code=C&state=other")! }
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
}
