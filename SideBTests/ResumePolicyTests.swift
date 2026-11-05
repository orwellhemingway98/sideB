import XCTest
@testable import SideB

final class ResumePolicyTests: XCTestCase {
    func testResumePolicy() {
        XCTAssertEqual(ResumePolicy.startPosition(saved: 600), 597); XCTAssertEqual(ResumePolicy.startPosition(saved: 2), 0)
        XCTAssertTrue(ResumePolicy.isFinished(position: 3571, duration: 3600)); XCTAssertFalse(ResumePolicy.isFinished(position: 3569, duration: 3600))
        XCTAssertFalse(ResumePolicy.isFinished(position: 3599, duration: nil))
        XCTAssertEqual(ResumePolicy.nextRate(after: 2), 1); XCTAssertEqual(ResumePolicy.nextRate(after: 1.2), 1.5); XCTAssertEqual(ResumePolicy.nextRate(after: 1.7), 1)
    }
}
