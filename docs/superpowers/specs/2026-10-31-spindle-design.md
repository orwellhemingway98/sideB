# Spindle — design

A contemporary listening companion for the Mac. It sits in the menu bar as a
Liquid Glass dial you feel through the trackpad, plays podcasts itself with
chapters, speed, Up Next and saved places, and acts as a remote for Spotify
and Apple Music.

Spindle is separate from ClickWheel (the life-size iPod app) and shares no
code with it at runtime. It copies ClickWheel's few files for controlling
Spotify and Apple Music.

## Intent

- **Who it's for:** the author, who listens mostly to podcasts and music on
  a MacBook while working.
- **What it must get right:**
  1. A dial that feels physical: turning it scrubs, with a tick you feel
     every 15 seconds and a firmer click at each chapter.
  2. Podcasts done properly: chapters, speed, Up Next, resume and offline
     listening.
- **What it is not:** a feed, a recommendation engine, or a music library
  browser. There are no notifications beyond what macOS shows for Now
  Playing.

## Platform and constraints

- macOS 26 or later, for the system Liquid Glass material. Native Swift and
  SwiftUI, AppKit where needed. Built with XcodeGen, like ClickWheel.
- Bundle identifier `com.mfelouro.Spindle`. Signed ad-hoc with the hardened
  runtime, and the Apple Events entitlement for the music remote.
- **Artwork:** all original or system-provided. Liquid Glass is a system
  material and may be used. No Apple logos, product artwork or icons.
- **Haptics:** need a Force Touch trackpad. Everything else works without
  one.
- **Repo:** private, `orwellhemingway98/spindle`. Nothing is pushed or
  published without the author asking.

## What you see and touch

### Menu bar strip

- An `NSStatusItem` showing a 13 pt artwork thumbnail and a 44 pt progress
  hairline, in a small glass capsule.
- With nothing playing, it shows a small empty glass disc.
- **Click:** opens the dial panel.
- **Scroll over the strip:** scrubs the current item without opening
  anything, with the same ticks as the dial.

### Dial panel

A 272 pt wide Liquid Glass panel that drops from the strip and closes when
you click elsewhere. Top to bottom:

1. **Header:** artwork (44 pt), episode or song title, and the show or
   artist. For music, the source is shown too ("· Spotify").
2. **The disc:** a clear glass disc (150 pt).
   - A thin white progress ring runs round it.
   - Small dots on the ring mark chapter starts.
   - The centre button shows play/pause.
3. **Times:** elapsed on the left, remaining on the right.
4. **Pills.**
   - Podcasts: `−15` · chapter (tap for the chapter list; hidden when there
     are no chapters) · speed (tap to cycle 1× → 1.2× → 1.5× → 2× → 1×) ·
     `+30`.
   - Music: ⏮ · ⏭.
5. **Up Next** (podcasts): the next three items. Click to play now. Drag
   reordering arrives in stage 2.
6. **Footer pills:** `Library` opens the Library window. `Pop out ↗`
   (stage 3) turns the disc into a floating dial.

**Disc gestures**

- **Turn:** scrubs. Turning works three ways:
  - two fingers turning on the trackpad (rotate gesture);
  - scrolling over the disc;
  - dragging round the disc with the pointer.
- **Press the centre:** play/pause.
- **Press the progress ring:** jumps to that point.

### Library window (full version in stage 2)

- A standard window with a Liquid Glass sidebar.
- **Sidebar:** Up Next, New Episodes, Shows, Downloaded. At the bottom:
  "Add by link" and "Import OPML…".
- **Search field:** searches Apple's public podcast directory
  (`https://itunes.apple.com/search?media=podcast&term=…`). Results show
  artwork, title and author, with a Follow button.
- **Episode rows:** artwork, title, show, date, duration, and how much is
  left if started or a downloaded mark. Buttons: ▶ and "+ Up Next".
- **Shows:** a grid of covers. Clicking one shows its episodes, newest
  first.
- **Stage 1 version:** a minimal window with search, Add by link, the shows
  you follow and their episodes.

### Floating dial (stage 3)

