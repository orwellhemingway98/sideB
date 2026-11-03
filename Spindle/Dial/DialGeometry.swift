import CoreGraphics

/// How scrolling moves through a song or episode, measured as turns, as the dial did: the haptic ticks and
/// the scrub speed are set in degrees.
enum DialGeometry {
    /// Degrees of turn per point of vertical scroll.
    static let scrollDegreesPerPoint: Double = 1
}
