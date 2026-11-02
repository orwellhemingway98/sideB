import CoreGraphics

/// The wheel in Liquid Glass: progress is light caught inside the glass rim, fading in from 12 o'clock, and
/// "now" is a droplet riding the edge that lifts off while you turn.
enum WheelLight {
    /// The light's band, just inside the disc's edge (still on the ring you turn).
    static let radius: CGFloat = DialGeometry.discSize / 2 - 4.5
    static let width: CGFloat = 3
    /// The share of the circle over which the light fades in from 12 o'clock, instead of starting with a cap.
    static let fadeLength = 0.07

    /// From the droplet's centre to the wheel's: on the edge at rest, half in the glass.
    static let dropletRest: CGFloat = DialGeometry.discSize / 2
    /// How far it pulls away from the edge while you turn.
    static let dropletLift: CGFloat = 5

    static func opacity(atFraction f: Double) -> Double {
        let t = min(1, max(0, f / fadeLength))
        return t * t * (3 - 2 * t)
    }

    static func dropletCentre(progress: Double, lift: Double, around centre: CGPoint) -> CGPoint {
        let angle = progress * 2 * .pi - .pi / 2
        let distance = dropletRest + dropletLift * lift
        return CGPoint(x: centre.x + distance * cos(angle), y: centre.y + distance * sin(angle))
    }

    static func dropletSize(lift: Double) -> CGFloat {
        8 + 2 * lift
    }
}
