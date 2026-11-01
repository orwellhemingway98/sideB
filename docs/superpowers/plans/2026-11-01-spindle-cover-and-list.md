# Spindle: Big Cover and the List Window — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A 240 pt cover on top of the dial panel. Clicking it drops a glass droplet that spreads into a window listing the show's episodes and chapters, or the Apple Music album or playlist. Clicking an item plays it in context.

**Architecture:**
- **Reading the album or playlist:** a new AppleScript reads the current Music album or playlist once, through `MusicRemote`, which caches the result by context.
- **The list model:** a pure `ListContent` mapping, driven by a small `@MainActor ListModel`, decides what the window shows.
- **The window:** a child `NSPanel` under the dial panel. It runs the drop-to-window morph inside its own `GlassEffectContainer`.

**Tech Stack:** Swift 5 mode, SwiftUI + AppKit, AppleScript, XCTest, XcodeGen. macOS 26+.

**Spec:** `docs/superpowers/specs/2026-11-01-spindle-cover-and-list-design.md`. To copy from: ClickWheel's `AppleMusicScripts.quoted(_:)` and its "ClickWheel" playlist refill (`../ipod_app/ClickWheel/Library/AppleMusicLibrary.swift`, `AppleMusicScripts.queue`).

## Global Constraints

- **Unchanged from v0.3.0:**
  - macOS 26 and Swift 5 mode.
  - No SF Symbols or Apple artwork in our own controls.
  - Tests run with `./scripts/test.sh`, building into `build.noindex/`.
  - Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  - Nothing is pushed unless the author asks.
- **Scripting:** never script an app that isn't running. Every value interpolated into AppleScript goes through `quoted(_:)`.
- **Cover (spec):**
  - 240 × 240 pt with 18 pt corners and a soft shadow. It replaces the 44 pt header art.
  - Hover scale 1.015; press scale 0.97.
  - A glass hint at the bottom-right reads "Episodes ⌄", "Album ⌄", "Playlist ⌄" or "Spotify ⌄".
  - With nothing playing there is no cover.
- **List window (spec):**
  - 12 pt below the panel, the panel's width (272 pt), up to 360 pt tall, then it scrolls.
  - The drop falls about 26 pt and spreads in about 0.6 s with a gentle spring. Closing reverses it.
  - It closes on:
    - a second click on the cover;
    - a click outside both windows;
    - Escape;
    - the panel closing;
    - the show, album or playlist changing. An episode or track changing within the same list does not close it.
- **Copy (spec):**
  - "Episodes | Chapters"
  - "No description."
  - "Nothing to list for this song."
  - "Couldn't read the album from Music."
  - "Sign in to Spotify to see the album and playlist."
- **Apple Music context (spec):**
  - Your own playlist (a user playlist with special kind none, other than "Spindle") is listed as a playlist.
  - Anything else is listed as the album: the same album and album artist from library playlist 1, ordered by disc then track number.
  - It's read once per context and cached. A stale result is dropped.
- **Plays in context (spec):**
  - A playlist row plays that track within the playlist.
  - An album row refills the "Spindle" playlist with the album from that track on, then plays it.

## Review Focus

1. **A small screen where a ~560 pt panel plus the list doesn't fit below.** The list goes to the left of the panel (or the right, if the left has no room) instead of off-screen. → Task 5 `testListMovesBesideThePanelWhenThereIsNoRoomBelow`.
2. **Clicking inside the list window.** It must not count as an outside click that closes the panel. → Task 5 `testClicksInTheListDoNotCloseThePanel`.
3. **The next track on the same album.** The window stays open and the highlight moves. A new album closes it. → Task 3 `testIdentityIsStableWithinOneAlbumAndChangesAcrossAlbums`.
4. **Music quits while the window is open.** The content becomes nothing and the window closes. → Task 3 `testMusicGoingAwayEmptiesTheList`.
5. **A 5,000-track playlist.** Reading is capped at 500 rows, listed as "and N more". → Task 1 `testLongContextsAreCappedAt500`.

