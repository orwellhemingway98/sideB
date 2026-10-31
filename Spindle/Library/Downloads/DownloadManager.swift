import Foundation
import SwiftData

enum DownloadState: Equatable {
    case none
    case downloading(Double)
    case downloaded
    case failed(String)
}

/// Downloads episodes by hand for offline listening. An episode only counts as downloaded once its
/// file has been moved into place, so a download cut short by quitting leaves nothing behind.
@MainActor
final class DownloadManager: ObservableObject {
    static let failedMessage = "Download failed. Try again."
    static let offlineMessage = "You're offline."

    private let library: LibraryStore
    private let session: DownloadSession
    private let root: URL

    private struct Active {
        let handle: DownloadHandle
        var progress: Double
    }

    @Published private var active: [PersistentIdentifier: Active] = [:]
    @Published private var failures: [PersistentIdentifier: String] = [:]

    init(library: LibraryStore, session: DownloadSession, root: URL) {
        self.library = library
        self.session = session
        self.root = root
    }

    func state(of episode: Episode) -> DownloadState {
        let id = episode.persistentModelID
        if let download = active[id] { return .downloading(download.progress) }
        if let message = failures[id] { return .failed(message) }
        if let file = episode.localFile, FileManager.default.fileExists(atPath: file.path) { return .downloaded }
        return .none
    }

    func download(_ episode: Episode) {
        switch state(of: episode) {
        case .downloading, .downloaded: return
        case .none, .failed: break
        }
        let id = episode.persistentModelID
        failures[id] = nil
        let handle = session.download(episode.enclosureURL,
                                      progress: { [weak self] fraction in self?.progressed(id, fraction) },
                                      completion: { [weak self, weak episode] result in
                                          guard let episode else { return }
                                          self?.finished(episode, id: id, result: result)
                                      })
        active[id] = Active(handle: handle, progress: 0)
    }

    func cancel(_ episode: Episode) {
        let id = episode.persistentModelID
        active.removeValue(forKey: id)?.handle.cancel()
    }

    func removeDownload(_ episode: Episode) {
        cancel(episode)
        failures[episode.persistentModelID] = nil
        if let file = episode.localFile { try? FileManager.default.removeItem(at: file) }
        objectWillChange.send()
        library.setLocalFile(nil, for: episode)
    }

    private func progressed(_ id: PersistentIdentifier, _ fraction: Double) {
        guard active[id] != nil else { return }
        active[id]?.progress = fraction
    }

    private func finished(_ episode: Episode, id: PersistentIdentifier, result: Result<URL, Error>) {
        // A cancelled download's late callback must change nothing.
        guard active.removeValue(forKey: id) != nil else {
            if case .success(let temporary) = result { try? FileManager.default.removeItem(at: temporary) }
            return
        }
        switch result {
        case .success(let temporary):
            let destination = EpisodeFiles.destination(for: episode, root: root)
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporary, to: destination)
                library.setLocalFile(destination, for: episode)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                failures[id] = Self.failedMessage
            }
        case .failure(let error):
            failures[id] = Connectivity.isOffline(error) ? Self.offlineMessage : Self.failedMessage
        }
    }
}
