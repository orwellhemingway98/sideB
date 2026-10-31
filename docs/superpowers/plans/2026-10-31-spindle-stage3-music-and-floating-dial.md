# Spindle Stage 3: Music and the Floating Dial — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the dial a remote for whatever Apple Music or Spotify is playing, with "most recent wins" against podcasts, and let the disc pop out into a floating dial.

**Architecture:**
- **MusicRemote:** a new main-actor `MusicRemote` polls the music apps every second through sources copied from ClickWheel (AppleScript), renaming the types so they don't clash with Spindle's own.
- **NowPlaying:** gains a mode (podcast or music), the switching rules, and a single `display` description that every view reads. Views stop reaching into `PodcastPlayer` for what to show.
- **Floating dial:** a small borderless glass panel that hosts the same `DiscView`. Its position and whether it's out are remembered.

**Tech Stack:** Swift 5 mode, SwiftUI + AppKit, NSAppleScript / Apple Events, XCTest, XcodeGen. macOS 26+.

**Spec:** `docs/superpowers/specs/2026-10-31-spindle-design.md` (stage 3 of 3: "Floating dial", "NowPlaying coordinator", "MusicRemote", music panel layout). Source code to copy from: `../ipod_app/ClickWheel/Player/` (AppleScriptRunner, MusicSource, NowPlayingInfo, AppleMusicSource, SpotifySource, ScriptOutputParser) and `../ipod_app/ClickWheelTests/ScriptOutputParserTests.swift`.

## Global Constraints

- **Carried over from stages 1–2:**
  - macOS 26, Swift 5 mode, bundle id `com.mfelouro.Spindle`, ad-hoc signing.
  - No SF Symbols and no Apple artwork in our own controls.
  - Tests run with `./scripts/test.sh`; builds go in `build.noindex/`.
  - Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
  - Nothing is pushed unless the author asks.
- **Apple Events:**
  - Entitlement `com.apple.security.automation.apple-events: true`.
  - Info.plist `NSAppleEventsUsageDescription`: "Spindle controls Apple Music and Spotify so it can show what's playing and play, pause, skip or scrub it."
- **Never launch a music app.** Only script an app whose `isRunning()` is true, which is ClickWheel's rule.
- **Polling:** the music apps are polled every 1 s (spec).
- **Most recent wins (spec):**
  - Starting a podcast pauses music via the remote.
  - When music starts (seen by polling), the podcast pauses and keeps its place.
  - The dial then controls the music until a podcast is started again.
- **Media centre (spec):** Spindle publishes Now Playing only for podcasts. In music mode it publishes nil, so the music app's own Now Playing and media keys take over.
- **Music panel (spec):**
  - **Header:** the source after the artist ("· Spotify" / "· Apple Music").
  - **Pills:** ⏮ ⏭ only, drawn in code. There are no chapter, speed or ±15/30 pills, and no chapter clicks.
  - **Up Next:** still lists the podcast queue.
- **Failures (spec):** a music app that isn't running, or a declined permission, reports "nothing playing" and never affects podcasts.
- **Floating dial (spec):**
  - It is a borderless Liquid Glass disc with the panel disc's gestures, kept above other windows.
  - It can be dragged anywhere, and its position is remembered.
  - Its right-click menu has "Put Back", which returns it to the menu bar.
- **Version:** bumps to 0.3.0 at merge (as in stage 2).

## Review Focus

1. **The music app quits mid-song, or the track disappears.** Spindle falls back to the podcast (paused, place kept) instead of showing an empty music panel. → Task 3 `testMusicGoingAwayFallsBackToThePodcast`.
2. **Automation permission declined.** There's no repeated prompting and no crash. Spindle reports nothing playing and podcasts still work. → Task 2 `testPermissionDeniedReportsNothing`.
3. **Scrubbing a song, then a poll arrives before the app has moved.** The ring must not jump back. → Task 2 `testPollDoesNotUndoARecentSeek`.
4. **Spotify and Music both playing.** Keep following the one that was already active, with no flip-flopping each second. → Task 2 `testTwoPlayingAppsKeepTheActiveOne`.
5. **The song changes while a scrub is pending.** Drop the pending scrub so it isn't applied to the new song. → Task 3 `testNewSongDropsAPendingScrub`.

