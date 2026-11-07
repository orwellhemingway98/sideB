import XCTest
@testable import SideB

/// A clicked song lights up straight away, because the app can take a moment to report it. If it never does,
/// the highlight goes back to what's really playing.
@MainActor
final class ListRowClickTests: XCTestCase {
    private var source: FakeMusicSource!
    private var remote: MusicRemote!
    private var nowPlaying: NowPlaying!
    private var list: ListModel!
    private let album = MusicContext(kind: .album, id: "album:AL1", title: "Night Roads",
                                     tracks: ["s1", "s2", "s3"].enumerated().map {
                                         ContextTrack(id: $1, disc: 1, number: $0 + 1, title: $1, artist: "Northern Static", duration: 200)
                                     }, totalCount: 3)

    private func start(patience: TimeInterval = 60) async {
        let library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [:]))
        source = FakeMusicSource(.appleMusic)
        remote = MusicRemote(sources: [source], every: { _, _ in NSObject() })
        nowPlaying = NowPlaying(player: PodcastPlayer(engine: FakeEngine(), library: library), media: FakeMediaCenter(),
                                haptics: FakeHaptics(), schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] },
                                music: remote)
        let context = album
        source.contextKeyValue = context.id
        source.play("s1", id: "s1")
        await remote.refresh()
        list = ListModel(nowPlaying: nowPlaying, library: library, loadContext: { _, _ in context }, rowPatience: patience)
        await list.reload()
        XCTAssertEqual(current, "s1")
    }

    private var current: String? {
        if case .music(_, let id) = list.content { return id }
        return nil
    }

    func testTheClickedRowLightsUpBeforeTheAppSaysAnything() async {
        await start()
        list.play(album.tracks[1], in: album)
        XCTAssertEqual(current, "s2")
        await remote.lastCommand?.value
        XCTAssertEqual(source.playedInContext.map(\.trackID), ["s2"])
        XCTAssertEqual(current, "s2")
    }

    func testAFailedClickGoesBackToWhatsPlaying() async throws {
        await start()
        source.commandFailure = .scriptFailed("timed out")
        list.play(album.tracks[1], in: album)
        XCTAssertEqual(current, "s2")
        await remote.lastCommand?.value
        for _ in 0..<40 where current != "s1" { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(current, "s1")
    }

    func testASongThatNeverArrivesGoesBackAfterAWhile() async throws {
        await start(patience: 0.05)
        list.play(album.tracks[1], in: album)
        await remote.lastCommand?.value
        for _ in 0..<40 where current != "s1" { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertEqual(current, "s1")
    }

    func testTheSongArrivingKeepsTheHighlightAfterThePatienceRunsOut() async throws {
        await start(patience: 0.05)
        list.play(album.tracks[1], in: album)
        await remote.lastCommand?.value
        source.play("s2", id: "s2")
        await remote.refresh()
        await list.reload()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(current, "s2")
    }

    func testAnEarlierClicksPatienceLeavesANewerClickAlone() async throws {
        await start(patience: 0.2)
        list.play(album.tracks[1], in: album)
        await remote.lastCommand?.value
        try await Task.sleep(for: .milliseconds(120))
        list.play(album.tracks[2], in: album)
        await remote.lastCommand?.value
        try await Task.sleep(for: .milliseconds(120))   // past the first click's time, not the second's
        XCTAssertEqual(current, "s3")
    }

    func testGoingBackNeverLeavesTheListStuckReading() async throws {
        await start(patience: 0.05)
        source.contextKeyValue = "album:OTHER"
        source.play("Elsewhere", id: "x1")
        await remote.refresh()
        list.play(album.tracks[1], in: album)
        await remote.lastCommand?.value
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(list.content.isLoading)
    }

    func testReturnLightsUpTheRowToo() async {
        await start()
        list.moveKey(by: 1)
        XCTAssertTrue(list.playKeyRow())
        XCTAssertEqual(current, "s2")
    }
}
