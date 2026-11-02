import XCTest
@testable import Spindle

@MainActor
final class ListContentTests: XCTestCase {
    private var library: LibraryStore!
    private var player: PodcastPlayer!
    private var engine: FakeEngine!
    private var music: FakeMusicSource!
    private var spotify: FakeMusicSource!
    private var remote: MusicRemote!
    private var nowPlaying: NowPlaying!
    private var show: Show!

    private func album(_ name: String, _ ids: [String]) -> MusicContext {
        MusicContext(kind: .album, id: "album:\(name)|Northern Static", title: name,
                     tracks: ids.enumerated().map { ContextTrack(id: $1, disc: 1, number: $0 + 1, title: $1,
                                                                 artist: "Northern Static", duration: 200) },
                     totalCount: ids.count)
    }

    override func setUp() async throws {
        let feed = URL(string: "https://example.com/feed")!
        library = LibraryStore.inMemory(fetcher: StubFetcher(responses: [feed: .success(SampleFeeds.longQuietThreeItems)]))
        show = try await library.follow(feedURL: feed)
        engine = FakeEngine()
        player = PodcastPlayer(engine: engine, library: library)
        music = FakeMusicSource(.appleMusic)
        spotify = FakeMusicSource(.spotify)
        music.stop()
        spotify.stop()
        remote = MusicRemote(sources: [music, spotify], every: { _, _ in NSObject() })
        nowPlaying = NowPlaying(player: player, media: FakeMediaCenter(), haptics: FakeHaptics(),
                                schedule: { _, _ in }, now: { 0 }, loadChapters: { _ in [] }, music: remote)
    }

    private func model(loadContext: ((MusicTrack, Bool) async -> MusicContext?)? = nil) -> ListModel {
        ListModel(nowPlaying: nowPlaying, library: library, loadContext: loadContext)
    }

    func testTheCountSitsAtTheFootOfTheList() {
        XCTAssertEqual(ListContent.countLine(shown: 11, total: 11), "11 songs")
        XCTAssertEqual(ListContent.countLine(shown: 1, total: 1), "1 song")
        XCTAssertEqual(ListContent.countLine(shown: 500, total: 812), "500 of 812 songs")
    }

    func testArrowKeysMoveThroughTheEpisodesFromTheOnePlaying() async {
        let episodes = library.episodes(of: show)
        player.open(episodes[1], autoplay: false)
        let list = model()
        await list.reload()
        XCTAssertNil(list.keyRow, "no outline until a key is pressed")
        list.moveKey(by: 1)
        XCTAssertEqual(list.keyRow, 2, "starts from the episode playing")
        list.moveKey(by: 1)
        XCTAssertEqual(list.keyRow, 2, "stops at the last row")
        list.moveKey(by: -5)
        XCTAssertEqual(list.keyRow, 0, "stops at the first row")
        XCTAssertTrue(list.playKeyRow())
        XCTAssertTrue(player.episode === episodes[0])
    }

    func testReturnPlaysTheOutlinedSongInItsAlbum() async {
        music.contextResult = .success(album("A", ["t1", "t2", "t3"]))
        music.contextKeyValue = "album:A|Northern Static"
        music.play("t1", id: "t1")
        await remote.refresh()
        let list = model()
        await list.reload()
        list.moveKey(by: 2)
        XCTAssertEqual(list.keyRow, 2)
        XCTAssertTrue(list.playKeyRow())
        await remote.lastCommand?.value
        XCTAssertEqual(music.playedInContext.map(\.trackID), ["t3"])
    }

    func testWithNoOutlineReturnHasNothingToPlay() async {
        player.open(library.episodes(of: show)[0], autoplay: false)
        let list = model()
        await list.reload()
        XCTAssertFalse(list.playKeyRow())
    }

    func testTheOutlineGoesWhenTheCoverTurnsBackOrTheListChanges() async {
        let episodes = library.episodes(of: show)
        player.open(episodes[0], autoplay: false)
        let list = model()
        await list.reload()
        list.showsList = true
        list.moveKey(by: 1)
        list.showsList = false
        XCTAssertNil(list.keyRow)
        list.moveKey(by: 1)
        list.tab = .chapters
        XCTAssertNil(list.keyRow, "another tab is another list")
    }

