import XCTest
@testable import SideB

final class TimeFormatTests: XCTestCase {
    func testClock() {
        XCTAssertEqual(TimeFormat.clock(0), "0:00")
        XCTAssertEqual(TimeFormat.clock(65), "1:05")
        XCTAssertEqual(TimeFormat.clock(3_845), "1:04:05")
        XCTAssertEqual(TimeFormat.clock(-4), "0:00")
    }

    func testRemaining() {
        XCTAssertEqual(TimeFormat.remaining(1_112), "\u{2212}18:32")
    }
}
