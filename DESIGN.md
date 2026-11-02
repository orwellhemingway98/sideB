---
name: Spindle
description: A Liquid Glass dial in the Mac menu bar, felt through the trackpad.
colors:
  ink: "#FFFFFF"
  ink-secondary: "rgba(235, 235, 245, 0.6)"
  row-highlight: "rgba(255, 255, 255, 0.18)"
  halo-track: "rgba(255, 255, 255, 0.14)"
  hairline: "rgba(255, 255, 255, 0.18)"
  card-back: "rgba(0, 0, 0, 0.22)"
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
artwork it shows. Spindle adds almost no colour of its own. Density is low and deliberate: a 272 pt panel holds a
240 pt cover, a title, the 150 pt disc and, when needed, one pill.

The iPod lineage is in behaviour, not imitation: the wheel you turn, the click you feel, the cover that turns over to
show what's inside. No Apple assets, logos or SF Symbols appear in Spindle's own controls; glyphs are drawn in code.

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
- **Halo Track** (`halo-track`): the unlit part of the halo round the disc.
- **Glass Hairline** (`hairline`): the 0.5 pt edge on the cover and its back.
- **Smoked Glass** (`card-back`): the back of the cover, so its list reads over any artwork-tinted glass.
- **Segment Track / Segment Light** (`segment-track`, `segment-selected`): the Episodes | Notes switch.

### Tertiary
- **Spotify Green** (`source-spotify`) and **Music Red** (`source-apple-music`): only the 6 pt dot after the artist
  name, saying where a song plays. Our own mark, never a logo.

### Named Rules
**The Borrowed Colour Rule.** Spindle never paints a surface with a colour of its own. Colour comes from the
artwork, the desktop through the glass, or the two source dots.

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

A single 272 pt column with 16 pt padding (`panel`): cover (240 × 240 pt), 10 pt, title block, then the disc row,
then pills. Rows are 14 pt apart; the disc row adds 8 pt on each side so the artist line and the pills sit 22 pt
(`around-disc`) from the halo's edge. The disc row reserves the halo's full 160 pt height so its gaps are real.

Times sit in the lower corners of the disc row, where the circle curves away. The bottom margin is 18 pt. The panel
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
Small glass capsule on the cover's bottom-right corner: "Episodes ⌄", "Album ⌄", "Playlist ⌄", "Spotify ⌄" on the
front; "Cover ⌃" on the back. Label type, 4 × 8 pt padding.

### Resume Pill
Soft glass capsule under the disc while music interrupts a podcast: a 22 pt show artwork (6 pt corners), "Resume" in
Quiet Ink, then the episode title in regular weight. Interactive glass that gives under the pointer.

### List Rows
Plain rows, 30 pt (songs, chapters) or 44 pt (episodes), 8 pt corners; the current one gets Row Light and semibold.
Number (albums only) in Quiet Ink, title, duration right-aligned in caption digits. Lists open centred on the
current item and fade softly at their scroll edges.

### Tab Switch
Episodes | Notes (or Chapters): a 2 pt-inset track in Segment Track with the selected half in Segment Light. Drawn
in SwiftUI rather than a system segmented control, because a system control doesn't turn with the cover.

### The Disc (signature)
A 150 pt clear glass disc with a 60 pt glass centre button (play/pause glyph drawn in code). Back and forward sit at
9 and 3 o'clock (drawn skip glyphs for music, "−15" and "+30" for podcasts); the podcast speed sits under the centre.
The **halo** is a 3 pt band 2 pt outside the disc's edge: Halo Track all round, lit in Glass Ink from 12 o'clock to
the current time, with chapter starts cut as small gaps. During Option + turn the halo shows the volume and the
centre shows the number for a second.

### The Cover (signature)
240 pt artwork with 14 pt corners and the Cover lift. It gives a little under the pointer (scale 1.015) and when
pressed (0.97). New artwork **develops in**: from blurred, 96% and transparent to sharp, full and solid on a soft
spring (response 0.45, damping 0.9); the title rises 6 pt and fades in with it, and the old cover stays until the new
one is ready. Clicking it **turns it over** (a 3D flip about the vertical axis, spring response 0.5, damping 0.86)
to the list on Smoked Glass; each face shows only while it faces you.

### Source Dot
A 6 pt circle after the artist name in Spotify Green or Music Red; hover shows the source's name, VoiceOver reads it.

## Do's and Don'ts

### Do:
- **Do** put window glass (`NSGlassEffectView`) behind every surface that should see the desktop: the panel and the
  floating dial.
- **Do** draw white ink with `NSColor.labelColor`.
- **Do** nest corners: 30 pt panel → 14 pt cover → 8 pt rows → 6 pt thumbs.
- **Do** use tabular digits for every time and number.
- **Do** give every motion a Reduce Motion crossfade.
- **Do** draw glyphs in code (play, pause, skip, library).

### Don't:
- **Don't** use SwiftUI `.glassEffect` for a whole window's surface: it only sees inside its own clear window and
  renders flat grey.
- **Don't** use Apple logos, product artwork or SF Symbols in Spindle's own controls.
- **Don't** shrink one of a pair of values (elapsed and remaining time) to make it fit.
- **Don't** add a window shadow to the panel; the glass carries its own.
- **Don't** open a second window for something the panel can show in place (the list lives on the back of the cover).
- **Don't** paint surfaces with Spindle's own colour.
