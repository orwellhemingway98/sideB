# Spindle Stage 1: Dial and Podcasts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A menu bar app whose Liquid Glass dial plays podcasts you follow, scrubbing with trackpad ticks every 15 s and a firmer click at chapters, with speed, saved places, a simple Up Next and a minimal Library window.

**Architecture:** Pure, tested cores (`DialEngine`, `HapticLimiter`, `ResumePolicy`, `FeedParser`, `ChapterLoader`, `DirectorySearch`) under thin AppKit/AVFoundation adapters (`Haptics`, `AVPlayerEngine`, `MediaCenter`). A `@MainActor` `NowPlaying` coordinator is the only thing the views and the dial talk to; it drives `PodcastPlayer`, which reads episodes from a SwiftData `LibraryStore`.

**Tech Stack:** Swift 5 language mode, SwiftUI + AppKit, AVFoundation, MediaPlayer, SwiftData, XCTest, XcodeGen. macOS 26+.

**Spec:** `docs/superpowers/specs/2026-10-31-spindle-design.md` (stage 1 of 3).

## Global Constraints

- macOS 26.0 deployment target; Liquid Glass via SwiftUI `.glassEffect(...)`; Swift language mode 5.
- Bundle id `com.mfelouro.Spindle`; ad-hoc signing (`CODE_SIGN_IDENTITY: "-"`), hardened runtime. No Apple Events entitlement until stage 3 (music).
- No Apple logos, product artwork or icons; no SF Symbols in our own drawn controls (system glass is fine). Icons are drawn in code.
- Nothing is pushed or published unless the author asks. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Tests run with `./scripts/test.sh` (log in `build.noindex/test.log`). Build output lives in `build.noindex/` so Spotlight skips it.
- Dial values (spec): 360° = 120 s at normal pace; acceleration above 360°/s, linear to 4× at 1,440°/s, speed measured over the last 100 ms; ticks every 15 s; chapters beat ticks; haptics at most one per 35 ms; seek commits after 150 ms of no turning.
- Playback values (spec): rates 1, 1.2, 1.5, 2 (cycle back to 1); skip −15 / +30; save every 5 s and on pause/seek end/switch/quit; resume at saved − 3 s; within the last 30 s counts as played.
- Spindle is a menu bar app: `LSUIElement` = YES (no Dock icon). The Library window activates the app when opened.

## Review Focus

1. An episode whose feed has no `itunes:duration`: the dial must still scrub and tick before the player reports a duration (no upper clamp until known). → Task 2 test `testUnknownDurationDoesNotClampForward`.
2. A feed item with no `<guid>`: it must still get a stable identity (the enclosure URL), or refreshes duplicate it. → Task 4 test `testMissingGuidFallsBackToEnclosureURL`.
3. Following the same show twice (pasted twice, or found by search after pasting): one show, not two. → Task 7 test `testFollowingTheSameFeedTwiceKeepsOneShow`.
4. Quitting or switching episodes mid-play: the place is saved at that moment, not up to 5 s earlier. → Task 8 tests `testPauseSavesImmediately`, `testSwitchingEpisodeSavesTheOldOne`.
5. Search terms with spaces and accents ("café crème"): correctly escaped, no crash on a malformed response. → Task 6 tests `testTermIsPercentEscaped`, `testMalformedResponseThrows`.

---

## File Structure

```
spindle/
  project.yml                      XcodeGen project (Task 1)
  scripts/test.sh                  regenerate + run tests (Task 1)
  Spindle/App/                     SpindleApp, AppDelegate, Info.plist (Tasks 1, 11)
  Spindle/Dial/                    DialEngine, HapticLimiter, Haptics, DialGeometry (Tasks 2, 3, 10)
  Spindle/Feeds/                   FeedModels, FeedParser, DurationParser, ChapterLoader, FeedFetcher, DirectorySearch (Tasks 4–6)
  Spindle/Library/                 Show, Episode, UpNextEntry, LibraryStore (Task 7)
  Spindle/Playback/                ResumePolicy, AudioEngine, AVPlayerEngine, PodcastPlayer, NowPlaying, MediaCenter (Tasks 8, 9)
  Spindle/UI/                      StatusStrip, DialPanel, DiscView, LibraryWindow, TimeFormat (Tasks 1, 10, 11)
  SpindleTests/                    one test file per unit
```

---

### Task 1: Project, test script and the time formatter

**Files:**
- Create: `project.yml`, `scripts/test.sh`, `Spindle/App/SpindleApp.swift`, `Spindle/App/AppDelegate.swift`, `Spindle/UI/TimeFormat.swift`
- Test: `SpindleTests/TimeFormatTests.swift`

**Interfaces:**
- Produces: `enum TimeFormat { static func clock(_ seconds: TimeInterval) -> String; static func remaining(_ seconds: TimeInterval) -> String }`

- [ ] **Step 1: Project files.** Copy ClickWheel's `project.yml` shape (`../ipod_app/project.yml`) with: name `Spindle`, targets `Spindle` (application, sources `[Spindle]`, Info.plist at `Spindle/App/Info.plist` with `CFBundleName`/`CFBundleDisplayName` "Spindle", version `0.1.0`, build `1`, `LSApplicationCategoryType: public.app-category.music`, `LSUIElement: true`) and `SpindleTests` (unit tests, host app `Spindle`); deployment target `"26.0"`; `PRODUCT_BUNDLE_IDENTIFIER: com.mfelouro.Spindle`; hardened runtime; ad-hoc signing. Copy `../ipod_app/scripts/test.sh` replacing ClickWheel with Spindle. `SpindleApp` is an `@main App` with `@NSApplicationDelegateAdaptor(AppDelegate.self)` and `Settings { EmptyView() }`; `AppDelegate.applicationDidFinishLaunching` returns early when `XCTestConfigurationFilePath` is set (as ClickWheel's `AppModel.isRunningTests`).

