---
name: sideB
description: A cover in the Mac menu bar, in Liquid Glass, that turns over to show what is on the other side.
colors:
  ink: "#FFFFFF"
  ink-secondary: "rgba(235, 235, 245, 0.6)"
  row-highlight: "rgba(255, 255, 255, 0.18)"
  hairline: "rgba(255, 255, 255, 0.18)"
  card-back: "rgba(0, 0, 0, 0.22)"
  key-outline: "rgba(255, 255, 255, 0.55)"
  segment-track: "rgba(255, 255, 255, 0.10)"
  segment-selected: "rgba(255, 255, 255, 0.22)"
  source-spotify: "#1ED760"
  source-apple-music: "#FA2D48"
typography:
  title:
    fontFamily: "SF Pro (system), -apple-system"
    fontSize: "16pt"
    fontWeight: 600
  body:
    fontFamily: "SF Pro (system), -apple-system"
    fontSize: "12pt"
    fontWeight: 400
  caption:
    fontFamily: "SF Pro (system), -apple-system"
    fontSize: "11pt"
    fontWeight: 400
    fontFeature: "tnum"
  label:
    fontFamily: "SF Pro (system), -apple-system"
    fontSize: "10pt"
    fontWeight: 600
    letterSpacing: "1pt"
rounded:
  panel: "30pt"
  cover: "14pt"
  row: "8pt"
  thumb: "6pt"
  capsule: "999pt"
spacing:
  hairline: "2pt"
  row-gap: "6pt"
  cover-to-title: "10pt"
  inner: "10pt"
  rows: "14pt"
  panel: "16pt"
components:
  hint-pill:
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.capsule}"
    padding: "4pt 8pt"
  resume-row:
    textColor: "{colors.ink}"
    rounded: "{rounded.row}"
  list-row:
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.row}"
    height: "30pt"
    padding: "0 6pt"
  list-row-current:
    backgroundColor: "{colors.row-highlight}"
    textColor: "{colors.ink}"
    rounded: "{rounded.row}"
  episode-row:
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.row}"
    height: "44pt"
  tab-switch:
    backgroundColor: "{colors.segment-track}"
    typography: "{typography.caption}"
    rounded: "{rounded.row}"
    padding: "2pt"
  tab-switch-selected:
    backgroundColor: "{colors.segment-selected}"
    rounded: "{rounded.thumb}"
  cover-back:
    backgroundColor: "{colors.card-back}"
    rounded: "{rounded.cover}"
    size: "240pt"
    padding: "10pt 6pt 32pt 6pt"
---

# Design System: sideB

## Overview

**Creative North Star: "The Other Side"**

sideB is a cover you can turn over. On the front, what's playing and nothing else; on the back, the album, the playlist
or the episodes it belongs to. It hangs at the edge of the author's work in the menu bar, is touched for a moment, and is
gone. It should feel **tactile, calm and precise**: the cover gives under the pointer and turns like a real sleeve,
nothing shouts, every detail is exact.

The material is the see-through window glass macOS draws (AppKit `NSGlassEffectView`): the desktop and the windows
behind show through the panel and the mini player, so sideB takes its colour from where it sits and from the
artwork it shows: the glass itself is tinted with the cover's colour. sideB adds no colour of its own. Density is low and deliberate: a 272 pt panel holds a
240 pt cover, a title, the progress line and its controls and, when needed, one pill.

The iPod lineage survives in the love of album covers and the click-wheel icon, not in a wheel: sideB tried a dial and
dropped it for a progress line and plain buttons. No Apple assets or logos appear; the playback buttons use Apple's SF
Symbols so they read as the Mac's own, and every other glyph is drawn in code.

**Key Characteristics:**
- Window glass everywhere the app has a surface; SwiftUI glass only for small controls inside it.
- Colour comes from artwork and the desktop; sideB's own ink is white at a few opacities.
- System type (SF Pro) at small, exact sizes; tabular digits for every time.
- Soft springs for every change; Reduce Motion always gets a plain crossfade.
- One gesture per thing: drag or scroll the progress line, press play, click the cover.

## Colors

A monochrome glass palette: white ink at a few strengths over translucent glass, with colour borrowed from the
artwork and two tiny source dots.

### Primary
- **Glass Ink** (`ink`): titles, the playback buttons, the progress line's fill, pill text. Always drawn with the system label
  colour (`NSColor.labelColor`) rather than SwiftUI's `.primary` or `.foreground`, which render grey on glass.

