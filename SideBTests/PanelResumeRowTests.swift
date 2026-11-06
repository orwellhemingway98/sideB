import XCTest
@testable import SideB

final class PanelResumeRowTests: XCTestCase {
    func testTheDetailNamesTheShowThenTheEpisode() {
        XCTAssertEqual(PanelView.resumeDetail(show: "The Daily", episode: "The Voters Who Flipped"),
                       "The Daily \u{00B7} The Voters Who Flipped")
    }

    func testWithoutAShowTheDetailIsJustTheEpisode() {
        XCTAssertEqual(PanelView.resumeDetail(show: nil, episode: "The Voters Who Flipped"), "The Voters Who Flipped")
        XCTAssertEqual(PanelView.resumeDetail(show: "", episode: "The Voters Who Flipped"), "The Voters Who Flipped")
    }
}
