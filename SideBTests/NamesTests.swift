import XCTest
@testable import SideB

/// One thing, one name: the mini player is shown and hidden by the same words wherever it's offered.
@MainActor
final class NamesTests: XCTestCase {
    func testTheMiniPlayerHasOnePairOfNames() {
        XCTAssertEqual(MiniPlacement.title(isOut: false), "Show Mini Player")
        XCTAssertEqual(MiniPlacement.title(isOut: true), "Hide Mini Player")
    }

    func testTheMenuBarMenuUsesThem() {
        XCTAssertEqual(StatusMenu.rows(miniPlayer: false, launchAtLogin: false)[1]?.title, MiniPlacement.title(isOut: false))
        XCTAssertEqual(StatusMenu.rows(miniPlayer: true, launchAtLogin: false)[1]?.title, MiniPlacement.title(isOut: true))
    }

    func testTheRightClickMenuUsesThem() {
        XCTAssertEqual(MiniPlayer.menu(onPutBack: {}, onLibrary: {}).items.first?.title, MiniPlacement.title(isOut: true))
    }

    func testSignInLabelsAreTitleCase() {
        XCTAssertEqual(SpotifyClientIDPrompt.buttonTitle(hasClientID: true), "Sign In to Spotify")
        XCTAssertEqual(SpotifyAccount.signingInTitle, "Signing In\u{2026}")
    }
}
