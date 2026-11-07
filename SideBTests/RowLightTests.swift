import XCTest
@testable import SideB

/// Every row lights the same way: softly under the pointer, Row Light when pressed or playing.
final class RowLightTests: XCTestCase {
    func testAtRestARowHasNoLight() {
        XCTAssertEqual(RowLightStyle.light(current: false, hovering: false, pressed: false), 0)
    }

    func testThePointerLightsItSoftly() {
        let hover = RowLightStyle.light(current: false, hovering: true, pressed: false)
        XCTAssertGreaterThan(hover, 0)
        XCTAssertLessThan(hover, RowLightStyle.rowLight)
    }

    func testPressingGivesRowLight() {
        XCTAssertEqual(RowLightStyle.light(current: false, hovering: true, pressed: true), RowLightStyle.rowLight)
    }

    func testWhatsPlayingKeepsRowLightUnderThePointer() {
        XCTAssertEqual(RowLightStyle.light(current: true, hovering: false, pressed: false), RowLightStyle.rowLight)
        XCTAssertEqual(RowLightStyle.light(current: true, hovering: true, pressed: false), RowLightStyle.rowLight)
    }
}
