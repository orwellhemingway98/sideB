import Foundation

protocol HTTPFetching: Sendable {
    func data(from url: URL) async throws -> Data
}

struct URLSessionFetcher: HTTPFetching {
    var session: URLSession = .shared

    func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Spindle/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
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
