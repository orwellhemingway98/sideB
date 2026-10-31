import XCTest
@testable import Spindle

final class DiscHostTests: XCTestCase {
    func testOnlyThePanelDiscFollowsThePanel() {
        XCTAssertTrue(DiscHost.panel.followsPanel)
        XCTAssertFalse(DiscHost.floating.followsPanel, "closing the panel mustn't switch off the floating dial's scrolling")
    }
}
