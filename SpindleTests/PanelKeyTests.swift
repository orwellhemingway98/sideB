import AppKit
import XCTest
@testable import Spindle

/// The keys the dial panel answers while it's the key window.
final class PanelKeyTests: XCTestCase {
    func testPlainKeysControlPlayback() {
        XCTAssertEqual(PanelKey(keyCode: 49, modifiers: []), .playPause, "Space")
        XCTAssertEqual(PanelKey(keyCode: 123, modifiers: []), .back, "←")
        XCTAssertEqual(PanelKey(keyCode: 124, modifiers: []), .forward, "→")
        XCTAssertEqual(PanelKey(keyCode: 36, modifiers: []), .turnCover, "Return")
        XCTAssertEqual(PanelKey(keyCode: 76, modifiers: []), .turnCover, "Enter")
        XCTAssertEqual(PanelKey(keyCode: 53, modifiers: []), .escape)
    }

    func testCommandLOpensTheLibrary() {
        XCTAssertEqual(PanelKey(keyCode: 37, modifiers: .command), .library)
        XCTAssertNil(PanelKey(keyCode: 37, modifiers: []), "a plain L does nothing")
    }

    func testModifiedKeysAreLeftAlone() {
        // ⌘← and the like belong to the system; arrow keys carry .function and .numericPad, which don't count.
        XCTAssertNil(PanelKey(keyCode: 123, modifiers: .command))
        XCTAssertNil(PanelKey(keyCode: 49, modifiers: .control))
        XCTAssertEqual(PanelKey(keyCode: 124, modifiers: [.function, .numericPad]), .forward)
    }

    func testOtherKeysAreLeftAlone() {
        XCTAssertNil(PanelKey(keyCode: 0, modifiers: []), "A")
        XCTAssertNil(PanelKey(keyCode: 126, modifiers: []), "↑")
    }
}