- [ ] **Step 2: Write the failing tests**

```swift
func testClock() {
    XCTAssertEqual(TimeFormat.clock(0), "0:00")
    XCTAssertEqual(TimeFormat.clock(65), "1:05")
    XCTAssertEqual(TimeFormat.clock(3_845), "1:04:05")
    XCTAssertEqual(TimeFormat.clock(-4), "0:00")
}
func testRemaining() {
    XCTAssertEqual(TimeFormat.remaining(1_112), "−18:32")   // U+2212 minus
}
```

- [ ] **Step 3: Run** `./scripts/test.sh` — Expected: build error, `TimeFormat` not found.
- [ ] **Step 4: Implement `TimeFormat`** (floor to whole seconds; hours only when ≥ 1 h).
- [ ] **Step 5: Run** `./scripts/test.sh` — Expected: `** TEST SUCCEEDED **`, 2 tests.
- [ ] **Step 6: Commit** `git add -A && git commit -m "Project, test script, time format"`.

---

### Task 2: DialEngine

**Files:**
- Create: `Spindle/Dial/DialEngine.swift`
- Test: `SpindleTests/DialEngineTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum Detent: Equatable { case tick(at: TimeInterval), chapter(at: TimeInterval) }
  struct DialStep: Equatable { let seek: TimeInterval; let detents: [Detent] }
  struct DialEngine {
      static let secondsPerDegree: Double = 120.0 / 360.0
      static let tickInterval: TimeInterval = 15
      mutating func turn(degrees: Double, at time: TimeInterval,
                         position: TimeInterval, duration: TimeInterval?,
                         chapters: [TimeInterval]) -> DialStep
      mutating func reset()   // forget the speed history
  }
  ```

Speed rule (the tests pin it): speed = sum of |degrees| of the samples with timestamps in `(time − 0.1, time]`, including this one, divided by 0.1 s. Multiplier = 1 when speed ≤ 360; otherwise `min(4, 1 + 3 × (speed − 360) / 1080)`. New position = clamp(position + degrees × secondsPerDegree × multiplier, 0, duration ?? .infinity); `seek` = new − old. Detents: every multiple of 15 s (greater than 0) and every chapter start (greater than 0) lying strictly past the old position and at or before the new one, in the direction of travel; a chapter within 0.5 s of a tick replaces that tick.

- [ ] **Step 1: Write the failing tests**

```swift
func testNormalPaceFullTurnIsTwoMinutes() {
    var e = DialEngine()
    var total = 0.0
    for i in 0..<36 { total += e.turn(degrees: 10, at: Double(i) * 0.1, position: 600 + total, duration: 3600, chapters: []).seek }
    XCTAssertEqual(total, 120, accuracy: 0.001)   // 10° per 100 ms = 100°/s, no acceleration
}
func testFastTurningAcceleratesUpToFourTimes() {
    var e = DialEngine()
    XCTAssertEqual(e.turn(degrees: 72, at: 0, position: 600, duration: 3600, chapters: []).seek, 72 * (1 + 3 * 360.0 / 1080) / 3, accuracy: 0.001) // 720°/s → 2×
    var f = DialEngine()
    XCTAssertEqual(f.turn(degrees: 300, at: 0, position: 600, duration: 3600, chapters: []).seek, 300 * 4 / 3, accuracy: 0.001)               // 3000°/s → capped 4×
}
func testClampsAtStartAndEnd() {
    var e = DialEngine()
    XCTAssertEqual(e.turn(degrees: -90, at: 0, position: 10, duration: 3600, chapters: []).seek, -10)
    e.reset()
    XCTAssertEqual(e.turn(degrees: 90, at: 1, position: 3590, duration: 3600, chapters: []).seek, 10)
}
func testUnknownDurationDoesNotClampForward() {
    var e = DialEngine()
    XCTAssertEqual(e.turn(degrees: 9, at: 0, position: 3599, duration: nil, chapters: []).seek, 3, accuracy: 0.001) // 90°/s, no acceleration
}
func testTicksEveryFifteenSecondsInDirectionOfTravel() {
    var e = DialEngine()
    // 54° in one event = 540°/s → 1.5× → 27 s
    XCTAssertEqual(e.turn(degrees: 54, at: 0, position: 14, duration: 3600, chapters: []).detents, [.tick(at: 15), .tick(at: 30)]) // 14 → 41
    e.reset()
    XCTAssertEqual(e.turn(degrees: -54, at: 1, position: 46, duration: 3600, chapters: []).detents, [.tick(at: 45), .tick(at: 30)]) // 46 → 19
}
func testChapterReplacesNearbyTickAndStandsAlone() {
    var e = DialEngine()
    XCTAssertEqual(e.turn(degrees: 54, at: 0, position: 14, duration: 3600, chapters: [0, 22, 30.3]).detents,  // 14 → 41
                   [.tick(at: 15), .chapter(at: 22), .chapter(at: 30.3)])
}
func testStartingExactlyOnABoundaryDoesNotRepeatIt() {
    var e = DialEngine()
    XCTAssertEqual(e.turn(degrees: 3, at: 0, position: 15, duration: 3600, chapters: [15]).detents, [])
}
```

- [ ] **Step 2: Run** `./scripts/test.sh -only-testing:SpindleTests/DialEngineTests` — Expected: build error, `DialEngine` not found.
- [ ] **Step 3: Implement `DialEngine`** per the rule above (keep samples as `[(time, |degrees|)]`, drop those older than 100 ms).
- [ ] **Step 4: Run** the same command — Expected: 7 tests pass.
- [ ] **Step 5: Commit** `"DialEngine: turning to seconds, acceleration, ticks and chapters"`.

