import Foundation

protocol HTTPFetching: Sendable {
    func data(from url: URL) async throws -> Data
    /// A conditional fetch: sends the validators from last time and reports a 304 as `.notModified`.
    func fetch(_ url: URL, validators: Validators) async throws -> FetchResult
}

/// What a server said about a feed's version, sent back next time so an unchanged feed costs nothing.
struct Validators: Equatable, Sendable {
    var etag: String?
    var lastModified: String?
}

enum FetchResult: Sendable {
    case fresh(Data, Validators)
    case notModified
}

extension HTTPFetching {
    func fetch(_ url: URL, validators: Validators) async throws -> FetchResult {
        .fresh(try await data(from: url), Validators())
    }
}

struct URLSessionFetcher: HTTPFetching {
    var session: URLSession = .shared

    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("sideB/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    func fetch(_ url: URL, validators: Validators) async throws -> FetchResult {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("sideB/0.1", forHTTPHeaderField: "User-Agent")
        if let etag = validators.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let modified = validators.lastModified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return .fresh(data, Validators()) }
        if http.statusCode == 304 { return .notModified }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return .fresh(data, Validators(etag: http.value(forHTTPHeaderField: "ETag"),
                                       lastModified: http.value(forHTTPHeaderField: "Last-Modified")))
    }
}

extension URL {
    /// The https form of an http URL (nil for anything else). macOS blocks plain http by default,
    /// and most old http feed and media links answer on https too.
    var httpsUpgraded: URL? {
        guard scheme?.lowercased() == "http", var parts = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        parts.scheme = "https"
        return parts.url
    }
}

enum Connectivity {
    /// The errors that mean "no network right now" rather than "that address is wrong".
    static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost: return true
        default: return false
        }
    }
}
