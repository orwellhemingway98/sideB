import AppKit
import XCTest
@testable import Spindle

@MainActor
final class ListWindowTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 1000)

    func testListGoesBelowThePanel() {
        let frame = ListPlacement.frame(panel: NSRect(x: 100, y: 400, width: 272, height: 560), height: 300, visible: screen)
        XCTAssertEqual(frame, NSRect(x: 100, y: 400 - 12 - 300, width: 272, height: 300))
    }

    func testListMovesBesideThePanelWhenThereIsNoRoomBelow() {
        let frame = ListPlacement.frame(panel: NSRect(x: 500, y: 50, width: 272, height: 560), height: 300,
                                        visible: NSRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(frame, NSRect(x: 500 - 12 - 272, y: 50 + 560 - 300, width: 272, height: 300))
    }

    func testListGoesRightWhenLeftHasNoRoom() {
        let frame = ListPlacement.frame(panel: NSRect(x: 10, y: 50, width: 272, height: 560), height: 300,
                                        visible: NSRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(frame.origin.x, 10 + 272 + 12)
        XCTAssertEqual(frame.maxY, 50 + 560)
    }

    func testHeightIsCappedAt360() {
        let frame = ListPlacement.frame(panel: NSRect(x: 100, y: 500, width: 272, height: 400), height: 900, visible: screen)
        XCTAssertEqual(frame.height, 360)
    }

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

    func testPlacementIsDecidedForTheTallestList() {
        // 300 pt would fit below, but the list may grow to 360 once it loads: put it beside from the start.
        let frame = ListPlacement.frame(panel: NSRect(x: 600, y: 350, width: 272, height: 560), height: 300, visible: screen)
        XCTAssertEqual(frame.origin.x, 600 - 12 - 272)
    }

    func testAlbumRowsQueueTheWholeAlbumFromTheClickedSong() {
        let script = AppleMusicSource.queueScript(trackIDs: ["a\"1", "b2"], startID: "b2", knownPlaylistID: "PL")
        XCTAssertTrue(script.contains(#"{"a\"1", "b2"}"#), "every id is quoted")
        XCTAssertTrue(script.contains(#"play (first track of q whose persistent ID is "b2")"#))
        XCTAssertTrue(script.contains(#"first user playlist whose persistent ID is "PL""#))
        XCTAssertTrue(script.contains("delete every track of q"), "refilled, never duplicated")
    }

    func testEpisodeRowsAreTallerThanSongRows() {
        // Episodes show the title with the date and length on a second line.
        XCTAssertEqual(ListPlacement.height(rows: 3), 56 + 3 * 30 + 12)
        XCTAssertEqual(ListPlacement.height(rows: 3, rowHeight: ListPlacement.twoLineRow), 56 + 3 * 44 + 12)
        XCTAssertEqual(ListPlacement.height(rows: 30, rowHeight: ListPlacement.twoLineRow), ListPlacement.maxHeight)
    }
}
