import Foundation
@testable import Spindle

/// Records download requests; the test drives progress and completion by hand.
final class FakeDownloadSession: DownloadSession {
    final class Request: DownloadHandle {
        let url: URL
        let progress: @MainActor (Double) -> Void
        let completion: @MainActor (Result<URL, Error>) -> Void
        private(set) var cancelled = false

        init(url: URL, progress: @escaping @MainActor (Double) -> Void,
             completion: @escaping @MainActor (Result<URL, Error>) -> Void) {
            self.url = url
            self.progress = progress
            self.completion = completion
        }

        func cancel() { cancelled = true }
    }

    private(set) var requests: [Request] = []

    func download(_ url: URL, progress: @escaping @MainActor (Double) -> Void,
                  completion: @escaping @MainActor (Result<URL, Error>) -> Void) -> DownloadHandle {
        let request = Request(url: url, progress: progress, completion: completion)
        requests.append(request)
        return request
    }

    /// A temporary file standing in for what URLSession hands over on completion.
    static func temporaryFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("spindle-dl-\(UUID().uuidString)")
        try Data("audio".utf8).write(to: url)
        return url
    }
}
