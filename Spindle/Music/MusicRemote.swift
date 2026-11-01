import AppKit

/// Follows whatever Apple Music or Spotify is playing (polled every second) and forwards commands to it.
/// Modelled on ClickWheel's PlayerHub. It never scripts an app that isn't running, since that would
/// launch it, and an app that declined permission is left alone until relaunch so macOS doesn't keep asking.
@MainActor
final class MusicRemote: ObservableObject {
    static let pollInterval: TimeInterval = 1
    /// A poll this close to a seek we asked for means the app has caught up.
    private static let seekTolerance: Double = 1.5
    /// Polls that may still report the old position after a seek, before we believe them.
    private static let pollsToIgnoreAfterSeek = 2

    @Published private(set) var track: MusicTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    /// The last album or playlist read failed (permission, Music quit, timeout).
    @Published private(set) var contextFailed = false
    /// Which album or playlist the current song plays from (worked out once per song, cheaply).
    @Published private(set) var contextKey: String?

    /// Album or playlist, for the cover's hint.
    var contextKind: MusicContext.Kind? {
        guard let contextKey else { return nil }
        return contextKey.hasPrefix("playlist:") ? .playlist : .album
    }

    /// The most recent command, so callers (and tests) can await it.
    private(set) var lastCommand: Task<Void, Never>?

    private let sources: [MusicSource]
    private let every: (TimeInterval, @escaping @MainActor () -> Void) -> AnyObject
    private var timer: AnyObject?
    private var isRefreshing = false
    private var lastActive: MusicSourceID?
    private var declined: Set<MusicSourceID> = []
    private var pendingSeek: (trackID: String, seconds: Double, pollsLeft: Int)?
    private var artworkTrackID: String?
    /// Albums and playlists already read, by context id ("playlist:…" / "album:…").
    private var contexts: [String: MusicContext] = [:]
    private var contextSource: MusicSourceID?
    /// Reads in progress, shared by everyone who asks for the same list.
    private var contextReads: [String: Task<Result<MusicContext?, MusicSourceError>, Never>] = [:]
    /// Which list the current song plays from, and for which song that was worked out.
    private var keyTrackID: String?

    init(sources: [MusicSource],
         every: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> AnyObject = RefreshScheduler.repeatingTimer) {
        self.sources = sources
        self.every = every
    }

    var source: MusicSourceID? { track?.source }

    private var activeSource: MusicSource? {
        sources.first { $0.id == track?.source }
    }

