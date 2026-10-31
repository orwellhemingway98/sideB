import AVFoundation

@MainActor
final class AVPlayerEngine: AudioEngine {
    private let player = AVPlayer()
    private var item: AVPlayerItem?
    private var statusObservation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    private var timeObserver: Any?
    private var isPlaying = false
    private var pendingStart: TimeInterval = 0
    /// True from load until the resume seek has completed; ticks in between would report a pre-resume time.
    private var seekOutstanding = false

    var onTime: ((TimeInterval) -> Void)?
    var onEnd: (() -> Void)?
    var onFailure: ((Error) -> Void)?

    /// Stored while paused and applied on `play()`: setting `player.rate` would start playback.
    var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if isPlaying { player.rate = rate }
        }
    }

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, !self.seekOutstanding, time.isNumeric else { return }
                self.onTime?(time.seconds)
            }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var currentTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    var duration: TimeInterval? {
        guard let item, item.status == .readyToPlay else { return nil }
        let seconds = item.duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }

    func load(_ url: URL, at time: TimeInterval) {
        tearDownItem()
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain
        self.item = item
        pendingStart = time
        seekOutstanding = time > 0
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let error = item.error ?? URLError(.unknown)
            Task { @MainActor in
                // Drop callbacks from an item that has since been replaced.
                guard let self, self.item === item else { return }
                switch status {
                case .readyToPlay: self.seekToPendingStart()
                case .failed: self.onFailure?(error)
                default: break
                }
            }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                            object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.item === item { self?.onEnd?() } }
        })
        observers.append(center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                                            object: item, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error ?? URLError(.unknown)
            MainActor.assumeIsolated { if self?.item === item { self?.onFailure?(error) } }
        })
        player.replaceCurrentItem(with: item)
    }

    func play() {
        isPlaying = true
        player.defaultRate = rate
        player.play()
    }

    func pause() {
        isPlaying = false
        player.pause()
    }

    func seek(to time: TimeInterval) {
        if let item, item.status != .readyToPlay {
            // Not ready yet: replace the resume point so the seek can't be lost.
            pendingStart = time
            seekOutstanding = time > 0
            return
        }
        pendingStart = 0
        seekOutstanding = false
        player.seek(to: CMTime(seconds: max(0, time), preferredTimescale: 600))
    }

    /// The resume point is applied once the item is ready; seeking earlier is lost on some remote MP3s.
    private func seekToPendingStart() {
        let time = pendingStart
        pendingStart = 0
        guard time > 0 else { seekOutstanding = false; return }
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.seekOutstanding = false
                self.onTime?(self.currentTime)
            }
        }
    }

    private func tearDownItem() {
        statusObservation = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}
