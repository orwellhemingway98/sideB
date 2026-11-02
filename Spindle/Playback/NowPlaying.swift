import Combine
import AppKit

/// Who the dial is steering: the podcast, or whatever Apple Music or Spotify is playing.
enum PlaybackMode: Equatable {
    case podcast, music
}

/// The one object the dial, the windows and the media keys talk to. Podcasts and music take turns:
/// whichever was started most recently is in control.
@MainActor
final class NowPlaying: ObservableObject {
    static let commitDelay: TimeInterval = 0.15
    /// Turning with Option held: one full turn goes from silent to full.
    static let degreesPerPercent = 3.6
    /// How long the volume stays on the disc after the last turn.
    static let volumeShownFor: TimeInterval = 1

    let player: PodcastPlayer
    let music: MusicRemote?
    private let media: MediaCenterPublishing
    private let haptics: HapticPerforming
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private let now: () -> TimeInterval
    private let loadChapters: (Episode) async -> [Chapter]

    private var dial = DialEngine()
    private var limiter = HapticLimiter()
    private var generation = 0
    private let optionHeld: () -> Bool
    private var volumeGeneration = 0
    /// Part of a percent turned but not yet applied.
    private var volumeRemainder = 0.0
    private var chapterTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    @Published private(set) var chapters: [Chapter] = []
    @Published private(set) var scrubPosition: TimeInterval?
    @Published private(set) var mode: PlaybackMode = .podcast
    /// The volume being set with Option + turn, shown on the disc for a moment; nil otherwise.
    @Published private(set) var volumeShown: Int?

    init(player: PodcastPlayer, media: MediaCenterPublishing, haptics: HapticPerforming,
         schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void,
         now: @escaping () -> TimeInterval, loadChapters: @escaping (Episode) async -> [Chapter],
         music: MusicRemote? = nil, optionHeld: @escaping () -> Bool = { NSEvent.modifierFlags.contains(.option) }) {
        self.optionHeld = optionHeld
        self.player = player
        self.music = music
        self.media = media
        self.haptics = haptics
        self.schedule = schedule
        self.now = now
        self.loadChapters = loadChapters

        media.onCommand = { [weak self] in self?.handle($0) }

        // Published values arrive before they are stored, so each sink passes its own new value along.
        player.$episode.dropFirst().sink { [weak self] in self?.episodeChanged($0) }.store(in: &cancellables)
        player.$isPlaying.dropFirst().sink { [weak self] playing in
            if playing { self?.podcastStarted() }
            self?.publish(isPlaying: playing)
        }.store(in: &cancellables)
        player.$rate.dropFirst().sink { [weak self] in self?.publish(rate: $0) }.store(in: &cancellables)
        // A stream without a feed duration learns its length after it starts; tell the media center then.
        player.$engineDuration.compactMap { $0 }.sink { [weak self] _ in self?.publish() }.store(in: &cancellables)
        player.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)