### Neutral
- **Quiet Ink** (`ink-secondary`): artist or show line, times under the progress line, the show and episode in the Resume row, list
  details, the podcast speed.
- **Row Light** (`row-highlight`): the current song, episode or chapter in a list, and any row being pressed.
- **Glass Tint**: the window glass of the panel and the mini player takes the cover's hue, lighter and livelier than
  the Cover Tint (HSB brightness 0.5–0.72, saturation up to 0.8), at 35% so the desktop still shows through. It eases
  in over about half a second when the cover changes; with no artwork the glass stays plain.
- **Glass Hairline** (`hairline`): the 0.5 pt edge on the cover and its back.
- **Cover Tint**: the back of the cover takes the cover's own colour: the artwork's average, kept to its hue but
  held to HSB brightness 0.14–0.32 and saturation ≤ 0.65, drawn at 85%. Even a white cover gives a back that white
  text reads on at 7:1, so it is the other side of the same object, not a new surface.
- **Smoked Glass** (`card-back`): the back of the cover when there is no artwork to take a tint from.
- **Key Outline** (`key-outline`): the 1.5 pt outline on the row the arrow keys have reached. An outline, never a
  fill, so it can't be mistaken for Row Light on what's playing.
- **Segment Track / Segment Light** (`segment-track`, `segment-selected`): the Episodes | Notes switch.

### Tertiary
- **Spotify Green** (`source-spotify`) and **Music Red** (`source-apple-music`): only the 6 pt dot after the artist
  name, saying where a song plays, always followed by the source's name. Our own mark, never a logo.

### Named Rules
**The Borrowed Colour Rule.** sideB never paints a surface with a colour of its own. Colour comes from the
artwork (the Glass Tint and the Cover Tint), the desktop through the glass, or the two source dots.

**The Label Ink Rule.** Anything that must read as white on glass uses `NSColor.labelColor`; `.primary` and
`.foreground` render grey there.

## Typography

**Display Font:** SF Pro (the system font, `.system(size:)`)
**Body Font:** SF Pro
**Label/Mono Font:** SF Pro with monospaced digits for times and numbers

**Character:** One family at small, exact sizes; hierarchy comes from size and weight steps, not from a second face.

### Hierarchy
- **Title** (semibold, 16 pt): the episode or song title under the cover, up to two lines. Room for two is always
  kept, so a shorter title leaves a gap above the progress line.
- **Volume** (caption, tabular digits): "Volume 40%" in place of the elapsed time during Option + scroll.
- **Body** (regular, 12 pt): the artist or show line, list rows, descriptions.
- **Caption** (regular, 11 pt, tabular digits): times under the progress line, row durations and dates, pill text.
- **Label** (semibold, 10 pt, 1 pt tracking, uppercase for list headings): the cover's hint pill, "UP NEXT", the
  album heading on the back of the cover. The podcast speed between the times is 11 pt semibold.

### Named Rules
**The Same Size Rule.** Paired values keep one size: elapsed and remaining times never shrink independently;
when space runs out, move them rather than scale them.

**The Steady Controls Rule.** The progress line and playback buttons stay put from song to song: a title that wraps
never moves them under the pointer.

## Layout

A single 272 pt column with 16 pt padding (`panel`): cover (240 × 240 pt), 10 pt, title block, then the progress
line with its times, the controls, then pills. Rows are 14 pt apart.

Times sit under the two ends of the progress line. The bottom margin is 18 pt. The panel
grows to fit its rows (about 491 pt with music and a Resume row) and must fit a 1280 × 800 screen (720 pt max).

The list lives on the back of the cover in the same 240 pt square: 10 pt inset at the top, 6 pt at the sides and
32 pt at the bottom so the "Cover" pill never covers a row. Song rows are 30 pt; episode rows are 44 pt (title, then
date and length).

## Elevation & Depth

Depth comes from the glass itself and one ambient shadow under the cover. The panel window draws no shadow of its
own (it would outline the square window past the rounded glass); the window keeps a clear margin round the glass so
the glass's own shadow fades out instead of being cut off. The mini player's window does the same.

### Shadow Vocabulary
- **Cover lift** (black 35%, radius 15 pt, y 10 pt): under the cover, so it sits above the panel glass.
- **Back lift** (black 25%, radius 12 pt, y 8 pt): under the back of the cover.

### Named Rules
**The One Lift Rule.** Only the cover lifts. Pills, rows, the progress line and the buttons sit in the glass, not on it.

