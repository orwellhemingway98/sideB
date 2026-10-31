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
    /// The engine's duration once the stream reports it (nil until then, and after each load), so the
    /// media center can be told the length of an episode whose feed didn't give one.
    @Published private(set) var engineDuration: TimeInterval?

    private var lastSaved: TimeInterval = 0
    private var finished = false
    /// Where the current load started. Until playback moves away from it (or the user seeks), the place
    /// is the saved one, not progress: the resume rewind must never be written back.
    private var loadPoint: TimeInterval = 0
    private var progressed = false
    /// Inside the last 30 s: the episode is already marked played with its place reset, so nothing is saved.
    private var inPlayedWindow = false
    private var needsReload = false
    /// Bumped on every load. A failure is handled at most once per generation; a failure in a new
    /// generation (the next episode opened after a dead link) is handled normally.
    /// True after a load at a resume point until the first tick near it: until then `position` is not real
    /// progress, so stray early ticks are ignored and nothing is saved.
    private var awaitingResume = false
    private var generation = 0
    private var failureHandledIn = -1

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
        library.remove(fromUpNext: episode)
        load(episode)
        engine.rate = rate
        library.rememberLastEpisode(episode)
        if autoplay { play() } else { isPlaying = false }
    }

    private func load(_ episode: Episode) {
        let start = ResumePolicy.startPosition(saved: episode.position)
        generation += 1
        engine.load(episode.playableURL, at: start)
        position = start
        lastSaved = start
        loadPoint = start
        progressed = false
        inPlayedWindow = false
        engineDuration = nil
        awaitingResume = start > 0
    }

    // MARK: Transport

    func play() {
        guard let episode else { return }
        if finished {
            // Replaying after the end: start over, tracking and saving again.
            finished = false
            inPlayedWindow = false
            progressed = true
            engine.seek(to: 0)
            position = 0
            lastSaved = 0
        }
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
        finished = false
        awaitingResume = false
        progressed = true
        let target = clamp(time)
        engine.seek(to: target)
        position = target
        updatePlayedWindow()
        saveNow()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: position + seconds)
    }

    /// Adds to Up Next, except the episode that is playing: it would only play again from the start.
    func enqueue(_ episode: Episode) {
        guard episode !== self.episode else { return }
        library.enqueue(episode)
    }

    func cycleRate() {
        rate = ResumePolicy.nextRate(after: rate)
        engine.rate = rate
    }

    /// Saves the place, but only real progress: not the rewound resume point, not inside the last 30 s.
    func saveNow() {
        guard let episode, !finished, !awaitingResume, progressed, !inPlayedWindow else { return }
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
        if engineDuration == nil, let known = engine.duration { engineDuration = known }
        if awaitingResume {
            // A tick far before the resume point comes from the item before its resume seek has landed.
            guard abs(time - position) <= ResumePolicy.saveInterval else { return }
            awaitingResume = false
        }
        if failure == "Unavailable", !needsReload { failure = nil }
        if let episode, episode.unavailable { library.setUnavailable(false, for: episode) }
        position = time
        if abs(time - loadPoint) > Self.stillAtLoadPoint { progressed = true }
        updatePlayedWindow()
        if abs(time - lastSaved) >= ResumePolicy.saveInterval {
            saveNow()
        }
    }

    /// Ticks this close to the load point are the resume seek landing, not listening.
    private static let stillAtLoadPoint: TimeInterval = 0.25

    /// Entering the last 30 s marks the episode played (once) and resets its place; playback carries on
    /// to the real end. Leaving the window by seeking back un-marks it.
    private func updatePlayedWindow() {
        guard let episode else { return }
        let inside = ResumePolicy.isFinished(position: position, duration: duration)
        guard inside != inPlayedWindow else { return }
        inPlayedWindow = inside
        if inside {
            library.markPlayed(episode)
        } else {
            library.markUnplayed(episode)
        }
    }

    /// Runs once per episode, at the engine's end. Up Next advances only here.
    private func finish() {
        guard let episode, !finished else { return }
        finished = true
        if !inPlayedWindow { library.markPlayed(episode) }
        inPlayedWindow = false
        advance()
    }

    /// Opens the next Up Next item; returns false (stopped, paused) when nothing is queued.
    @discardableResult
    private func advance() -> Bool {
        if let next = library.popNext() {
            open(next, autoplay: true)
            return true
        }
        engine.pause()
        isPlaying = false
        return false
    }

    private func handleFailure(_ error: Error) {
        guard episode != nil, !finished, failureHandledIn != generation else { return }
        failureHandledIn = generation
        if Connectivity.isOffline(error) {
            saveNow()
            engine.pause()
            isPlaying = false
            needsReload = true
            failure = "Offline"
        } else {
            saveNow()
            if let dead = episode { library.setUnavailable(true, for: dead) }
            if !advance() { needsReload = true }
            failure = "Unavailable"
        }
    }
}
