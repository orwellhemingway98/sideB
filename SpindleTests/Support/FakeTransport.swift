import Foundation
@testable import Spindle

/// Answers HTTP requests from a queue of canned replies, by URL path, and records what was asked.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    enum Reply {
        case status(Int, String = "", headers: [String: String] = [:])
        case offline
    }

    private let lock = NSLock()
    private var replies: [String: [Reply]] = [:]
    private var _requests: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { _requests } }
    func requests(to path: String) -> [URLRequest] { requests.filter { $0.url?.path == path } }

    /// Queues a reply for `path`; the last one queued repeats once the others are used.
    func reply(_ path: String, _ reply: Reply) {
        lock.withLock { replies[path, default: []].append(reply) }
    }

    func reply(_ path: String, json: String) { reply(path, .status(200, json)) }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let next: Reply? = lock.withLock {
            _requests.append(request)
            guard var queue = replies[path], let first = queue.first else { return nil }
            if queue.count > 1 { queue.removeFirst(); replies[path] = queue }
            return first
        }
        switch next {
        case .status(let code, let body, let headers):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
            return (Data(body.utf8), response)
        case .offline, nil:
            throw URLError(.notConnectedToInternet)
        }
    }
}
