import AppKit
import SwiftUI
import XCTest
@testable import Spindle

final class DialSpokenValueTests: XCTestCase {
    func testTheLineSaysWhetherItIsPlayingAndWhere() {
        XCTAssertEqual(Transport.spokenValue(isPlaying: true, position: 724, duration: 2890), "Playing, 12:04 of 48:10")
        XCTAssertEqual(Transport.spokenValue(isPlaying: false, position: 0, duration: 200), "Paused, 0:00 of 3:20")
    }

    func testWithoutALengthItSaysOnlyTheState() {
        XCTAssertEqual(Transport.spokenValue(isPlaying: true, position: 30, duration: nil), "Playing")
    }

    func testWithNothingLoadedItSaysSo() {
        XCTAssertEqual(Transport.spokenValue(isPlaying: nil, position: 0, duration: nil), "Nothing playing")
    }
}

/// VoiceOver reads only the side of the cover that faces you. (SwiftUI builds its accessibility tree only for a
/// running screen reader, so the rule both the drawing and VoiceOver follow is tested directly.)
final class CoverFacesTests: XCTestCase {
    func testTheCoverFacesYouUntilHalfWay() {
        XCTAssertTrue(CoverFace.isFacing(angle: 0, isBack: false))
        XCTAssertTrue(CoverFace.isFacing(angle: 90, isBack: false))
        XCTAssertFalse(CoverFace.isFacing(angle: 91, isBack: false))
        XCTAssertFalse(CoverFace.isFacing(angle: 180, isBack: false))
    }

    func testTheBackFacesYouPastHalfWay() {
        XCTAssertFalse(CoverFace.isFacing(angle: 0, isBack: true))
        XCTAssertFalse(CoverFace.isFacing(angle: 90, isBack: true))
        XCTAssertTrue(CoverFace.isFacing(angle: 180, isBack: true))
    }

    func testExactlyOneSideFacesYouAtEveryAngle() {
        for angle in stride(from: 0.0, through: 180, by: 5) {
            XCTAssertNotEqual(CoverFace.isFacing(angle: angle, isBack: false), CoverFace.isFacing(angle: angle, isBack: true),
                              "at \(angle)°")
        }
    }
}
