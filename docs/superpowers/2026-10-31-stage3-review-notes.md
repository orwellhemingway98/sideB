# Spindle stage 3 — review notes

Decisions taken during the music and floating-dial build and findings left for later, kept from the build ledger.

## Rulings

- | T5 → T6 | FloatingDialController, DialPlacement, onPopOut on the panel | DialPanelController init gains onPopOut — Ruling P1 |
- Ruling P1: DialPanelController/DialPanelView gain an optional onPopOut closure (nil hides the pill) so existing construction compiles until Task 6 wires it — cost if wrong: one optional parameter
- Task 2: Ruling: MusicRemote exposes lastCommand (Task) so tests and callers can await a command, as ClickWheel's PlayerHub does — not in the plan's interface — cost if wrong: one extra property
- Task 3: Ruling: NowPlaying also gains displayDuration (the dial's length in either mode), which Task 4's views need — not in Task 3's interface — cost if wrong: none
- Final: Ruling: I2 — add a "Resume <episode>" pill in music mode when a podcast is open, which plays it (and so pauses the music) — the spec's "until a podcast is started again" needs a way to start it from the dial — cost if wrong: one pill to remove
- Final: Ruling: M4 glyph mirroring and M7 grab-bar hit area are visual fixes with no failing-first test — checked by hand — cost if wrong: a glyph or a grab area to tweak

## Deferred minors

- Final: minor (deferred): M1 a command's own refresh can be skipped (≤1 s lag); M5 permission granted later needs a relaunch; M6 floating dial frame not kept on screen after a display change; M8 floating panel can't become key (check first-click on screen); M9 music ring steps once a second; M10 ad-hoc signing makes TCC re-ask after rebuilds; M12 dead appName, double blank line, thin fallback test