---

### Task 3: Haptics

**Files:**
- Create: `Spindle/Dial/HapticLimiter.swift`, `Spindle/Dial/Haptics.swift`
- Test: `SpindleTests/HapticLimiterTests.swift`

**Interfaces:**
- Consumes: `Detent` (Task 2).
- Produces:
  ```swift
  enum HapticKind: Equatable { case tick, chapter }
  struct HapticLimiter {
      static let minInterval: TimeInterval = 0.035
      mutating func next(for detents: [Detent], at time: TimeInterval) -> HapticKind?
  }
  protocol HapticPerforming { func perform(_ kind: HapticKind) }
  final class Haptics: HapticPerforming   // .tick → .generic, .chapter → .levelChange, performanceTime .now
  ```

Rule: one haptic per call at most. If the detents contain a chapter, return `.chapter` always (chapters are never dropped, even inside 35 ms). Otherwise return `.tick` only if ≥ 35 ms since the last haptic returned; else nil. Empty detents → nil.

- [ ] **Step 1: Write the failing tests**

```swift
func testTickThenTooSoonThenAllowed() {
    var l = HapticLimiter()
    XCTAssertEqual(l.next(for: [.tick(at: 15)], at: 0), .tick)
    XCTAssertNil(l.next(for: [.tick(at: 30)], at: 0.020))
    XCTAssertEqual(l.next(for: [.tick(at: 45)], at: 0.036), .tick)
}
func testChapterIsNeverDropped() {
    var l = HapticLimiter()
    _ = l.next(for: [.tick(at: 15)], at: 0)
    XCTAssertEqual(l.next(for: [.tick(at: 30), .chapter(at: 31)], at: 0.010), .chapter)
}
func testNothingCrossedNothingFelt() {
    var l = HapticLimiter()
    XCTAssertNil(l.next(for: [], at: 0))
}
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/HapticLimiterTests` — Expected: build error.
- [ ] **Step 3: Implement** `HapticLimiter` and `Haptics` (`NSHapticFeedbackManager.defaultPerformer.perform(_:performanceTime: .now)`).
- [ ] **Step 4: Run** — Expected: 3 pass.
- [ ] **Step 5: Commit** `"Haptics: tick and chapter, rate-limited"`.

---

### Task 4: Feed parsing

**Files:**
- Create: `Spindle/Feeds/FeedModels.swift`, `Spindle/Feeds/DurationParser.swift`, `Spindle/Feeds/FeedParser.swift`
- Test: `SpindleTests/FeedParserTests.swift`, `SpindleTests/DurationParserTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct Chapter: Codable, Equatable { let start: TimeInterval; let title: String }
  struct ParsedFeed: Equatable { let title: String; let author: String?; let artworkURL: URL?; let summary: String?; let episodes: [ParsedEpisode] }
  struct ParsedEpisode: Equatable {
      let guid: String; let title: String; let published: Date?; let duration: TimeInterval?
      let enclosureURL: URL; let enclosureType: String?; let chaptersURL: URL?
      let inlineChapters: [Chapter]; let summary: String?
  }
  enum FeedError: Error, Equatable { case notAFeed }
  enum FeedParser { static func parse(_ data: Data) throws -> ParsedFeed }
  enum DurationParser { static func seconds(_ text: String) -> TimeInterval? }   // "3120", "52:00", "1:04:00", "00:00:05.500"
  ```

Namespaces: `itunes` = `http://www.itunes.com/dtds/podcast-1.0.dtd`, `podcast` = `https://podcastindex.org/namespace/1.0`, `psc` = `http://podlove.org/simple-chapters`. Match by element *local name* plus namespace URI (`shouldProcessNamespaces = true`). Artwork: `itunes:image@href`, else `image/url`. Items without an enclosure URL are skipped. guid: `<guid>` text, else the enclosure URL string. Dates: RFC 822 (`EEE, dd MMM yyyy HH:mm:ss Z`, `en_US_POSIX`), nil if unparseable. Text accumulates across CDATA and character callbacks, trimmed.

- [ ] **Step 1: Write the failing tests** (sample feeds as inline string literals in the test file)

```swift
func testDurations() {
    XCTAssertEqual(DurationParser.seconds("3120"), 3120)
    XCTAssertEqual(DurationParser.seconds("52:00"), 3120)
    XCTAssertEqual(DurationParser.seconds("1:04:00"), 3840)
    XCTAssertEqual(DurationParser.seconds("00:00:05.500"), 5.5)
    XCTAssertNil(DurationParser.seconds(""))
    XCTAssertNil(DurationParser.seconds("about an hour"))
}
func testParsesShowAndEpisodes() throws {
    let feed = try FeedParser.parse(Data(Self.longQuiet.utf8))   // 2 items, itunes:image, itunes:author, CDATA title "Ep. 112 — Rooms & Rooms"
    XCTAssertEqual(feed.title, "The Long Quiet")
    XCTAssertEqual(feed.author, "Field Studio")
    XCTAssertEqual(feed.artworkURL, URL(string: "https://example.com/art.jpg"))
    XCTAssertEqual(feed.episodes.count, 2)
    XCTAssertEqual(feed.episodes[0].title, "Ep. 112 — Rooms & Rooms")
    XCTAssertEqual(feed.episodes[0].duration, 3120)
    XCTAssertEqual(feed.episodes[0].enclosureURL, URL(string: "https://example.com/112.mp3"))
    XCTAssertEqual(feed.episodes[0].chaptersURL, URL(string: "https://example.com/112-chapters.json"))
}
func testInlinePodloveChapters() throws {
    let feed = try FeedParser.parse(Data(Self.withPSC.utf8))     // psc:chapter start="00:00:00" "Intro", start="12:30.5" "Basement tapes"
    XCTAssertEqual(feed.episodes[0].inlineChapters, [Chapter(start: 0, title: "Intro"), Chapter(start: 750.5, title: "Basement tapes")])
}
func testMissingGuidFallsBackToEnclosureURL() throws {
    let feed = try FeedParser.parse(Data(Self.noGuid.utf8))
    XCTAssertEqual(feed.episodes[0].guid, "https://example.com/9.mp3")
}
func testItemWithoutEnclosureIsSkipped() throws {
    XCTAssertEqual(try FeedParser.parse(Data(Self.oneWithoutEnclosure.utf8)).episodes.count, 1)
}
func testNotAFeedThrows() {
    XCTAssertThrowsError(try FeedParser.parse(Data("<html><body>hi</body></html>".utf8))) { XCTAssertEqual($0 as? FeedError, .notAFeed) }
}
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/FeedParserTests -only-testing:SpindleTests/DurationParserTests` — Expected: build error.
- [ ] **Step 3: Implement** the three files (`XMLParserDelegate` class kept private inside `FeedParser.swift`).
- [ ] **Step 4: Run** — Expected: 6 pass.
- [ ] **Step 5: Commit** `"Feed parsing: RSS, iTunes and podcast namespaces, Podlove chapters"`.

