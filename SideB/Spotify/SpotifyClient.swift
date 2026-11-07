import Foundation

enum SpotifyError: Error, Equatable {
    case notSignedIn
    /// Spotify refused the login (revoked or expired); it has been forgotten.
    case expired
    /// This sign-in predates a permission the call needs; signing in again grants it.
    case missingPermission
    case network
    case http(Int)
}

/// Sends one HTTP request and waits for the reply. Synchronous because music sources are called off the main
/// actor and expect blocking calls.
protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    /// Ten seconds, or less if the request asked for less.
    static func timeout(for request: URLRequest) -> TimeInterval { min(request.timeoutInterval, 10) }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        var request = request
        request.timeoutInterval = Self.timeout(for: request)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome: Result<(Data, HTTPURLResponse), Error> = .failure(URLError(.unknown))
        // The completion runs on URLSession's own queue, so waiting here never starves it.
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let response = response as? HTTPURLResponse {
                outcome = .success((data ?? Data(), response))
            } else {
                outcome = .failure(error ?? URLError(.badServerResponse))
            }
            done.signal()
        }.resume()
        done.wait()
        return try outcome.get()
    }
}

/// Talks to the Spotify Web API as the signed-in user: adds the access token, renews it shortly before it runs
/// out or when Spotify says it has, and waits out one rate limit. Safe to call from any thread.
final class SpotifyClient: @unchecked Sendable {
    /// Renew this long before the access token expires.
    private static let refreshMargin: TimeInterval = 60

    private let clientID: @Sendable () -> String?
    private let store: SpotifyTokenStore
    private let transport: HTTPTransport
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) -> Void
    private let onSignedOut: @Sendable (_ expired: Bool) -> Void
    private let onMissingPermission: @Sendable () -> Void
    private let lock = NSLock()
    /// The store, read once (the Keychain may ask the first time).
    private var cached: SpotifyTokens??

    init(clientID: @escaping @Sendable () -> String?, store: SpotifyTokenStore,
         transport: HTTPTransport = URLSessionTransport(), now: @escaping @Sendable () -> Date = { Date() },
         sleep: @escaping @Sendable (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
         onSignedOut: @escaping @Sendable (_ expired: Bool) -> Void = { _ in },
         onMissingPermission: @escaping @Sendable () -> Void = {}) {
        self.clientID = clientID
        self.store = store
        self.transport = transport
        self.now = now
        self.sleep = sleep
        self.onSignedOut = onSignedOut
        self.onMissingPermission = onMissingPermission
    }

    var isSignedIn: Bool { tokens != nil }

    private var tokens: SpotifyTokens? {
        get { lock.withLock { if cached == nil { cached = .some(store.load()) }; return cached! } }
        set {
            lock.withLock {
                cached = .some(newValue)
                if let newValue { store.save(newValue) } else { store.clear() }
            }
        }
    }

    /// Trades the code from the sign-in page for a login and keeps it.
    func exchange(code: String, verifier: String) throws {
        guard let clientID = clientID() else { throw SpotifyError.notSignedIn }
        let (data, response) = try send(SpotifyAuth.tokenRequest(code: code, verifier: verifier, clientID: clientID))
        guard response.statusCode == 200 else { throw SpotifyError.http(response.statusCode) }
        do { tokens = try SpotifyAuth.tokens(from: data, previous: nil, now: now()) }
        catch { throw SpotifyError.http(response.statusCode) }
    }

    func signOut() {
        tokens = nil
        onSignedOut(false)
    }

    /// GETs a Web API URL. Nil for 204 No Content.
    func get(_ url: URL) throws -> Data? {
        try authorized(URLRequest(url: url))
    }

    /// PUTs JSON to a Web API URL. Throws unless Spotify accepts it. `timeout` is how long to wait for a reply
    /// when someone is waiting on it; left out, the transport's own limit applies.
    func put(_ url: URL, body: Data, timeout: TimeInterval? = nil) throws {
        var request = URLRequest(url: url)
        if let timeout { request.timeoutInterval = timeout }
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try authorized(request)
    }

    private func authorized(_ base: URLRequest) throws -> Data? {
        var token = try accessToken(forceRefresh: false)
        var refreshed = false
        var waited = false
        while true {
            var request = base
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try send(request)
            switch response.statusCode {
            case 200..<300:
                return response.statusCode == 204 || data.isEmpty ? nil : data
            case 401 where !refreshed:
                refreshed = true
                token = try accessToken(forceRefresh: true)
            case 429 where !waited:
                waited = true
                sleep(min(Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 1, 10))
            case 403 where Self.isMissingPermission(data):
                onMissingPermission()
                throw SpotifyError.missingPermission
            default:
                throw SpotifyError.http(response.statusCode)
            }
        }
    }

    /// Spotify says why it refused in the reply: other 403s (no Premium, say) won't be cured by signing in again.
    private static func isMissingPermission(_ reply: Data) -> Bool {
        String(decoding: reply, as: UTF8.self).lowercased().contains("insufficient client scope")
    }

    private func accessToken(forceRefresh: Bool) throws -> String {
        guard let current = tokens else { throw SpotifyError.notSignedIn }
        guard forceRefresh || current.expiresAt.timeIntervalSince(now()) < Self.refreshMargin else {
            return current.accessToken
        }
        guard let clientID = clientID() else { throw SpotifyError.notSignedIn }
        let (data, response) = try send(SpotifyAuth.refreshRequest(refreshToken: current.refreshToken, clientID: clientID))
        switch response.statusCode {
        case 200:
            guard let renewed = try? SpotifyAuth.tokens(from: data, previous: current, now: now()) else {
                throw SpotifyError.http(200)
            }
            tokens = renewed
            return renewed.accessToken
        case 400, 401:
            // Spotify no longer accepts this login: forget it, so the Sign in button comes back.
            tokens = nil
            onSignedOut(true)
            throw SpotifyError.expired
        default:
            throw SpotifyError.http(response.statusCode)
        }
    }

    private func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        do { return try transport.send(request) }
        catch { throw SpotifyError.network }
    }
}