---

## File Structure

```
Spindle/Music/MusicTypes.swift          MusicSourceID, MusicPlayerState, MusicTrack, MusicSnapshot, ArtworkRef, MusicSourceError, MusicSource (Task 1)
Spindle/Music/AppleScriptRunner.swift   copied (Task 1)
Spindle/Music/ScriptOutputParser.swift  copied, types renamed (Task 1)
Spindle/Music/AppleMusicSource.swift, SpotifySource.swift   copied, + pause() (Task 1)
Spindle/Music/MusicRemote.swift         polling, active source, commands, artwork, pending seek (Task 2)
Spindle/Playback/NowPlaying.swift       mode, switching, music transport, display (Tasks 3, 4)
Spindle/Playback/NowPlayingDisplay.swift   the display description (Task 4)
Spindle/UI/DialPanel.swift, DiscView.swift, StatusStrip.swift, ArtworkCache.swift   read `display` (Task 4)
Spindle/UI/FloatingDial.swift           controller + view + placement store (Task 5)
Spindle/App/AppDelegate.swift, project.yml, README.md   (Tasks 1, 6)
```

---

### Task 1: Music sources copied from ClickWheel

**Files:**
- Create: the five `Spindle/Music/` files above (MusicTypes, AppleScriptRunner, ScriptOutputParser, AppleMusicSource, SpotifySource)
- Modify: `project.yml` (entitlements file `Spindle/App/Spindle.entitlements` with Apple Events, plus `NSAppleEventsUsageDescription`)
- Test: `SpindleTests/ScriptOutputParserTests.swift`, copied from ClickWheel with the types renamed

**Interfaces:**
- Produces:
  - **Copied as they are, renamed only:**
    - `SourceID` becomes `MusicSourceID`.
    - `PlayerState` becomes `MusicPlayerState`.
    - ClickWheel's `NowPlayingInfo` becomes `MusicTrack`. Spindle already has a `NowPlayingInfo`.
    - `PlayerSnapshot` becomes `MusicSnapshot`. Keep its `volume` field and `MusicTrack.index`/`count`, so the scripts and the parser stay verbatim.
    - `ArtworkRef`, `MusicSourceError` and `AppleScriptRunner` keep their names.
  - **`protocol MusicSource: AnyObject`:** `id: MusicSourceID`, `isRunning() -> Bool`, `snapshot() throws -> MusicSnapshot`, `artwork() throws -> ArtworkRef`, `playPause() throws`, `pause() throws`, `next() throws`, `previous() throws`, `setPosition(_ seconds: Double) throws`.
  - **Dropped:** `setVolume`, because Spindle leaves volume to the keyboard.
  - **New:** `pause()` is `tell("pause")` in both sources.

- [ ] **Step 1:** Copy `ScriptOutputParserTests.swift`, rename the types, and change `@testable import ClickWheel` to `Spindle`.
- [ ] **Step 2: Run** `-only-testing:SpindleTests/ScriptOutputParserTests`. Expected: build error, `ScriptOutputParser` not found.
- [ ] **Step 3:** Copy the five files, rename the types, add `pause()`, and drop volume control. Add the entitlement and the usage string.
- [ ] **Step 4: Run** the full suite. Expected: all pass, including the copied parser tests.
- [ ] **Step 5: Commit** `"Music sources from ClickWheel: Apple Music and Spotify over AppleScript"`.

---

### Task 2: MusicRemote

**Files:**
- Create: `Spindle/Music/MusicRemote.swift`
- Test: `SpindleTests/MusicRemoteTests.swift`, `SpindleTests/Support/FakeMusicSource.swift`

**Interfaces:**
- Consumes: Task 1 types. `RefreshScheduler.repeatingTimer` is the shape of the timer seam.
- Produces:
  ```swift
  @MainActor final class MusicRemote: ObservableObject {
      static let pollInterval: TimeInterval = 1
      init(sources: [MusicSource],
           every: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> AnyObject = RefreshScheduler.repeatingTimer)
      @Published private(set) var track: MusicTrack?
      @Published private(set) var isPlaying: Bool
      @Published private(set) var artwork: NSImage?        // for the current track, loaded once per trackID
      var source: MusicSourceID? { track?.source }
      func start()                    // refresh now, then every pollInterval
      func refresh() async            // one poll; scripts run off the main actor (Task.detached); never overlaps itself
      func playPause(); func pause(); func next(); func previous()
      func setPosition(_ seconds: Double)
  }
  ```
