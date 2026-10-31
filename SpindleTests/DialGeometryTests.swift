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
}
