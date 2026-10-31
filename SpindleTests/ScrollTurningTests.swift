import AppKit
import XCTest
@testable import Spindle

@MainActor
final class ScrollTurningTests: XCTestCase {
    func testScrollOnlyTurnsInsideTheVisibleDisc() {
        let disc = NSWindow()
        let other = NSWindow()
        let inside = CGPoint(x: 75, y: 40)
        XCTAssertFalse(ScrollTurning.shouldTurn(eventWindow: other, discWindow: disc, windowVisible: true,
                                                pointInDisc: inside, discSize: 150))
        XCTAssertFalse(ScrollTurning.shouldTurn(eventWindow: disc, discWindow: disc, windowVisible: false,
                                                pointInDisc: inside, discSize: 150))
        XCTAssertFalse(ScrollTurning.shouldTurn(eventWindow: disc, discWindow: disc, windowVisible: true,
                                                pointInDisc: CGPoint(x: 5, y: 5), discSize: 150))
        XCTAssertTrue(ScrollTurning.shouldTurn(eventWindow: disc, discWindow: disc, windowVisible: true,
                                               pointInDisc: inside, discSize: 150))
    }
}
