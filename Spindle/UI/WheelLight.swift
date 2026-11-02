import CoreGraphics

/// The wheel in Liquid Glass: progress is light caught inside the glass rim, fading in from 12 o'clock.
enum WheelLight {
    /// The light's band, just inside the disc's edge (still on the ring you turn).
    static let radius: CGFloat = DialGeometry.discSize / 2 - 4.5
    static let width: CGFloat = 3
    /// The share of the circle over which the light fades in from 12 o'clock, instead of starting with a cap.
    static let fadeLength = 0.07

    static func opacity(atFraction f: Double) -> Double {
        let t = min(1, max(0, f / fadeLength))
        return t * t * (3 - 2 * t)
    }
}