## Shapes

Continuous (squircle) corners throughout, nested so curves run parallel: the panel at 30 pt, the cover and its back
at 14 pt (30 pt less the 16 pt padding), list rows and the tab switch at 8 pt, small artwork and selected segments at
6 pt. Pills and the progress line are capsules; the source dot is a circle. Edges are 0.5 pt glass
hairlines, never solid borders.

**The Parallel Corners Rule.** An inner radius is the outer radius less the gap between them.

## Components

### Hint Pill
Small glass capsule on the cover's bottom-right corner: "Episodes", "Album", "Playlist" or "Details" on the front,
"Cover" on the back, each followed by the **turn mark**: an arc round a flat ellipse with an arrowhead (a coin seen
edge-on, turning), 11 × 9 pt, stroked 1.3 pt in Glass Ink, mirrored on the back. Drawn in code; VoiceOver skips it
and reads "Show album" or "Show the cover". Label type, 4 × 8 pt padding. In the panel it rests at 60%, so the art keeps
its corner, and comes up to full with the corner buttons when the pointer is on the panel.

### Resume Row
A plain row under the controls while music interrupts a podcast, built like the Up Next rows and with no container, so
it doesn't compete with the playback buttons. A 28 pt show artwork (6 pt corners) lined up with the cover's left edge,
then "Resume podcast" in Glass Ink at 12 pt over the show and episode title in Quiet Ink at 11 pt, cut short at the end
of the episode title. Under the pointer it lights like every row (see List Rows), reaching 5 pt past the column, as the Up
Next rows do. Up Next is the podcast queue, so it shows only under a podcast and never beside this row.

### Notes Under the Controls
In the panel, plain centred text in Quiet Ink at 11 pt, with no container, under the playback buttons so the buttons never move. A
failed music command says so ("Spotify didn't respond. Try again.") for five seconds, until a command works, or until
the song changes. A Spotify sign-in that predates a permission asks to be renewed, with a Sign In Again pill, until it
is; other refusals, like no Premium or no active device, never ask.

### List Rows
Plain rows, 30 pt (songs, chapters) or 44 pt (episodes), 8 pt corners; the current one gets Row Light and semibold.
Every row in sideB lights the same way: white at 10% under the pointer and Row Light when pressed, over 0.15 s; a row
that cuts its title short shows it whole on hover.
The row the arrow keys have reached gets the Key Outline. A clicked song takes Row Light at once, before the app has
reported it, and gives it back if the click fails or the song hasn't arrived after three seconds. The heading is the album or playlist name alone (label
type); the count sits at the foot of the list in caption type: "11 songs", or "500 of 812 songs" when only part
could be read. No account controls on the back: Sign Out of Spotify lives in the menu bar menu.
Number (albums only) in Quiet Ink, title, duration right-aligned in caption digits. Lists open centred on the
current item and fade softly at their scroll edges.

### Tab Switch
Episodes | Notes (or Chapters): a 2 pt-inset track in Segment Track with the selected half in Segment Light. Drawn
in SwiftUI rather than a system segmented control, because a system control doesn't turn with the cover.

### The Progress Line and Controls
Simple and pragmatic, so the cover stays the signature. Under the title, a 240 pt progress line (a bold
6 pt capsule, white 22% track, white fill; 8 pt under the pointer or while dragging) with the times under its two
ends in caption digits. Drag it to move through the song or episode (a real drag, past 3 pt: a stray click does nothing; the elapsed and
remaining times follow the pointer, and nothing seeks until you let go), or scroll over
it to scrub with haptic ticks. Option + scroll sets the volume, said in words where the elapsed time was ("Volume
40%"); the line always shows time.
Playing, the fill glides on between the player's ticks at the playback speed (never more than 1.5 s ahead).

Under it, centred, in Apple's SF Symbols at 20 pt: back, play/pause (a plain 30 pt symbol, no glass circle) whose symbol
swaps with the system's replace effect, and forward (`backward.fill` / `forward.fill` for music, `gobackward.15` /
`goforward.30` for podcasts). A podcast's speed sits between the two times as a quiet text button, clear of the buttons.

