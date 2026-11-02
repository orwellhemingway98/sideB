import CoreGraphics
import Foundation

/// Angles round the disc in view coordinates (y down): 0° at the top, increasing clockwise.
enum DialGeometry {
    /// Degrees of turn per point of vertical scroll.
    static let scrollDegreesPerPoint: Double = 1

    /// The angle of `point` around `center`, in 0..<360.
    static func angle(of point: CGPoint, around center: CGPoint) -> Double {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        let degrees = atan2(dx, -dy) * 180 / .pi
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// The shortest signed turn from `a` to `b`, in −180...180 (clockwise positive).
    static func delta(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// The time a point on the ring stands for: its share of a full turn of `duration`.
    static func time(atRingPoint point: CGPoint, center: CGPoint, duration: TimeInterval) -> TimeInterval {
        angle(of: point, around: center) / 360 * duration
    }

    // MARK: Zones of the 150 pt disc

    /// What a press on the disc lands on.
    enum Zone: Equatable { case centre, back, forward, speed, ring, outside }

    static let discSize: CGFloat = 150
    static let centreRadius: CGFloat = 30
    static let ringBand: ClosedRange<CGFloat> = 45...75
    /// The back and forward controls sit inside the ring at 9 and 3 o'clock, this far from the middle.
    static let controlOffset: CGFloat = 45
    static let controlRadius: CGFloat = 15
    /// The speed label's centre, below the centre button, and its half-size.
    static let speedOffset: CGFloat = 41
    static let speedHalfSize = CGSize(width: 16, height: 9)

    static func zone(of point: CGPoint, speedShown: Bool) -> Zone {
        let c = discSize / 2
        let dx = point.x - c, dy = point.y - c
        if hypot(dx, dy) <= centreRadius { return .centre }
        if hypot(dx + controlOffset, dy) <= controlRadius { return .back }
        if hypot(dx - controlOffset, dy) <= controlRadius { return .forward }
        if speedShown, abs(dx) <= speedHalfSize.width, abs(dy - speedOffset) <= speedHalfSize.height { return .speed }
        return ringBand.contains(hypot(dx, dy)) ? .ring : .outside
    }

    // MARK: The halo

    /// The time shows as a thin band of light just outside the disc's edge, as if from beneath it.
    static let haloWidth: CGFloat = 3
    static let haloRadius: CGFloat = discSize / 2 + 2 + haloWidth / 2
    /// The halo's outer edge, side to side: what the disc really takes up in a layout.
    static let haloSide: CGFloat = 2 * (haloRadius + haloWidth / 2)
    /// The glass the floating dial puts round its disc.
    static let floatingPadding: CGFloat = 10
}
