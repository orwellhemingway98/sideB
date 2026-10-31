import Foundation
@testable import Spindle

final class StubFetcher: HTTPFetching, @unchecked Sendable {
    private enum Mode {
        case fixed(Result<String, Error>)
        case perURL
    }

    private let mode: Mode
    private let lock = NSLock()
    private var responses: [URL: Result<String, Error>]
    private var _requested: [URL] = []

    var requested: [URL] {
        lock.lock(); defer { lock.unlock() }
        return _requested
    }

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
        lock.lock(); defer { lock.unlock() }
        responses[url] = result
    }

    func data(from url: URL) async throws -> Data {
        let result: Result<String, Error>
        lock.lock()
        _requested.append(url)
        switch mode {
        case .fixed(let fixed): result = fixed
        case .perURL: result = responses[url] ?? .failure(URLError(.fileDoesNotExist))
        }
        lock.unlock()
        return Data(try result.get().utf8)
    }
}