    func testPodcastContentListsTheShowNewestFirst() async {
        let episodes = library.episodes(of: show)
        player.open(episodes[1], autoplay: false)
        let list = model()
        await list.reload()
        guard case .podcast(let listed, let current, _, _, let description) = list.content else {
            return XCTFail("expected podcast content, got \(list.content)")
        }
        XCTAssertEqual(listed.map(\.guid), ["lq-113", "lq-112", "lq-111"])
        XCTAssertTrue(current === episodes[1])
        XCTAssertFalse(description.isEmpty)
        XCTAssertEqual(list.content.identity, show.feedURL.absoluteString)
        XCTAssertEqual(list.tab, .episodes)
    }

    func testIdentityIsStableWithinOneAlbumAndChangesAcrossAlbums() async {
        music.contextResult = .success(album("A", ["t1", "t2"]))
        music.contextKeyValue = "album:A|Northern Static"
        music.play("t1", id: "t1")
        await remote.refresh()
        let list = model()
        await list.reload()
        let first = list.content.identity
        XCTAssertEqual(first, "album:A|Northern Static")
        music.play("t2", id: "t2")
        await remote.refresh()
        await list.reload()
        XCTAssertEqual(list.content.identity, first, "the next song on the same album keeps the list")
        music.contextResult = .success(album("B", ["t3"]))
        music.contextKeyValue = "album:B|Northern Static"
        music.play("t3", id: "t3")
        await remote.refresh()
        await list.reload()
        XCTAssertEqual(list.content.identity, "album:B|Northern Static")
    }

    func testMusicGoingAwayEmptiesTheList() async {
        music.contextResult = .success(album("A", ["t1"]))
        music.play("t1", id: "t1")
        await remote.refresh()
        let list = model()
        await list.reload()
        music.running = false
        await remote.refresh()
        await list.reload()
        guard case .nothing = list.content else { return XCTFail("expected nothing, got \(list.content)") }
        XCTAssertNil(list.content.identity)
    }

    func testSongsWithNoContextSayNothingToList() async {
        music.contextResult = .success(nil)
        music.play("Radio", id: "r1")
        await remote.refresh()
        let list = model()
        await list.reload()
        guard case .musicMessage(_, let text) = list.content else { return XCTFail("got \(list.content)") }
        XCTAssertEqual(text, "Nothing to list for this song.")
    }

    func testReadFailureSaysCouldNotRead() async {
        music.contextResult = .failure(.scriptFailed("timeout"))
        music.play("Song", id: "t1")
        await remote.refresh()
        let list = model()
        await list.reload()
        guard case .musicMessage(_, let text) = list.content else { return XCTFail("got \(list.content)") }
        XCTAssertEqual(text, "Couldn't read the album from Music.")
    }

    func testStaleContextIsDropped() async {
        music.play("t1", id: "t1")
        await remote.refresh()
        var release: CheckedContinuation<Void, Never>?
        let list = model(loadContext: { [unowned self] track, _ in
            if track.trackID == "t1" {
                await withCheckedContinuation { release = $0 }
                return album("A", ["t1"])
            }
            return album("B", ["t3"])
        })
        let stale = Task { await list.reload() }
        while release == nil { await Task.yield() }
        music.play("t3", id: "t3")
        await remote.refresh()
        await list.reload()                // loads B
        release?.resume()
        await stale.value                  // A arrives late and must be ignored
        XCTAssertEqual(list.content.identity, "album:B|Northern Static")
    }

    func testSpotifyShowsDetails() async {
        spotify.play("Blue Hour Drive", id: "s1")
        await remote.refresh()
        let list = model()
        await list.reload()
        guard case .spotify(let track) = list.content else { return XCTFail("got \(list.content)") }
        XCTAssertEqual(track.title, "Blue Hour Drive")
    }

    private func signedInSpotify() -> SpotifyAccount {
        let store = MemoryTokenStore()
        store.save(SpotifyTokens(accessToken: "A", refreshToken: "R", expiresAt: .distantFuture))
        return SpotifyAccount(store: store, transport: FakeTransport(), defaults: UserDefaults(suiteName: "ListContentTests")!,
                              authenticate: { _ in throw CancellationError() })
    }