---

### Task 5: Chapters and fetching

**Files:**
- Create: `Spindle/Feeds/ChapterLoader.swift`, `Spindle/Feeds/FeedFetcher.swift`
- Test: `SpindleTests/ChapterLoaderTests.swift`

**Interfaces:**
- Consumes: `Chapter` (Task 4).
- Produces:
  ```swift
  protocol HTTPFetching { func data(from url: URL) async throws -> Data }
  struct URLSessionFetcher: HTTPFetching      // throws on non-2xx
  enum ChapterLoader {
      static func decodeJSON(_ data: Data) throws -> [Chapter]   // {"chapters":[{"startTime":0,"title":"Intro"}…]}, sorted by start, untitled dropped
      static func load(chaptersURL: URL?, inline: [Chapter], audioChapters: () async -> [Chapter],
                       fetcher: HTTPFetching) async -> [Chapter]
  }
  enum AudioFileChapters { static func read(from url: URL) async -> [Chapter] }   // AVURLAsset chapterMetadataGroups, common title key
  ```

Order (spec): chapters URL JSON → inline Podlove → audio file. A source that fails or yields `[]` falls through to the next; all empty → `[]`.

- [ ] **Step 1: Write the failing tests**

```swift
func testDecodesPodcastChaptersJSON() throws {
    let json = #"{"version":"1.2.0","chapters":[{"startTime":750.5,"title":"Basement tapes"},{"startTime":0,"title":"Intro"},{"startTime":900}]}"#
    XCTAssertEqual(try ChapterLoader.decodeJSON(Data(json.utf8)), [Chapter(start: 0, title: "Intro"), Chapter(start: 750.5, title: "Basement tapes")])
}
func testJSONWinsOverInlineAndAudio() async {
    let got = await ChapterLoader.load(chaptersURL: URL(string: "https://x/c.json"), inline: [Chapter(start: 0, title: "inline")],
                                       audioChapters: { [Chapter(start: 0, title: "audio")] }, fetcher: StubFetcher(json: #"{"chapters":[{"startTime":0,"title":"json"}]}"#))
    XCTAssertEqual(got.map(\.title), ["json"])
}
func testFailingJSONFallsToInline() async {
    let got = await ChapterLoader.load(chaptersURL: URL(string: "https://x/c.json"), inline: [Chapter(start: 0, title: "inline")],
                                       audioChapters: { [] }, fetcher: StubFetcher(error: URLError(.notConnectedToInternet)))
    XCTAssertEqual(got.map(\.title), ["inline"])
}
func testFallsThroughToAudioFile() async {
    let got = await ChapterLoader.load(chaptersURL: nil, inline: [], audioChapters: { [Chapter(start: 0, title: "audio")] }, fetcher: StubFetcher(json: "{}"))
    XCTAssertEqual(got.map(\.title), ["audio"])
}
```
(`StubFetcher` is a small test helper conforming to `HTTPFetching`.)

- [ ] **Step 2: Run** `-only-testing:SpindleTests/ChapterLoaderTests` — Expected: build error.
- [ ] **Step 3: Implement** the two files.
- [ ] **Step 4: Run** — Expected: 4 pass.
- [ ] **Step 5: Commit** `"Chapters from JSON, feed or audio file; HTTP fetcher"`.

---

### Task 6: Directory search

**Files:**
- Create: `Spindle/Feeds/DirectorySearch.swift`
- Test: `SpindleTests/DirectorySearchTests.swift`