    func start() {
        Task { await refresh() }
        timer = every(Self.pollInterval) { [weak self] in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let wanted = sources.filter { !declined.contains($0.id) }
        let results = await Task.detached { () -> [(MusicSourceID, Result<MusicSnapshot, MusicSourceError>)] in
            wanted.compactMap { source in
                guard source.isRunning() else { return nil }
                do { return (source.id, .success(try source.snapshot())) }
                catch let error as MusicSourceError { return (source.id, .failure(error)) }
                catch { return (source.id, .failure(.scriptFailed(error.localizedDescription))) }
            }
        }.value
        apply(results)
        // A new song: work out which list it plays from (for the cover's hint), once per song.
        if let song = track, song.trackID != keyTrackID,
           let source = sources.first(where: { $0.id == song.source }) {
            await updateContextKey(for: song, source: source)
        }
    }

    func playPause() { command { try $0.playPause() } }
    func pause() { command { try $0.pause() } }
    func next() { command { try $0.next() } }
    func previous() { command { try $0.previous() } }

    func setPosition(_ seconds: Double) {
        guard var current = track else { return }
        let target = min(max(0, seconds), current.duration)
        pendingSeek = (current.trackID, target, Self.pollsToIgnoreAfterSeek)
        current.position = target
        track = current
        command { try $0.setPosition(target) }
    }

    // MARK: - Album or playlist

    /// The album or playlist `track` plays from. Read once off the main actor and cached, so the next song on
    /// the same album costs nothing. Nil when the app can't say; `contextFailed` tells a read error apart.
    /// The album or playlist `track` plays from. Cached by that list's id (a song on two lists shows the one it
    /// is playing from); `refresh` reads Music again, so opening the list picks up playlist edits. Overlapping
    /// requests share one read. Nil when the app can't say; `contextFailed` tells a read error apart.
    func context(for track: MusicTrack, refresh: Bool = false) async -> MusicContext? {
        if contextSource != track.source {
            contexts = [:]
            contextReads = [:]
            contextSource = track.source
        }
        guard let source = sources.first(where: { $0.id == track.source }) else { return nil }
        // Cheap, and asked every time: the same song may now be playing from a different list.
        await updateContextKey(for: track, source: source)
        let key = contextKey ?? "song:" + track.trackID
        if !refresh, let cached = contexts[key] {
            setContextFailed(false)
            return cached
        }
        let read: Task<Result<MusicContext?, MusicSourceError>, Never>
        if let running = contextReads[key] {
            read = running
        } else {
            read = Task.detached {
                do { return .success(try source.context()) }
                catch let error as MusicSourceError { return .failure(error) }
                catch { return .failure(.scriptFailed(error.localizedDescription)) }
            }
            contextReads[key] = read
        }
        let result = await read.value
        contextReads[key] = nil
        switch result {
        case .success(let context?):
            contexts[key] = context
            setContextFailed(false)
            return context
        case .success(nil):
            setContextFailed(false)
            return nil
        case .failure:
            setContextFailed(true)
            return nil
        }
    }

    /// Only announce a change when there is one: every announcement wakes the list.
    private func setContextFailed(_ value: Bool) {
        if contextFailed != value { contextFailed = value }
    }

    /// Asks the app which list the song plays from (a quick script, once per song).
    private func updateContextKey(for track: MusicTrack, source: MusicSource) async {
        let trackID = track.trackID
        let key = await Task.detached { try? source.contextKey() }.value ?? nil
        // A late answer for a song that has since changed is dropped.
        guard self.track?.trackID == trackID else { return }
        keyTrackID = trackID
        if contextKey != key { contextKey = key }
    }

    /// Plays a song from the list, carrying on through its album or playlist.
    func play(contextTrack: ContextTrack, in context: MusicContext) {
        command { try $0.play(trackID: contextTrack.id, in: context) }
    }

    // MARK: - Private

    private func apply(_ results: [(MusicSourceID, Result<MusicSnapshot, MusicSourceError>)]) {
        var snapshots: [MusicSourceID: MusicSnapshot] = [:]
        for (id, result) in results {
            switch result {
            case .success(let snapshot): snapshots[id] = snapshot
            case .failure(.permissionDenied): declined.insert(id)
            case .failure: break
            }
        }
        let order = MusicSourceID.allCases.filter { snapshots[$0] != nil }
        let playing = order.filter { snapshots[$0]?.state == .playing && snapshots[$0]?.track != nil }
        let withTrack = order.filter { snapshots[$0]?.track != nil }
        let chosen: MusicSourceID?
        if let last = lastActive, playing.contains(last) {
            chosen = last
        } else if let first = playing.first {
            chosen = first
        } else if let last = lastActive, withTrack.contains(last) {
            chosen = last
        } else {
            chosen = withTrack.first
        }
        if let chosen { lastActive = chosen }

        let snapshot = chosen.flatMap { snapshots[$0] }
        var newTrack = snapshot?.track
        if var polled = newTrack, let pending = pendingSeek {
            if pending.trackID != polled.trackID || abs(polled.position - pending.seconds) <= Self.seekTolerance
                || pending.pollsLeft == 0 {
                pendingSeek = nil
            } else {
                polled.position = pending.seconds
                pendingSeek = (pending.trackID, pending.seconds, pending.pollsLeft - 1)
                newTrack = polled
            }
        } else if newTrack == nil {
            pendingSeek = nil
        }
        if track != newTrack { track = newTrack }
        if newTrack == nil, contextKey != nil {
            contextKey = nil
            keyTrackID = nil
        }
        let nowPlaying = snapshot?.state == .playing && newTrack != nil
        if isPlaying != nowPlaying { isPlaying = nowPlaying }
        loadArtworkIfNeeded()
    }

    private func loadArtworkIfNeeded() {
        guard let track, let source = activeSource else {
            artworkTrackID = nil
            artwork = nil
            return
        }
        guard track.trackID != artworkTrackID else { return }
        artworkTrackID = track.trackID
        artwork = nil
        let trackID = track.trackID
        Task {
            let ref = await Task.detached { (try? source.artwork()) ?? .none }.value
            let data: Data?
            switch ref {
            case .data(let raw): data = raw
            case .url(let url): data = try? await URLSession.shared.data(from: url).0
            case .none: data = nil
            }
            guard self.artworkTrackID == trackID, let data, let image = NSImage(data: data) else { return }
            self.artwork = image
        }
    }

    private func command(_ action: @escaping @Sendable (MusicSource) throws -> Void) {
        guard let source = activeSource else {
            lastCommand = nil
            return
        }
        lastCommand = Task {
            let error = await Task.detached { () -> MusicSourceError? in
                do { try action(source); return nil }
                catch let error as MusicSourceError { return error }
                catch { return .scriptFailed(error.localizedDescription) }
            }.value
            if case .permissionDenied = error { declined.insert(source.id) }
            await refresh()
        }
    }
}
