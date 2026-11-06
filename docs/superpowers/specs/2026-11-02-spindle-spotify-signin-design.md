# Spindle — Spotify sign-in

Piece 2 of the cover and list work (see `2026-11-01-spindle-cover-and-list-design.md`). Today a Spotify song's
list shows only its details and "Sign in to Spotify to see the album and playlist." After this, the author signs
in once and Spotify songs list their album or playlist like Apple Music songs do.

## Intent

- **Who it's for:** the author, who has Spotify Premium and registers a free Spotify developer app themself.
- **What it must get right:**
  - Signing in happens once; the login refreshes itself.
  - The list behaves exactly like Apple Music's: current song highlighted, click a song to play it in context.
  - No secret is shipped in the app and no Spotify data leaves the Mac except calls to Spotify.

## Platform and constraints

- **Unchanged:** macOS 26, Swift 5 mode, no SF Symbols or Apple artwork in our controls, nothing pushed unless
  the author asks. Playback control stays AppleScript, except for playing a row (below); Spindle never scripts an app that isn't running.
- **Spotify's rules (February 2026 Development Mode, checked 2026-11-02):**
  - The app owner needs Premium; at most 5 users may sign in.
  - `GET /playlists/{id}/items` only returns songs for playlists the user owns or collaborates on. For others,
    `items` is absent.
  - Batch endpoints are gone; single-item endpoints (`/albums/{id}`, `/albums/{id}/tracks`) remain.
  - Redirect URIs must be a loopback IP or a custom scheme. We use `spindle://callback`.

## What the author sees

- **Signed out, Spotify playing, list open:** the song details as today, then a glass **Sign in to Spotify**
  button in place of the note.
- **First sign-in:** a small sheet asks for the **Client ID** (one text field, Continue / Cancel), with a line:
  "Create a free app at developer.spotify.com/dashboard with redirect URI spindle://callback, then paste its
  Client ID." The ID is remembered; later sign-ins skip this step.
- **Then:** Spotify's own sign-in page opens in a system web sheet (`ASWebAuthenticationSession`). On approval
  the sheet closes and the list shows "Reading Spotify…", then the album or playlist.
- **Signed in:**
  - Album: every song, numbered, current one highlighted.
  - The author's own or collaborative playlist: its songs (cap 500, as Music), current one highlighted.
  - Anything else (Spotify's or other people's playlists, Liked Songs, radio, artist pages, no context): the
    song's album.
  - Clicking a song plays it and continues through that album or playlist.
  - The cover hint reads "Album ⌄" / "Playlist ⌄" from the context, like Music, instead of "Spotify ⌄".
  - A small **Sign out** text button sits at the bottom of the list.
- **Cancelled sign-in:** back to the button, no message.
- **Sign-in or refresh fails, or access is revoked:** tokens are cleared, the button returns with
  "Spotify sign-in expired." above it.
- **Network or Spotify error while reading:** "Couldn't read the album from Spotify." (same treatment as Music's).

## How it works

- **Auth:** Authorization Code with PKCE (S256), no client secret.
  - Scopes: `user-read-currently-playing user-read-playback-state user-modify-playback-state
    playlist-read-private playlist-read-collaborative`.
  - A random `state` is checked on return.
  - Info.plist registers the `spindle` URL scheme (`CFBundleURLTypes`) so the callback reaches the app.
- **Storage:** Client ID in UserDefaults (`spotifyClientID`); access token, its expiry and refresh token in the
  Keychain (generic password, service `com.mfelouro.Spindle.spotify`). Because the build is ad-hoc signed,
  macOS may ask once after a rebuild to let Spindle read its Keychain item; "Always Allow" settles it.
- **Tokens:** refreshed when within 60 s of expiry or on a 401 (one retry). A new refresh token in the reply
  replaces the old one.
- **Reading (only when signed in):**
  - `contextKey()`: `GET /me/player/currently-playing` → `context.type` + id → `"album:<id>"` /
    `"playlist:<id>"`; anything else, or no context → `"album:<the song's album id>"`. One call per song change
    (MusicRemote already calls it once per song). 204 (nothing playing) → nil.
  - `context()`: for an album, `GET /albums/{id}` then follow `tracks.next` pages (50 each). For a playlist,
    `GET /playlists/{id}/items` pages (50 each, up to 500, `market=from_token`); a 403/404 or missing `items`
    falls back to the song's album. Local files and episodes in a playlist are skipped.
  - Row ids are `spotify:track:<id>` (the same form AppleScript's `id of current track` gives), so
    `MusicContext.row(for:)` highlights the current song by id, then by title and artist.
  - 429: wait `Retry-After` once, then fail.
- **Playing a row (changed in 0.16.4):** first the Web API, `PUT /me/player/play` with
  `{"context_uri": "spotify:album:…", "offset": {"uri": "spotify:track:…"}}` (or playlist), because the AppleScript
  command brings Spotify's window forward. If that is signed out, refused or offline, AppleScript
  `play track "spotify:track:…" in context "spotify:album:…"`, so a click always plays the song, even with an older
  sign-in or no active Connect device.
- **Not signed in:** `SpotifySource` behaves as today (`contextKey`/`context` nil) and the list shows the button.

## Units

- **`SpotifyAuth`** (pure parts tested): builds the authorize URL (PKCE verifier/challenge, state), parses the
  callback URL, builds token and refresh requests, decodes token replies.
- **`SpotifyTokenStore`:** protocol with a Keychain implementation and an in-memory one for tests.
- **`SpotifyAccount`** (`ObservableObject`, main actor): `isSignedIn`, `expired`, `signIn(clientID:)`,
  `signOut()`, `validAccessToken() async throws`. Runs `ASWebAuthenticationSession`; takes an HTTP transport so
  tests use canned replies.
- **`SpotifyWebAPI`:** currently-playing, album and playlist reads, mapped to `MusicContext` by a pure
  `SpotifyContextParser` (JSON → `MusicContext`) that is tested on its own fixtures.
- **`SpotifySource`:** gains `contextKey()`, `context()` and `play(trackID:in:)` backed by the above (blocking
  calls are fine: MusicRemote already runs them off the main actor).
- **`ListModel` / `ListContent`:** Spotify goes through the same `.music` / `.musicLoading` / `.musicMessage`
  path as Music when signed in; `.spotify(track)` remains for signed-out, now with the button. Loading text
  "Reading Spotify…".
- **`ListWindow`:** the Sign in button, the Client ID sheet, the expired line, the Sign out footer.

## Testing

- **Automated (no network):**
  - PKCE challenge for a known verifier (RFC 7636 test vector); authorize URL query items; state mismatch rejected.
  - Token reply decoding; refresh keeps the old refresh token when none is returned.
  - Refresh before expiry and after a 401; a failed refresh signs out with `expired`.
  - Context key for album, playlist, collection/artist/nil contexts, and 204.
  - Album paging (two pages), playlist paging and the 500 cap, local files skipped, missing `items` → album
    fallback.
  - Row ids match the AppleScript id; highlight works.
  - The play script text for album and playlist contexts.
  - `ListModel`: signed out → `.spotify`; signed in → `.music`.
- **By hand (the author):** register the app, sign in, open an album, one of their playlists and a Spotify
  playlist (falls back to the album), click a song, sign out.

## Build order

One plan: auth (PKCE, token store, account) → Web API reads and parser → SpotifySource → list UI and sign-in
sheet → URL scheme and wiring → version 0.6.0.
