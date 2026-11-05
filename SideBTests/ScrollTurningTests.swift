import AppKit
import XCTest
@testable import SideB

@MainActor
final class ScrollTurningTests: XCTestCase {
    func testScrollOnlyTurnsOnTheVisibleLine() {
        let line = NSWindow()
        let other = NSWindow()
        let bounds = CGRect(x: 0, y: 0, width: 240, height: 16)
        let inside = CGPoint(x: 120, y: 8)
        XCTAssertFalse(ScrollTurning.shouldTurn(eventWindow: other, lineWindow: line, windowVisible: true,
                                                pointInLine: inside, lineBounds: bounds))
        XCTAssertFalse(ScrollTurning.shouldTurn(eventWindow: line, lineWindow: line, windowVisible: false,
                                                pointInLine: inside, lineBounds: bounds))
        XCTAssertFalse(ScrollTurning.shouldTurn(eventWindow: line, lineWindow: line, windowVisible: true,
                                                pointInLine: CGPoint(x: 120, y: 40), lineBounds: bounds))
        XCTAssertTrue(ScrollTurning.shouldTurn(eventWindow: line, lineWindow: line, windowVisible: true,
                                               pointInLine: inside, lineBounds: bounds))
    }
}
