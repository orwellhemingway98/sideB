import Foundation

@MainActor
final class PodcastPlayer: ObservableObject {
    private let engine: AudioEngine
    private let library: LibraryStore

    @Published private(set) var episode: Episode?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var rate: Float = 1
    /// "Offline" or "Unavailable".
    @Published private(set) var failure: String?

    private var lastSaved: TimeInterval = 0
    private var finished = false
    private var needsReload = false

    init(engine: AudioEngine, library: LibraryStore) {
        self.engine = engine
        self.library = library
        engine.onTime = { [weak self] time in self?.handleTime(time) }
        engine.onEnd = { [weak self] in self?.finish() }
        engine.onFailure = { [weak self] error in self?.handleFailure(error) }
    }

    var duration: TimeInterval? { engine.duration ?? episode?.duration }

    // MARK: Opening

    func open(_ episode: Episode, autoplay: Bool) {
        saveNow()
        self.episode = episode
        failure = nil
        finished = false
        needsReload = false
        load(episode)
        engine.rate = rate
        library.lastEpisodeGUID = episode.guid
        if autoplay { play() } else { isPlaying = false }
    }

    private func load(_ episode: Episode) {
        let start = episode.played ? 0 : ResumePolicy.startPosition(saved: episode.position)
        engine.load(episode.playableURL, at: start)
        position = start
        lastSaved = start
    }

    // MARK: Transport

    func play() {
        guard let episode else { return }
        if needsReload {
            needsReload = false
            failure = nil
            load(episode)
        }
        engine.play()
        isPlaying = true
    }

    func pause() {
        engine.pause()
        isPlaying = false
        saveNow()
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: TimeInterval) {
        guard episode != nil else { return }
        let target = clamp(time)
        engine.seek(to: target)
        position = target
        saveNow()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: position + seconds)
    }

    func cycleRate() {
        rate = ResumePolicy.nextRate(after: rate)
        engine.rate = rate
    }

    func saveNow() {
        guard let episode, !finished else { return }
        library.savePosition(position, of: episode)
        lastSaved = position
    }

    private func clamp(_ time: TimeInterval) -> TimeInterval {
        var target = max(0, time)
        if let duration { target = min(target, duration) }
        return target
    }

    // MARK: Engine callbacks

    private func handleTime(_ time: TimeInterval) {
        guard episode != nil, !finished else { return }
        position = time
        if ResumePolicy.isFinished(position: time, duration: duration) {
            finish()
        } else if abs(time - lastSaved) >= ResumePolicy.saveInterval {
            saveNow()
        }
    }

    /// Runs once per episode, whether the end arrives as a callback or as a time near the end.
    private func finish() {
        guard let episode, !finished else { return }
        finished = true
        library.markPlayed(episode)
        advance()
    }

    private func advance() {
        if let next = library.popNext() {
            open(next, autoplay: true)
        } else {
            engine.pause()
            isPlaying = false
        }
    }

    private func handleFailure(_ error: Error) {
        guard episode != nil else { return }
        if Self.isOffline(error) {
            saveNow()
            engine.pause()
            isPlaying = false
            needsReload = true
            failure = "Offline"
        } else {
            let hadNext = library.upNext.first != nil
            if let episode, !hadNext { library.savePosition(position, of: episode) }
            advance()
            failure = "Unavailable"
        }
    }

    private static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost: return true
        default: return false
        }
    }
}
