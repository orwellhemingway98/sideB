# Spindle big cover and list window — review notes

Decisions taken while building the cover and list window, and findings left for later.

## Rulings

- Task 1: Ruling: an album row queues the whole album and starts at the clicked song (ClickWheel's queue), not only 'from that track on' — ⏮ then reaches earlier songs — cost if wrong: the playlist holds songs before the start
- Task 1: Ruling: durations parse with ',' or '.' since AppleScript writes the system locale's decimal — cost if wrong: none
- Task 3: Ruling: musicLoading and musicMessage carry the trackID (plan had no payload) so identity can be "loading:<id>" / "song:<id>" — cost if wrong: none
- Task 3: Ruling: ListModel takes an optional loadContext closure (defaults to MusicRemote.context) so the stale-read test can hold a read open — cost if wrong: one init parameter
- Task 4: Ruling: the panel with a podcast and one Up Next row measures about 644 pt tall, not the spec's estimated ~560 — every element is as specified; it still fits a 13-inch screen below the menu bar — cost if wrong: trim spacing
- Task 5: Ruling: PanelClickPolicy also takes the panel's anchor (the status bar window) — the existing monitor already exempted it — cost if wrong: one parameter
- Task 5: Ruling: Escape goes to the list first through a DialPanelController.escapeHandler hook (closes only the list); the panel closes on the next Escape — cost if wrong: Escape takes two presses to close both
- Task 5: Ruling: the list controller itself reloads ListModel on NowPlaying changes (debounced 0.3 s while shown), instead of AppDelegate (plan Task 6) — keeps the list's upkeep in one place — cost if wrong: none
- Task 5: Ruling: placed below the panel, the list window also covers the 12 pt gap so the falling drop is visible; the morph runs inside the window (two windows can't morph into each other) — cost if wrong: the drop starts at the window's top rather than inside the panel
- Final: Ruling: I5 (list detaches before the panel hides) and I6 (bulk Music read) have no failing-first unit test — AppKit child-window timing and live AppleScript can't run in tests; checked by reading and by hand — cost if wrong: the list may reappear with the panel, or reads stay slow
- Final: Ruling: the cheap "which list" script runs once per new song (inside the poll) and on every list read — the price of correct hints and contexts — cost if wrong: one short Apple event burst per song

## Deferred minors

- Final: minor (deferred): stale contextFailed with overlapping reads (mitigated by shared in-flight reads); folder/subscription playlists fall back to album; podcast reload cost while playing (now keyed); songs past the 500 cap never highlighted; accessibility label reads the ⌄ glyph; panel may exceed a 1280×800 screen with 3 Up Next rows (check)
