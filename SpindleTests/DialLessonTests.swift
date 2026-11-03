import Combine
import XCTest
@testable import Spindle

/// The one-time caption that teaches the dial: shown until the first turn, then never again.
@MainActor
final class DialLessonTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "DialLessonTests")!
        defaults.removePersistentDomain(forName: "DialLessonTests")
    }

    func testTheFirstTurnEndsTheLessonForGood() {
        let turned = PassthroughSubject<Void, Never>()
        let lesson = DialLesson(defaults: defaults, turned: turned.eraseToAnyPublisher())
        XCTAssertFalse(lesson.learned)
        turned.send()
        XCTAssertTrue(lesson.learned)
        let later = DialLesson(defaults: defaults, turned: Empty().eraseToAnyPublisher())
        XCTAssertTrue(later.learned, "remembered across launches")
    }

    func testTurningTheDialSaysSo() {
        let player = PodcastPlayer(engine: FakeEngine(), library: LibraryStore.inMemory(fetcher: StubFetcher(responses: [:])))
        let nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                    schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] })
        let lesson = DialLesson(defaults: defaults, turned: nowPlaying.turned)
        nowPlaying.turn(degrees: 10)
        XCTAssertFalse(lesson.learned, "nothing to steer, so nothing was turned")
    }

    func testTheCaptionNamesWhatTheDialMovesThrough() {
        XCTAssertEqual(DialLesson.caption(for: .music), "Scroll over the line to move through the song \u{00B7} \u{2325} + scroll for volume")
        XCTAssertEqual(DialLesson.caption(for: .podcast), "Scroll over the line to move through the episode \u{00B7} \u{2325} + scroll for volume")
    }

    func testTheEmptyPanelNamesEverySource() {
        XCTAssertEqual(DialPanelView.emptyTitle, "Nothing playing")
        XCTAssertEqual(DialPanelView.emptyLine, "Play something in Music or Spotify and it shows up here. Or follow a podcast.")
    }
}

final class PlaybackFailureCopyTests: XCTestCase {
    func testAFailureSaysWhatHappenedAndThatPlayTriesAgain() {
        XCTAssertEqual(DialPanelView.failureMessage("Offline"), "You're offline. Spindle kept your place.")
        XCTAssertEqual(DialPanelView.failureMessage("Unavailable"), "This episode couldn't be played.")
        XCTAssertEqual(DialPanelView.failureMessage("Something else"), "Something else")
    }
}

final class ChapterMenuTitleTests: XCTestCase {
    func testBeforeTheFirstChapterTheMenuSaysChapters() {
        XCTAssertEqual(DialPanelView.chapterMenuTitle(current: nil), "Chapters")
        XCTAssertEqual(DialPanelView.chapterMenuTitle(current: Chapter(start: 60, title: "Signal")), "Signal")
    }
}
