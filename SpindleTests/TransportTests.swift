import AppKit
import SwiftUI
import XCTest
@testable import Spindle

/// The progress line and controls that replaced the dial.
final class TransportTests: XCTestCase {
    func testTheLineGlidesOnBetweenTicks() {
        // Playing, it moves on smoothly from the last known place at the playback speed.
        XCTAssertEqual(Transport.flowingProgress(position: 100, elapsed: 0.5, rate: 2, duration: 1000, playing: true),
                       0.101, accuracy: 0.0001)
        XCTAssertEqual(Transport.flowingProgress(position: 100, elapsed: 0.5, rate: 1, duration: 1000, playing: false),
                       0.1, accuracy: 0.0001, "paused, it holds still")
        XCTAssertEqual(Transport.flowingProgress(position: 100, elapsed: 30, rate: 1, duration: 1000, playing: true),
                       0.1 + Transport.maxGlide / 1000, accuracy: 0.0001, "if ticks stop, it doesn't run away")
        XCTAssertEqual(Transport.flowingProgress(position: 999, elapsed: 1, rate: 1, duration: 1000, playing: true),
                       1, accuracy: 0.0001)
    }

    func testTheButtonsUseApplesOwnSymbols() {
        XCTAssertEqual(Transport.Symbols(isMusic: true, isPlaying: false),
                       Transport.Symbols(back: "backward.fill", playPause: "play.fill", forward: "forward.fill"))
        XCTAssertEqual(Transport.Symbols(isMusic: true, isPlaying: true).playPause, "pause.fill")
        XCTAssertEqual(Transport.Symbols(isMusic: false, isPlaying: false),
                       Transport.Symbols(back: "gobackward.15", playPause: "play.fill", forward: "goforward.30"))
        for name in ["backward.fill", "forward.fill", "play.fill", "pause.fill", "gobackward.15", "goforward.30"] {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
    }

    func testDraggingTheLineSeeksWhereThePointerIs() {
        XCTAssertEqual(Transport.fraction(atX: 50, width: 200), 0.25)
        XCTAssertEqual(Transport.fraction(atX: -10, width: 200), 0, "held at the start")
        XCTAssertEqual(Transport.fraction(atX: 260, width: 200), 1, "held at the end")
        XCTAssertEqual(Transport.fraction(atX: 10, width: 0), 0)
    }
}
