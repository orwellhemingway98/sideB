import XCTest
@testable import SideB

final class HapticLimiterTests: XCTestCase {
    func testTickThenTooSoonThenAllowed() {
        var l = HapticLimiter()
        XCTAssertEqual(l.next(for: [.tick(at: 15)], at: 0), .tick)
        XCTAssertNil(l.next(for: [.tick(at: 30)], at: 0.020))
        XCTAssertEqual(l.next(for: [.tick(at: 45)], at: 0.036), .tick)
    }

    func testChapterIsNeverDropped() {
        var l = HapticLimiter()
        _ = l.next(for: [.tick(at: 15)], at: 0)
        XCTAssertEqual(l.next(for: [.tick(at: 30), .chapter(at: 31)], at: 0.010), .chapter)
    }

    func testNothingCrossedNothingFelt() {
        var l = HapticLimiter()
        XCTAssertNil(l.next(for: [], at: 0))
    }

    func testChapterCountsAsLastHapticForLaterTicks() {
        var l = HapticLimiter()
        XCTAssertEqual(l.next(for: [.chapter(at: 10)], at: 1.000), .chapter)
        XCTAssertNil(l.next(for: [.tick(at: 15)], at: 1.020))
    }

    func testTickAtExactlyMinIntervalIsAllowed() {
        var l = HapticLimiter()
        XCTAssertEqual(l.next(for: [.tick(at: 15)], at: 0), .tick)
        XCTAssertEqual(l.next(for: [.tick(at: 30)], at: 0.035), .tick)
    }
}