- **Choosing the active source:**
  1. Among running sources, prefer a playing one: the previously active source if it is playing, else the first that is playing.
  2. If none is playing, take the previously active source if it has a track.
  3. Otherwise, the first source with a track. With none at all, `track = nil` and `isPlaying = false`.
- **Errors:**
  - Any `MusicSourceError` from a source counts as "no snapshot" from that source.
  - `permissionDenied` also stops polling that source until relaunch, so macOS doesn't prompt over and over.
- **Pending seek:**
  - After `setPosition(s)`, `track.position` shows `s` at once.
  - The next two polls of the same `trackID` are ignored for position, unless they report within 1.5 s of `s`.
  - A different `trackID` clears the pending seek.
- **Commands:** they go to the active source off the main actor, followed by a `refresh()`.

- [ ] **Step 1: Write the failing tests.** `FakeMusicSource` has settable `running`, a `snapshot` result, an `artworkRef` and a `failure`, and records the commands it receives.

```swift
func testPicksThePlayingApp() async          // Music paused with a track, Spotify playing → track.source == .spotify, isPlaying
func testTwoPlayingAppsKeepTheActiveOne() async   // Music playing first; then Spotify also playing → stays .appleMusic over 3 polls
func testNotRunningAppsAreNeverScripted() async   // running = false → snapshot never called; track nil
func testPermissionDeniedReportsNothing() async   // throws .permissionDenied → track nil, isPlaying false; second poll doesn't call snapshot again
func testCommandsGoToTheActiveSource() async      // playPause/next/previous/pause/setPosition(42) recorded on Spotify only
func testPollDoesNotUndoARecentSeek() async       // position 10; setPosition(120) → track.position 120; poll reporting 10.5 → still 120; poll reporting 121 → 121
func testANewTrackClearsAPendingSeek() async
func testArtworkLoadsOncePerTrack() async         // .data(png) → artwork non-nil; second poll same trackID → artwork() called once
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/MusicRemoteTests`. Expected: build error.
- [ ] **Step 3: Implement.** Mirror ClickWheel's `PlayerHub.refresh` structure: guard against overlapping refreshes, never script a source that isn't running, and run scripts in `Task.detached`.
- [ ] **Step 4: Run.** Expected: 8 pass, and the full suite passes.
- [ ] **Step 5: Commit** `"MusicRemote: follow Apple Music or Spotify, poll every second"`.

---

### Task 3: Most recent wins

**Files:**
- Modify: `Spindle/Playback/NowPlaying.swift`
- Test: `SpindleTests/NowPlayingModeTests.swift`

**Interfaces:**
- Consumes: `MusicRemote` from Task 2. Tests drive it through `FakeMusicSource` plus `await remote.refresh()`.
- Produces:
  - `enum PlaybackMode: Equatable { case podcast, music }`.
  - In `NowPlaying`:
    - `@Published private(set) var mode: PlaybackMode = .podcast`.
    - `init(..., music: MusicRemote? = nil)`, so existing tests compile unchanged.
    - `func next()` and `func previous()`, which act in music mode only.
- **Switching:**
  - When `music.isPlaying` goes false to true:
    - if the podcast is playing, `player.pause()` (its place is saved);
    - set `mode = .music`;
    - flush nothing (drop any pending podcast scrub by bumping the generation);
    - call `media.publish(nil)`.
  - When `player.isPlaying` goes false to true:
    - if `music.isPlaying`, `music.pause()`;
    - set `mode = .podcast`;
    - republish the podcast.
  - At start, if music is playing and the podcast isn't, set `mode = .music`.
  - If in music mode the music `track` becomes nil, set `mode = .podcast` (Review Focus 1).
  - A new music `trackID` drops a pending scrub (generation bump plus `dial.reset()`).
- **In music mode:**
  - `displayPosition` = `scrubPosition ?? music.track?.position ?? 0`.
  - `turn(degrees:)` uses the music duration with no chapters, and its commit calls `music.setPosition`.
  - `jump(to:)` calls `music.setPosition`, clamped.
  - `toggle()` calls `music.playPause()`.
  - `skip(by:)` jumps.
  - Media commands are ignored, because Spindle has published nil.

