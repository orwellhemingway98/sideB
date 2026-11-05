import Foundation

enum HapticKind: Equatable { case tick, chapter }

/// Turns the detents one dial step crossed into at most one haptic.
/// Chapters always get through; ticks are held to one per 35 ms.
struct HapticLimiter {
    static let minInterval: TimeInterval = 0.035
    private static let epsilon: TimeInterval = 1e-9

    private var lastHaptic: TimeInterval?

    mutating func next(for detents: [Detent], at time: TimeInterval) -> HapticKind? {
        guard !detents.isEmpty else { return nil }
        let hasChapter = detents.contains { if case .chapter = $0 { return true } else { return false } }
        if hasChapter {
            lastHaptic = time
            return .chapter
        }
        if let last = lastHaptic, time - last < Self.minInterval - Self.epsilon { return nil }
        lastHaptic = time
        return .tick
    }
}
