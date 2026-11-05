# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS 26+ app (Swift, SwiftUI, AppKit where needed), built with XcodeGen. Not one of Impeccable's
`web` / `ios` / `android` / `adaptive` values: follow the macOS Human Interface Guidelines and native AppKit/SwiftUI
behaviour, not web patterns.

## Users

- **Now:** the author, listening to podcasts and music on a MacBook while working in other apps (often AutoCAD).
  sideB lives in the menu bar so control never means leaving the work.
- **Later:** a public release, as the author did with ClickWheel (a GitHub release). People who aren't the author
  will meet sideB for the first time, so first-run, empty states and plain-language setup start to matter.

## Product Purpose

A contemporary listening companion for the Mac: a dial in the menu bar that you turn and feel through the trackpad.
It plays podcasts itself and acts as a remote for Apple Music and Spotify.

At its best it does two things at once (both confirmed by the author):

1. **Control without leaving work:** glance at what's playing, turn to scrub, skip or pause from the menu bar,
   then get back to the work in the other app.
2. **An object you enjoy:** it should feel physical and beautiful — the dial, the haptic ticks, the glass, the
   iPod lineage.

It is not a feed, a recommendation engine or a music library browser, and it sends no notifications beyond what
macOS shows for Now Playing.

## Positioning

A tactile dial rather than a window of buttons: turning it scrubs, with a haptic tick every 15 seconds and a firmer
click at chapters, on the trackpad. One small object steers whatever is playing — sideB's own podcasts, Apple
Music or Spotify, whichever was started most recently — from the menu bar.

## Operating Context

- Used in short glances between other work, mostly by mouse/trackpad; the panel drops from the menu bar strip and
  closes when you click elsewhere. It can also be popped out as a mini player: just the cover, floating, with its controls on
  hover and its list on the back.
- Music apps are controlled through AppleScript; sideB never launches an app that isn't running.
- Podcasts come from RSS feeds the author follows (search Apple's podcast directory, paste a feed, or import OPML),
  with downloads for offline listening.

## Capabilities and Constraints

- **Panel:** big cover (turns over to show the album, playlist or episodes on its back), title and artist/show with
  a small coloured source dot and its name, a progress line with the times under it, back, play/pause and
  forward (and a podcast's speed), Resume pill when music interrupts a podcast, Up Next, chapter menu.
- **Progress input:** drag the line, or scroll over it to scrub with haptic ticks; Option + scroll sets volume
  (tick every 10%).
- **Podcasts:** chapters (feed, Podcasting 2.0 JSON, in-file), speed, resume, Up Next, downloads, hourly refresh,
  OPML import, Library window.
- **Music:** Apple Music albums and playlists read through AppleScript; Spotify albums and the user's own
  playlists through the Web API after a personal sign-in (PKCE, `sideb://callback`).
- **Menu bar menu:** Open Library, the mini player, Launch at Login, Spotify sign-in or sign-out, Quit.
- **Haptics** need a Force Touch trackpad; everything else works without one.
- **Repo:** private (`orwellhemingway98/spindle`); nothing is pushed or published unless the author asks.
- **Undecided for a public release:** signing and notarisation (builds are ad-hoc signed today); Spotify — the
  developer app's Development Mode allows 5 users and requires the owner to have Premium, so Spotify lists for the
  public are an open question; first-run and onboarding.

## Brand Commitments

- **Name:** sideB. **App icon:** the author's own click-wheel icon (`SideB/Resources/AppIcon.icon`).
- **No Apple assets:** original or system-provided artwork only; no Apple logos or product artwork. Liquid Glass, as
  a system material, is allowed, and so are SF Symbols for the playback buttons (back, play/pause, forward and the
  podcast skips), which the author chose so they read as the Mac's own; other glyphs stay drawn in code.
- **Glass is the look:** the author wants the see-through window glass (AppKit `NSGlassEffectView`, as in the
  native popover) to be the look and feel of the whole app.
- **iPod lineage** without imitation: the dial, the cover that turns over, the tactile clicks.
- **Voice:** plain, short, friendly English in the UI ("Find a show in Library", "Resume …").

## Evidence on Hand

- Specs: `docs/superpowers/specs/` (core design, cover and list, Spotify sign-in). Backlog: `docs/backlog.md`.
- No users other than the author yet; no testimonials, press, metrics or pricing exist — do not invent them.

## Product Principles

1. **Stay out of the way.** Every interaction should be a glance and a gesture; never pull the author out of the
   app they're working in.
2. **Feel, then see.** The dial's haptics and motion carry meaning; visuals confirm what the hand already felt.
3. **One object, every source.** Podcasts, Apple Music and Spotify are steered the same way; differences show only
   where they must.
4. **Native and quiet.** System materials and behaviours over custom chrome; restraint over decoration.
5. **Never block on the network.** Show what's already known at once; read the rest quietly.

## Accessibility & Inclusion

Keep what's there: VoiceOver labels and actions on the progress line and controls, Reduce Motion fallbacks (crossfades
instead of the cover develop-in, the cover flip and other motion), and keyboard dismissal with Escape. No further
standard has been set.
