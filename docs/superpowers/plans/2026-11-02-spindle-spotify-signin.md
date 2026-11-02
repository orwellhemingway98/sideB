# Spotify sign-in — implementation plan

> Executed inline (native) in the session; the author said "build it" after approving the spec.

**Goal:** Spotify songs list their album or playlist once the author signs in.
**Spec:** `docs/superpowers/specs/2026-11-02-spindle-spotify-signin-design.md`
**Architecture:** synchronous, lock-guarded Spotify client (MusicSource calls already run off the main actor),
pure auth and JSON parsing, a main-actor `SpotifyAccount` for the UI. Playback stays AppleScript.

## Global constraints

- macOS 26, Swift 5 mode, XcodeGen; tests via `./scripts/test.sh`, never touching the network or Keychain.
- No SF Symbols / Apple artwork. No push without asking. Version 0.6.0 / build 12.

## Review focus

1. A token refresh that fails on the network must not sign the author out (only a 400/401 from Spotify does).
2. A read finishing after sign-out or a song change must not show stale rows (ListModel generation already).
3. Playlists the author doesn't own: `items` absent or 403/404 → the song's album, and the hint follows.
4. Episodes, local files and null items inside playlists are skipped, never crash.
5. Not signed in: no Web API call at all.

## Tasks

### Task 1: Auth — `Spindle/Spotify/SpotifyAuth.swift`, `SpotifyTokenStore.swift`, `SpotifyClient.swift`
- `SpotifyTokens {accessToken, refreshToken, expiresAt}` (Codable).
- `SpotifyAuth`: `makeVerifier()`, `challenge(for:)`, `makeState()`, `authorizeURL(clientID:challenge:state:)`,
  `code(from:state:) throws`, `tokenRequest(code:verifier:clientID:)`, `refreshRequest(refreshToken:clientID:)`,
  `tokens(from:previous:now:) throws`.
- `SpotifyTokenStore` protocol; `KeychainTokenStore`, `MemoryTokenStore`.
- `HTTPTransport` protocol (`send(_:) throws -> (Data, HTTPURLResponse)`), `URLSessionTransport`.
- `SpotifyClient`: `isSignedIn`, `exchange(code:verifier:)`, `signOut()`, `get(_:) throws -> Data?` (nil on 204),
  refresh within 60 s of expiry or on 401 (once), 429 waits Retry-After once, `onSignedOut(expired:)`.
- Tests `SpotifyAuthTests`, `SpotifyClientTests`: RFC 7636 vector; URL query; state mismatch/denied; decoding keeps
  old refresh token; refresh before expiry; 401 retry; 400 on refresh → signed out + expired; network error on
  refresh keeps tokens; 429 retry.

### Task 2: Reading — `SpotifyContextParser.swift`, `SpotifyWebAPI.swift`
- Parser: `playing(from:)`, `contextKey(_:unreadable:)`, `albumPage`, `playlistPage`, track mapping with
  `spotify:track:` ids, `is_local`/non-track/null items skipped.
- `SpotifyWebAPI(client:)`: `contextKey() throws -> String?`, `context() throws -> MusicContext?` with paging
  (cap `MusicContextParser.cap`), playlist fallback to album, remembers unreadable playlists.
- Tests `SpotifyWebAPITests` with JSON fixtures through a fake transport.

### Task 3: Source and list — `SpotifySource.swift`, `ListModel.swift`, `ListContent.swift`
- `SpotifySource(api:)` implements `contextKey`, `context`, `play(trackID:in:)` (`playScript(trackID:contextID:)`).
- `ListModel(spotify:)`: signed out → `.spotify`; signed in → the `.music` path; key includes sign-in;
  "Couldn't read the album from Spotify."; hint "Spotify ⌄" only while no context kind.
- Tests in `ListContentTests`, `SpotifySourceTests`.

### Task 4: UI and wiring — `SpotifyAccount.swift`, `ListWindow.swift`, `AppDelegate.swift`, `project.yml`
- `SpotifyAccount` (main actor): `isSignedIn`, `expired`, `isSigningIn`, `clientID`, `signIn()`, `signOut()`;
  `authenticate` injectable (default `ASWebAuthenticationSession`); Client ID asked with an `NSAlert` text field.
- List: Sign in button + expired line; "Reading Spotify…"; Sign out footer under a Spotify list; reload on account
  changes.
- Tests `SpotifyAccountTests` (fake authenticate + transport). Version 0.6.0 / 12.
