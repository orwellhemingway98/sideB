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
    private var validatorsByURL: [URL: Validators] = [:]
    private var notModified: Set<URL> = []
    private var _validatorsSeen: [Validators] = []

    var requested: [URL] { lock.withLock { _requested } }
    /// The validators each conditional fetch was sent, in order.
    var validatorsSeen: [Validators] { lock.withLock { _validatorsSeen } }

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
        lock.withLock { responses[url] = result }
    }

    /// Validators the server hands out with a full response for `url`.
    func setValidators(_ url: URL, _ validators: Validators) {
        lock.withLock { validatorsByURL[url] = validators }
    }

    /// From now on `url` answers a conditional fetch with 304.
    func markNotModified(_ url: URL) {
        lock.withLock { _ = notModified.insert(url) }
    }

    func data(from url: URL) async throws -> Data {
        let result: Result<String, Error> = lock.withLock {
            _requested.append(url)
            switch mode {
            case .fixed(let fixed): return fixed
            case .perURL: return responses[url] ?? .failure(URLError(.fileDoesNotExist))
            }
        }
        return Data(try result.get().utf8)
    }

    func fetch(_ url: URL, validators: Validators) async throws -> FetchResult {
        let (isNotModified, served) = lock.withLock {
            _validatorsSeen.append(validators)
            return (notModified.contains(url), validatorsByURL[url] ?? Validators())
        }
        if isNotModified { return .notModified }
        return .fresh(try await data(from: url), served)
    }
}
