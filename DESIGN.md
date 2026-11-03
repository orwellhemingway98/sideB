---
name: Spindle
description: A Liquid Glass dial in the Mac menu bar, felt through the trackpad.
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
  volume:
    fontFamily: "SF Pro (system), -apple-system"
    fontSize: "17pt"
    fontWeight: 600
    fontFeature: "tnum"
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
  around-disc: "22pt"
components:
  hint-pill:
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.capsule}"
    padding: "4pt 8pt"
  resume-pill:
    textColor: "{colors.ink}"
    typography: "{typography.caption}"
    rounded: "{rounded.capsule}"
    padding: "4pt 12pt 4pt 4pt"
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

# Design System: Spindle

## Overview

**Creative North Star: "The Quiet Wheel"**

Spindle is the iPod's wheel made calm and made of glass. One wheel, one cover, nothing else asking for attention:
it hangs at the edge of the author's work in the menu bar, is touched for a moment, and is gone. It should feel
**tactile, calm and precise** — physical controls you feel through the trackpad, nothing shouting, every detail
exact.

The material is the see-through window glass macOS draws (AppKit `NSGlassEffectView`): the desktop and the windows
behind show through the panel and the floating dial, so Spindle takes its colour from where it sits and from the
artwork it shows: the glass itself is tinted with the cover's colour. Spindle adds no colour of its own. Density is low and deliberate: a 272 pt panel holds a
240 pt cover, a title, the 150 pt disc and, when needed, one pill.

The iPod lineage is in behaviour, not imitation: the wheel you turn, the click you feel, the cover that turns over to
show what's inside. No Apple assets or logos appear; the playback buttons use Apple's SF Symbols so they read as the Mac's own,
and every other glyph is drawn in code.

**Key Characteristics:**
- Window glass everywhere the app has a surface; SwiftUI glass only for small controls inside it.
- Colour comes from artwork and the desktop; Spindle's own ink is white at a few opacities.
- System type (SF Pro) at small, exact sizes; tabular digits for every time.
- Soft springs for every change; Reduce Motion always gets a plain crossfade.
- One gesture per thing: turn the disc, press its centre, click the cover.

## Colors

A monochrome glass palette: white ink at a few strengths over translucent glass, with colour borrowed from the
artwork and two tiny source dots.

### Primary
- **Glass Ink** (`ink`): titles, glyphs on the disc, the lit halo, pill text. Always drawn with the system label
  colour (`NSColor.labelColor`) rather than SwiftUI's `.primary` or `.foreground`, which render grey on glass.

### Neutral
- **Quiet Ink** (`ink-secondary`): artist or show line, times beside the disc, "Resume" in the Resume pill, list
  details, the podcast speed.
- **Row Light** (`row-highlight`): the current song, episode or chapter in a list.
- **Glass Tint**: the window glass of the panel and floating dial takes the cover's hue, lighter and livelier than
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
**The Borrowed Colour Rule.** Spindle never paints a surface with a colour of its own. Colour comes from the
artwork (the Glass Tint and the Cover Tint), the desktop through the glass, or the two source dots.

**The Label Ink Rule.** Anything that must read as white on glass uses `NSColor.labelColor`; `.primary` and
`.foreground` render grey there.

## Typography

**Display Font:** SF Pro (the system font, `.system(size:)`)
**Body Font:** SF Pro
**Label/Mono Font:** SF Pro with monospaced digits for times and numbers

**Character:** One family at small, exact sizes; hierarchy comes from size and weight steps, not from a second face.

### Hierarchy
- **Title** (semibold, 16 pt): the episode or song title under the cover, up to two lines.
- **Volume** (semibold, 17 pt, tabular digits): the volume number in the centre of the disc during Option + turn.
- **Body** (regular, 12 pt): the artist or show line, list rows, descriptions.
- **Caption** (regular, 11 pt, tabular digits): times beside the disc, row durations and dates, pill text.
- **Label** (semibold, 10 pt, 1 pt tracking, uppercase for list headings): the cover's hint pill, "UP NEXT", the
  album heading on the back of the cover. The podcast speed under the disc's centre is 9 pt semibold.

