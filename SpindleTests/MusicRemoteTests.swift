import AppKit
import XCTest
@testable import Spindle

@MainActor
final class MusicRemoteTests: XCTestCase {
    private var music: FakeMusicSource!
    private var spotify: FakeMusicSource!
    private var remote: MusicRemote!

    override func setUp() {
        music = FakeMusicSource(.appleMusic)
        spotify = FakeMusicSource(.spotify)
        remote = MusicRemote(sources: [music, spotify], every: { _, _ in NSObject() })
    }

    func testPicksThePlayingApp() async {
        music.play("Paused Song", id: "m1", state: .paused)
        spotify.play("Blue Hour Drive", id: "s1")
        await remote.refresh()
        XCTAssertEqual(remote.track?.source, .spotify)
        XCTAssertEqual(remote.track?.title, "Blue Hour Drive")
        XCTAssertTrue(remote.isPlaying)
    }

    func testTwoPlayingAppsKeepTheActiveOne() async {
        music.play("First", id: "m1")
        spotify.stop()
        await remote.refresh()
        XCTAssertEqual(remote.source, .appleMusic)
        spotify.play("Second", id: "s1")
        for _ in 0..<3 {
            await remote.refresh()
            XCTAssertEqual(remote.source, .appleMusic, "no flip-flopping between two playing apps")
        }
    }

    func testNotRunningAppsAreNeverScripted() async {
        music.running = false
        spotify.running = false
        await remote.refresh()
        XCTAssertEqual(music.snapshotCalls + spotify.snapshotCalls, 0, "scripting a closed app would launch it")
        XCTAssertNil(remote.track)
        XCTAssertFalse(remote.isPlaying)
    }

    func testPermissionDeniedReportsNothing() async {
        spotify.running = false
        music.failure = .permissionDenied
        await remote.refresh()
        XCTAssertNil(remote.track)
        XCTAssertFalse(remote.isPlaying)
        await remote.refresh()
        XCTAssertEqual(music.snapshotCalls, 1, "a declined permission isn't asked for again every second")
    }

    func testCommandsGoToTheActiveSource() async {
        music.stop()
        spotify.play("Song", id: "s1")
        await remote.refresh()
        remote.playPause(); await remote.lastCommand?.value
        remote.next(); await remote.lastCommand?.value
        remote.previous(); await remote.lastCommand?.value
        remote.pause(); await remote.lastCommand?.value
        remote.setPosition(42); await remote.lastCommand?.value
        XCTAssertEqual(spotify.commands, [.playPause, .next, .previous, .pause, .setPosition(42)])
        XCTAssertEqual(music.commands, [])
    }

    func testPollDoesNotUndoARecentSeek() async {
        spotify.running = false
        music.play("Song", id: "m1", position: 10)
        await remote.refresh()
        remote.setPosition(120)
        XCTAssertEqual(remote.track?.position, 120, "the seek shows straight away")
        await remote.lastCommand?.value          // its own refresh still sees the old position
        music.play("Song", id: "m1", position: 10.5)
        await remote.refresh()
        XCTAssertEqual(remote.track?.position, 120)
        music.play("Song", id: "m1", position: 121)
        await remote.refresh()
        XCTAssertEqual(remote.track?.position, 121)
    }

    func testANewTrackClearsAPendingSeek() async {
        spotify.running = false
        music.play("Song", id: "m1", position: 10)
        await remote.refresh()
        remote.setPosition(120)
        await remote.lastCommand?.value
        music.play("Next song", id: "m2", position: 3)
        await remote.refresh()
        XCTAssertEqual(remote.track?.position, 3)
    }

    func testArtworkLoadsOncePerTrack() async throws {
        spotify.running = false
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 2, height: 2).fill(); image.unlockFocus()
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?
            .representation(using: .png, properties: [:]))
        music.artworkRef = .data(png)
        music.play("Song", id: "m1")
        await remote.refresh()
        while remote.artwork == nil { await Task.yield() }
        await remote.refresh()
        XCTAssertEqual(music.artworkCalls, 1)
    }
}
