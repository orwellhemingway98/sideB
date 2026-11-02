import XCTest
@testable import Spindle

/// The list arrives as a glass drop: it forms at the panel's edge, falls, then spreads into the window.
@MainActor
final class DropletTests: XCTestCase {
    private var scheduled: [(delay: TimeInterval, run: @MainActor () -> Void)] = []

    private func state() -> DropletState {
        DropletState(after: { [unowned self] delay, run in scheduled.append((delay, run)) }, animate: { _, change in change() })
    }

    private func runNext() {
        let next = scheduled.removeFirst()
        next.run()
    }

    func testOpeningFormsFallsThenSpreads() {
        let drop = state()
        XCTAssertEqual(drop.phase, .hidden)
        drop.open()
        XCTAssertEqual(drop.phase, .forming)
        XCTAssertEqual(scheduled.first?.delay, DropletState.formDuration)
        runNext()
        XCTAssertEqual(drop.phase, .falling)
        XCTAssertEqual(scheduled.first?.delay, DropletState.fallDuration)
        runNext()
        XCTAssertEqual(drop.phase, .open)
        XCTAssertTrue(drop.isOpen)
        XCTAssertTrue(scheduled.isEmpty)
    }

    func testClosingRunsBackUpIntoThePanel() {
        let drop = state()
        drop.open(); runNext(); runNext()
        var closed = false
        drop.close { closed = true }
        XCTAssertEqual(drop.phase, .falling, "the list gathers back into a drop")
        XCTAssertFalse(drop.isOpen)
        runNext()
        XCTAssertEqual(drop.phase, .forming, "and rises to the panel's edge")
        runNext()
        XCTAssertEqual(drop.phase, .hidden)
        runNext()
        XCTAssertTrue(closed)
    }

    func testClosingMidwayCancelsTheOpening() {
        let drop = state()
        drop.open()
        var closed = false
        drop.close { closed = true }
        // The opening's pending steps now do nothing.
        while !scheduled.isEmpty { runNext() }
        XCTAssertEqual(drop.phase, .hidden)
        XCTAssertTrue(closed)
    }

    func testReduceMotionSkipsTheDrop() {
        let drop = DropletState(after: { [unowned self] d, r in scheduled.append((d, r)) }, animate: { _, change in change() },
                                reduceMotion: { true })
        drop.open()
        XCTAssertEqual(drop.phase, .open)
        XCTAssertTrue(scheduled.isEmpty)
    }
}
