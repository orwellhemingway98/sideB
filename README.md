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
