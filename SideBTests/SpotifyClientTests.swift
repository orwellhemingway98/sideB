import XCTest
@testable import SideB

final class SpotifyClientTests: XCTestCase {
    private var transport: FakeTransport!
    private var store: MemoryTokenStore!
    private var now = Date(timeIntervalSince1970: 10_000)
    private var signedOut: [Bool] = []
    private var slept: [TimeInterval] = []
    private let me = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!

    override func setUp() {
        transport = FakeTransport()
        store = MemoryTokenStore()
        signedOut = []
        slept = []
    }

    private func client(clientID: String? = "abc") -> SpotifyClient {
        SpotifyClient(clientID: { clientID }, store: store, transport: transport,
                      now: { [unowned self] in self.now }, sleep: { [unowned self] in self.slept.append($0) },
                      onSignedOut: { [unowned self] in self.signedOut.append($0) })
    }

    private func signIn(expiresIn: TimeInterval = 3600) {
        store.save(SpotifyTokens(accessToken: "A", refreshToken: "R", expiresAt: now.addingTimeInterval(expiresIn)))
    }

    func testNotSignedInMakesNoCall() {
        XCTAssertFalse(client().isSignedIn)
        XCTAssertThrowsError(try client().get(me)) { XCTAssertEqual($0 as? SpotifyError, .notSignedIn) }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testExchangeSavesTokens() throws {
        transport.reply("/api/token", json: #"{"access_token":"A","expires_in":3600,"refresh_token":"R"}"#)
        let client = client()
        try client.exchange(code: "C", verifier: "v")
        XCTAssertTrue(client.isSignedIn)
        XCTAssertEqual(store.load()?.accessToken, "A")
    }

    func testGetSendsTheBearerToken() throws {
        signIn()
        transport.reply(me.path, json: "{}")
        XCTAssertEqual(try client().get(me), Data("{}".utf8))
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Authorization"), "Bearer A")
    }

    func testNoContentIsNil() throws {
        signIn()
        transport.reply(me.path, .status(204))
        XCTAssertNil(try client().get(me))
    }

    func testRefreshesShortlyBeforeExpiry() throws {
        signIn(expiresIn: 30)
        transport.reply("/api/token", json: #"{"access_token":"B","expires_in":3600}"#)
        transport.reply(me.path, json: "{}")
        _ = try client().get(me)
        XCTAssertEqual(transport.requests(to: me.path).last?.value(forHTTPHeaderField: "Authorization"), "Bearer B")
        XCTAssertEqual(store.load()?.refreshToken, "R")
    }

    func testRetriesOnceAfterA401() throws {
        signIn()
        transport.reply(me.path, .status(401))
        transport.reply(me.path, json: "{}")
        transport.reply("/api/token", json: #"{"access_token":"B","expires_in":3600}"#)
        XCTAssertEqual(try client().get(me), Data("{}".utf8))
        XCTAssertEqual(transport.requests(to: me.path).count, 2)
    }

    func testARefusedRefreshSignsOutAsExpired() {
        signIn(expiresIn: 0)
        transport.reply("/api/token", .status(400, #"{"error":"invalid_grant"}"#))
        let client = client()
        XCTAssertThrowsError(try client.get(me)) { XCTAssertEqual($0 as? SpotifyError, .expired) }
        XCTAssertNil(store.load())
        XCTAssertFalse(client.isSignedIn)
        XCTAssertEqual(signedOut, [true])
    }

    func testOfflineRefreshKeepsTheLogin() {
        signIn(expiresIn: 0)
        transport.reply("/api/token", .offline)
        XCTAssertThrowsError(try client().get(me)) { XCTAssertEqual($0 as? SpotifyError, .network) }
        XCTAssertNotNil(store.load())
        XCTAssertEqual(signedOut, [])
    }

    func testWaitsOnceWhenRateLimited() throws {
        signIn()
        transport.reply(me.path, .status(429, headers: ["Retry-After": "2"]))
        transport.reply(me.path, json: "{}")
        _ = try client().get(me)
        XCTAssertEqual(slept, [2])
    }

    func testOtherErrorsAreReported() {
        signIn()
        transport.reply(me.path, .status(500))
        XCTAssertThrowsError(try client().get(me)) { XCTAssertEqual($0 as? SpotifyError, .http(500)) }
    }

    // MARK: PUT

    func testPutSendsTheBodyAsJSONWithTheBearerToken() throws {
        signIn()
        transport.reply(me.path, .status(204))
        try client().put(me, body: Data("{}".utf8))
        let request = transport.requests.last
        XCTAssertEqual(request?.httpMethod, "PUT")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer A")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request?.httpBody, Data("{}".utf8))
    }

    func testPutRetriesWithTheSameBodyAfterA401() throws {
        signIn()
        transport.reply(me.path, .status(401))
        transport.reply(me.path, .status(204))
        transport.reply("/api/token", json: #"{"access_token":"B","expires_in":3600}"#)
        try client().put(me, body: Data("{}".utf8))
        let retry = transport.requests(to: me.path).last
        XCTAssertEqual(transport.requests(to: me.path).count, 2)
        XCTAssertEqual(retry?.httpMethod, "PUT")
        XCTAssertEqual(retry?.value(forHTTPHeaderField: "Authorization"), "Bearer B")
        XCTAssertEqual(retry?.httpBody, Data("{}".utf8))
    }

    func testPutWaitsOnceWhenRateLimited() throws {
        signIn()
        transport.reply(me.path, .status(429, headers: ["Retry-After": "2"]))
        transport.reply(me.path, .status(204))
        try client().put(me, body: Data("{}".utf8))
        XCTAssertEqual(slept, [2])
        XCTAssertEqual(transport.requests(to: me.path).count, 2)
    }

    func testPutReportsARefusal() {
        signIn()
        transport.reply(me.path, .status(403))
        XCTAssertThrowsError(try client().put(me, body: Data())) { XCTAssertEqual($0 as? SpotifyError, .http(403)) }
    }

    func testSignOutForgetsTheLogin() {
        signIn()
        let client = client()
        client.signOut()
        XCTAssertNil(store.load())
        XCTAssertFalse(client.isSignedIn)
        XCTAssertEqual(signedOut, [false])
    }
}
