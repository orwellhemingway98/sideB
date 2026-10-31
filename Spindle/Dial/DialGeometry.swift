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
}
