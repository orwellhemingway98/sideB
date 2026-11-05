import XCTest
@testable import SideB

final class DialEngineTests: XCTestCase {
    func testNormalPaceFullTurnIsTwoMinutes() {
        var e = DialEngine()
        var total = 0.0
        for i in 0..<36 { total += e.turn(degrees: 10, at: Double(i) * 0.1, position: 600 + total, duration: 3600, chapters: []).seek }
        XCTAssertEqual(total, 120, accuracy: 0.001)   // 10° per 100 ms = 100°/s, no acceleration
    }
    func testFastTurningAcceleratesUpToFourTimes() {
        var e = DialEngine()
        XCTAssertEqual(e.turn(degrees: 72, at: 0, position: 600, duration: 3600, chapters: []).seek, 72 * (1 + 3 * 360.0 / 1080) / 3, accuracy: 0.001) // 720°/s → 2×
        var f = DialEngine()
        XCTAssertEqual(f.turn(degrees: 300, at: 0, position: 600, duration: 3600, chapters: []).seek, 300 * 4 / 3, accuracy: 0.001)               // 3000°/s → capped 4×
    }
    func testClampsAtStartAndEnd() {
        var e = DialEngine()
        XCTAssertEqual(e.turn(degrees: -90, at: 0, position: 10, duration: 3600, chapters: []).seek, -10)
        e.reset()
        XCTAssertEqual(e.turn(degrees: 90, at: 1, position: 3590, duration: 3600, chapters: []).seek, 10)
    }
    func testUnknownDurationDoesNotClampForward() {
        var e = DialEngine()
        XCTAssertEqual(e.turn(degrees: 9, at: 0, position: 3599, duration: nil, chapters: []).seek, 3, accuracy: 0.001) // 90°/s, no acceleration
    }
    func testTicksEveryFifteenSecondsInDirectionOfTravel() {
        var e = DialEngine()
        // 54° in one event = 540°/s → 1.5× → 27 s
        XCTAssertEqual(e.turn(degrees: 54, at: 0, position: 14, duration: 3600, chapters: []).detents, [.tick(at: 15), .tick(at: 30)]) // 14 → 41
        e.reset()
        XCTAssertEqual(e.turn(degrees: -54, at: 1, position: 46, duration: 3600, chapters: []).detents, [.tick(at: 45), .tick(at: 30)]) // 46 → 19
    }
    func testChapterReplacesNearbyTickAndStandsAlone() {
        var e = DialEngine()
        XCTAssertEqual(e.turn(degrees: 54, at: 0, position: 14, duration: 3600, chapters: [0, 22, 30.3]).detents,  // 14 → 41
                       [.tick(at: 15), .chapter(at: 22), .chapter(at: 30.3)])
    }
    func testStartingExactlyOnABoundaryDoesNotRepeatIt() {
        var e = DialEngine()
        XCTAssertEqual(e.turn(degrees: 3, at: 0, position: 15, duration: 3600, chapters: [15]).detents, [])
    }
}
