import AppKit
import XCTest
@testable import SideB

/// Compiles every script sideB sends to Music against Music's own dictionary. A variable named like one of
/// Music's terms (`names`, `artists`) compiles everywhere except inside `tell application "Music"`.
final class AppleMusicScriptTests: XCTestCase {
    private func assertCompiles(_ body: String, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let source = AppleScriptMusicSource.wrapped(body, bundleIdentifier: "com.apple.Music")
        guard let script = NSAppleScript(source: source) else { return XCTFail("\(name): no script", file: file, line: line) }
        var error: NSDictionary?
        let compiled = script.compileAndReturnError(&error)
        XCTAssertTrue(compiled, "\(name): \(error?[NSAppleScript.errorMessage] ?? "")", file: file, line: line)
    }

    func testAPlaylistKeptFromBeforeTheRenameTakesTheNewName() {
        let script = AppleMusicSource.queueScript(trackIDs: ["A1"], startID: "A1", knownPlaylistID: "PL")
        XCTAssertTrue(script.contains("set name of q to \"sideB\""))
    }

    func testEveryMusicScriptCompiles() {
        assertCompiles(AppleMusicSource.snapshotScript, "snapshot")
        assertCompiles(AppleMusicSource.contextKeyScript, "context key")
        assertCompiles(AppleMusicSource.contextScript, "context")
        assertCompiles(AppleMusicSource.queueScript(trackIDs: ["A1", "B2"], startID: "B2", knownPlaylistID: "PL"), "queue")
    }
}
