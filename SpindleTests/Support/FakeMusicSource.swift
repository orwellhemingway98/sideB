import Foundation
@testable import Spindle

/// A music app the test drives: whether it runs, what it reports, and which commands it got.
/// MusicRemote calls it off the main actor, so its state is locked.
final class FakeMusicSource: MusicSource, @unchecked Sendable {
    enum Command: Equatable { case playPause, pause, next, previous, setPosition(Double) }

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

    init(_ id: MusicSourceID) { self.id = id }

    var running: Bool { get { lock.withLock { _running } } set { lock.withLock { _running = newValue } } }
    var failure: MusicSourceError? { get { lock.withLock { _failure } } set { lock.withLock { _failure = newValue } } }
    var artworkRef: ArtworkRef { get { lock.withLock { _artwork } } set { lock.withLock { _artwork = newValue } } }
    var commands: [Command] { lock.withLock { _commands } }
    var snapshotCalls: Int { lock.withLock { _snapshotCalls } }
    var artworkCalls: Int { lock.withLock { _artworkCalls } }

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
        lock.withLock { _artworkCalls += 1; return _artwork }
    }

    private func record(_ command: Command) { lock.withLock { _commands.append(command) } }
    func playPause() throws { record(.playPause) }
    func pause() throws { record(.pause) }
    func next() throws { record(.next) }
    func previous() throws { record(.previous) }
    func setPosition(_ seconds: Double) throws { record(.setPosition(seconds)) }
}
