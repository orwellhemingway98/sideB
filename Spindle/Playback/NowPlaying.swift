import Combine
import Foundation

/// The one object the dial, the windows and the media keys talk to.
@MainActor
final class NowPlaying: ObservableObject {
    static let commitDelay: TimeInterval = 0.15

    let player: PodcastPlayer
    private let media: MediaCenterPublishing
    private let haptics: HapticPerforming
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private let now: () -> TimeInterval
    private let loadChapters: (Episode) async -> [Chapter]

    private var dial = DialEngine()
    private var limiter = HapticLimiter()
    private var generation = 0
    private var chapterTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    @Published private(set) var chapters: [Chapter] = []
    @Published private(set) var scrubPosition: TimeInterval?

    init(player: PodcastPlayer, media: MediaCenterPublishing, haptics: HapticPerforming,
         schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void,
         now: @escaping () -> TimeInterval, loadChapters: @escaping (Episode) async -> [Chapter]) {
        self.player = player
        self.media = media
        self.haptics = haptics
        self.schedule = schedule
        self.now = now
        self.loadChapters = loadChapters

        media.onCommand = { [weak self] in self?.handle($0) }

        // Published values arrive before they are stored, so each sink passes its own new value along.
        player.$episode.dropFirst().sink { [weak self] in self?.episodeChanged($0) }.store(in: &cancellables)
        player.$isPlaying.dropFirst().sink { [weak self] in self?.publish(isPlaying: $0) }.store(in: &cancellables)
        player.$rate.dropFirst().sink { [weak self] in self?.publish(rate: $0) }.store(in: &cancellables)
        player.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    var displayPosition: TimeInterval { scrubPosition ?? player.position }

    var currentChapter: Chapter? {
        let position = displayPosition
        return chapters.last { $0.start <= position }
    }

    // MARK: Dial

    func turn(degrees: Double) {
        guard player.episode != nil else { return }
        let time = now()
        let position = displayPosition
        let step = dial.turn(degrees: degrees, at: time, position: position,
                             duration: player.duration, chapters: chapters.map(\.start))
        if let kind = limiter.next(for: step.detents, at: time) { haptics.perform(kind) }
        scrubPosition = position + step.seek
        generation += 1
        let mine = generation
        schedule(Self.commitDelay) { [weak self] in
            guard let self, self.generation == mine else { return }
            self.commit()
        }
    }

    func jump(to time: TimeInterval) {
        guard player.episode != nil else { return }
        generation += 1
        var target = max(0, time)
        if let duration = player.duration { target = min(target, duration) }
        player.seek(to: target)
        scrubPosition = nil
        publish()
    }

    private func commit() {
        guard let target = scrubPosition else { return }
        player.seek(to: target)
        scrubPosition = nil
        publish()
    }

    // MARK: Transport

    func toggle() { player.toggle() }

    /// Starts from what the dial shows and wins over any pending scrub commit.
    func skip(by seconds: TimeInterval) {
        jump(to: displayPosition + seconds)
    }

    func cycleRate() { player.cycleRate() }

    func play(_ episode: Episode) {
        player.open(episode, autoplay: true)
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
        switch command {
        case .play: player.play()
        case .pause: player.pause()
        case .toggle: player.toggle()
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
        publish(episode: episode, position: 0)
        chapterTask = Task { [weak self, loadChapters] in
            let loaded = await loadChapters(episode)
            guard let self, !Task.isCancelled, self.player.episode === episode else { return }
            self.chapters = loaded
        }
    }

    // MARK: Publishing

    private func publish(isPlaying: Bool? = nil, rate: Float? = nil) {
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
