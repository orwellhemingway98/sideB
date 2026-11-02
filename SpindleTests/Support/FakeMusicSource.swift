import Foundation
@testable import Spindle

/// A music app the test drives: whether it runs, what it reports, and which commands it got.
/// MusicRemote calls it off the main actor, so its state is locked.
final class FakeMusicSource: MusicSource, @unchecked Sendable {
    enum Command: Equatable { case playPause, pause, next, previous, setPosition(Double), setVolume(Int) }

    let id: MusicSourceID
    var displayName: String { id.displayName }
    private let lock = NSLock()
    private var _running = true
    private var _snapshot = MusicSnapshot(state: .stopped, track: nil, volume: 50)
    private var _failure: MusicSourceError?
    private var _artwork: ArtworkRef = .none
    private var _commands: [Command] = []
    private var _snapshotCalls = 0
    private var _artworkCalls = 0
    private var _contextResult: Result<MusicContext?, MusicSourceError> = .success(nil)
    private var _contextCalls = 0
    private var _contextKey: String?
    private var _contextKeyCalls = 0
    private var _playedInContext: [(trackID: String, contextID: String)] = []
    private var _ignoresVolume = false
    private var _artworkGate: DispatchSemaphore?

    init(_ id: MusicSourceID) { self.id = id }

    var running: Bool { get { lock.withLock { _running } } set { lock.withLock { _running = newValue } } }
    var failure: MusicSourceError? { get { lock.withLock { _failure } } set { lock.withLock { _failure = newValue } } }
    var artworkRef: ArtworkRef { get { lock.withLock { _artwork } } set { lock.withLock { _artwork = newValue } } }
    var commands: [Command] { lock.withLock { _commands } }
    var snapshotCalls: Int { lock.withLock { _snapshotCalls } }
    var artworkCalls: Int { lock.withLock { _artworkCalls } }
    /// What context() answers (nil by default, like Spotify).
    var contextResult: Result<MusicContext?, MusicSourceError> {
        get { lock.withLock { _contextResult } } set { lock.withLock { _contextResult = newValue } }
    }
    var contextCalls: Int { lock.withLock { _contextCalls } }
    /// What contextKey() answers: which album or playlist the current song plays from.
    var contextKeyValue: String? { get { lock.withLock { _contextKey } } set { lock.withLock { _contextKey = newValue } } }
    var contextKeyCalls: Int { lock.withLock { _contextKeyCalls } }
    var playedInContext: [(trackID: String, contextID: String)] { lock.withLock { _playedInContext } }
    /// Like an app slow to report a new volume: keeps reporting the old one.
    /// When set, artwork() waits for a signal, like a slow download.
    var artworkGate: DispatchSemaphore? { get { lock.withLock { _artworkGate } } set { lock.withLock { _artworkGate = newValue } } }
    var ignoresVolume: Bool { get { lock.withLock { _ignoresVolume } } set { lock.withLock { _ignoresVolume = newValue } } }

    /// Reports a track in the given state.
    func play(_ title: String, id trackID: String = "t1", state: MusicPlayerState = .playing,
              position: Double = 0, duration: Double = 240, artist: String = "Northern Static") {
        let track = MusicTrack(trackID: trackID, title: title, artist: artist, album: "Album",
                               duration: duration, position: position, index: nil, count: nil, source: id)
        lock.withLock { _snapshot = MusicSnapshot(state: state, track: track, volume: 50) }
    }

    func stop() {
        lock.withLock { _snapshot = MusicSnapshot(state: .stopped, track: nil, volume: 50) }
    }

    func isRunning() -> Bool { running }

    func snapshot() throws -> MusicSnapshot {
        try lock.withLock {
            _snapshotCalls += 1
            if let failure = _failure { throw failure }
            return _snapshot
        }
    }

    func artwork() throws -> ArtworkRef {
        artworkGate?.wait()
        return lock.withLock { _artworkCalls += 1; return _artwork }
    }

    func context() throws -> MusicContext? {
        try lock.withLock {
            _contextCalls += 1
            return try _contextResult.get()
        }
    }

    func contextKey() throws -> String? {
        lock.withLock { _contextKeyCalls += 1; return _contextKey }
    }

    func play(trackID: String, in context: MusicContext) throws {
        lock.withLock { _playedInContext.append((trackID, context.id)) }
    }

    private func record(_ command: Command) { lock.withLock { _commands.append(command) } }
    func playPause() throws { record(.playPause) }
    func pause() throws { record(.pause) }
    func next() throws { record(.next) }
    func previous() throws { record(.previous) }
    func setPosition(_ seconds: Double) throws { record(.setPosition(seconds)) }
    func setVolume(_ percent: Int) throws {
        record(.setVolume(percent))
        lock.withLock { if !_ignoresVolume { _snapshot.volume = percent } }
    }
}
