# Spindle stage 2 — review notes

Decisions taken during the Library build and findings left for later, kept from the build ledger.

## Rulings

- | T9 (self) | LibrarySection.show(PersistentIdentifier) replaces stage 1's selectedShow; existing LibraryViewModelTests use selectedShow | Ruling P1 |
- | T10 → T9 | view model needs DownloadManager + RefreshScheduler | T9's init gains them; Ruling P1 covers |
- Ruling P1: T9 keeps `selectedShow` as a computed bridge onto `section` (.show(id)) so stage 1's tests and callers keep working; LibraryViewModel.init gains `downloads: DownloadManager? = nil, scheduler: RefreshScheduler? = nil` defaults so existing tests compile — cost if wrong: one redundant property
- Task 9: Ruling: an import that finds nothing reads "No shows found in that file." — the plan's "leave out zero parts" left an empty string — cost if wrong: one line of copy
- Task 9: Ruling: the sidebar keeps a "Following" list of shows by title (with the broken-feed note) under the four sections — stage 1's per-show error note needs a home and the grid has no room for it — cost if wrong: a longer sidebar
- Task 9: Ruling: the view model takes downloads/scheduler/artwork as optional init parameters (P1) — stage 1 tests build it without them — cost if wrong: views hide the download control when nil
- Final: Ruling: M11 version bump to 0.2.0 happens at merge/tag time, not in the fix pass — cost if wrong: none
- Final: Ruling: I2 query cost fixed with store-side predicate/sort/limit but has no failing-first test (speed, not behaviour); behaviour pinned by the existing newEpisodes/downloaded tests — cost if wrong: the Library may still feel slow with a huge library
- Final: Ruling: M2 strong capture of the episode in the download completion has no failing-first test (release timing can't be forced) — cost if wrong: a rare stuck "Downloading 100%"
- Final: Ruling: NSAllowsArbitraryLoadsForMedia added so plain-http episodes can stream; downloads still go over https only — the narrowest ATS relaxation — cost if wrong: one Info.plist key
- Final: Ruling: stage 1's testFailedRefreshRecordsErrorOnceAndSuccessClearsIt now simulates a server error instead of being offline, since offline is quiet per spec — cost if wrong: none

## Deferred minors

- Task 9: minor (deferred): SpindleTests/Support/StubFetcher.swift uses lock()/unlock() in async code (Swift 6 warnings, from stage 1)
- Final: minor (deferred): M1 cancel+redownload race; M3 extension from URL path; M4 identity compare in cleaner; M5 progress floods main actor; M6 one bad XML entity rejects the whole OPML; M8 context-menu played marks bypass the player for the current episode; M9 played vs unplayed look the same; M10 dead selectedShow setter/refresh(_:)/unreachable placeholder, LibraryStore 328 lines; M12 URLSession retains its delegate (comment); M13 app-modal open panel; M14 v0.1.0-played episodes have no playedAt so their downloads never clean up; M15 OPML de-dupes by exact string
