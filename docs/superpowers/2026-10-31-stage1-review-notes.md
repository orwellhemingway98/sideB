# Spindle stage 1 — review notes

Decisions taken during the build and findings deferred to later stages, kept from the build ledger.

## Rulings

- Task 5: Ruling: StubFetcher's unsynchronised state races under Task 7's two-at-a-time refreshAll — Task 7's implementer adds a lock to StubFetcher as part of Task 7 — cost if wrong: a flaky test
- Task 8: Ruling: 'Unavailable' set after opening the next episode would sit on a healthy episode — clear failure on the next episode's first onTime (test still sees it right after the skip) — cost if wrong: message flashes briefly
- Task 8: Ruling: remove "played → start at 0" (controller decision) — markPlayed already zeroes position, so finished episodes still start at 0 and replays resume — cost if wrong: a fully-played episode reopened mid-replay resumes instead of restarting
- Task 10: Ruling: keep the mandated scroll monitor but guard it (own window, visible, inside the disc circle) and remove it on panel close — an overlay NSView would steal the disc's clicks — cost if wrong: one more monitor to maintain
- Task 10: Ruling: rotate sign = +1 (SwiftUI positive Angle is clockwise), one named constant, confirmed in Task 11's hand check — cost if wrong: flip one constant
- Task 11: Ruling: the plan's hand-check step needs the author's trackpad and eyes — implementer does wiring, tests, build and a launch smoke test; the feel/look check happens with the author after the final review — cost if wrong: none, it's the same check later
- Task 11: Ruling: use NSApp.activate(ignoringOtherApps: true) for the Library and the startup alert, overriding the plan's "NSApp.activate()" — the spec/constraint outcome is "activates the app"; ClickWheel needed the same — cost if wrong: one deprecation warning
- Task 11: Ruling: add a right-click menu on the strip (Open Library…, Quit Spindle) — spec gives no way to quit a Dock-less app; plan gap — cost if wrong: a small extra menu the author may want elsewhere
- Final: Ruling: I2 — in the last 30 s an episode is marked played and its place reset, but playback continues; Up Next advances only on onEnd; pausing/switching inside the window still counts as played — the spec's "counts as played" is about the place, not cutting audio; nobody wants endings clipped — cost if wrong: one condition to flip back
- Final: Ruling: parked — a reload (offline/dead link) inside the last 30 s restarts the episode from 0 — rare (tail usually buffered); fix in stage 2 with a load(_:at:) variant — cost if wrong: re-hearing an episode's start after a network drop in its final seconds
- Final: Ruling: parked — seeking back after a real onEnd keeps the episode marked played — matches the existing replay-after-finish behaviour; revisit with stage 2's played/unplayed controls — cost if wrong: an episode shows as played while partly re-listened

## Deferred minors

- Task 1: minor (deferred): TimeFormat has no tests for NaN/infinity guard or fractional-second flooring
- Task 1: minor (deferred): remaining() of a negative value gives "−0:00"
- Task 2: minor (deferred): DialEngine assumes a non-decreasing clock (comment it)
- Task 2: minor (deferred): chapter just behind the old position doesn't suppress the next tick (near-double bump)
- Task 2: minor (deferred): no tests for backward chapter order, window edge, clamped-end detents
- Task 3: minor (deferred): no test just under 35 ms (0.0349) for the limiter
- Task 4: minor (deferred): bare HTML entities like &nbsp; still make XMLParser reject a feed
- Task 4: minor (deferred): untested published/summary fallback/image-url precedence/enclosureType/namespace collisions
- Task 4: minor (deferred): raw child tags in description keep only trailing text; <rss> with no channel returns empty title; duration "0" → 0; chapters unsorted
- Task 5: minor (deferred): no test for empty-JSON fall-through or sort inside load; negative/NaN startTime not rejected; all locales passed as preferred languages
- Task 6: minor (deferred): one malformed item fails the whole search response; force unwraps on constant base URL
- Task 6: minor (deferred): addingPercentEncoding ?? "" would silently send an empty term
- Task 7: minor (deferred): save()/fetch errors swallowed (try?) — at least log; relationships set before insert; untested: played/localFile kept on refresh, nil dates last, follow-twice doesn't refetch
- Task 7: minor (deferred): savePosition notifies observers on every call — fine at the 5 s cadence, don't call it per tick
- Task 8: minor (deferred): Swift 6 isolation of AVPlayerEngine deinit; isFinished falls back to feed duration before ready; untested toggle/skip clamps/seek save/double-finish guard
- Task 8: minor (deferred): failed resume seek can leave awaitingResume set until the user seeks; stale seek completion can clear seekOutstanding for a newer load (player guard filters it); doc comment misplaced above `generation`
- Task 9: minor (deferred): MediaCenter returns .success with no episode / commands always enabled; episode-change publish uses position 0; FakeHaptics in FakeMediaCenter.swift; untested .seek/.rate commands, jump clamp, published subtitle
- Task 10: minor (deferred): failed artwork never retried; show(below:) doesn't clamp the bottom edge; DialPanel.swift at ~280 lines holds view+window+controller
- Task 10: minor (deferred): reopening with pointer already over the disc leaves scroll-to-turn dead until the pointer moves (carried into Task 11 as cheap fix)
- Task 11: minor (deferred): last-episode restore faults all episodes and matches guid across shows; local click monitor will need care for future popovers; feed parsing runs on the main actor; LibraryStore.follow maps offline to invalidFeed
- Task 11: minor (deferred): Ctrl-click toggles the panel instead of opening the right-click menu

## To check by hand

- Task 5: ⚠️ resolved — Chapter is Codable, Equatable (Task 4), GREEN run confirms init(start:title:)
- Task 10: ⚠️ for the hand check: onHover in non-activating panel, glass centre button vs tap/drag, chapter Menu glass label, glass in status item, panel auto-resize, white ring contrast on light wallpaper, rotate direction
- Task 11: ⚠️ for the author: a real click on Library must bring the window forward with keyboard focus (ignoringOtherApps may be a no-op on macOS 14+; fallbacks noted)
- Final: minor (deferred, leave): no ATS exception for http feeds (rare); trackpad momentum may keep scrubbing (⚠️ check); unused refresh(_:)/skip(by:); inMemory in app target; duplicated clamp/progress maths; misplaced doc comment
