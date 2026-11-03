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

    func testTheLightSitsJustOutsideTheGlassEdge() {
        XCTAssertGreaterThan(WheelLight.radius - WheelLight.width / 2, DialGeometry.discSize / 2)
        XCTAssertLessThanOrEqual(WheelLight.radius + WheelLight.width / 2, DialGeometry.haloSide / 2,
                                 "within the room the panel keeps round the disc")
    }

    func testBackAndForwardAreFaintAtRestAndFullOverTheWheel() {
        XCTAssertEqual(DiscView.controlOpacity(pointerNear: false), 0.35)
        XCTAssertEqual(DiscView.controlOpacity(pointerNear: true), 1)
    }

    func testTurningEasesTheLightThickerAndBrighter() {
        XCTAssertEqual(WheelLight.lineWidth(turn: 0), 3)
        XCTAssertEqual(WheelLight.lineWidth(turn: 1), 4)
        XCTAssertEqual(WheelLight.lineWidth(turn: 0.5), 3.5, "in between while it eases")
        XCTAssertEqual(WheelLight.brightness(turn: 0), 0.85, accuracy: 0.001)
        XCTAssertEqual(WheelLight.brightness(turn: 1), 1, accuracy: 0.001)
        XCTAssertLessThanOrEqual(WheelLight.lineRadius(turn: 1) + WheelLight.lineWidth(turn: 1) / 2,
                                 DialGeometry.haloSide / 2, "the thicker band still fits its room")
    }

    func testTheVolumeLevelDoesNotFadeIn() {
        // A level, not a journey: 3% volume must show, not vanish in the fade from 12 o'clock.
        XCTAssertEqual(WheelLight.opacity(atFraction: 0.03, fades: false), 1)
        XCTAssertLessThan(WheelLight.opacity(atFraction: 0.03, fades: true), 0.5)
    }

    func testChaptersAheadAreMarkedAndThosePassedAreBreaks() {
        let split = WheelLight.chapters([0, 0.2, 0.5, 0.8], progress: 0.4)
        XCTAssertEqual(split.breaks, [0.2], "cut into the light already played; none at 12 o'clock")
        XCTAssertEqual(split.ahead, [0.5, 0.8], "small marks where the light hasn't reached")
    }

    func testPopOutAndPutBackAreDrawnArrows() {
        let box = CGRect(x: 0, y: 0, width: 10, height: 10)
        for back in [false, true] {
            let bounds = PopOutGlyph(back: back).path(in: box).boundingRect
            XCTAssertFalse(bounds.isEmpty)
            XCTAssertTrue(box.insetBy(dx: -0.01, dy: -0.01).contains(bounds))
        }
    }

    func testTheLightGlidesOnBetweenTicks() {
        // Playing, the light moves on smoothly from the last known place at the playback speed.
        let p = WheelLight.flowingProgress(position: 100, elapsed: 0.5, rate: 2, duration: 1000, playing: true)
        XCTAssertEqual(p, 0.101, accuracy: 0.0001)
        XCTAssertEqual(WheelLight.flowingProgress(position: 100, elapsed: 0.5, rate: 1, duration: 1000, playing: false),
                       0.1, accuracy: 0.0001, "paused, it holds still")
        XCTAssertEqual(WheelLight.flowingProgress(position: 100, elapsed: 30, rate: 1, duration: 1000, playing: true),
                       0.1 + WheelLight.maxGlide / 1000, accuracy: 0.0001, "if ticks stop, it doesn't run away")
        XCTAssertEqual(WheelLight.flowingProgress(position: 999, elapsed: 1, rate: 1, duration: 1000, playing: true),
                       1, accuracy: 0.0001)
    }

    func testAGlintTravelsAlongTheLightNowAndThen() {
        XCTAssertEqual(WheelLight.glint(at: 0) ?? -1, 0, accuracy: 0.001, "starts at 12 o'clock")
        let mid = try? XCTUnwrap(WheelLight.glint(at: WheelLight.glintTravel / 2))
        XCTAssertEqual(mid ?? -1, 0.5, accuracy: 0.05, "halfway along the light")
        XCTAssertNil(WheelLight.glint(at: WheelLight.glintTravel + 0.1), "then rests")
        XCTAssertEqual(WheelLight.glint(at: WheelLight.glintPeriod) ?? -1, 0, accuracy: 0.001, "and comes round again")
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