**Interfaces:**
- Consumes: `HTTPFetching` (Task 5).
- Produces:
  ```swift
  struct DirectoryResult: Equatable, Identifiable { var id: URL { feedURL }; let title: String; let author: String; let artworkURL: URL?; let feedURL: URL }
  enum DirectorySearch {
      static func url(for term: String) -> URL      // https://itunes.apple.com/search?media=podcast&entity=podcast&limit=25&term=…
      static func decode(_ data: Data) throws -> [DirectoryResult]   // collectionName, artistName, artworkUrl600, feedUrl; results without feedUrl dropped
      static func search(_ term: String, fetcher: HTTPFetching) async throws -> [DirectoryResult]  // blank term → []
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
func testTermIsPercentEscaped() {
    let url = DirectorySearch.url(for: "café crème")
    XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "term" }?.value, "café crème")
    XCTAssertTrue(url.absoluteString.contains("term=caf%C3%A9%20cr%C3%A8me"))
}
func testDecodesResultsAndDropsThoseWithoutFeeds() throws {
    let json = #"{"resultCount":2,"results":[{"collectionName":"Tidewater","artistName":"Salt Co","artworkUrl600":"https://e/a.jpg","feedUrl":"https://e/feed"},{"collectionName":"No Feed","artistName":"X"}]}"#
    XCTAssertEqual(try DirectorySearch.decode(Data(json.utf8)), [DirectoryResult(title: "Tidewater", author: "Salt Co", artworkURL: URL(string: "https://e/a.jpg"), feedURL: URL(string: "https://e/feed")!)])
}
func testMalformedResponseThrows() {
    XCTAssertThrowsError(try DirectorySearch.decode(Data("<html>".utf8)))
}
func testBlankTermSearchesNothing() async throws {
    let r = try await DirectorySearch.search("  ", fetcher: StubFetcher(error: URLError(.badURL)))
    XCTAssertEqual(r, [])
}
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/DirectorySearchTests` — Expected: build error.
- [ ] **Step 3: Implement** (build with `URLComponents`; `Decodable` private structs).
- [ ] **Step 4: Run** — Expected: 4 pass.
- [ ] **Step 5: Commit** `"Directory search via Apple's public podcast search"`.

---

### Task 7: Library store

**Files:**
- Create: `Spindle/Library/Show.swift`, `Spindle/Library/Episode.swift`, `Spindle/Library/UpNextEntry.swift`, `Spindle/Library/LibraryStore.swift`
- Test: `SpindleTests/LibraryStoreTests.swift`

**Interfaces:**
- Consumes: `FeedParser`, `ParsedFeed`, `Chapter` (Task 4); `HTTPFetching` (Task 5).
- Produces:
  ```swift
  @Model final class Show { @Attribute(.unique) var feedURL: URL; var title: String; var author: String?; var artworkURL: URL?
      var summary: String?; var lastUpdated: Date?; var lastError: String?; var errorSince: Date?
      @Relationship(deleteRule: .cascade, inverse: \Episode.show) var episodes: [Episode] }
  @Model final class Episode { var guid: String; var show: Show?; var title: String; var published: Date?; var duration: TimeInterval?
      var enclosureURL: URL; var enclosureType: String?; var chaptersURL: URL?; var inlineChaptersData: Data?; var summary: String?
      var position: TimeInterval = 0; var played = false; var localFile: URL?
      var inlineChapters: [Chapter] { get }   // decodes inlineChaptersData
      var playableURL: URL { get } }          // localFile if it exists on disk, else enclosureURL
  @Model final class UpNextEntry { var episode: Episode?; var order: Int }
  enum LibraryError: Error, Equatable { case invalidFeed }
  @MainActor final class LibraryStore: ObservableObject {
      init(container: ModelContainer, fetcher: HTTPFetching, defaults: UserDefaults = .standard)
      static func inMemory(fetcher: HTTPFetching) -> LibraryStore          // for tests and previews; fresh throwaway UserDefaults suite
      var shows: [Show] { get }                                            // by title
      func episodes(of show: Show) -> [Episode]                            // newest first
      func follow(feedURL: URL) async throws -> Show                       // fetch+parse; existing show returned unchanged
      func refresh(_ show: Show) async                                     // upsert by guid; record lastError/errorSince on failure
      func refreshAll() async                                              // two at a time
      var upNext: [Episode] { get }
      func enqueue(_ episode: Episode)                                     // append unless already queued
      func remove(fromUpNext episode: Episode)
      func popNext() -> Episode?                                           // removes and returns the first
      func savePosition(_ position: TimeInterval, of episode: Episode)
      func markPlayed(_ episode: Episode)                                  // played = true, position = 0
      var lastEpisodeGUID: String? { get set }                             // UserDefaults "lastEpisodeGUID", to restore at launch
  }
  ```

Feed URL identity: compare with `https` scheme and no trailing slash (`http://e/feed/` and `https://e/feed` are the same show); store the URL as given the first time. Refresh keeps `position`, `played` and `localFile` of existing episodes and only updates their metadata. Errors: on failure set `lastError` to the error's description and `errorSince` only if it was nil; on success clear both and set `lastUpdated`.

- [ ] **Step 1: Write the failing tests** (in-memory store, `StubFetcher` serving a feed string per URL)