---

## File Structure

```
Spindle/Music/MusicContext.swift            MusicContext, ContextTrack, MusicContextParser (Task 1)
Spindle/Music/AppleMusicSource.swift        + context() and play(trackID:in:) scripts (Task 1)
Spindle/Music/MusicTypes.swift              MusicSource gains context() / play(trackID:in:) with defaults (Task 1)
Spindle/Music/MusicRemote.swift             + context(for:), play(contextTrack:in:) (Task 2)
Spindle/UI/List/ListContent.swift           pure mapping, identity, hint, plain text (Task 3)
Spindle/UI/List/ListModel.swift             @MainActor model that loads and publishes ListContent (Task 3)
Spindle/UI/DialPanel.swift                  cover header (Task 4)
Spindle/UI/List/ListWindow.swift            controller, placement, droplet view, rows (Task 5)
Spindle/App/AppDelegate.swift               wiring (Task 6)
```

---

### Task 1: Reading the album or playlist from Music

**Files:**
- Create: `Spindle/Music/MusicContext.swift`
- Modify:
  - `Spindle/Music/MusicTypes.swift`
  - `Spindle/Music/AppleMusicSource.swift`
  - `SpindleTests/Support/FakeMusicSource.swift` (it gains `contextResult` and records `playedInContext`)
- Test: `SpindleTests/MusicContextTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct ContextTrack: Equatable, Identifiable { let id: String; let disc: Int; let number: Int; let title: String; let artist: String; let duration: Double }
  struct MusicContext: Equatable {
      enum Kind: Equatable { case album, playlist }
      let kind: Kind; let id: String; let title: String
      let tracks: [ContextTrack]      // at most 500
      let totalCount: Int             // before the cap
  }
  enum MusicContextParser {
      static let cap = 500
      /// Header record "kind␟id␟title␟totalCount", then one record per track "id␟disc␟number␟title␟artist␟duration",
      /// records separated by ASCII 30, fields by ASCII 31. "" → nil. Album tracks are sorted by disc, then number.
      static func parse(_ output: String) -> MusicContext?
  }
  extension MusicSource {   // defaults: Spotify (and fakes that don't override) have no context
      func context() throws -> MusicContext? { nil }
      func play(trackID: String, in context: MusicContext) throws {}
  }
  ```
  These are protocol requirements with default implementations.
- **Album context id:** `"album:" + album + "|" + albumArtist`. **Playlist context id:** `"playlist:" + persistentID`.
- **AppleScript, in `AppleMusicSource`:**
  - `context()`:
    - with a 10 s timeout, read `current track` and `current playlist`;
    - choose playlist vs album by the spec rule;
    - emit the header plus up to 500 tracks;
    - an error inside the script returns "".
  - `play(trackID:in:)`:
    - **playlist:** `play (first track of (first user playlist whose persistent ID is …) whose persistent ID is …)`;
    - **album:** refill the "Spindle" playlist with the album's tracks from that track on, then `play track 1` of it. Model it on ClickWheel's `AppleMusicScripts.queue`, and remember the playlist id under the UserDefaults key `spindlePlaylistID`.

- [ ] **Step 1: Write the failing tests**

```swift
func testParsesAnAlbumInDiscAndTrackOrder()     // tracks given as (2,1),(1,2),(1,1) → ids ordered (1,1),(1,2),(2,1); kind .album; title "Night Roads"
func testParsesAPlaylistInItsOwnOrder()          // kind .playlist keeps script order
func testEmptyOutputIsNil()                      // "" → nil; header only → context with 0 tracks
func testFieldsMayContainOddCharacters()         // title with quotes, commas, "é", "&" parse intact
func testLongContextsAreCappedAt500()            // header totalCount 5000, 500 records → tracks.count 500, totalCount 5000
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/MusicContextTests`. Expected: build error.
- [ ] **Step 3: Implement** the types, the parser, the protocol requirements and defaults, and the two Music scripts. The scripts aren't unit-tested, apart from going through `quoted(_:)`.
- [ ] **Step 4: Run** the full suite. Expected: all tests pass.
- [ ] **Step 5: Commit** `"Read the album or playlist a Music song is playing from"`.

