# Spindle Stage 2: The Library — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the minimal Library into the full one: New Episodes, a Shows grid, Downloaded, Up Next you can reorder, downloads for offline listening that clean up after themselves, OPML import, hourly refresh and clear error states. Also close the two items parked at the end of stage 1.

**Architecture:** New pure or injectable units (`RefreshScheduler`, `DownloadManager` behind a `DownloadSession` protocol, `DownloadCleaner`, `OPMLImporter`) sit beside the existing `LibraryStore`, which gains queries and Up Next ordering. Feed parsing moves off the main actor first, because hourly refresh would otherwise hitch the UI. The Library window is rebuilt from small view files around an extended `LibraryViewModel`.

**Tech Stack:** Swift 5 mode, SwiftUI and AppKit, SwiftData, URLSession download tasks, XCTest, XcodeGen. macOS 26+.

**Spec:** `docs/superpowers/specs/2026-10-31-spindle-design.md` (stage 2 of 3). Stage 1's decisions and parked items are in `docs/superpowers/2026-10-31-stage1-review-notes.md`.

## Global Constraints

- Every constraint from stage 1 still holds:
  - macOS 26, Swift 5 mode, bundle id `com.mfelouro.Spindle`, ad-hoc signing.
  - No SF Symbols or Apple artwork; draw icons in code and use text buttons.
  - Run tests with `./scripts/test.sh`; build into `build.noindex/`.
  - Commit trailers read `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  - Nothing is pushed unless the author asks.
- Refresh (spec): every show is checked at launch and then every hour (3600 s), two feeds at a time. New episodes appear in New Episodes; nothing is added to Up Next automatically.
- Downloads (spec):
  - Use `URLSession` download tasks into `Application Support/Spindle/Episodes`.
  - The author starts every download by hand from an episode row.
  - A played episode's download is deleted 7 days after it was played.
- OPML (spec): read `outline` elements that have an `xmlUrl` and follow each, skipping shows already followed.
- Error copy (spec):
  - A show that fails to update shows "Couldn't update · last worked <date>".
  - A dead audio link shows "Unavailable" on its episode row.
  - Bad input shows a short message next to the field and adds nothing.
- Library window (spec):
  - The sidebar lists Up Next, New Episodes, Shows and Downloaded, with "Add by link" and "Import OPML…" at the bottom.
  - Episode rows show artwork, title, show, date, duration, how much is left (if started) or a downloaded mark, ▶ and "+ Up Next". The ▶ is drawn in code.
  - Shows is a grid of covers; clicking a cover shows that show's episodes, newest first.
- Existing APIs stay stable unless a task says otherwise: `LibraryStore` (follow, refreshAll, episodes(of:), upNext, enqueue, remove(fromUpNext:), popNext, markPlayed, markUnplayed, lastEpisode), `PodcastPlayer`, `NowPlaying`.

## Review Focus

1. **Deleting a download while that episode is playing:** playback must continue, and the clean-up must skip the current episode. → Task 5 `testCleanupSkipsTheEpisodePlayingNow`.
2. **The Refresh button pressed during the hourly refresh:** one refresh runs at a time, and the second request joins the first. → Task 2 `testOverlappingRefreshesRunOnce`.
3. **A download that fails (404, disk full, offline):** the episode stays playable by streaming, shows the failure, and can be retried. → Task 4 `testFailedDownloadCanBeRetried`.
4. **Quitting mid-download:** a partial file never becomes `localFile`, and after relaunch the episode reads "not downloaded". → Task 4 `testLocalFileIsSetOnlyWhenTheDownloadCompletes`.
5. **An OPML file with folders, duplicates, non-http links, or not OPML at all:** nested outlines are found, duplicates and invalid links are skipped, the counts are reported, and garbage gives a clear message. → Task 6 `testNestedDuplicateAndInvalidOutlines`, `testNotOPMLThrows`.

---

## File Structure

```
Spindle/Library/LibraryStore.swift      + newEpisodes, downloaded, moveUpNext, markPlayed playedAt, parse off main (Tasks 1, 3)
Spindle/Library/Episode.swift           + playedAt, unavailable (Tasks 3, 7)
Spindle/Library/RefreshScheduler.swift  hourly/at-launch refresh, coalescing (Task 2)
Spindle/Library/Downloads/DownloadManager.swift, DownloadSession.swift, EpisodeFiles.swift (Task 4)
Spindle/Library/Downloads/DownloadCleaner.swift (Task 5)
Spindle/Feeds/OPMLImporter.swift        (Task 6)
Spindle/Playback/PodcastPlayer.swift    unavailable mark, the two parked fixes (Tasks 7, 8)
Spindle/UI/Library/                      LibraryViewModel, LibraryWindow, Sidebar, EpisodeRow, ShowGrid, UpNextList (Task 9; replaces UI/LibraryWindow.swift)
Spindle/App/AppDelegate.swift           wiring (Task 10)
```

---

### Task 1: Feed parsing off the main actor

**Files:**
- Modify: `Spindle/Feeds/FeedModels.swift`, `Spindle/Library/LibraryStore.swift`
- Test: `SpindleTests/LibraryStoreTests.swift`

**Interfaces:**
- Produces: `ParsedFeed`, `ParsedEpisode` and `Chapter` become `Sendable`. `LibraryStore` parses inside the nonisolated fetch: `private nonisolated static func fetchAndParse(_ url: URL, with: HTTPFetching) async -> Result<ParsedFeed, Error>`. `finish(_:with: Result<ParsedFeed, Error>)` only applies the result on the main actor. `follow(feedURL:)` also parses off the main actor and keeps its errors (`invalidFeed` / `offline`).

- [ ] **Step 1: Write the failing test**

```swift
func testParsingHappensOffTheMainActor() async throws
    // FeedParser.parseObserver records Thread.isMainThread for every parse; refreshAll() and follow(feedURL:) → all recorded values false
