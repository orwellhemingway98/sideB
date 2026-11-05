import Foundation

enum TimeFormat {
    /// "m:ss", or "h:mm:ss" from one hour up. Negative and non-finite values read as 0:00.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? Int(max(0, seconds).rounded(.down)) : 0
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Time left, with a true minus sign (U+2212): "−18:32".
    static func remaining(_ seconds: TimeInterval) -> String {
        "\u{2212}" + clock(seconds)
    }
}
