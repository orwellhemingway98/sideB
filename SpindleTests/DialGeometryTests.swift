import XCTest
@testable import Spindle

final class DialGeometryTests: XCTestCase {
    func testAngleIsClockwiseFromTop() {
        let c = CGPoint(x: 75, y: 75)
        XCTAssertEqual(DialGeometry.angle(of: CGPoint(x: 75, y: 0), around: c), 0, accuracy: 0.001)
        XCTAssertEqual(DialGeometry.angle(of: CGPoint(x: 150, y: 75), around: c), 90, accuracy: 0.001)
        XCTAssertEqual(DialGeometry.angle(of: CGPoint(x: 0, y: 75), around: c), 270, accuracy: 0.001)
    }

    func testDeltaTakesTheShortWayRoundTheTop() {
        XCTAssertEqual(DialGeometry.delta(from: 350, to: 10), 20, accuracy: 0.001)
        XCTAssertEqual(DialGeometry.delta(from: 10, to: 350), -20, accuracy: 0.001)
    }

    func testRingPointToTime() {
        XCTAssertEqual(DialGeometry.time(atRingPoint: CGPoint(x: 75, y: 150), center: CGPoint(x: 75, y: 75), duration: 3600), 1800, accuracy: 0.001)
    }

    // MARK: Zones of the 150 pt disc

    func testPressesFindTheirZone() {
        typealias G = DialGeometry
        XCTAssertEqual(G.zone(of: CGPoint(x: 75, y: 75), speedShown: true), .centre)
        XCTAssertEqual(G.zone(of: CGPoint(x: 30, y: 75), speedShown: true), .back)       // 9 o'clock
        XCTAssertEqual(G.zone(of: CGPoint(x: 120, y: 75), speedShown: true), .forward)   // 3 o'clock
        XCTAssertEqual(G.zone(of: CGPoint(x: 75, y: 116), speedShown: true), .speed)     // under the button
        XCTAssertEqual(G.zone(of: CGPoint(x: 75, y: 12), speedShown: true), .ring)       // the top of the ring
        XCTAssertEqual(G.zone(of: CGPoint(x: 75, y: 116), speedShown: false), .outside,
                       "with no speed label (music) the spot does nothing, as before")
        XCTAssertEqual(G.zone(of: CGPoint(x: 2, y: 2), speedShown: true), .outside)
    }

    // MARK: The halo

    func testTheHaloSitsJustOutsideTheDisc() {
        typealias G = DialGeometry
        let edge = G.discSize / 2
        XCTAssertEqual(G.haloRadius - G.haloWidth / 2 - edge, 2, accuracy: 0.01, "a 2 pt gap, so it reads as under the disc")
        XCTAssertLessThanOrEqual(G.haloRadius + G.haloWidth / 2, edge + G.floatingPadding,
                                 "it fits inside the floating dial's glass")
    }
}
