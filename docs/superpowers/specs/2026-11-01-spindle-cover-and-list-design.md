# Spindle — big cover and the list window

An addition to Spindle v0.3.0. The dial panel gets a big cover on top. Clicking the cover lets a glass droplet fall
from the panel and spread into its own window, which lists what you're listening within: the show's episodes and
chapters for a podcast, or the album or playlist for Apple Music.

This is piece 1 of 2. Piece 2, Spotify sign-in, lets Spotify songs list their album or playlist too. It gets its own
spec because it needs a Spotify developer app the author registers, a browser sign-in and token storage.

## Intent

- **Who it's for:** the author, who asked for a much bigger cover. Clicking the cover shows the contents of the
  album, playlist or show.
- **What it must get right:**
  - The cover is big and the dial stays full size.
  - The list arrives with a Liquid Glass motion: a droplet that becomes a window (the author chose this over a
    panel that grows).
  - Clicking an item plays it in context.

## Platform and constraints

- **Unchanged from v0.3.0:**
  - macOS 26 and Swift 5 mode.
  - No SF Symbols or Apple artwork in Spindle's own controls.
  - Nothing is pushed unless the author asks.
- **Music:** it is still controlled only through AppleScript. Spindle never scripts an app that isn't running.
- **The floating dial is unchanged:** just the disc.

## The panel

- **Layout, top to bottom (272 pt wide, about 560 pt tall with something playing):**
  1. The cover: 240 × 240 pt with 18 pt corners and a soft shadow.
  2. Title, then subtitle ("show" or "artist · source").
  3. The 150 pt disc, unchanged.
  4. Times and pills, unchanged.
  5. Resume (in music mode) and Up Next, unchanged.
  6. The footer.
- **The cover:**
  - It replaces the 44 pt header artwork.
  - A small glass hint sits at its bottom-right corner:
    - podcasts: "Episodes ⌄";
    - Apple Music: "Album ⌄" or "Playlist ⌄";
    - Spotify: "Spotify ⌄".
  - On hover it scales up slightly (1.015); while pressed it scales down (0.97).
  - Clicking it toggles the list window.
- **Nothing playing:** no cover. The panel looks as it does today.

## The list window

### Motion

- **Opening (macOS Liquid Glass morphing):**
  - A small glass drop pinches off the bottom edge of the panel and falls about 26 pt.
  - It spreads into the list window, which sits 12 pt below the panel and is the panel's width.
  - About 0.6 s with a gentle spring.
- **Closing:** the reverse; the window shrinks back into a drop that rejoins the panel.
- **It closes when:**
  - the cover is clicked again;
  - you click outside both windows;
  - Escape is pressed;
  - the panel closes;
  - what's playing changes to a different show, album or playlist.

  An episode or track change within the same list does not close it.
- **Size:** the window grows with its rows, up to 360 pt tall. Beyond that it scrolls.

### Contents

- **Podcast: a two-part toggle at the top, "Episodes | Chapters".** It opens on Episodes.
  - **Episodes:**
    - The show's episodes, newest first, the same list as the Library.
    - The current episode is highlighted.
    - Each row shows the title, date and length (or "N left").
    - Clicking a row plays it (`NowPlaying.play`).
  - **Chapters:**
    - The current episode's chapters with their start times. The current chapter is highlighted.
    - Clicking one jumps there (`NowPlaying.jump`).
    - Without chapters, the episode's description shows as plain text (HTML tags stripped).
- **Apple Music:**
  - What it lists:
    - If the current playlist is one of your own playlists (a user playlist whose special kind is none), it lists
      that playlist, titled with the playlist's name. The exception is Spindle's own "Spindle" playlist: that one
      counts as the album it was filled from, so the window lists the album.
    - Otherwise it lists the song's album from your library: the tracks with the same album and album artist,
      ordered by disc number then track number, titled with the album's name.
  - The current track is highlighted. Each row shows the number, title and length.
  - **Clicking a row:**
    - In a playlist: Music plays that track within the playlist.
    - In an album: Spindle plays the album from that track. It does this by refilling a playlist named "Spindle"
      with the album from that track on, the same approach as ClickWheel's "ClickWheel" playlist.
  - **When it's read:** once when the window opens, then cached by album or playlist id. It isn't read again every
    second.
  - **Tracks Music can't list** (a radio station, a stream, a song not in your library): the window says "Nothing
    to list for this song."
- **Spotify:**
  - It shows the song, artist, album and length.
  - Below that: "Sign in to Spotify to see the album and playlist." This line becomes a button in piece 2.

## Units

- **`MusicContext`:** the album or playlist for the current Music track.
  - `kind` is `.album` or `.playlist`, plus `title` and `tracks`. Each entry in `tracks` has an id, number, title,
    artist and duration.
  - It's read through `AppleMusicContextSource`: AppleScript run off the main actor, with the output parsed like
    the existing scripts (fields separated by ASCII 31, rows by ASCII 30).
  - Its parser is pure and tested.
- **`MusicRemote` gains:**
  - `context(for track: MusicTrack) async -> MusicContext?`, cached by track and context.
  - `play(contextTrack:in:)`.

  Spotify returns nil until piece 2.
- **`ListContent`:** what the window shows, built from `NowPlaying` (mode, episode, chapters, music track and
  context). It's a pure enum that can be tested on its own:
  - `.podcast(episodes, current, chapters, currentChapter, description)`;
  - `.music(context, currentTrackID)`;
  - `.spotifyDetails(track)`;
  - `.nothing`.
- **`ListWindowController`:**
  - A borderless, non-activating glass `NSPanel` attached under the dial panel (a child window).
  - It runs the droplet morph using `GlassEffectContainer` and `glassEffectID` / `glassEffectTransition`.
  - It closes on the conditions above.
- **`DialPanelView`:** the cover header replaces the 44 pt header.

## Errors

- **Music scripting fails** (permission, Music quits, timeout): the window says "Couldn't read the album from
  Music." and offers nothing to click. The panel itself is unaffected.
- **Episode description:** an empty or missing one shows "No description."
- **Stale context:** a context read for one album that arrives after the song has moved to another album is
  dropped.

## Testing

- **Automated:**
  - The context parser (album, playlist, empty, odd characters).
  - Album vs playlist selection.
  - The ordering by disc then track number.
  - The `ListContent` mapping for each case.
  - The cover hint text.
  - That a stale context is dropped.
  - That clicking an album row asks for "play album from track N".
- **By hand:**
  - The droplet motion.
  - The panel height on a small screen.
  - That clicking a track in Music plays it in the right context.

## Build order

This is a single plan: context reading → `ListContent` → the cover header → the list window and its motion →
wiring.
