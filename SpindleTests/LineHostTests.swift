import XCTest
@testable import Spindle

final class LineHostTests: XCTestCase {
    func testOnlyThePanelsLineFollowsThePanel() {
        XCTAssertTrue(LineHost.panel.followsPanel)
        XCTAssertFalse(LineHost.floating.followsPanel, "closing the panel mustn't switch off the mini player's scrolling")
    }
}
