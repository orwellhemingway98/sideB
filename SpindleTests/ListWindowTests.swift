import AppKit
import XCTest
@testable import Spindle

@MainActor
final class ListWindowTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 1000)





    func testClicksInTheListDoNotCloseThePanel() {
        func window() -> NSWindow {
            NSWindow(contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.borderless], backing: .buffered, defer: true)
        }
        let panel = window(), list = window(), statusBar = window(), library = window()
        XCTAssertFalse(PanelClickPolicy.closesPanel(clickWindow: list, panel: panel, anchor: statusBar, children: [list]))
        XCTAssertFalse(PanelClickPolicy.closesPanel(clickWindow: panel, panel: panel, anchor: statusBar, children: [list]))
        XCTAssertFalse(PanelClickPolicy.closesPanel(clickWindow: statusBar, panel: panel, anchor: statusBar, children: []))
        XCTAssertFalse(PanelClickPolicy.closesPanel(clickWindow: nil, panel: panel, anchor: statusBar, children: []))
        XCTAssertTrue(PanelClickPolicy.closesPanel(clickWindow: library, panel: panel, anchor: statusBar, children: [list]))
    }


    func testAlbumRowsQueueTheWholeAlbumFromTheClickedSong() {
        let script = AppleMusicSource.queueScript(trackIDs: ["a\"1", "b2"], startID: "b2", knownPlaylistID: "PL")
        XCTAssertTrue(script.contains(#"{"a\"1", "b2"}"#), "every id is quoted")
        XCTAssertTrue(script.contains(#"play (first track of q whose persistent ID is "b2")"#))
        XCTAssertTrue(script.contains(#"first user playlist whose persistent ID is "PL""#))
        XCTAssertTrue(script.contains("delete every track of q"), "refilled, never duplicated")
    }

    func testTheCoverRectIsWhereThePanelDrawsIt() {
        // The panel's window holds a clear margin for the glass's shadow; the cover sits inside it.
        let m = PanelController.shadowMargin
        let bounds = NSRect(x: 0, y: 0, width: 272 + m.left + m.right, height: 507 + m.top + m.bottom)
        XCTAssertEqual(PanelView.coverRect(in: bounds, flipped: true, margin: m),
                       NSRect(x: m.left + 16, y: m.top + 16, width: 240, height: 240))
        XCTAssertEqual(PanelView.coverRect(in: bounds, flipped: false, margin: m),
                       NSRect(x: m.left + 16, y: bounds.height - m.top - 16 - 240, width: 240, height: 240))
    }

    func testTheGlassRectIsThePanelLessItsShadowMargin() {
        let m = PanelController.shadowMargin
        let bounds = NSRect(x: 0, y: 0, width: 272 + m.left + m.right, height: 507 + m.top + m.bottom)
        XCTAssertEqual(PanelView.glassRect(in: bounds, flipped: true, margin: m),
                       NSRect(x: m.left, y: m.top, width: 272, height: 507))
        XCTAssertEqual(PanelView.glassRect(in: bounds, flipped: false, margin: m),
                       NSRect(x: m.left, y: m.bottom, width: 272, height: 507))
    }

    func testTheShadowHasRoomButNeverCoversTheMenuBarIcon() {
        let m = PanelController.shadowMargin
        XCTAssertGreaterThanOrEqual(m.left, 20)
        XCTAssertEqual(m.left, m.right, "the panel stays centred under its icon")
        XCTAssertGreaterThanOrEqual(m.bottom, 20)
        XCTAssertLessThanOrEqual(m.top, PanelController.gapBelowIcon, "the window stops at the icon's bottom edge")
    }

    func testEpisodeRowsAreTallerThanSongRows() {
        // Episodes show the title with the date and length on a second line.
        XCTAssertEqual(ListPlacement.height(rows: 3), 56 + 3 * 30 + 12)
        XCTAssertEqual(ListPlacement.height(rows: 3, rowHeight: ListPlacement.twoLineRow), 56 + 3 * 44 + 12)
        XCTAssertEqual(ListPlacement.height(rows: 30, rowHeight: ListPlacement.twoLineRow), ListPlacement.maxHeight)
    }
}
