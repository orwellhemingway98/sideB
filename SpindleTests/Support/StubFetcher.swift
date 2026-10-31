import Foundation
@testable import Spindle

final class StubFetcher: HTTPFetching, @unchecked Sendable {
    private enum Mode {
        case fixed(Result<String, Error>)
        case perURL
    }

    private let mode: Mode
    private var responses: [URL: Result<String, Error>]
    private(set) var requested: [URL] = []

    init(json: String) {
        mode = .fixed(.success(json))
        responses = [:]
    }

    init(error: Error) {
        mode = .fixed(.failure(error))
        responses = [:]
    }

    init(responses: [URL: Result<String, Error>] = [:]) {
        mode = .perURL
        self.responses = responses
    }

    func set(_ url: URL, _ result: Result<String, Error>) {
        responses[url] = result
    }

    func data(from url: URL) async throws -> Data {
        requested.append(url)
        let result: Result<String, Error>
        switch mode {
        case .fixed(let fixed): result = fixed
        case .perURL: result = responses[url] ?? .failure(URLError(.fileDoesNotExist))
        }
        return Data(try result.get().utf8)
    }
}
