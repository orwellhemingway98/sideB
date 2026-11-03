import Foundation

/// The wheel in Liquid Glass: progress is a band of light just outside the glass edge, fading in from
/// 12 o'clock, with no track.
enum WheelLight {
    /// The light's band, just outside the disc's edge, where the halo always sat.
    static let radius: CGFloat = DialGeometry.haloRadius
    static let width: CGFloat = DialGeometry.haloWidth
    /// The share of the circle over which the light fades in from 12 o'clock, instead of starting with a cap.
    static let fadeLength = 0.07

    /// How strongly the light shows at a share of the circle: it fades in from 12 o'clock for time, but a
    /// volume level is shown whole, or a low volume would vanish in the fade.
    static func opacity(atFraction f: Double, fades: Bool = true) -> Double {
        guard fades else { return 1 }
        let t = min(1, max(0, f / fadeLength))
        return t * t * (3 - 2 * t)
    }

    /// While the wheel is turned (0 at rest, 1 turning, in between as it eases) the band thickens by a point,
    /// growing inward so it stays within its room, and brightens to full white.
    static func lineWidth(turn: Double) -> CGFloat { width + CGFloat(turn) }
    static func lineRadius(turn: Double) -> CGFloat { radius - CGFloat(turn) / 2 }
    static func brightness(turn: Double) -> Double { 0.85 + 0.15 * turn }

    /// Chapter starts already played are small breaks in the light; those still ahead, where there's no light
    /// to cut, are small marks. None at 12 o'clock.
    static func chapters(_ starts: [Double], progress: Double) -> (breaks: [Double], ahead: [Double]) {
        let starts = starts.filter { $0 > 0 }
        return (starts.filter { $0 < progress }, starts.filter { $0 >= progress })
    }

    /// Between ticks of the player the light glides on at the playback speed, so it flows rather than steps;
    /// it never runs more than this many seconds past the last known place, in case the ticks stop.
    static let maxGlide: TimeInterval = 1.5

    static func flowingProgress(position: TimeInterval, elapsed: TimeInterval, rate: Double, duration: TimeInterval,
                                playing: Bool) -> Double {
        guard duration > 0 else { return 0 }
        let glide = playing ? min(max(0, elapsed) * rate, maxGlide) : 0
        return min(1, max(0, (position + glide) / duration))
    }

    /// Now and then, while playing, a soft glint travels along the light from 12 o'clock to now, as light moves
    /// through glass: it takes `glintTravel` seconds and comes round every `glintPeriod`.
    static let glintTravel: TimeInterval = 2.4
    static let glintPeriod: TimeInterval = 7

    /// Where the glint is along the light (0 at 12 o'clock, 1 at now), or nil while it rests.
    static func glint(at time: TimeInterval) -> Double? {
        let phase = time.truncatingRemainder(dividingBy: glintPeriod)
        guard phase >= 0, phase <= glintTravel else { return nil }
        let t = phase / glintTravel
        return t * t * (3 - 2 * t)
    }
}
