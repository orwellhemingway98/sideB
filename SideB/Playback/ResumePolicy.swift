import Foundation

enum ResumePolicy {
    static let saveInterval: TimeInterval = 5
    static let rewind: TimeInterval = 3
    static let finishedWithin: TimeInterval = 30
    static let rates: [Float] = [1, 1.2, 1.5, 2]

    /// Resume a little before where you stopped.
    static func startPosition(saved: TimeInterval) -> TimeInterval {
        max(0, saved - rewind)
    }

    static func isFinished(position: TimeInterval, duration: TimeInterval?) -> Bool {
        guard let duration else { return false }
        return duration - position <= finishedWithin
    }

    /// 1 → 1.2 → 1.5 → 2 → 1; an unknown rate goes to 1.
    static func nextRate(after rate: Float) -> Float {
        guard let index = rates.firstIndex(of: rate) else { return 1 }
        return rates[(index + 1) % rates.count]
    }
}