    func testSignedInSpotifyListsItsAlbum() async {
        spotify.contextResult = .success(album("S", ["spotify:track:s1", "spotify:track:s2"]))
        spotify.contextKeyValue = "album:S|Northern Static"
        spotify.play("Blue Hour Drive", id: "spotify:track:s2")
        await remote.refresh()
        let list = ListModel(nowPlaying: nowPlaying, library: library, spotify: signedInSpotify())
        await list.reload()
        guard case .music(let context, let current) = list.content else { return XCTFail("got \(list.content)") }
        XCTAssertEqual(context.title, "S")
        XCTAssertEqual(current, "spotify:track:s2")
    }

    func testSpotifyReadFailureNamesSpotify() async {
        spotify.contextResult = .failure(.scriptFailed("offline"))
        spotify.play("Song", id: "spotify:track:s1")
        await remote.refresh()
        let list = ListModel(nowPlaying: nowPlaying, library: library, spotify: signedInSpotify())
        await list.reload()
        guard case .musicMessage(_, let text) = list.content else { return XCTFail("got \(list.content)") }
        XCTAssertEqual(text, "Couldn't read the album from Spotify.")
    }

    func testSigningOutGoesBackToDetails() async {
        spotify.contextResult = .success(album("S", ["spotify:track:s1"]))
        spotify.play("Song", id: "spotify:track:s1")
        await remote.refresh()
        let account = signedInSpotify()
        let list = ListModel(nowPlaying: nowPlaying, library: library, spotify: account)
        await list.reload()
        account.signOut()
        XCTAssertTrue(list.needsReload, "signing in or out changes what the list shows")
        await list.reload()
        guard case .spotify = list.content else { return XCTFail("got \(list.content)") }
    }

    func testSignedInSpotifyHints() {
        XCTAssertEqual(ListContent.hint(mode: .music, source: .spotify, contextKind: .album), "Album \u{2304}")
        XCTAssertEqual(ListContent.hint(mode: .music, source: .spotify, contextKind: .playlist), "Playlist \u{2304}")
        XCTAssertEqual(ListContent.spokenHint(mode: .music, source: .spotify, contextKind: .album), "Show album")
    }

    func testTheSecondTabIsNotesWithoutChapters() {
        XCTAssertEqual(ListContent.secondTabTitle(hasChapters: true), "Chapters")
        XCTAssertEqual(ListContent.secondTabTitle(hasChapters: false), "Notes")
    }

    func testOpeningShowsTheAlbumAlreadyReadAtOnce() async {
        music.contextResult = .success(album("A", ["t1", "t2"]))
        music.contextKeyValue = "album:A|Northern Static"
        music.play("t2", id: "t2")
        await remote.refresh()
        _ = await remote.context(for: remote.track!)          // read once before, so it's cached
        var release: CheckedContinuation<Void, Never>?
        let list = model(loadContext: { [unowned self] track, refresh in
            await withCheckedContinuation { release = $0 }     // a slow re-read
            return await remote.context(for: track, refresh: refresh)
        })
        list.showNow(force: true)
        guard case .music(let context, let current) = list.content else { return XCTFail("got \(list.content)") }
        XCTAssertEqual(context.title, "A", "no \"Reading Music…\" while the re-read runs")
        XCTAssertEqual(current, "t2")
        let reading = Task { await list.reload(force: true) }
        while release == nil { await Task.yield() }
        guard case .music = list.content else { return XCTFail("the cached list stays up, got \(list.content)") }
        release?.resume()
        await reading.value
        guard case .music = list.content else { return XCTFail("got \(list.content)") }
    }

    func testAFailedReReadKeepsTheCachedAlbum() async {
        music.contextResult = .success(album("A", ["t1"]))
        music.contextKeyValue = "album:A|Northern Static"
        music.play("t1", id: "t1")
        await remote.refresh()
        _ = await remote.context(for: remote.track!)
        let list = model(loadContext: { _, _ in nil })
        await list.reload(force: true)
        guard case .music(let context, _) = list.content else { return XCTFail("got \(list.content)") }
        XCTAssertEqual(context.title, "A")
    }

