import XCTest
@testable import SideB

/// A music command that fails says so, instead of nothing happening.
@MainActor
final class MusicRemoteFailureTests: XCTestCase {
    private var spotify: FakeMusicSource!
    private var remote: MusicRemote!
    private static let failure = "Spotify didn't respond. Try again."

    private func start(patience: TimeInterval = 60) async {
        spotify = FakeMusicSource(.spotify)
        remote = MusicRemote(sources: [spotify], every: { _, _ in NSObject() }, commandNotePatience: patience)
        spotify.play("Japan", id: "s1")
        await remote.refresh()
    }

    func testAFailedCommandSaysSo() async {
        await start()
        spotify.commandFailure = .scriptFailed("timed out")
        remote.next()
        await remote.lastCommand?.value
        XCTAssertEqual(remote.commandFailure, Self.failure)
    }

    func testAWorkingCommandClearsIt() async {
        await start()
        spotify.commandFailure = .scriptFailed("timed out")
        remote.next()
        await remote.lastCommand?.value
        spotify.commandFailure = nil
        remote.next()
        await remote.lastCommand?.value
        XCTAssertNil(remote.commandFailure)
    }

    func testItGoesAwayOnItsOwn() async throws {
        await start(patience: 0.05)
        spotify.commandFailure = .scriptFailed("timed out")
        remote.next()
        await remote.lastCommand?.value
        XCTAssertNotNil(remote.commandFailure)
        for _ in 0..<40 where remote.commandFailure != nil { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertNil(remote.commandFailure)
    }

    func testAnOlderFailuresTimerLeavesANewerOneUp() async throws {
        await start(patience: 0.2)
        spotify.commandFailure = .scriptFailed("timed out")
        remote.next()
        await remote.lastCommand?.value
        try await Task.sleep(for: .milliseconds(120))
        remote.next()
        await remote.lastCommand?.value
        try await Task.sleep(for: .milliseconds(120))   // past the first one's time, not the second's
        XCTAssertNotNil(remote.commandFailure)
    }

    func testANewSongClearsIt() async {
        await start()
        spotify.commandFailure = .scriptFailed("timed out")
        remote.next()
        await remote.lastCommand?.value
        spotify.play("Intimate", id: "s2")   // the script timed out, but Spotify did move on
        await remote.refresh()
        XCTAssertNil(remote.commandFailure)
    }

    func testTheSameSongMovingOnKeepsIt() async {
        await start()
        spotify.commandFailure = .scriptFailed("timed out")
        remote.next()
        await remote.lastCommand?.value
        spotify.play("Japan", id: "s1", position: 12)
        await remote.refresh()
        XCTAssertEqual(remote.commandFailure, Self.failure)
    }

    func testARefusedPermissionIsLeftToTheAccessNote() async {
        await start()
        spotify.commandFailure = .permissionDenied
        remote.next()
        await remote.lastCommand?.value
        XCTAssertNil(remote.commandFailure)
        XCTAssertTrue(remote.declined.contains(.spotify))
    }

    func testAFailedRowClickSaysSo() async {
        await start()
        spotify.commandFailure = .scriptFailed("timed out")
        let context = MusicContext(kind: .album, id: "album:AL1", title: "Night Roads", tracks: [], totalCount: 0)
        remote.play(contextTrack: ContextTrack(id: "t", disc: 1, number: 1, title: "T", artist: "A", duration: 1), in: context)
        await remote.lastCommand?.value
        XCTAssertEqual(remote.commandFailure, Self.failure)
    }
}
