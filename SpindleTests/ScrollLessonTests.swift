import Combine
import XCTest
@testable import Spindle

/// The one-time caption that teaches the line: shown until the first scroll, then never again.
@MainActor
final class ScrollLessonTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "ScrollLessonTests")!
        defaults.removePersistentDomain(forName: "ScrollLessonTests")
    }

    func testTheFirstTurnEndsTheLessonForGood() {
        let turned = PassthroughSubject<Void, Never>()
        let lesson = ScrollLesson(defaults: defaults, turned: turned.eraseToAnyPublisher())
        XCTAssertFalse(lesson.learned)
        turned.send()
        XCTAssertTrue(lesson.learned)
        let later = ScrollLesson(defaults: defaults, turned: Empty().eraseToAnyPublisher())
        XCTAssertTrue(later.learned, "remembered across launches")
    }

    func testTurningTheDialSaysSo() {
        let player = PodcastPlayer(engine: FakeEngine(), library: LibraryStore.inMemory(fetcher: StubFetcher(responses: [:])))
        let nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                    schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] })
        let lesson = ScrollLesson(defaults: defaults, turned: nowPlaying.turned)
        nowPlaying.turn(degrees: 10)
        XCTAssertFalse(lesson.learned, "nothing to steer, so nothing was turned")
    }

    func testTheCaptionNamesWhatTheDialMovesThrough() {
        XCTAssertEqual(ScrollLesson.caption(for: .music), "Scroll over the line to move through the song \u{00B7} \u{2325} + scroll for volume")
        XCTAssertEqual(ScrollLesson.caption(for: .podcast), "Scroll over the line to move through the episode \u{00B7} \u{2325} + scroll for volume")
    }

    func testTheEmptyPanelNamesEverySource() {
        XCTAssertEqual(PanelView.emptyTitle, "Nothing playing")
        XCTAssertEqual(PanelView.emptyLine, "Play something in Music or Spotify and it shows up here. Or follow a podcast.")
    }
}

final class PlaybackFailureCopyTests: XCTestCase {
    func testAFailureSaysWhatHappenedAndThatPlayTriesAgain() {
        XCTAssertEqual(PanelView.failureMessage("Offline"), "You're offline. Spindle kept your place.")
        XCTAssertEqual(PanelView.failureMessage("Unavailable"), "This episode couldn't be played.")
        XCTAssertEqual(PanelView.failureMessage("Something else"), "Something else")
    }
}

final class ChapterMenuTitleTests: XCTestCase {
    func testBeforeTheFirstChapterTheMenuSaysChapters() {
        XCTAssertEqual(PanelView.chapterMenuTitle(current: nil), "Chapters")
        XCTAssertEqual(PanelView.chapterMenuTitle(current: Chapter(start: 60, title: "Signal")), "Signal")
    }
}