- [ ] **Step 1: Write the failing tests**

```swift
func testMusicStartingPausesThePodcastAndKeepsItsPlace() async
    // podcast playing at 600 (fireTime(600)); music source starts playing; refresh → player.isPlaying false, episode.position 600, mode .music, media last published nil
func testStartingAPodcastPausesTheMusic() async
    // mode .music with music playing; nowPlaying.play(episode) → music source recorded .pause, mode .podcast
func testTheDialScrubsTheSongInMusicMode() async
    // music playing, duration 240, position 30; turn(30) → scrubPosition 40; run scheduled → source recorded setPosition(40)
func testToggleAndSkipControlTheMusic() async      // toggle → playPause; next() → next; previous() → previous
func testMusicGoingAwayFallsBackToThePodcast() async   // mode .music; source stops running; refresh → mode .podcast
func testNewSongDropsAPendingScrub() async         // turn(30); new trackID on refresh; run the scheduled commit → no setPosition recorded
func testNoMusicRemoteMeansPodcastOnly()           // init without music → mode .podcast, existing behaviour
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/NowPlayingModeTests`. Expected: build errors.
- [ ] **Step 3: Implement.** Use Combine sinks on `music.$isPlaying` and `music.$track` (with `removeDuplicates` on trackID), alongside the existing `player` sinks.
- [ ] **Step 4: Run** the full suite. Expected: all pass, including every existing NowPlaying test.
- [ ] **Step 5: Commit** `"Most recent wins: podcasts and music take turns on the dial"`.

---

### Task 4: One display for every view, and the music panel

**Files:**
- Create: `Spindle/Playback/NowPlayingDisplay.swift`
- Modify:
  - `Spindle/Playback/NowPlaying.swift`
  - `Spindle/UI/DialPanel.swift`, `DiscView.swift`, `StatusStrip.swift`
  - `Spindle/UI/ArtworkCache.swift` (`ArtworkView` gains `image: NSImage? = nil`, which takes precedence over `url`)
- Test: `SpindleTests/NowPlayingDisplayTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct NowPlayingDisplay: Equatable {
      enum Kind: Equatable { case podcast, music }
      let kind: Kind
      let title: String
      let subtitle: String          // show title, or artist
      let sourceLabel: String?      // nil for podcasts; "Apple Music" / "Spotify"
      let artworkURL: URL?          // podcasts
      let artworkSeed: String
      let duration: TimeInterval?
      let isPlaying: Bool
  }
  extension NowPlaying {
      var display: NowPlayingDisplay?        // nil when nothing is open in the current mode
      var musicArtwork: NSImage? { get }     // music.artwork in music mode, else nil
  }
  ```
- **Views:** every "what's playing" read goes through `display`, `displayPosition` and `musicArtwork`. That covers:
  - the header, times and failure text;
  - the strip's artwork and progress;
  - the disc's progress ring, chapter dots and play/pause glyph.
- **Music mode in the panel:**
  - **Header:** the title, then "Artist · Spotify".
  - **Pills:** ⏮ ⏭ only. Draw them as small Shapes, two triangles plus a bar. Not SF Symbols.
  - **Hidden:** the chapter pill and the rate pill, plus no chapter dots on the disc.
  - **Up Next:** still shown.
- **Podcast mode:** unchanged.

- [ ] **Step 1: Write the failing tests**

```swift
func testPodcastDisplay()          // open ep → kind .podcast, title ep title, subtitle "The Long Quiet", sourceLabel nil, isPlaying mirrors player
func testMusicDisplay() async      // music playing "Blue Hour Drive" by "Northern Static" on Spotify → kind .music, subtitle "Northern Static", sourceLabel "Spotify", duration 240
func testNothingOpenIsNil()
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/NowPlayingDisplayTests`. Expected: build error.
- [ ] **Step 3: Implement** `display`, then switch the three views over to it.
- [ ] **Step 4: Run** the full suite and build the app. Expected: all tests pass and there are no warnings.
- [ ] **Step 5: Commit** `"The dial shows and steers whatever is playing; music panel with previous/next"`.

---

### Task 5: The floating dial

