import CoreGraphics

/// The wheel in Liquid Glass: progress is a band of light just outside the glass edge, fading in from
/// 12 o'clock, with no track.
enum WheelLight {
    /// The light's band, just outside the disc's edge, where the halo always sat.
    static let radius: CGFloat = DialGeometry.haloRadius
    static let width: CGFloat = DialGeometry.haloWidth
    /// The share of the circle over which the light fades in from 12 o'clock, instead of starting with a cap.
    static let fadeLength = 0.07

    static func opacity(atFraction f: Double) -> Double {
        let t = min(1, max(0, f / fadeLength))
        return t * t * (3 - 2 * t)
    }
}