### Mini Player
The floating window is only the cover: the panel's 240 pt cover in a 10 pt frame of window glass tinted with the
cover's colour, 260 × 260 pt with 24 pt corners (the cover's 14 plus the frame), in a clear window margin with no window
shadow. At rest there is nothing else on it, except a note when there's something to say: one at a time, on smoked glass
at 85% with 8 pt corners, so it reads over any artwork or list. With the pointer over it, controls fade in: Library, a
turn hint and Hide Mini Player along the top, and the title (12 pt semibold) and artist or show (11 pt), the progress line, times
and playback buttons along the bottom over a soft dark fade that keeps them readable on any artwork. Clicking the cover turns it over to its list, exactly as in the panel but with
its own list and flip; dragging it (past 3 pt) moves it; right-click gives Hide Mini Player, the Library and Quit. It has one pair of names everywhere it's offered: Show
Mini Player and Hide Mini Player. With nothing
playing it is a plain glass tile saying "Nothing playing", with a Find a Show pill. It takes the panel's keys once
clicked, without bringing sideB forward; Esc only turns its cover back, because it floats by choice.

### The Cover (signature)
240 pt artwork with 14 pt corners and the Cover lift. It gives a little under the pointer (scale 1.015) and when
pressed (0.97). New artwork **develops in**: from blurred, 96% and transparent to sharp, full and solid on a soft
spring (response 0.45, damping 0.9); the title rises 6 pt and fades in with it, and the old cover stays until the new
one is ready. Clicking it **turns it over** (a 3D flip about the vertical axis, spring response 0.5, damping 0.86)
to the list on the Cover Tint; each face shows only while it faces you, and VoiceOver reads only that face and
moves to it after the turn. Library and Show Mini Player sit in its top corners at 35% at rest and full under the pointer.

### Keys
While the panel is open: Space plays or pauses, ← and → go back and forward (a song, or 15 and 30 seconds), Return
turns the cover, R resumes the podcast music interrupted (the Resume row shows a faint R keycap), ⌘L opens the Library, Escape turns the cover back and then closes the panel. On the back, ↑ and ↓
move the Key Outline and Return plays that row. Keys held with ⌘, ⌥ or ⌃ (other than ⌘L) are left to macOS. The menu bar
menu's Keyboard Shortcuts… lists them all, and the scroll gestures after them.

### The Menu Bar Strip
The small glass capsule in the menu bar: a 13 pt artwork and a 44 pt progress bar, or an empty glass circle with nothing
open. Paused, the artwork and bar dim to 40% on the same glass, so a glance tells playing from paused without opening
anything, and the strip keeps its width. Hovering names the title and artist; VoiceOver hears the state too ("Paused,
Japan, Fontaines D.C."). Click for the panel, right-click for the menu, scroll to scrub.

### Source Dot
A 6 pt circle after the artist name in Spotify Green or Music Red, then the source's name ("Spotify" or "Music") in
Quiet Ink, so the source never rests on colour alone (red and green are the pair colour-blind people confuse most).
The artist line gives way first when space runs short; VoiceOver reads "Spotify" or "Apple Music".

## Do's and Don'ts

### Do:
- **Do** put window glass (`NSGlassEffectView`) behind every surface that should see the desktop: the panel and the
  mini player, tinted with the cover's colour.
- **Do** draw white ink with `NSColor.labelColor`.
- **Do** keep the panel and the mini player in the dark appearance (`darkAqua`), so that ink stays white in
  Light mode too.
- **Do** nest corners: 30 pt panel → 14 pt cover → 8 pt rows → 6 pt thumbs.
- **Do** use tabular digits for every time and number.
- **Do** give every motion a Reduce Motion crossfade.
- **Do** use SF Symbols for the playback buttons (`backward.fill`, `play.fill` / `pause.fill` with the symbol
  replace transition, `forward.fill`; `gobackward.15` and `goforward.30` for podcasts) and draw the other glyphs in
  code (library, show and hide the mini player, the turn mark), never Unicode arrows.

### Don't:
- **Don't** use SwiftUI `.glassEffect` for a whole window's surface: it only sees inside its own clear window and
  renders flat grey.
- **Don't** use Apple logos or product artwork; keep SF Symbols to the playback buttons.
- **Don't** shrink one of a pair of values (elapsed and remaining time) to make it fit.
- **Don't** add a window shadow to the panel; the glass carries its own.
- **Don't** use up and down arrows (⌄ ⌃) on the cover's hint: the cover turns sideways, it doesn't drop down.
- **Don't** put account controls on the back of the cover.
- **Don't** hide controls entirely until hover; show them faintly at rest.
- **Don't** open a second window for something the panel can show in place (the list lives on the back of the cover).
- **Don't** paint surfaces with sideB's own colour.
