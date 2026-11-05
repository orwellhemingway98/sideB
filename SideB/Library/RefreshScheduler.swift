import Foundation

/// Checks every show at launch and then every hour. A refresh asked for while one is running joins it,
/// so the Refresh button and the hourly timer never fetch the same feeds twice at once.
@MainActor
final class RefreshScheduler: ObservableObject {
    static let interval: TimeInterval = 3600

    @Published private(set) var isRefreshing = false

    private let refresh: @MainActor () async -> Void
    private let every: (TimeInterval, @escaping @MainActor () -> Void) -> AnyObject
    private var inFlight: Task<Void, Never>?
    private var timer: AnyObject?

    /// `every` schedules a repeating tick and returns a token; dropping the token cancels it.
    init(refresh: @escaping @MainActor () async -> Void,
         every: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> AnyObject = RefreshScheduler.repeatingTimer) {
        self.refresh = refresh
        self.every = every
    }

    /// Refreshes now, then every `interval`.
    func start() {
        trigger()
        timer = every(Self.interval) { [weak self] in self?.trigger() }
    }

    func refreshNow() async {
        trigger()
        await inFlight?.value
    }

    /// Starts a refresh unless one is already running.
    private func trigger() {
        guard inFlight == nil else { return }
        isRefreshing = true
        inFlight = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            self.inFlight = nil
            self.isRefreshing = false
        }
    }

    /// A main-run-loop timer with a minute's tolerance, wrapped so releasing it invalidates it.
    nonisolated static func repeatingTimer(_ interval: TimeInterval, _ tick: @escaping @MainActor () -> Void) -> AnyObject {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated(tick) }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        return TimerToken(timer)
    }

    private final class TimerToken {
        private let timer: Timer
        init(_ timer: Timer) { self.timer = timer }
        deinit { timer.invalidate() }
    }
}
