import CoreGraphics

/// How scrolling moves through a song or episode, measured as turns: the haptic ticks and
/// the scrub speed are set in degrees.
enum ScrollGeometry {
    /// Degrees of turn per point of vertical scroll.
    static let scrollDegreesPerPoint: Double = 1
}