---

### Task 2: MusicRemote reads and plays contexts

**Files:**
- Modify: `Spindle/Music/MusicRemote.swift`
- Test: `SpindleTests/MusicRemoteContextTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  ```swift
  extension MusicRemote {
      /// The context for `track`, read off the main actor from its source, cached by track id (and the context id it returns).
      /// Returns nil when the source has none or reading fails; `contextFailed` is true only for a read error.
      func context(for track: MusicTrack) async -> MusicContext?
      private(set) var contextFailed: Bool   // @Published
      func play(contextTrack: ContextTrack, in context: MusicContext)   // via lastCommand, then refresh
  }
  ```
- Errors from the read: `MusicSourceError` sets `contextFailed`, and `nil` without an error is "nothing to list". A second call for a track whose context is already cached doesn't script again.

- [ ] **Step 1: Write the failing tests**

```swift
func testContextIsReadOnceAndCached() async       // two calls for the same track → source context() called once
func testAnotherTrackOnTheSameAlbumReusesIt() async   // track t2 whose cached context contains t2 → no new read
func testReadFailureIsReported() async             // context() throws .scriptFailed → nil, contextFailed true
func testSpotifyHasNoContext() async               // a FakeMusicSource(.spotify) without contextResult → nil, contextFailed false
func testPlayingARowGoesToTheSource() async        // play(contextTrack:in:) → source recorded playedInContext (id, context.id)
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/MusicRemoteContextTests`. Expected: build error.
- [ ] **Step 3: Implement.** Keep the cache as `[contextID: MusicContext]` plus `[trackID: contextID]`, and clear both when the active source changes.
- [ ] **Step 4: Run** the full suite. Expected: pass.
- [ ] **Step 5: Commit** `"MusicRemote: read and play albums and playlists"`.

---

### Task 3: What the list shows

**Files:**
- Create: `Spindle/UI/List/ListContent.swift`, `Spindle/UI/List/ListModel.swift`
- Test: `SpindleTests/ListContentTests.swift`

**Interfaces:**
- Consumes:
  - `NowPlaying`: `mode`, `player.episode`, `chapters`, `currentChapter`, `music`.
  - `LibraryStore.episodes(of:)`.
  - `MusicRemote.context(for:)` and `contextFailed`.
- Produces:
  ```swift
  enum ListContent {
      case podcast(episodes: [Episode], current: Episode, chapters: [Chapter], currentChapter: Chapter?, description: String)
      case music(MusicContext, currentTrackID: String)
      case musicLoading
      case musicMessage(String)        // "Nothing to list for this song." / "Couldn't read the album from Music."
      case spotify(MusicTrack)
      case nothing
      /// What the list is about: the show's feed URL, the context id, "spotify:" + album, or nil for nothing.
      var identity: String? { get }
      static func hint(mode: PlaybackMode, source: MusicSourceID?, contextKind: MusicContext.Kind?) -> String
      static func plainText(fromHTML html: String?) -> String   // tags stripped, entities decoded, whitespace collapsed; "" → "No description."
  }
  @MainActor final class ListModel: ObservableObject {
      init(nowPlaying: NowPlaying, library: LibraryStore)
      @Published private(set) var content: ListContent
      @Published var tab: PodcastTab                  // enum PodcastTab { case episodes, chapters }, default .episodes
      func reload() async                             // rebuilds content; loads the music context when needed
  }
  ```
- **Identity:** a music identity comes from the loaded context's id. While it's loading, the identity is `"loading:" + trackID`; that loading identity doesn't count as a change for closing purposes. Task 5 compares only non-loading identities.
- **Hint:**
  - podcast → "Episodes ⌄";
  - Apple Music → "Playlist ⌄" for a playlist, otherwise "Album ⌄";
  - Spotify → "Spotify ⌄".

- [ ] **Step 1: Write the failing tests**

```swift
func testPodcastContentListsTheShowNewestFirst() async
func testIdentityIsStableWithinOneAlbumAndChangesAcrossAlbums() async
    // context album:A containing t1,t2: track t1 then t2 → same identity; t3 on album:B → different