```swift
func testFollowAddsShowWithEpisodesNewestFirst() async throws
    // follow → shows.count == 1, title "The Long Quiet", episodes(of:).map(\.title) == ["Ep. 112 — Rooms & Rooms", "Ep. 111 — …"]
func testFollowingTheSameFeedTwiceKeepsOneShow() async throws
    // follow "https://example.com/feed", then "http://example.com/feed/" → shows.count == 1
func testFollowingSomethingThatIsNotAFeedThrows() async
    // stub returns "<html>" → throws LibraryError.invalidFeed, shows.isEmpty
func testRefreshAddsNewEpisodesAndKeepsPlaces() async throws
    // follow; savePosition(600, of: first); stub now serves 3 items → episodes count 3, first.position == 600
func testFailedRefreshRecordsErrorOnceAndSuccessClearsIt() async throws
    // stub error twice → lastError != nil, errorSince unchanged by second failure; stub ok → lastError == nil, errorSince == nil
func testUpNextQueueOrder() async throws
    // enqueue a, b, a → upNext == [a, b]; remove(a) → [b]; popNext() == b; popNext() == nil
func testMarkPlayedResetsPosition() async throws
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/LibraryStoreTests` — Expected: build error.
- [ ] **Step 3: Implement** the four files (`ModelContainer(for: Show.self, Episode.self, UpNextEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly:))`; the app's on-disk store lives at `Application Support/Spindle/Library.store`).
- [ ] **Step 4: Run** — Expected: 7 pass.
- [ ] **Step 5: Commit** `"Library: follow shows, refresh, saved places, Up Next"`.

---

### Task 8: Podcast player

**Files:**
- Create: `Spindle/Playback/ResumePolicy.swift`, `Spindle/Playback/AudioEngine.swift`, `Spindle/Playback/AVPlayerEngine.swift`, `Spindle/Playback/PodcastPlayer.swift`
- Test: `SpindleTests/ResumePolicyTests.swift`, `SpindleTests/PodcastPlayerTests.swift`

**Interfaces:**
- Consumes: `Episode`, `LibraryStore` (Task 7).
- Produces:
  ```swift
  enum ResumePolicy {
      static let saveInterval: TimeInterval = 5; static let rewind: TimeInterval = 3; static let finishedWithin: TimeInterval = 30
      static let rates: [Float] = [1, 1.2, 1.5, 2]
      static func startPosition(saved: TimeInterval) -> TimeInterval          // max(0, saved − 3)
      static func isFinished(position: TimeInterval, duration: TimeInterval?) -> Bool  // duration known and duration − position ≤ 30
      static func nextRate(after rate: Float) -> Float                       // 1 → 1.2 → 1.5 → 2 → 1; unknown → 1
  }
  @MainActor protocol AudioEngine: AnyObject {
      func load(_ url: URL, at time: TimeInterval); func play(); func pause(); func seek(to time: TimeInterval)
      var rate: Float { get set }; var currentTime: TimeInterval { get }; var duration: TimeInterval? { get }
      var onTime: ((TimeInterval) -> Void)? { get set }      // ~every 0.5 s while playing
      var onEnd: (() -> Void)? { get set }
      var onFailure: ((Error) -> Void)? { get set } }
  final class AVPlayerEngine: AudioEngine   // AVPlayer; audioTimePitchAlgorithm = .timeDomain; periodic time observer 0.5 s
  @MainActor final class PodcastPlayer: ObservableObject {
      init(engine: AudioEngine, library: LibraryStore)
      @Published private(set) var episode: Episode?; @Published private(set) var isPlaying: Bool
      @Published private(set) var position: TimeInterval; @Published private(set) var rate: Float
      @Published private(set) var failure: String?       // "Offline" / "Unavailable"
      var duration: TimeInterval? { get }                 // engine's, else episode's
      func open(_ episode: Episode, autoplay: Bool)       // saves the old one first; loads at startPosition
      func play(); func pause(); func toggle()
      func seek(to time: TimeInterval); func skip(by seconds: TimeInterval); func cycleRate()
      func saveNow()                                      // also called on quit
  }
  ```

Behaviour: save on every `onTime` when ≥ 5 s since the last save, and immediately on pause, seek, open (for the old episode) and `saveNow`. On `onEnd`, or on `onTime` when `isFinished`, mark played and open `library.popNext()` with autoplay (nothing queued → stop, paused). `onFailure`: `URLError.notConnectedToInternet`/`.networkConnectionLost` → `failure = "Offline"`, place saved; the next `play()` reloads the URL at `startPosition(saved:)` and clears `failure`; anything else → `failure = "Unavailable"` and advance to the next Up Next item. Sets `library.lastEpisodeGUID` on open.

- [ ] **Step 1: Write the failing tests** (`FakeEngine` records calls and lets the test fire `onTime`/`onEnd`/`onFailure`)

```swift
func testResumePolicy() {
    XCTAssertEqual(ResumePolicy.startPosition(saved: 600), 597); XCTAssertEqual(ResumePolicy.startPosition(saved: 2), 0)
    XCTAssertTrue(ResumePolicy.isFinished(position: 3571, duration: 3600)); XCTAssertFalse(ResumePolicy.isFinished(position: 3569, duration: 3600))
    XCTAssertFalse(ResumePolicy.isFinished(position: 3599, duration: nil))
    XCTAssertEqual(ResumePolicy.nextRate(after: 2), 1); XCTAssertEqual(ResumePolicy.nextRate(after: 1.2), 1.5); XCTAssertEqual(ResumePolicy.nextRate(after: 1.7), 1)
}
func testOpenResumesThreeSecondsEarly()        // episode.position 600 → engine.load(at: 597)
func testSavesEveryFiveSecondsWhilePlaying()   // new episode (position 0): onTime 1, 3 → episode.position still 0; onTime 6 → 6
func testPauseSavesImmediately()               // onTime 602; pause() → episode.position == 602
func testSwitchingEpisodeSavesTheOldOne()      // A at 900 via onTime, open(B) → A.position == 900
func testFinishingMarksPlayedAndPlaysNext()    // queue B; onEnd → A.played, A.position == 0, player.episode == B, engine.play called
func testOfflineKeepsPlaceAndSaysSo()          // onFailure(URLError(.notConnectedToInternet)) → failure == "Offline", episode unchanged
func testDeadLinkSkipsToNext()                 // queue B; onFailure(URLError(.fileDoesNotExist)) → failure == "Unavailable", episode == B
func testPlayAfterOfflineReloadsAtTheSavedPlace() // at 700, onFailure(offline); play() → engine.load(at: 697) again, failure == nil
func testCycleRateSetsEngineRate()             // cycleRate x2 → engine.rate == 1.5
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/ResumePolicyTests -only-testing:SpindleTests/PodcastPlayerTests` — Expected: build error.
- [ ] **Step 3: Implement** the four files.
- [ ] **Step 4: Run** — Expected: 10 pass.
- [ ] **Step 5: Commit** `"Podcast player: resume, saving, speed, auto-advance, failures"`.

---

### Task 9: NowPlaying coordinator and the Mac's Now Playing

**Files:**
- Create: `Spindle/Playback/NowPlaying.swift`, `Spindle/Playback/MediaCenter.swift`
- Test: `SpindleTests/NowPlayingTests.swift`

**Interfaces:**
- Consumes: `PodcastPlayer` (Task 8); `DialEngine`, `DialStep` (Task 2); `HapticLimiter`, `HapticPerforming` (Task 3); `ChapterLoader`, `AudioFileChapters` (Task 5).
- Produces:
  ```swift
  struct NowPlayingInfo: Equatable { let title: String; let subtitle: String; let artworkURL: URL?; let duration: TimeInterval?
      let position: TimeInterval; let rate: Float; let isPlaying: Bool }
  @MainActor protocol MediaCenterPublishing: AnyObject { func publish(_ info: NowPlayingInfo?)
      var onCommand: ((MediaCommand) -> Void)? { get set } }
  enum MediaCommand: Equatable { case play, pause, toggle, skip(TimeInterval), seek(to: TimeInterval), rate(Float) }
  final class MediaCenter: MediaCenterPublishing   // MPNowPlayingInfoCenter + MPRemoteCommandCenter (skip intervals 15/30, rates from ResumePolicy)
  @MainActor final class NowPlaying: ObservableObject {
      init(player: PodcastPlayer, media: MediaCenterPublishing, haptics: HapticPerforming,
           schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void,   // tests run it by hand
           now: @escaping () -> TimeInterval, loadChapters: @escaping (Episode) async -> [Chapter])
      @Published private(set) var chapters: [Chapter]
      @Published private(set) var scrubPosition: TimeInterval?    // set while turning; views show it instead of position
      var displayPosition: TimeInterval { get }                    // scrubPosition ?? player.position
      var currentChapter: Chapter? { get }                         // last chapter with start ≤ displayPosition
      func turn(degrees: Double)       // DialEngine step from displayPosition; haptic via limiter; scrubPosition += seek; (re)schedule commit in 0.15 s
      func jump(to time: TimeInterval) // ring click: commit now
      func toggle(); func skip(by: TimeInterval); func cycleRate(); func play(_ episode: Episode)
  }
  ```

Stage 1 has podcasts only; `NowPlaying` is written so stage 3 can add a music source behind it without changing the views. Commit = `player.seek(to: scrubPosition)`, then `scrubPosition = nil`. Each new turn cancels the pending commit (use a generation counter: the scheduled closure commits only if its generation is still current). Chapters load when the episode changes, via `loadChapters` (`ChapterLoader.load` with `AudioFileChapters.read`). `publish` is called on episode, play state, rate and committed-seek changes; `nil` when nothing is open.

- [ ] **Step 1: Write the failing tests**

```swift
func testTurningPreviewsThenCommitsAfterQuiet()   // position 600; turn(30) → scrubPosition == 610, engine not seeked; run scheduled → engine.seek(610), scrubPosition nil
func testANewTurnPostponesTheCommit()             // turn, turn, run first scheduled closure → no seek; run second → one seek to the summed position
func testTicksAndChaptersReachTheHaptics()        // position 14, chapters [22]; now 0: turn(54) (14 → 41) → haptics.performed == [.chapter]; now 0.04: turn(15) (→ ~50.6, crosses 45 only) → [.chapter, .tick]
func testJumpCommitsImmediately()                 // jump(to: 1200) → engine.seek(1200), no schedule
func testCurrentChapter()                         // chapters [0 Intro, 750 Tapes], position 800 → "Tapes"
func testMediaCommandsDriveThePlayer()            // media.onCommand?(.skip(-15)) → engine.seek(585); (.toggle) → isPlaying flips
func testPublishesNowPlaying()                    // play(ep) → media.published.last??.title == "Ep. 112 — Rooms & Rooms", isPlaying true; toggle() → last??.isPlaying == false
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/NowPlayingTests` — Expected: build error.
- [ ] **Step 3: Implement** the two files.
- [ ] **Step 4: Run** — Expected: 7 pass.
- [ ] **Step 5: Commit** `"NowPlaying: dial scrubbing with haptics, chapters, media keys"`.

---

### Task 10: The disc, the dial panel and the menu bar strip

**Files:**
- Create: `Spindle/Dial/DialGeometry.swift`, `Spindle/UI/DiscView.swift`, `Spindle/UI/DialPanel.swift`, `Spindle/UI/StatusStrip.swift`, `Spindle/UI/ArtworkCache.swift`
- Test: `SpindleTests/DialGeometryTests.swift`

**Interfaces:**
- Consumes: `NowPlaying` (Task 9), `LibraryStore` (Task 7), `TimeFormat` (Task 1).
- Produces:
  ```swift
  enum DialGeometry {
      static func angle(of point: CGPoint, around center: CGPoint) -> Double          // degrees, 0 at top, clockwise, 0..<360 (y down)
      static func delta(from a: Double, to b: Double) -> Double                        // shortest signed turn, −180...180
      static func time(atRingPoint point: CGPoint, center: CGPoint, duration: TimeInterval) -> TimeInterval
      static let scrollDegreesPerPoint: Double = 1
  }
  struct DiscView: View            // 150 pt glass disc, progress ring, chapter dots, centre play/pause (drawn, no SF Symbols)
  final class DialPanelController  // NSPanel (borderless, nonactivating, transparent) hosting DialPanelView; show(below: NSStatusBarButton), closes on outside click
  final class StatusStripController // NSStatusItem with a hosted 13 pt artwork + 44 pt progress capsule; click toggles the panel; scrollWheel → nowPlaying.turn
  final class ArtworkCache          // URL → NSImage, in memory, async load
  ```

Panel content (spec §Dial panel, podcast variant): header (44 pt art, title, show); `DiscView`; elapsed / `TimeFormat.remaining`; pills `−15`, chapter (hidden without chapters; tap shows a menu of chapters → `jump(to:)`), rate label (`1×`, `1.2×`…; tap → `cycleRate`), `+30`; "UP NEXT" with up to three rows (tap → `play`); footer pill `Library` (Task 11 opens the window). `Pop out` is stage 3 and not shown. All glass via `.glassEffect(.regular, in: shape)`. The failure label ("Offline"/"Unavailable") replaces the times when set. Disc gestures: `RotateGesture` → `turn(degrees: Δ)`; scroll over the disc (local `NSEvent` monitor while the pointer is inside, `scrollingDeltaY × scrollDegreesPerPoint`, sign so that scrolling down turns clockwise); drag on the disc ring → `turn(DialGeometry.delta(prev, cur))`; tap centre → `toggle`; tap on the ring → `jump(to: DialGeometry.time(atRingPoint:…))`. Nothing open: disc shows an empty ring and "Find a show in Library".

- [ ] **Step 1: Write the failing tests**

```swift
func testAngleIsClockwiseFromTop() {
    let c = CGPoint(x: 75, y: 75)
    XCTAssertEqual(DialGeometry.angle(of: CGPoint(x: 75, y: 0), around: c), 0, accuracy: 0.001)
    XCTAssertEqual(DialGeometry.angle(of: CGPoint(x: 150, y: 75), around: c), 90, accuracy: 0.001)
    XCTAssertEqual(DialGeometry.angle(of: CGPoint(x: 0, y: 75), around: c), 270, accuracy: 0.001)
}
func testDeltaTakesTheShortWayRoundTheTop() {
    XCTAssertEqual(DialGeometry.delta(from: 350, to: 10), 20, accuracy: 0.001)
    XCTAssertEqual(DialGeometry.delta(from: 10, to: 350), -20, accuracy: 0.001)
}
func testRingPointToTime() {
    XCTAssertEqual(DialGeometry.time(atRingPoint: CGPoint(x: 75, y: 150), center: CGPoint(x: 75, y: 75), duration: 3600), 1800, accuracy: 0.001)
}
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/DialGeometryTests` — Expected: build error.
- [ ] **Step 3: Implement** `DialGeometry`, then the views and controllers.
- [ ] **Step 4: Run** the full suite `./scripts/test.sh` — Expected: all pass.
- [ ] **Step 5: Commit** `"Dial panel, disc and menu bar strip in Liquid Glass"`.

---

### Task 11: Minimal Library window, wiring and hand check

**Files:**
- Create: `Spindle/UI/LibraryWindow.swift`
- Modify: `Spindle/App/AppDelegate.swift`, `README.md`
- Test: `SpindleTests/LibraryViewModelTests.swift`

**Interfaces:**
- Consumes: `LibraryStore` (Task 7), `DirectorySearch` (Task 6), `NowPlaying` (Task 9), `DialPanelController`, `StatusStripController` (Task 10).
- Produces:
  ```swift
  @MainActor final class LibraryViewModel: ObservableObject {
      init(library: LibraryStore, fetcher: HTTPFetching, nowPlaying: NowPlaying)
      @Published var query: String; @Published private(set) var results: [DirectoryResult]; @Published private(set) var message: String?
      func search() async                 // DirectorySearch; errors → message "Search isn't available right now."
      func follow(_ result: DirectoryResult) async
      func addByLink(_ text: String) async // invalid URL or LibraryError.invalidFeed → message "That link isn't a podcast feed."
  }
  final class LibraryWindowController   // NSWindow 760×520, glass sidebar: Search, Add by link, followed shows, Refresh (→ refreshAll); detail: episodes (▶ play, + Up Next)
  ```

AppDelegate wiring: build `LibraryStore` on disk, `AVPlayerEngine`, `PodcastPlayer`, `MediaCenter`, `Haptics`, `NowPlaying` (schedule via `DispatchQueue.main.asyncAfter`, `now` via `ProcessInfo.processInfo.systemUptime`), `StatusStripController`, `DialPanelController`; restore `lastEpisodeGUID` paused; `refreshAll()` at launch; `applicationWillTerminate` → `player.saveNow()`. Opening the Library calls `NSApp.activate()`.

- [ ] **Step 1: Write the failing tests**

```swift
func testAddByLinkRejectsNonsense() async     // "not a url" → message == "That link isn't a podcast feed.", library.shows.isEmpty
func testAddByLinkFollows() async             // stub feed at https://example.com/feed → library.shows.count == 1, message == nil
func testSearchFailureShowsMessage() async    // stub throws → message == "Search isn't available right now.", results == []
func testFollowFromResults() async            // result with feedURL served by stub → shows.count == 1
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/LibraryViewModelTests` — Expected: build error.
- [ ] **Step 3: Implement** `LibraryViewModel`, `LibraryWindowController` and the AppDelegate wiring; add a README "Run it" section (`xcodegen generate`, open, Run; `./scripts/test.sh`).
- [ ] **Step 4: Run** `./scripts/test.sh` — Expected: `** TEST SUCCEEDED **`, every test passing.
- [ ] **Step 5: Hand check** (build and run the Debug app): follow a real show by search and by pasted link; play; turn with two fingers on the trackpad and feel ticks every 15 s and a firmer click at a chapter (pick a show that publishes chapters); speed pill cycles; pause, quit, relaunch → the episode is back, paused, 3 s before where it stopped; play/pause key and Control Center work; Wi-Fi off mid-stream → "Offline". Note results in the commit message.
- [ ] **Step 6: Commit** `"Library window, wiring, hand-checked stage 1"`.

---

## Stage 1 done when

All tests pass, the hand check passes, and the author has tried it and said it looks and feels right. Then merge to `main` (on request) and tag `v0.1.0`; push only when asked.