**Files:**
- Create: `Spindle/UI/FloatingDial.swift`
- Modify: `Spindle/UI/DialPanel.swift` (footer pill "Pop out ↗" calls `onPopOut`)
- Test: `SpindleTests/FloatingDialTests.swift`

**Interfaces:**
- Consumes: `DiscView(nowPlaying:)`, `NowPlaying`.
- Produces:
  ```swift
  final class DialPlacement {                     // UserDefaults key "dialPoppedOut"
      init(defaults: UserDefaults = .standard)
      var isPoppedOut: Bool { get set }
  }
  @MainActor final class FloatingDialController {
      static let autosaveName = "SpindleFloatingDial"
      init(nowPlaying: NowPlaying, placement: DialPlacement, onPutBack: @escaping () -> Void, onLibrary: @escaping () -> Void)
      var isShown: Bool { get }
      func show()      // placement.isPoppedOut = true
      func putBack()   // hides; placement.isPoppedOut = false; calls onPutBack
  }
  ```
- **The window:**
  - An `NSPanel` with `[.borderless, .nonactivatingPanel]`, clear and shadowed.
  - Level `.floating`, collection behaviour `[.canJoinAllSpaces, .fullScreenAuxiliary]`, and `setFrameAutosaveName(autosaveName)`. If nothing has been saved yet, it is centred on the main screen's visible frame.
  - Content is 170×196: the 150 pt `DiscView` inside a glass circle, with a 36×6 glass grab bar 10 pt below it.
  - The grab bar is an `NSViewRepresentable` whose `mouseDown` calls `window.performDrag(with:)`. Turning still happens on the disc.
  - Right-click (`.contextMenu` on the whole content) offers "Put Back", "Open Library…" and "Quit Spindle".
- **The panel's footer:** gains "Pop out ↗", which closes the panel and shows the floating dial.

- [ ] **Step 1: Write the failing tests**

```swift
func testPlacementIsRemembered()                 // fresh suite: false; set true; new DialPlacement on same suite → true
func testShowAndPutBack()                        // show → isShown, placement.isPoppedOut; putBack → !isShown, !isPoppedOut, onPutBack called once
```

- [ ] **Step 2: Run** `-only-testing:SpindleTests/FloatingDialTests`. Expected: build error.
- [ ] **Step 3: Implement** the placement store, the controller, the view and the panel pill.
- [ ] **Step 4: Run** the full suite. Expected: all pass.
- [ ] **Step 5: Commit** `"Pop the dial out into a floating glass disc"`.

---

### Task 6: Wiring and launch check

**Files:**
- Modify: `Spindle/App/AppDelegate.swift`, `README.md`

**Wiring:**
- **At launch:**
  - Create `MusicRemote(sources: [AppleMusicSource(), SpotifySource()])` and pass it to `NowPlaying`, then call `music.start()`.
  - Create `DialPlacement` and `FloatingDialController`.
  - If `placement.isPoppedOut`, show the floating dial.
- **Callbacks:**
  - The panel's `onPopOut` closes the panel and shows the floating dial.
  - Its `onPutBack` does nothing more; the strip is always there.
- **Strip right-click menu:** add "Show Floating Dial" / "Put Dial Back" according to the dial's current state.
- **README:** a "Music" paragraph covering:
  - the remote and the permission prompt;
  - most recent wins;
  - and a "Floating dial" paragraph.

- [ ] **Step 1: Run** the full suite. Expected: all pass.
- [ ] **Step 2: Launch check.**
  1. Build the Debug app and launch it.
  2. Use System Events to confirm the strip exists, and that the floating dial window appears after "Show Floating Dial" from the strip's right-click menu.
  3. Quit cleanly, with no crash report.
  4. Don't start music or change the author's settings, beyond the floating-dial toggle you then put back.
  5. Expect the macOS Automation prompt at launch if Music or Spotify is running. Note that in the report, and don't click it.
- [ ] **Step 3: Commit** `"Wire the music remote and the floating dial into the app"`.

## Stage 3 done when

- All tests pass and the launch check passes.
- The author has played music and a podcast and felt them take turns on the dial, and has tried the floating dial.

Then merge to `main` on request, bump to 0.3.0 and tag `v0.3.0`. Push only when asked.
