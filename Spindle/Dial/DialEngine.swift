import Foundation

/// A moment on the dial worth a haptic bump.
enum Detent: Equatable {
    case tick(at: TimeInterval)
    case chapter(at: TimeInterval)
}

/// What one turn of the dial does: how far to seek and which detents it crossed.
struct DialStep: Equatable {
    let seek: TimeInterval
    let detents: [Detent]
}

/// Turns dial rotation into seconds of scrubbing, with speed-based acceleration,
/// and reports the 15-second ticks and chapter starts crossed on the way.
struct DialEngine {
    static let secondsPerDegree: Double = 120.0 / 360.0
    static let tickInterval: TimeInterval = 15

    private static let speedWindow: TimeInterval = 0.1
    private static let epsilon = 1e-9
    private static let chapterSnap: TimeInterval = 0.5

    private var samples: [(time: TimeInterval, degrees: Double)] = []

    mutating func turn(degrees: Double, at time: TimeInterval,
                       position: TimeInterval, duration: TimeInterval?,
                       chapters: [TimeInterval]) -> DialStep {
        // Keep samples in the half-open window (time - 0.1, time].
        samples.removeAll { $0.time <= time - Self.speedWindow + Self.epsilon }
        samples.append((time, abs(degrees)))
        let speed = samples.reduce(0) { $0 + $1.degrees } / Self.speedWindow
        let multiplier = speed <= 360 ? 1 : min(4, 1 + 3 * (speed - 360) / 1080)

        let target = position + degrees * Self.secondsPerDegree * multiplier
        let newPosition = min(max(target, 0), duration ?? .infinity)
        return DialStep(seek: newPosition - position,
                        detents: Self.detents(from: position, to: newPosition, chapters: chapters))
    }

    /// Forget the speed history.
    mutating func reset() {
        samples.removeAll()
    }

    private static func detents(from old: TimeInterval, to new: TimeInterval,
                                chapters: [TimeInterval]) -> [Detent] {
        guard old != new else { return [] }
        let forward = new > old
        let lo = min(old, new), hi = max(old, new)
        // Forward: lo < t <= hi. Backward: lo <= t < hi.
        func crossed(_ t: TimeInterval) -> Bool {
            guard t > 0 else { return false }
            return forward ? (t > lo && t <= hi) : (t >= lo && t < hi)
        }

        let crossedChapters = chapters.filter(crossed)
        var ticks: [TimeInterval] = []
        var k = (lo / tickInterval).rounded(.down) * tickInterval
        while k <= hi {
            if crossed(k) && !crossedChapters.contains(where: { abs($0 - k) <= chapterSnap }) {
                ticks.append(k)
            }
            k += tickInterval
        }

        var all: [Detent] = ticks.map { .tick(at: $0) } + crossedChapters.map { .chapter(at: $0) }
        func time(_ d: Detent) -> TimeInterval {
            switch d { case .tick(let t), .chapter(let t): return t }
        }
        all.sort { forward ? time($0) < time($1) : time($0) > time($1) }
        return all
    }
}