### Named Rules
**The Same Size Rule.** Paired values keep one size: elapsed and remaining times never shrink independently;
when space runs out, move them (they sit in the disc row's lower corners) rather than scale them.

## Layout

A single 272 pt column with 16 pt padding (`panel`): cover (240 × 240 pt), 10 pt, title block, then the progress
line with its times, the controls, then pills. Rows are 14 pt apart.

Times sit under the two ends of the progress line. The bottom margin is 18 pt. The panel
grows to fit its rows (about 507 pt with music and a Resume pill) and must fit a 1280 × 800 screen (720 pt max).

The list lives on the back of the cover in the same 240 pt square: 10 pt inset at the top, 6 pt at the sides and
32 pt at the bottom so the "Cover" pill never covers a row. Song rows are 30 pt; episode rows are 44 pt (title, then
date and length).

## Elevation & Depth

Depth comes from the glass itself and one ambient shadow under the cover. The panel window draws no shadow of its
own (it would outline the square window past the rounded glass); the window keeps a clear margin round the glass so
the glass's own shadow fades out instead of being cut off.

### Shadow Vocabulary
- **Cover lift** (black 35%, radius 15 pt, y 10 pt): under the cover, so it sits above the panel glass.
- **Back lift** (black 25%, radius 12 pt, y 8 pt): under the back of the cover.

### Named Rules
**The One Lift Rule.** Only the cover lifts. Pills, rows and the disc sit in the glass, not on it.

## Shapes

Continuous (squircle) corners throughout, nested so curves run parallel: the panel at 30 pt, the cover and its back
at 14 pt (30 pt less the 16 pt padding), list rows and the tab switch at 8 pt, small artwork and selected segments at
6 pt. Pills are capsules; the disc, its centre button and the source dot are circles. Edges are 0.5 pt glass
hairlines, never solid borders.

**The Parallel Corners Rule.** An inner radius is the outer radius less the gap between them.

## Components

### Hint Pill
Small glass capsule on the cover's bottom-right corner: "Episodes", "Album", "Playlist" or "Spotify" on the front,
"Cover" on the back, each followed by the **turn mark**: an arc round a flat ellipse with an arrowhead (a coin seen
edge-on, turning), 11 × 9 pt, stroked 1.3 pt in Glass Ink, mirrored on the back. Drawn in code; VoiceOver skips it
and reads "Show album" or "Show the cover". Label type, 4 × 8 pt padding.

### Resume Pill
Soft glass capsule under the disc while music interrupts a podcast: a 22 pt show artwork (6 pt corners), "Resume" in
Quiet Ink, then the episode title in regular weight. Interactive glass that gives under the pointer.

### List Rows
Plain rows, 30 pt (songs, chapters) or 44 pt (episodes), 8 pt corners; the current one gets Row Light and semibold.
The row the arrow keys have reached gets the Key Outline. The heading is the album or playlist name alone (label
type); the count sits at the foot of the list in caption type: "11 songs", or "500 of 812 songs" when only part
could be read. No account controls on the back: Sign Out of Spotify lives in the menu bar menu.
Number (albums only) in Quiet Ink, title, duration right-aligned in caption digits. Lists open centred on the
current item and fade softly at their scroll edges.

### Tab Switch
Episodes | Notes (or Chapters): a 2 pt-inset track in Segment Track with the selected half in Segment Light. Drawn
in SwiftUI rather than a system segmented control, because a system control doesn't turn with the cover.

### The Progress Line and Controls
The dial is gone: Spindle chose something simpler and more pragmatic. Under the title, a 240 pt progress line (a bold
6 pt capsule, white 22% track, white fill; 8 pt under the pointer or while dragging) with the times under its two
ends in caption digits. Drag it to move through the song or episode, or scroll over it to scrub with the haptic
ticks the dial had (Option + scroll sets the volume: the line shows the level and the times read "Volume 40%").
Playing, the fill glides on between the player's ticks at the playback speed (never more than 1.5 s ahead).

Under it, centred, in Apple's SF Symbols at 20 pt: back, a 52 pt glass play/pause button whose symbol swaps with
the system's replace effect, and forward (`backward.fill` / `forward.fill` for music, `gobackward.15` /
`goforward.30` for podcasts). A podcast's speed sits at the right as a quiet text button.

### Mini Player
The floating window is a small Now Playing card in the panel's language: 340 × 164 pt of window glass tinted with
the cover's colour, with 26 pt corners (the cover's 12 plus the 14 pt padding). Top: the 56 pt cover with its
hairline and a small lift (the One Lift rule holds: only the cover casts a shadow), the title (15 pt semibold) and
the artist line with its source (13 pt). Then the times either side of a 6 pt progress line. Then back, a 44 pt
glass play/pause and forward, the panel's controls at a smaller size. Drag it by the cover or titles; right-click for
Put Back, the Library and Quit.

### The Cover (signature)
240 pt artwork with 14 pt corners and the Cover lift. It gives a little under the pointer (scale 1.015) and when
pressed (0.97). New artwork **develops in**: from blurred, 96% and transparent to sharp, full and solid on a soft
spring (response 0.45, damping 0.9); the title rises 6 pt and fades in with it, and the old cover stays until the new
one is ready. Clicking it **turns it over** (a 3D flip about the vertical axis, spring response 0.5, damping 0.86)
to the list on the Cover Tint; each face shows only while it faces you, and VoiceOver reads only that face and
moves to it after the turn. Library and Pop out sit in its top corners at 35% at rest and full under the pointer.

### Keys
While the panel is open: Space plays or pauses, ← and → go back and forward (a song, or 15 and 30 seconds), Return
turns the cover, ⌘L opens the Library, Escape turns the cover back and then closes the panel. On the back, ↑ and ↓
move the Key Outline and Return plays that row. Keys held with ⌘, ⌥ or ⌃ (other than ⌘L) are left to macOS.

### Source Dot
A 6 pt circle after the artist name in Spotify Green or Music Red, then the source's name ("Spotify" or "Music") in
Quiet Ink, so the source never rests on colour alone (red and green are the pair colour-blind people confuse most).
The artist line gives way first when space runs short; VoiceOver reads "Spotify" or "Apple Music".

## Do's and Don'ts

### Do:
- **Do** put window glass (`NSGlassEffectView`) behind every surface that should see the desktop: the panel and the
  floating dial, tinted with the cover's colour.
- **Do** draw white ink with `NSColor.labelColor`.
- **Do** keep the panel and the floating dial in the dark appearance (`darkAqua`), so that ink stays white in
  Light mode too.
- **Do** nest corners: 30 pt panel → 14 pt cover → 8 pt rows → 6 pt thumbs.
- **Do** use tabular digits for every time and number.
- **Do** give every motion a Reduce Motion crossfade.
- **Do** use SF Symbols for the playback buttons (`backward.fill`, `play.fill` / `pause.fill` with the symbol
  replace transition, `forward.fill`; `gobackward.15` and `goforward.30` for podcasts) and draw the other glyphs in
  code (library, pop out and put back, the turn mark), never Unicode arrows.

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
- **Don't** paint surfaces with Spindle's own colour.
