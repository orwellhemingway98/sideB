import Foundation

protocol DownloadHandle: AnyObject {
    func cancel()
}

/// Downloads one file with progress. The completion gets a temporary file the caller then moves.
protocol DownloadSession: AnyObject {
    func download(_ url: URL, progress: @escaping @MainActor (Double) -> Void,
                  completion: @escaping @MainActor (Result<URL, Error>) -> Void) -> DownloadHandle
}

/// URLSession download tasks. URLSession deletes its own temporary file as soon as the delegate
/// returns, so the file is moved to a holding place first and that copy is handed on.
final class URLSessionDownloads: NSObject, DownloadSession, URLSessionDownloadDelegate, @unchecked Sendable {
    private struct Callbacks {
        let progress: @MainActor (Double) -> Void
        let completion: @MainActor (Result<URL, Error>) -> Void
    }

    private let lock = NSLock()
    private var callbacks: [Int: Callbacks] = [:]
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    private final class Handle: DownloadHandle {
        let task: URLSessionDownloadTask
        init(_ task: URLSessionDownloadTask) { self.task = task }
        func cancel() { task.cancel() }
    }

    func download(_ url: URL, progress: @escaping @MainActor (Double) -> Void,
                  completion: @escaping @MainActor (Result<URL, Error>) -> Void) -> DownloadHandle {
        var request = URLRequest(url: url)
        request.setValue("sideB/0.1", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        lock.withLock { callbacks[task.taskIdentifier] = Callbacks(progress: progress, completion: completion) }
        task.resume()
        return Handle(task)
    }

    private func callbacks(for task: URLSessionTask, remove: Bool = false) -> Callbacks? {
        lock.withLock { remove ? callbacks.removeValue(forKey: task.taskIdentifier) : callbacks[task.taskIdentifier] }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0, let callbacks = callbacks(for: downloadTask) else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in callbacks.progress(fraction) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let callbacks = callbacks(for: downloadTask, remove: true) else { return }
        let result: Result<URL, Error>
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            result = .failure(URLError(.badServerResponse))
        } else {
            let holding = FileManager.default.temporaryDirectory.appendingPathComponent("sideb-\(UUID().uuidString)")
            result = Result { try FileManager.default.moveItem(at: location, to: holding); return holding }
        }
        Task { @MainActor in callbacks.completion(result) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let callbacks = callbacks(for: task, remove: true) else { return }
        Task { @MainActor in callbacks.completion(.failure(error)) }
    }
}