- A borderless Liquid Glass disc with the same gestures as the panel's
  disc. It stays above other windows.
- It can be dragged anywhere, and its position is remembered.
- "Put back" in its right-click menu returns it to the menu bar.

## The dial behaviour

`DialEngine` is pure logic. It has no UI and no audio.

- **Input:** `turn(degrees:at:)`, where degrees are clockwise-positive and
  the time is in seconds. All three gestures convert to degrees: a
  scroll's vertical delta at 1 pt = 1°, and dragging uses the change in
  angle around the disc's centre.
- **Speed:**
  - At normal pace, a full turn (360°) is 120 seconds of audio.
  - Faster turning accelerates. Above 360°/s, the seconds per degree rise
    linearly up to 4× at 1,440°/s, measured over the last 100 ms.
- **Output:** `DialStep { seek: TimeInterval, detents: [Detent] }`.
  - `seek` is the change to apply to the playhead, clamped to
    `0…duration`.
  - `detents` lists, in order, every boundary crossed:
    - `.tick` for every multiple of 15 s of the playhead's position;
    - `.chapter` for every chapter start. A chapter wins over a tick at
      the same moment.
- **Feel:** `Haptics` plays `.tick` as `NSHapticFeedbackManager`'s
  `.generic` pattern and `.chapter` as `.levelChange`, both
  `performanceTime: .now`.
  - At most one haptic per 35 ms. During fast turns the extra ticks are
    dropped, but a chapter is never dropped in favour of a tick.
- **While scrubbing:** the playhead follows live. The audio seeks when the
  turning stops for 150 ms, or immediately for a centre press or a jump
  on the ring.

## Playback

### NowPlaying coordinator

- Owns the single "what's playing" that every view and the dial use.
- **State:** current item (title, subtitle, artwork, duration, position,
  chapters, rate, isPlaying, source), plus `upNext`.
- **Commands:** play, pause, toggle, seek(to:), skip(by:), setRate,
  next, previous, playEpisode(_:), and `dial(_: DialStep)`.
- **Who's in control: the most recent wins.**
  - Starting a podcast pauses music via the remote.
  - When music starts (detected by polling every second), the podcast
    pauses and keeps its place.
  - The dial then controls the music until a podcast is started again.
- **Mac media integration:** publishes podcast playback to
  `MPNowPlayingInfoCenter` and handles `MPRemoteCommandCenter`. That
  covers play/pause/toggle, skip ±, change playback position and change
  rate, so media keys, AirPods and Control Center work.
  - Music apps publish their own, so Spindle doesn't publish for music.

### PodcastPlayer

- Built on `AVPlayer`. It plays a local file when the episode is
  downloaded, otherwise it streams the enclosure URL.
- **Rate:** 1, 1.2, 1.5 or 2, with pitch kept (`audioTimePitchAlgorithm`
  `.timeDomain`).
- **Saving your place:**
  - It saves every 5 s while playing, and on pause, seek end, switching
    episode and quit.
  - It resumes from the saved place minus 3 s.
  - Within the last 30 s, an episode counts as played: its place resets
    and Up Next moves on.
- **Finishing:** plays the next Up Next item automatically.

### MusicRemote

- **Copied from ClickWheel:**
  - the AppleScript runner;
  - the Spotify and Apple Music sources;
  - the output parser.
- **Exposes:** now playing (title, artist, album, artwork, duration,
  position, isPlaying), play/pause, next/previous and set position.
- **Prompts:** asks for Automation permission on first use.
- **Failures:** if a music app isn't running or permission is declined, it
  reports "nothing playing" and never affects podcasts.

## Podcast library

### Model

Stored with SwiftData in the app's Application Support folder.

- **`Show`:** feed URL (unique), title, author, artwork URL, description,
  last updated, last error, and the date the error began.
- **`Episode`:**
  - Identity: guid (unique per show), show, title, published date,
    duration, enclosure URL and type.
  - Content: chapters URL, description.
  - Listening state: saved position, played, local file path, download
    state.
- **`UpNextEntry`:** episode, order.

### Feeds

- `FeedFetcher`: `URLSession`, sending If-None-Match/If-Modified-Since
  when known.
