import SwiftUI
import XCTest
@testable import Spindle

/// The wheel in Liquid Glass: light inside the rim, and a centre glyph that morphs.
final class GlassWheelTests: XCTestCase {
    func testTheLightFadesInFromTwelveOClock() {
        XCTAssertEqual(WheelLight.opacity(atFraction: 0), 0, accuracy: 0.001)
        XCTAssertLessThan(WheelLight.opacity(atFraction: WheelLight.fadeLength / 2), 0.75)
        XCTAssertEqual(WheelLight.opacity(atFraction: WheelLight.fadeLength), 1, accuracy: 0.001)
        XCTAssertEqual(WheelLight.opacity(atFraction: 0.6), 1, accuracy: 0.001)
    }

    func testTheLightSitsInsideTheGlassEdge() {
        XCTAssertLessThan(WheelLight.radius + WheelLight.width / 2, DialGeometry.discSize / 2)
        XCTAssertGreaterThan(WheelLight.radius - WheelLight.width / 2, DialGeometry.ringBand.lowerBound,
                             "still on the ring you turn")
    }

    func testPlayMorphsIntoPause() {
        let box = CGRect(x: 0, y: 0, width: 18, height: 20)
        let play = PlayPauseGlyph(morph: 0).path(in: box).boundingRect
        let pause = PlayPauseGlyph(morph: 1).path(in: box).boundingRect
        XCTAssertEqual(PlayPauseGlyph(isPlaying: true).path(in: box).boundingRect, pause)
        XCTAssertEqual(PlayPauseGlyph(isPlaying: false).path(in: box).boundingRect, play)
        let halfway = PlayPauseGlyph(morph: 0.5).path(in: box).boundingRect
        XCTAssertFalse(halfway.isEmpty)
        XCTAssertNotEqual(halfway, play)
        XCTAssertNotEqual(halfway, pause)
        XCTAssertEqual(PlayPauseGlyph(morph: 0.5).animatableData, 0.5)
    }
}
