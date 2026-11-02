import AppKit
import XCTest
@testable import Spindle

/// Compiles every script Spindle sends to Music against Music's own dictionary. A variable named like one of
/// Music's terms (`names`, `artists`) compiles everywhere except inside `tell application "Music"`.
final class AppleMusicScriptTests: XCTestCase {
    private func assertCompiles(_ body: String, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let source = AppleScriptMusicSource.wrapped(body, bundleIdentifier: "com.apple.Music")
        guard let script = NSAppleScript(source: source) else { return XCTFail("\(name): no script", file: file, line: line) }
        var error: NSDictionary?
        let compiled = script.compileAndReturnError(&error)
        XCTAssertTrue(compiled, "\(name): \(error?[NSAppleScript.errorMessage] ?? "")", file: file, line: line)
    }

    func testEveryMusicScriptCompiles() {
        assertCompiles(AppleMusicSource.snapshotScript, "snapshot")
        assertCompiles(AppleMusicSource.contextKeyScript, "context key")
        assertCompiles(AppleMusicSource.contextScript, "context")
        assertCompiles(AppleMusicSource.queueScript(trackIDs: ["A1", "B2"], startID: "B2", knownPlaylistID: "PL"), "queue")
    }
}