- `FeedParser` (`XMLParser`) reads RSS 2.0 with the `itunes:` and
  `podcast:` namespaces:
  - title, author, image;
  - for each item: guid, title, pubDate, `itunes:duration` (seconds or
    h:mm:ss) and enclosure;
  - `podcast:chapters` (URL) and `psc:chapters` (inline).
- `ChapterLoader` builds the chapter list, using the first source found:
  1. `podcast:chapters` JSON;
  2. Podlove Simple Chapters in the feed;
  3. chapter markers inside the audio file
     (`AVAsset` `chapterMetadataGroups`).
- `Refresher` checks every show at launch and every hour, two feeds at a
  time. New episodes appear in New Episodes; nothing is added to Up Next
  automatically.

### Finding and adding shows

- `DirectorySearch`: the iTunes Search API. Results are mapped to title,
  author, artwork and feed URL.
- **Add by link:** paste a feed URL. It's fetched and checked before the
  show is followed.
- `OPMLImporter` (stage 2): reads `outline` elements with `xmlUrl` and
  follows each one, skipping shows already followed.

### Downloads (stage 2)

- `URLSession` download tasks into `Application Support/Spindle/Episodes`.
- Downloads are started by hand from any episode row.
- A played episode's download is deleted 7 days after it was played.

## Errors

- **Offline:**
  - Downloaded episodes play as usual.
  - A streaming episode shows "Offline" on the disc and resumes from its
    saved place once the network is back.
  - Feed checks fail quietly and retry at the next hourly check.
- **A broken feed:**
  - The show is marked with its last error and the date it began. The
    Library says "Couldn't update · last worked <date>".
  - Its existing episodes stay playable.
  - Other shows are unaffected.
- **A dead audio link:** the episode row shows "Unavailable", and playback
  moves to the next Up Next item.
- **No chapters:** the 15 s ticks still play; the chapter pill and the
  chapter dots are hidden.
- **Music app missing or permission declined:** the music side reports
  "nothing playing". Podcasts are unaffected.
- **Bad input:** an invalid feed link or OPML file shows a short message
  next to the field, and nothing is added.

## Testing

- **Automated (XCTest via `./scripts/test.sh`, as in ClickWheel):**
  - `DialEngine`:
    - seconds per degree at normal speed;
    - acceleration and the 4× cap;
    - clamping at 0 and at the duration;
    - tick and chapter detents in both directions;
    - a chapter winning over a tick at the same time.
  - The `Haptics` rate limiter: 35 ms, and chapters never dropped.
  - `FeedParser` against sample feeds in the test bundle: durations in
    both formats, missing fields, both chapter formats.
  - `ChapterLoader`: the order of chapter sources.
  - `DirectorySearch`: decoding a saved response.
  - `OPMLImporter` (stage 2).
  - `NowPlaying`, with stand-in players: most recent wins; position is
    saved on switch; the played threshold advances Up Next.
  - Up Next order operations.
- **Checked by hand:**
  - the haptic feel on a Force Touch trackpad;
  - the glass over light, dark and busy wallpapers;
  - the media keys and Control Center.
- The author tries each stage before it is merged.

## Build stages

Each stage ends in something usable day to day, and gets its own plan.

1. **Dial and podcasts.**
   - The menu bar strip and dial panel.
   - `DialEngine` and haptics.
   - `PodcastPlayer` with speed, chapters and saved places.
   - Adding shows by search or by link.
   - Checking feeds for new episodes at launch (and on demand).
   - The minimal Library window.
   - A simple Up Next: add, play now, auto-advance.
   - Mac media integration.
2. **The Library.**
   - The full Library window: New Episodes, Shows grid, Downloaded.
   - Downloads and their clean-up.
   - OPML import.
   - Hourly refresh, on top of stage 1's check at launch.
   - Drag to reorder Up Next.
   - Feed error states.
3. **Music and the floating dial.**
   - `MusicRemote`, copied from ClickWheel.
   - The coordinator's most-recent-wins rule.
   - The music panel layout.
   - Pop out to a floating dial, with its position remembered.
