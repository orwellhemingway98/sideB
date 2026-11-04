import XCTest
@testable import Spindle

@MainActor
final class StatusMenuTests: XCTestCase {
    private final class FakeLoginItem: LoginItem {
        var isEnabled = false
        var fail = false
        func setEnabled(_ on: Bool) throws {
            if fail { throw CocoaError(.featureUnsupported) }
            isEnabled = on
        }
    }

    func testRowsTopToBottom() {
        let rows = StatusMenu.rows(miniPlayer: false, launchAtLogin: false)
        XCTAssertEqual(rows.map { $0?.title }, ["Open Library\u{2026}", "Show Mini Player", nil, "Launch at Login", nil,
                                                "Quit Spindle"])
        XCTAssertEqual(rows.compactMap { $0?.command }, [.library, .miniPlayer, .launchAtLogin, .quit])
    }

    func testSignedInToSpotifyTheMenuOffersToSignOut() {
        let rows = StatusMenu.rows(miniPlayer: nil, launchAtLogin: false, spotifySignedIn: true)
        XCTAssertEqual(rows.map { $0?.title }, ["Open Library\u{2026}", nil, "Launch at Login", nil,
                                                "Sign Out of Spotify", nil, "Quit Spindle"])
        XCTAssertEqual(rows[4]?.command, .signOutOfSpotify)
        XCTAssertFalse(StatusMenu.rows(miniPlayer: nil, launchAtLogin: false).contains { $0?.command == .signOutOfSpotify })
    }

    func testSignedOutOfSpotifyTheMenuOffersToSignIn() {
        let rows = StatusMenu.rows(miniPlayer: nil, launchAtLogin: false, spotifySignedIn: false)
        XCTAssertEqual(rows[4]?.title, "Sign In to Spotify\u{2026}")
        XCTAssertEqual(rows[4]?.command, .signInToSpotify)
    }

    func testTheTickFollowsTheLoginItem() {
        XCTAssertEqual(StatusMenu.rows(miniPlayer: nil, launchAtLogin: true).compactMap { $0?.isOn },
                       [false, true, false])
        XCTAssertEqual(StatusMenu.rows(miniPlayer: true, launchAtLogin: false)[1]?.title, "Hide Mini Player")
    }

    func testChoosingItTurnsLaunchAtLoginOnAndOff() {
        let item = FakeLoginItem()
        var errors: [Error] = []
        StatusMenu.toggle(item) { errors.append($0) }
        XCTAssertTrue(item.isEnabled)
        StatusMenu.toggle(item) { errors.append($0) }
        XCTAssertFalse(item.isEnabled)
        item.fail = true
        StatusMenu.toggle(item) { errors.append($0) }
        XCTAssertEqual(errors.count, 1, "a refusal is reported, not swallowed")
    }
}