func testMusicGoingAwayEmptiesTheList() async     // music track nil and no episode → .nothing, identity nil
func testSongsWithNoContextSayNothingToList() async
func testReadFailureSaysCouldNotRead() async
func testStaleContextIsDropped() async   // reload starts for t1 (album A); before it returns the track becomes t3 (album B) → content ends as B's context, never A's
func testSpotifyShowsDetails() async
func testHints()                                   // the four cases above
func testPlainTextFromHTML()                       // "<p>Hi &amp; <b>bye</b></p>\n\n" → "Hi & bye"; nil → "No description."
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/ListContentTests`. Expected: build error.
- [ ] **Step 3: Implement.** Use `NSAttributedString` HTML import for the entities, or a small regex plus a table of entities. The test fixes the output, so either works.
- [ ] **Step 4: Run.** Expected: pass.
- [ ] **Step 5: Commit** `"List content: episodes and chapters, album or playlist, Spotify details"`.

---

### Task 4: The cover header

**Files:**
- Modify: `Spindle/UI/DialPanel.swift` (it gains an `onCover: (() -> Void)?` parameter, defaulting to nil, and a `hint: String`)

**Interfaces:**
- Consumes:
  - `ListContent.hint(...)` (Task 3).
  - `ArtworkView(…, image:)`.
  - `NowPlaying.display` and `musicArtwork`.
- The `header(_:)` view becomes:
  - the 240 pt `ArtworkView` with 18 pt corners;
  - a shadow (radius 15, y 10, black 35%);
  - the glass hint capsule at the bottom-right, with 10 pt text;
  - hover and press scales of 1.015 and 0.97 with a 0.25 s spring;
  - a tap that calls `onCover`;
  - the title (14 pt semibold), then the subtitle below the cover.
- The disc, times, pills, Resume, Up Next and footer stay as they are.

- [ ] **Step 1:** There are no new unit tests; the hint text is tested in Task 3. Build the app. Expected: no warnings.
- [ ] **Step 2: Visual check.** Render `DialPanelView` with a podcast open into an offscreen `NSHostingView` window, as in stage 1 Task 10, and save it to the scratchpad. Look at it, then delete the throwaway test.
- [ ] **Step 3: Run** the full suite. Expected: pass.
- [ ] **Step 4: Commit** `"Big cover on top of the dial panel"`.

---

### Task 5: The droplet list window

**Files:**
- Create: `Spindle/UI/List/ListWindow.swift`
- Modify: `Spindle/UI/DialPanel.swift` (the panel's click monitor ignores its child windows; closing the panel closes the list)
- Test: `SpindleTests/ListWindowTests.swift`

**Interfaces:**
- Consumes: `ListModel` (Task 3), `NowPlaying`, `DialPanelController`.
- Produces:
  ```swift
  enum ListPlacement {
      static let gap: CGFloat = 12, width: CGFloat = 272, maxHeight: CGFloat = 360
      /// Below the panel when it fits in `visible`; else to its left; else to its right. Top-aligned beside it.
      static func frame(panel: NSRect, height: CGFloat, visible: NSRect) -> NSRect
  }
  enum PanelClickPolicy {
      /// The panel closes on a click in another Spindle window, except the status bar and the panel's own children.
      static func closesPanel(clickWindow: NSWindow?, panel: NSWindow, children: [NSWindow]) -> Bool
  }
  @MainActor final class ListWindowController {
      init(model: ListModel, nowPlaying: NowPlaying)
      var isShown: Bool { get }
      func toggle(below panel: NSWindow)
      func close(animated: Bool)        // reverse morph, then orderOut after 0.4 s
  }
  ```
- **The window:**
  - An `NSPanel` with `[.borderless, .nonactivatingPanel]`, clear, with no shadow (the glass draws its own).
  - It's added with `panel.addChildWindow(_:ordered: .above)`.
  - It's sized for the full list from the start; the content animates inside it.
- **Morph (spec motion):**
  - Inside one `GlassEffectContainer`, a 34 pt glass circle starts at the top centre, 26 pt above its final position.
  - With `.spring(response: 0.6, dampingFraction: 0.78)` it morphs into the full rounded rectangle (corner 26).
  - The two shapes share one `glassEffectID` in a namespace; the content fades in after 0.25 s.
  - Closing runs the reverse.
- **Closing:**
  - The list window's own click and Escape monitors, plus the panel's `didClose`.
  - A `ListModel` identity change, when both identities are non-nil and neither is a loading identity, closes it.
- **Rows:**
  - **Podcast:** the "Episodes | Chapters" segmented control bound to `tab`. Rows call `nowPlaying.play(episode)` and `nowPlaying.jump(to:)`. Without chapters, the description is shown.
  - **Music:** rows call `music.play(contextTrack:in:)`. Over the cap, a footer reads "and N more".
  - **Spotify:** a details block plus the sign-in line, as plain text.
  - The current item is highlighted with a 18% white fill.

- [ ] **Step 1: Write the failing tests**

```swift
func testListGoesBelowThePanel()        // panel (100,400,272,560) in visible (0,0,1440,1000), height 300 → (100, 400-12-300, 272, 300)
func testListMovesBesideThePanelWhenThereIsNoRoomBelow()
    // panel (500,50,272,560), visible (0,0,1440,900) → x 500-12-272 = 216, top-aligned: y = 50+560-300
