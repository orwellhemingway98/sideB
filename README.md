# Spindle

A contemporary listening companion for the Mac: a Liquid Glass dial in the menu
bar that you feel through the trackpad, and a podcast player done properly.
It plays podcasts itself and acts as a remote for Spotify and Apple Music.

Work in progress.

## Run it

Spindle needs macOS 26 (Liquid Glass) and Xcode 26.

```sh
brew install xcodegen
xcodegen generate          # makes Spindle.xcodeproj from project.yml
open Spindle.xcodeproj     # then Product › Run (⌘R)
```

Spindle lives in the menu bar (no Dock icon). Click its glass disc for the
dial; "Library" in the dial panel opens the Library window. Right-click the
disc for "Open Library…" and "Quit Spindle".

Run the tests with `./scripts/test.sh` (full log in `build.noindex/test.log`).

## The Library (stage 2)

Open the Library from the dial's **Library** pill, or right-click the menu bar strip and choose
**Open Library…**.

- **New Episodes:** everything unplayed from the shows you follow, newest first. Spindle checks
  for new episodes at launch and then every hour, or straight away with **Refresh**.
- **Shows:** your shows as covers. Click one to see its episodes.
- **Up Next:** drag to reorder, or take an episode out with **Remove**.
- **Downloaded:** episodes saved for listening offline. Choose **Download** on any episode.
  A download is removed a week after you've played the episode.
- **Import OPML…:** brings in the shows you follow in another podcast app. Export an OPML
  file from that app first (often under Settings or Library › Export).

