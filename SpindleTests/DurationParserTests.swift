import XCTest
@testable import Spindle

final class DurationParserTests: XCTestCase {
    func testDurations() {
        XCTAssertEqual(DurationParser.seconds("3120"), 3120)
        XCTAssertEqual(DurationParser.seconds("52:00"), 3120)
        XCTAssertEqual(DurationParser.seconds("1:04:00"), 3840)
        XCTAssertEqual(DurationParser.seconds("00:00:05.500"), 5.5)
        XCTAssertNil(DurationParser.seconds(""))
        XCTAssertNil(DurationParser.seconds("about an hour"))
    }
}