    func testWithNothingCachedItSaysReading() async {
        music.play("t1", id: "t1")
        await remote.refresh()
        let list = model()
        list.showNow(force: true)
        guard case .musicLoading = list.content else { return XCTFail("got \(list.content)") }
    }

    func testHints() {
        XCTAssertEqual(ListContent.hint(mode: .podcast, source: nil, contextKind: nil), "Episodes \u{2304}")
        XCTAssertEqual(ListContent.hint(mode: .music, source: .appleMusic, contextKind: .playlist), "Playlist \u{2304}")
        XCTAssertEqual(ListContent.hint(mode: .music, source: .appleMusic, contextKind: nil), "Album \u{2304}")
        XCTAssertEqual(ListContent.hint(mode: .music, source: .spotify, contextKind: nil), "Spotify \u{2304}")
    }

    func testPlainTextFromHTML() {
        XCTAssertEqual(ListContent.plainText(fromHTML: "<p>Hi &amp; <b>bye</b></p>\n\n"), "Hi & bye")
        XCTAssertEqual(ListContent.plainText(fromHTML: "Line one<br>Line   two"), "Line one Line two")
        XCTAssertEqual(ListContent.plainText(fromHTML: nil), "No description.")
        XCTAssertEqual(ListContent.plainText(fromHTML: "  "), "No description.")
    }

    // MARK: Review fixes

    func testReloadIsNeededOnlyWhenWhatIsPlayingChanges() async {
        let episodes = library.episodes(of: show)
        player.open(episodes[0], autoplay: false)
        let list = model()
        await list.reload()
        XCTAssertFalse(list.needsReload)
        engine.fireTime(30)
        XCTAssertFalse(list.needsReload, "position ticks don't rebuild the list")
        player.open(episodes[1], autoplay: false)
        XCTAssertTrue(list.needsReload)
    }

    func testCloseRule() {
        typealias Rule = ListCloseRule
        XCTAssertEqual(Rule.decide(last: nil, identity: "loading:t1", isLoading: true), .keep(nil))
        XCTAssertEqual(Rule.decide(last: nil, identity: "album:A", isLoading: false), .keep("album:A"))
        XCTAssertEqual(Rule.decide(last: "album:A", identity: "loading:t9", isLoading: true), .keep("album:A"))
        XCTAssertEqual(Rule.decide(last: "album:A", identity: "album:A", isLoading: false), .keep("album:A"))
        XCTAssertEqual(Rule.decide(last: "album:A", identity: "album:B", isLoading: false), .close)
        XCTAssertEqual(Rule.decide(last: "album:A", identity: nil, isLoading: false), .close)
    }

    func testAStreamedSongIsHighlightedInItsAlbum() async {
        music.contextResult = .success(album("A", ["lib1", "lib2"]))
        music.contextKeyValue = "album:A|Northern Static"
        music.play("lib2", id: "stream7")   // same song, streamed copy
        await remote.refresh()
        let list = model()
        await list.reload()
        guard case .music(_, let current) = list.content else { return XCTFail("got \(list.content)") }
        XCTAssertEqual(current, "lib2")
    }

    func testSpokenHintsHaveNoArrow() {
        XCTAssertEqual(ListContent.spokenHint(mode: .podcast, source: nil, contextKind: nil), "Show episodes")
        XCTAssertEqual(ListContent.spokenHint(mode: .music, source: .appleMusic, contextKind: .playlist), "Show playlist")
        XCTAssertEqual(ListContent.spokenHint(mode: .music, source: .appleMusic, contextKind: nil), "Show album")
        XCTAssertEqual(ListContent.spokenHint(mode: .music, source: .spotify, contextKind: nil), "Show song details")
    }

    func testEpisodeDatesDropThisYear() {
        let gb = Locale(identifier: "en_GB")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
        let now = date(2026, 11, 2)
        XCTAssertEqual(ListContent.episodeDate(date(2026, 10, 31), now: now, locale: gb, calendar: calendar), "31 Oct")
        XCTAssertEqual(ListContent.episodeDate(date(2025, 12, 30), now: now, locale: gb, calendar: calendar), "30 Dec 2025")
    }
}