        if let music {
            music.$isPlaying.dropFirst().removeDuplicates().sink { [weak self] playing in
                if playing { self?.musicStarted() }
            }.store(in: &cancellables)
            music.$track.map { $0?.trackID }.removeDuplicates().dropFirst().sink { [weak self] id in
                self?.musicTrackChanged(to: id)
            }.store(in: &cancellables)
            music.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
            if music.isPlaying, !player.isPlaying { mode = .music }
        }
    }

    // MARK: Who's in control

    /// The podcast waiting while music has the dial; the panel offers to resume it.
    var pausedEpisode: Episode? {
        mode == .music ? player.episode : nil
    }

    /// Plays the waiting podcast, which pauses the music and gives the dial back to the podcast.
    func resumePodcast() {
        guard mode == .music, player.episode != nil else { return }
        flushScrub()
        player.play()
    }

    /// Music started (seen by polling): the podcast pauses, keeping its place, and the dial follows the music.
    private func musicStarted() {
        guard mode != .music || player.isPlaying else { return }
        dropScrub()
        mode = .music
        if player.isPlaying { player.pause() }
        media.publish(nil)  // the music app publishes its own Now Playing
    }

    /// A podcast started: the music pauses and the dial follows the podcast again.
    private func podcastStarted() {
        // Polling may not have seen the music start yet, so pause any music app we know about;
        // pausing one that is already paused does nothing.
        if music?.track != nil { music?.pause() }
        guard mode != .podcast else { return }
        dropScrub()
        mode = .podcast
        publish()
    }

    private func musicTrackChanged(to id: String?) {
        guard mode == .music else { return }
        dropScrub()
        if id == nil {
            // The music went away (app quit, nothing loaded): back to the podcast, still paused.
            mode = .podcast
            publish()
        }
    }

    /// Forgets a pending scrub: it belonged to what was playing before.
    private func dropScrub() {
        generation += 1
        scrubPosition = nil
        dial.reset()
    }

    var displayPosition: TimeInterval {
        if let scrubPosition { return scrubPosition }
        return mode == .music ? music?.track?.position ?? 0 : player.position
    }

    /// The length of whatever the dial is steering.
    var displayDuration: TimeInterval? {
        guard mode == .music else { return player.duration }
        // Radio and live streams report no length: there's nothing to scrub.
        guard let duration = music?.track?.duration, duration > 0 else { return nil }
        return duration
    }

    private var hasSomethingToSteer: Bool {
        mode == .music ? displayDuration != nil : player.episode != nil
    }

    var currentChapter: Chapter? {
        let position = displayPosition
        return chapters.last { $0.start <= position }
    }

    // MARK: Dial

    func turn(degrees: Double) {
        guard hasSomethingToSteer else { return }
        if optionHeld() { return turnVolume(degrees: degrees) }
        let time = now()
        let position = displayPosition
        let step = dial.turn(degrees: degrees, at: time, position: position, duration: displayDuration,
                             chapters: mode == .music ? [] : chapters.map(\.start))
        if let kind = limiter.next(for: step.detents, at: time) { haptics.perform(kind) }
        scrubPosition = position + step.seek
        generation += 1
        let mine = generation
        schedule(Self.commitDelay) { [weak self] in
            guard let self, self.generation == mine else { return }
            self.commit()
        }
    }

    /// The volume of whatever the dial steers: Spindle's own for a podcast, the app's for music.
    private var currentVolume: Int? {
        mode == .music ? music?.volume : player.volume
    }

    /// Option + turn: a tick every 10%, a firmer stop at 0 and 100. A podcast's volume follows at once;
    /// a music app's is set once the turning pauses, so a fast turn isn't one script per percent.
    private func turnVolume(degrees: Double) {
        guard let base = volumeShown ?? currentVolume else { return }
        volumeRemainder += degrees / Self.degreesPerPercent
        let steps = Int(volumeRemainder.rounded(.towardZero))
        volumeRemainder -= Double(steps)
        let target = min(100, max(0, base + steps))
        if target != base {
            if target == 0 || target == 100 {
                haptics.perform(.chapter)
            } else {
                let passed = target > base ? Array(base + 1...target) : Array(target...base - 1)
                if passed.contains(where: { $0 % 10 == 0 }) { haptics.perform(.tick) }
            }
        }
        // Turning further past an end is dropped, so turning back responds at once.
        if (target == 100 && volumeRemainder > 0) || (target == 0 && volumeRemainder < 0) { volumeRemainder = 0 }
        volumeShown = target
        volumeGeneration += 1
        let mine = volumeGeneration
        if mode == .music {
            schedule(Self.commitDelay) { [weak self] in
                guard let self, self.volumeGeneration == mine else { return }
                self.music?.setVolume(target)
            }
        } else {
            player.setVolume(target)
        }
        schedule(Self.volumeShownFor) { [weak self] in
            guard let self, self.volumeGeneration == mine else { return }
            self.volumeShown = nil
            self.volumeRemainder = 0
        }
    }

    func jump(to time: TimeInterval) {
        guard hasSomethingToSteer else { return }
        generation += 1
        var target = max(0, time)
        if let duration = displayDuration { target = min(target, duration) }
        seek(to: target)
        scrubPosition = nil
        publish()
    }

    private func commit() {
        guard let target = scrubPosition else { return }
        seek(to: target)
        scrubPosition = nil
        publish()
    }

    private func seek(to target: TimeInterval) {
        if mode == .music { music?.setPosition(target) } else { player.seek(to: target) }
    }

    // MARK: Transport

    /// Commits a pending scrub now, so the next action (or quitting) starts from what the dial shows.
    /// The scheduled commit then finds a newer generation and does nothing.
    func flushScrub() {
        guard scrubPosition != nil else { return }
        generation += 1
        commit()
    }

    func toggle() {
        flushScrub()
        if mode == .music { music?.playPause() } else { player.toggle() }
    }

    /// The music's previous and next tracks (podcasts have no such thing).
    func next() {
        guard mode == .music else { return }
        dropScrub()
        music?.next()
    }

    func previous() {
        guard mode == .music else { return }
        dropScrub()
        music?.previous()
    }

    /// The disc's 9 o'clock: the previous song, or 15 seconds back in a podcast.
    func back() {
        if mode == .music { previous() } else { skip(by: -15) }
    }

    /// The disc's 3 o'clock: the next song, or 30 seconds on in a podcast.
    func forward() {
        if mode == .music { next() } else { skip(by: 30) }
    }

    /// Starts from what the dial shows and wins over any pending scrub commit.
    func skip(by seconds: TimeInterval) {
        jump(to: displayPosition + seconds)
    }

    func cycleRate() { player.cycleRate() }

    func play(_ episode: Episode) {
        flushScrub()
        // Opening starts playback, which hands control to the podcast; if it was already playing,
        // isPlaying doesn't change, so hand control over here.
        let wasPlaying = player.isPlaying
        player.open(episode, autoplay: true)
        if wasPlaying { podcastStarted() }
        publish()
    }

    private func setRate(_ rate: Float) {
        guard ResumePolicy.rates.contains(rate) else { return }
        var steps = 0
        while player.rate != rate, steps < ResumePolicy.rates.count {
            player.cycleRate()
            steps += 1
        }
    }

    private func handle(_ command: MediaCommand) {
        // In music mode Spindle publishes nothing, so these belong to the podcast only.
        guard mode == .podcast else { return }
        switch command {
        case .play: flushScrub(); player.play()
        case .pause: flushScrub(); player.pause()
        case .toggle: toggle()
        case .skip(let seconds): skip(by: seconds)
        case .seek(let time): jump(to: time)
        case .rate(let rate): setRate(rate)
        }
    }

    // MARK: Chapters

    func episodeChanged(_ episode: Episode?) {
        chapterTask?.cancel()
        chapters = []
        scrubPosition = nil
        generation += 1
        dial.reset()
        guard let episode else {
            media.publish(nil)
            return
        }
        if mode == .podcast { publish(episode: episode, position: 0) }
        chapterTask = Task { [weak self, loadChapters] in
            let loaded = await loadChapters(episode)
            guard let self, !Task.isCancelled, self.player.episode === episode else { return }
            self.chapters = loaded
        }
    }

    // MARK: Publishing

    private func publish(isPlaying: Bool? = nil, rate: Float? = nil) {
        guard mode == .podcast else { return }
        guard let episode = player.episode else {
            media.publish(nil)
            return
        }
        publish(episode: episode, position: player.position, isPlaying: isPlaying, rate: rate)
    }

    private func publish(episode: Episode, position: TimeInterval, isPlaying: Bool? = nil, rate: Float? = nil) {
        media.publish(NowPlayingInfo(
            title: episode.title,
            subtitle: episode.show?.title ?? "",
            artworkURL: nil,
            duration: player.duration,
            position: position,
            rate: rate ?? player.rate,
            isPlaying: isPlaying ?? player.isPlaying))
    }
}