```
To support it, add `static var parseObserver: ((Bool) -> Void)?` (internal, test-only) to `FeedParser`. It is called with `Thread.isMainThread` at the start of `parse`. The test sets it, calls `refreshAll()` and then `follow(feedURL:)`, and asserts that every recorded value is `false`. It resets the observer in `tearDown`.

- [ ] **Step 2: Run** `timeout 900 ./scripts/test.sh -only-testing:SpindleTests/LibraryStoreTests`. Expected: FAIL, because the parse happens on the main thread.
- [ ] **Step 3: Implement** the Sendable conformances and move parsing into the nonisolated static.
- [ ] **Step 4: Run** the full suite. Expected: all pass, including the existing refresh and follow tests.
- [ ] **Step 5: Commit** `"Library: parse feeds off the main actor"`.

---

### Task 2: Hourly refresh that never overlaps

**Files:**
- Create: `Spindle/Library/RefreshScheduler.swift`
- Test: `SpindleTests/RefreshSchedulerTests.swift`

**Interfaces:**
- Consumes: `LibraryStore.refreshAll() async`.
- Produces:
  ```swift
  @MainActor final class RefreshScheduler: ObservableObject {
      static let interval: TimeInterval = 3600
      init(refresh: @escaping @MainActor () async -> Void,
           every: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> AnyObject)  // returns a token; dropping it cancels
      @Published private(set) var isRefreshing: Bool
      func start()                    // refresh now, then every `interval`
      func refreshNow() async         // joins a refresh already running instead of starting another
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
func testStartRefreshesNowAndSchedulesHourly()
    // start() → refresh called once; captured interval == 3600; firing the captured tick → refresh called twice
func testOverlappingRefreshesRunOnce() async
    // refresh is a closure that suspends on a continuation; call refreshNow() twice concurrently → refresh body entered once;
    // resume → both calls return; isRefreshing false afterwards
func testRefreshAfterOneFinishesRunsAgain() async
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/RefreshSchedulerTests`. Expected: build error.
- [ ] **Step 3: Implement.** Keep the in-flight `Task<Void, Never>?`; a second `refreshNow()` awaits the same task. The real `every` uses a `Timer` scheduled on the main run loop with `tolerance` of 60 s, wrapped in a token object that invalidates on deinit.
- [ ] **Step 4: Run.** Expected: 3 pass, full suite passes.
- [ ] **Step 5: Commit** `"Refresh every hour, one at a time"`.

---

### Task 3: Library queries, played date and Up Next order

**Files:**
- Modify: `Spindle/Library/Episode.swift`, `Spindle/Library/LibraryStore.swift`
- Test: `SpindleTests/LibraryStoreTests.swift`

**Interfaces:**
- Produces:
  - `Episode.playedAt: Date?`. `markPlayed` sets it to `now()` and `markUnplayed` clears it.
  - `LibraryStore.newEpisodes(limit: Int = 100) -> [Episode]`: unplayed episodes across all shows, newest first, using the same ordering rule as `episodes(of:)`.
  - `LibraryStore.downloaded -> [Episode]`: episodes whose `localFile` exists on disk, newest first.
  - `LibraryStore.moveUpNext(from: IndexSet, to: Int)`: List `.onMove` semantics. Renumber `order` 1…n and save once.

- [ ] **Step 1: Write the failing tests**

```swift
func testNewEpisodesAreUnplayedAcrossShowsNewestFirst()
    // follow longQuietThreeItems + withPSC; markPlayed(lq-113) → newEpisodes() first is lq-112's title, and no played episode appears
func testNewEpisodesRespectsTheLimit()
func testMarkPlayedRecordsWhenAndUnplayedClearsIt()
    // injected now = d → markPlayed → playedAt == d; markUnplayed → nil
func testDownloadedListsOnlyEpisodesWhoseFileExists()
    // set localFile to a temp file that exists for one episode and a missing path for another → downloaded == [first]
func testMoveUpNextReorders()
    // enqueue a, b, c; moveUpNext(from: [2], to: 0) → upNext == [c, a, b]; a fresh read of the store agrees
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/LibraryStoreTests`. Expected: build errors.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: all pass.
- [ ] **Step 5: Commit** `"Library: new episodes, downloaded, played date, reorder Up Next"`.

---

### Task 4: Downloads

**Files:**
- Create: `Spindle/Library/Downloads/DownloadSession.swift`, `DownloadManager.swift`, `EpisodeFiles.swift`
- Test: `SpindleTests/DownloadManagerTests.swift` and `SpindleTests/Support/FakeDownloadSession.swift`

**Interfaces:**
- Consumes: `Episode`, `LibraryStore` (Task 3).
- Produces:
  ```swift
  protocol DownloadSession: AnyObject {
      /// Starts downloading; progress 0…1; completion gives a temporary file URL or an error. Returns a cancel handle.
      func download(_ url: URL, progress: @escaping @MainActor (Double) -> Void,
                    completion: @escaping @MainActor (Result<URL, Error>) -> Void) -> DownloadHandle
  }
  protocol DownloadHandle: AnyObject { func cancel() }
  final class URLSessionDownloads: DownloadSession   // URLSession download task with a delegate; User-Agent Spindle/0.1
  enum EpisodeFiles {
      static func directory(root: URL) -> URL                       // root/Episodes
      static func destination(for episode: Episode, root: URL) -> URL
          // Episodes/<sha256(feedURL) first 16 hex>/<sha256(guid) first 16 hex>.<ext from enclosure, else "mp3">
  }
  enum DownloadState: Equatable { case none, downloading(Double), downloaded, failed(String) }
  @MainActor final class DownloadManager: ObservableObject {
      init(library: LibraryStore, session: DownloadSession, root: URL)   // root = Application Support/Spindle in the app
      func state(of episode: Episode) -> DownloadState
      func download(_ episode: Episode)     // no-op if downloading or downloaded
      func cancel(_ episode: Episode)
      func removeDownload(_ episode: Episode)   // deletes the file, clears localFile
  }
  ```
- Rules:
  - On completion, move the temporary file to its destination, replacing any existing file, then set `episode.localFile` and save through a new `LibraryStore.setLocalFile(_:for:)`.
  - On failure, the state is `.failed(message)`, where the message is "Download failed. Try again." or, offline, "You're offline."; `localFile` is untouched.
  - `download` after `.failed` starts again.
  - States are keyed by `persistentModelID`.

- [ ] **Step 1: Write the failing tests.** The FakeDownloadSession records requests and lets the test call `progress` and `completion`.

```swift
func testDownloadMovesTheFileAndMarksTheEpisode()
    // download(a); fake progress 0.5 → state .downloading(0.5); complete with a temp file → file exists at destination, a.localFile == destination, state .downloaded
func testLocalFileIsSetOnlyWhenTheDownloadCompletes()
    // download(a); progress 0.9; then a new DownloadManager over the same library (relaunch) → a.localFile == nil, state .none
func testFailedDownloadCanBeRetried()
    // complete with URLError(.badServerResponse) → .failed("Download failed. Try again."), localFile nil; download(a) again → second request recorded
func testOfflineFailureSaysOffline()
func testCancelStopsAndResets()
func testRemoveDownloadDeletesTheFile()
func testDestinationIsStablePerFeedAndGuid()
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/DownloadManagerTests`. Expected: build error.
- [ ] **Step 3: Implement.** `URLSessionDownloads` is a thin, untested adapter. The temporary file must be moved inside the delegate's `didFinishDownloadingTo` callback before it returns; the URL handed to `completion` points to that moved copy.
- [ ] **Step 4: Run.** Expected: 7 pass, full suite passes.
- [ ] **Step 5: Commit** `"Downloads for offline listening"`.

---

### Task 5: Download clean-up

**Files:**
- Create: `Spindle/Library/Downloads/DownloadCleaner.swift`
- Test: `SpindleTests/DownloadCleanerTests.swift`

**Interfaces:**
- Consumes: `DownloadManager.removeDownload` (Task 4); `Episode.playedAt` (Task 3).
- Produces: `enum DownloadCleaner { static let keepAfterPlayed: TimeInterval = 7 * 24 * 3600; @MainActor static func purge(_ episodes: [Episode], now: Date, excluding current: Episode?, remove: (Episode) -> Void) }`. It removes downloads of episodes that are `played`, have `playedAt <= now − 7 days`, have a `localFile`, and are not `current`.

- [ ] **Step 1: Write the failing tests**

```swift
func testRemovesDownloadsPlayedMoreThanSevenDaysAgo()     // played 8 days ago → removed; 6 days ago → kept; unplayed → kept
func testCleanupSkipsTheEpisodePlayingNow()
func testExactlySevenDaysIsRemoved()
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/DownloadCleanerTests`. Expected: build error.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: 3 pass.
- [ ] **Step 5: Commit** `"Clean up downloads a week after they're played"`.

---

### Task 6: OPML import

**Files:**
- Create: `Spindle/Feeds/OPMLImporter.swift`
- Modify: `Spindle/Library/LibraryStore.swift`
- Test: `SpindleTests/OPMLImporterTests.swift`

**Interfaces:**
- Consumes: `LibraryStore.follow(feedURL:)`.
- Produces:
  ```swift
  enum OPMLError: Error, Equatable { case notOPML }
  enum OPMLImporter { static func feedURLs(from data: Data) throws -> [URL] }   // every outline@xmlUrl at any depth, http(s) only, de-duplicated in order
  struct ImportSummary: Equatable { var followed = 0; var alreadyFollowed = 0; var failed = 0 }
  extension LibraryStore { func importFeeds(_ urls: [URL]) async -> ImportSummary }   // two at a time; existing shows count as alreadyFollowed
  ```
- Root must be `<opml>`, otherwise throw `.notOPML`. Attribute lookup is case-insensitive (`xmlUrl` / `xmlURL` / `xmlurl`).

- [ ] **Step 1: Write the failing tests**

```swift
func testNestedDuplicateAndInvalidOutlines()
    // body > outline(folder) > outline xmlUrl a; outline xmlUrl a (dup); outline xmlUrl "ftp://x"; outline xmlURL b → [a, b]
func testNotOPMLThrows()                      // "<rss/>" and "garbage" → .notOPML
func testImportCountsFollowedExistingAndFailed() async
    // already follow a; stub serves b as a feed and c as "<html>" → ImportSummary(followed: 1, alreadyFollowed: 1, failed: 1)
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/OPMLImporterTests`. Expected: build error.
- [ ] **Step 3: Implement.** Use `XMLParser`, as `FeedParser` does, including the leading whitespace/BOM tolerance (reuse its helper if you can make it internal).
- [ ] **Step 4: Run.** Expected: 3 pass.
- [ ] **Step 5: Commit** `"Import shows from an OPML file"`.

---

### Task 7: "Unavailable" on dead episodes

**Files:**
- Modify: `Spindle/Library/Episode.swift`, `Spindle/Library/LibraryStore.swift`, `Spindle/Playback/PodcastPlayer.swift`
- Test: `SpindleTests/PodcastPlayerTests.swift`

**Interfaces:**
- Produces: `Episode.unavailable: Bool = false` and `LibraryStore.setUnavailable(_ value: Bool, for: Episode)`. `PodcastPlayer` marks it `true` when it handles an "Unavailable" failure, and `false` on the first real tick of that episode.

- [ ] **Step 1: Write the failing tests**

```swift
func testDeadLinkMarksTheEpisodeUnavailable()   // queue b; fireFailure(.fileDoesNotExist) on a → a.unavailable == true
func testPlayingItLaterClearsTheMark()           // a.unavailable = true; open(a); fireTime(1) → false
func testOfflineDoesNotMarkUnavailable()
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/PodcastPlayerTests`. Expected: build errors.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: all pass.
- [ ] **Step 5: Commit** `"Mark episodes with dead audio links unavailable"`.

---

### Task 8: The two parked stage 1 fixes

**Files:**
- Modify: `Spindle/Playback/PodcastPlayer.swift`
- Test: `SpindleTests/PodcastPlayerTests.swift`

**Interfaces:**
- Produces:
  - A private `load(_ episode: Episode, at start: TimeInterval)` variant.
  - **Reload inside the last 30 s:** an offline reload or retry while `inPlayedWindow` reloads at the live `position`, not at the saved 0.
  - **Seeking back after a real end:** with nothing queued, seeking back after `onEnd` to more than 30 s before the end un-marks the episode as played (`markUnplayed`) and resumes normal saving.

- [ ] **Step 1: Write the failing tests**

```swift
func testOfflineReloadInsideTheLastThirtySecondsResumesThere()
    // duration 3600; fireTime(3580); fireFailure(offline); play() → last engine load at 3580 (not 0)
func testSeekingBackAfterTheEndUnmarksPlayed()
    // nothing queued; fireTime(3580); fireEnd(); seek(to: 100) → played == false; pause() → position 100 saved
```

- [ ] **Step 2: Run.** Expected: both fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full suite. Expected: all pass, including the existing end-of-episode tests.
- [ ] **Step 5: Commit** `"Player: reload near the end where you were; seeking back after the end un-marks played"`.

---

### Task 9: The full Library window

**Files:**
- Create: `Spindle/UI/Library/LibraryViewModel.swift`, `LibraryWindow.swift`, `LibrarySidebar.swift`, `EpisodeRow.swift`, `ShowGrid.swift`, `UpNextList.swift`
- Delete: `Spindle/UI/LibraryWindow.swift` (its contents move and grow here)
- Test: `SpindleTests/LibraryViewModelTests.swift`

**Interfaces:**
- Consumes: Tasks 2–7 (`RefreshScheduler`, `newEpisodes`, `downloaded`, `moveUpNext`, `DownloadManager`, `OPMLImporter` / `importFeeds`, `unavailable`). Also `ArtworkCache` and `NowPlaying.play` / `player.enqueue`, all from stage 1.
- Produces:
  ```swift
  enum LibrarySection: Hashable { case upNext, newEpisodes, shows, downloaded, show(PersistentIdentifier) }
  extension LibraryViewModel {
      @Published var section: LibrarySection            // default .newEpisodes
      @Published private(set) var importMessage: String?
      func importOPML(_ data: Data) async             // message: "Followed 3 shows · 1 already followed · 1 couldn't be added", parts with 0 left out;
                                                       // OPMLError → "That file isn't an OPML list of podcasts."
      static func importSummaryText(_ s: ImportSummary) -> String
  }
  ```
- The view model keeps its stage 1 API (search, follow, addByLink, messages), and following a show selects `.show(id)`.
- **Layout (spec):**
  - **Sidebar:** the search field and its message at the top, with results showing 28 pt artwork, title, author and Follow (spec). Below it, the sections Up Next, New Episodes, Shows and Downloaded, then the followed shows listed by title (each with the "Couldn't update · last worked <date>" note when broken). At the bottom: the "Add by link" field and message, "Import OPML…" (an `NSOpenPanel` for `.opml` and `.xml` files, then `importOPML`) with its message, and Refresh (disabled while `isRefreshing`, label "Refreshing…").
  - **Detail by section:**
    - Up Next: `UpNextList`, with drag to reorder via `moveUpNext` and a "Remove" text button per row.
    - New Episodes: `EpisodeRow`s.
    - Shows: `ShowGrid`, a `LazyVGrid` of 120 pt covers with 10 pt corners and the title below; a click selects `.show(id)`.
    - Downloaded: `EpisodeRow`s.
    - `.show(id)`: that show's episodes as `EpisodeRow`s, under the show title.
- **`EpisodeRow` (spec):**
  - 40 pt artwork (from `ArtworkCache`, falling back to a gradient tile), the title, then "show · date · duration · N left", with "Downloaded" or "Unavailable" when they apply.
  - Buttons:
    - a drawn ▶ that calls `nowPlaying.play`;
    - "+ Up Next";
    - a download control: "Download", "Downloading 42%" (which cancels on click), "Downloaded" (with a context menu "Remove Download"), or "Retry download" after a failure, with the failure as a tooltip.
  - Context menu: "Mark as Played" / "Mark as Unplayed", and "Remove Download" when downloaded.
- No SF Symbols. Use the standard window and sidebar, which macOS draws in Liquid Glass.

- [ ] **Step 1: Write the failing tests**

```swift
func testImportSummaryText()
    // (3,1,1) → "Followed 3 shows · 1 already followed · 1 couldn't be added"; (1,0,0) → "Followed 1 show"; (0,2,0) → "2 already followed"
func testImportingNotOPMLSaysSo() async          // importMessage == "That file isn't an OPML list of podcasts."
func testImportingFollowsShows() async           // OPML with two stubbed feeds → library.shows.count == 2, message "Followed 2 shows"
func testFollowingSelectsTheShowSection() async  // after addByLink success → section == .show(id of that show)
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/LibraryViewModelTests`. Expected: build errors.
- [ ] **Step 3: Implement** the view model, then the views. Each view file stays under about 200 lines.
- [ ] **Step 4: Run** the full suite. Expected: all pass. Also build the app with no warnings.
- [ ] **Step 5: Commit** `"The full Library: Up Next, New Episodes, Shows grid, Downloaded, OPML"`.

---

### Task 10: Wiring and launch check

**Files:**
- Modify: `Spindle/App/AppDelegate.swift`, `README.md`

**Interfaces:**
- Consumes: everything above.
- At launch:
  - Create one `DownloadManager(library:session: URLSessionDownloads(), root: <Application Support/Spindle>)` and one `RefreshScheduler(refresh: { await library.refreshAll() }, every: <Timer token>)`. Pass both to the Library view model.
  - Replace stage 1's bare `Task { await library.refreshAll() }` with `scheduler.start()`.
  - Run `DownloadCleaner.purge(library.downloaded, now: .now, excluding: player.episode, remove: downloads.removeDownload)` at launch and after each refresh. Hook it into the scheduler's refresh closure.
- README: a short "What's in stage 2" paragraph, and how to import an OPML file.

- [ ] **Step 1: Run** the full suite. Expected: all pass.
- [ ] **Step 2: Build** the Debug app and launch it. Check through System Events that the strip exists. Open the Library through the strip's right-click "Open Library…" and screenshot the window: Up Next, New Episodes, Shows and Downloaded show in the sidebar. Quit cleanly and check that no crash report appeared. Don't follow real shows or start downloads.
- [ ] **Step 3: Commit** `"Wire downloads, hourly refresh and clean-up into the app"`.

## Stage 2 done when

All tests pass, the launch check passes, and the author has tried the Library and said it looks and works right. Then merge to `main` on request and tag `v0.2.0`. Push only when asked.