func testListGoesRightWhenLeftHasNoRoom()   // panel at x 10 → x 10+272+12
func testHeightIsCappedAt360()
func testClicksInTheListDoNotCloseThePanel()  // closesPanel(clickWindow: list, panel: p, children: [list]) == false; other window → true; nil → false
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/ListWindowTests`. Expected: build error.
- [ ] **Step 3: Implement** the placement, the policy (used by the panel's existing local monitor), the controller, the droplet view and the rows.
- [ ] **Step 4: Run** the full suite and build the app. Expected: all tests pass and there are no warnings.
- [ ] **Step 5: Commit** `"The droplet list window: episodes and chapters, album or playlist"`.

---

### Task 6: Wiring and launch check

**Files:**
- Modify: `Spindle/App/AppDelegate.swift`, `README.md`

- **AppDelegate:**
  - Create `ListModel(nowPlaying:library:)` and `ListWindowController`.
  - Pass the panel `onCover: { list.toggle(below: panelWindow) }`, with `DialPanelController` exposing its window for this.
  - When the list opens, call `await model.reload()`. Also call it on every `nowPlaying.objectWillChange`, debounced by 0.3 s while the list is shown.
- **README:** a short "Big cover" paragraph.
- [ ] **Step 1: Run** the full suite. Expected: pass.
- [ ] **Step 2: Launch check.**
  1. Build and launch.
  2. Open the panel through System Events.
  3. Screenshot it. The cover appears when something is open; if nothing is playing, note that the cover is absent, as the spec says.
  4. Click the cover if present, and screenshot the list window.
  5. Quit cleanly, with no crash report.
  6. Don't play, follow or change anything.
- [ ] **Step 3: Commit** `"Wire the cover and list window into the app"`.

## Done when

All tests pass, the launch check passes, and the author has watched the droplet open over a podcast and an Apple Music album and said it looks right. Then merge on request and tag `v0.4.0`. Push only when asked.
