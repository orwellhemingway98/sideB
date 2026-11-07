import AppKit
import XCTest
@testable import SideB

/// The strip answers a glance: whether it's playing, and on hover what.
@MainActor
final class StatusStripTests: XCTestCase {
    private func display(title: String = "Japan", subtitle: String = "Fontaines D.C.", isPlaying: Bool = true) -> NowPlayingDisplay {
        NowPlayingDisplay(kind: .music, title: title, subtitle: subtitle, source: .spotify, artworkURL: nil,
                          artworkSeed: title, duration: 194, isPlaying: isPlaying)
    }

    func testPausedIsDimmerThanPlaying() {
        XCTAssertEqual(StatusStripView.contentOpacity(isPlaying: true), 1)
        XCTAssertLessThan(StatusStripView.contentOpacity(isPlaying: false), 1)
    }

    func testTheTooltipNamesWhatsPlaying() {
        XCTAssertEqual(StatusStripView.toolTip(for: display()), "Japan \u{00B7} Fontaines D.C.")
    }

    func testTheTooltipIsJustTheTitleWithoutASubtitle() {
        XCTAssertEqual(StatusStripView.toolTip(for: display(subtitle: "")), "Japan")
    }

    func testWithNothingOpenThereIsNoTooltip() {
        XCTAssertNil(StatusStripView.toolTip(for: nil))
    }

    func testVoiceOverHearsTheStateAndWhatsPlaying() {
        XCTAssertEqual(StatusStripView.spokenValue(for: display()), "Playing, Japan, Fontaines D.C.")
        XCTAssertEqual(StatusStripView.spokenValue(for: display(isPlaying: false)), "Paused, Japan, Fontaines D.C.")
        XCTAssertEqual(StatusStripView.spokenValue(for: display(subtitle: "")), "Playing, Japan")
        XCTAssertEqual(StatusStripView.spokenValue(for: nil), "Nothing playing")
    }

    func testDescribingAButtonSetsBoth() {
        let button = NSButton()
        StatusStripController.describe(button, as: display(isPlaying: false))
        XCTAssertEqual(button.toolTip, "Japan \u{00B7} Fontaines D.C.")
        XCTAssertEqual(button.accessibilityValue() as? String, "Paused, Japan, Fontaines D.C.")
        StatusStripController.describe(button, as: nil)
        XCTAssertNil(button.toolTip)
        XCTAssertEqual(button.accessibilityValue() as? String, "Nothing playing")
    }
}
