# Memorise — Round 12 Plan: playback controls in the Lyrics tab, no jump to Spotify

- **Date:** 2026-11-18
- **Source:** the owner's request on 2026-11-18 (§1).
- **Owner of this file:** the planner. The implementor runs PC1 and the frontend runs PC2. Both tick the tracker (§3).
- **Conventions:** `CLAUDE.md` and PLAN.md §16 apply.
  - Pure request building and decoding stay in `MemoriseCore`, which imports only Foundation. Networking stays in the App target.
  - Never hand-edit the `.xcodeproj`. Record every deviation in PLAN.md §17.
  - **No wire changes.** Nothing new is persisted.
  - **No new Spotify scopes.** `user-modify-playback-state` and `user-read-playback-state` are already requested.
- **Commits:** one segment = one commit, with the message given in the segment. Stage **only** the files that segment touches. Never stage the QA agent's uncommitted files (`App/Tests/`, `project.yml`, `docs/TEST_COVERAGE.md`, `.github/workflows/core-tests.yml`, the test files in `MemoriseCoreTests`).
- **Tests:** none in this plan. The tester owns tests. Acceptance criteria are for the tester and the owner.

---

## 1. Findings

| ID | Owner request | What the code does today | Segment |
|---|---|---|---|
| **H1** | Track controls in the Lyrics tab, e.g. pause a song to read the lyrics. | There are none. The home card and the reader only *show* what's playing (R10 LA4, LA5). | **PC1** (API), **PC2** (UI) |
| **H2** | The first time you tap a song, the app switches to Spotify. Don't do that. | `SpotifyClient.play` sends `PUT /me/player/play` with no device. When no Spotify device is **active**, which is typical on the first tap after a while, Spotify answers `404 NO_ACTIVE_DEVICE`. The client then calls `openURL("spotify:track:…")`, which leaves the app. Usually the phone *is* still a Spotify Connect device; it's just not the active one. `GET /me/player/devices` lists it, and `PUT /me/player/play?device_id=<id>` starts it without leaving Memorise. | **PC1** |

**Limit to know about (owner):** the Web API can only start playback on a device that Spotify knows about. If the Spotify app isn't running at all (force-quit, or iOS has suspended it for a long time), there's **no device** and no API call can wake it. In that case Memorise **no longer switches apps by itself**. It shows "Spotify isn't open on any device" with an **Open Spotify** button. That jump happens only if you tap the button, and after it you come back and tap ▶ in Memorise.

### Decisions

| ID | Decision | By | Status |
|---|---|---|---|
| **P-10** | Memorise **never opens the Spotify app on its own**. With no active device it picks an available device, preferring this phone, and plays there. With no device at all, it shows a notice with an **Open Spotify** button. | planner (owner request) | decided |
| **P-11** | Controls are **previous · play/pause · next**, on the Lyrics home "Now playing" card and in the reader. No seek bar, volume or shuffle (the static-lyrics rule L-D1 makes seeking of little use). | planner | decided |
| **P-12** | **Amends P-6.** The reader gets one bottom **player bar** in place of the header "Playing / Paused" chip. The bar's content depends on what Spotify is doing:<br>• **the open song** → the three controls;<br>• **another song** → that song, play/pause and **Show lyrics** (tap to switch, never auto-follow, as the owner confirmed);<br>• **nothing** → **▶ Play this song**. | planner | decided |
| **P-13** | A song started from a **playlist** or from **Liked** plays *in that context*, so next and previous follow the list. Songs from Recent and search play on their own, as today. If Spotify refuses the context, retry once with the song alone. | planner | decided |

---

## 2. Coverage map

| Finding | Segment | Agent |
|---|---|---|
| H2 (device pick, no auto-open), H1 API (pause, resume, next, previous, context play), shared player state | **PC1** | implementor |
| H1 UI (controls on the home card and the reader bar, the no-device notice) | **PC2** | frontend |

---

## 3. Tracker

| Segment | Covers | Agent | Status | Notes |
|---|---|---|---|---|
| PC1 Player API: device pick, controls, context play, no auto-open | H1, H2, P-10, P-13 | implementor | ☑ | First |
| PC2 Controls on the home card and the reader player bar | H1, P-11, P-12 | frontend | ☐ | After PC1 |

---

## 4. Segments

### PC1 · H1, H2 · Player API: device pick, controls, context play, no auto-open

**Agent:** implementor.

**Commit:** `R12-PC1: play on an available Spotify device instead of opening Spotify; pause, resume, next, previous`

**Files:**
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/SpotifyRequests.swift`
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/SpotifyModels.swift`
- `App/Sources/Services/Lyrics/SpotifyClient.swift`
- `App/Sources/Services/Lyrics/NowPlayingMonitor.swift`
- `App/Sources/Features/Lyrics/LyricsHomeViewModel.swift`
- `App/Sources/Features/Lyrics/LyricsHomeView.swift` (**only** to pass a `PlayContext` into `TrackList`, step 6)
- `PLAN_M6_LYRICS.md` §4.9 (wording)

**Steps:**
1. **Core, `SpotifyRequests` (pure; all ids checked with `isValidID`):**
   - `play(trackID:context:deviceID:token:)` replaces `play(trackID:token:)`:
     - `PUT /me/player/play`, plus `?device_id=<id>` when given.
     - Body `{"uris":["spotify:track:<id>"]}` for `.none`.
     - Body `{"context_uri":"<uri>","offset":{"uri":"spotify:track:<id>"}}` otherwise.
     - Keep a `play(trackID:token:)` overload that forwards with `.none` if tests use it.
   - `resume(deviceID:token:)`: `PUT /me/player/play` with **no body** (optional `device_id`).
   - `pause(token:)`: `PUT /me/player/pause`.
   - `next(token:)`: `POST /me/player/next`.
   - `previous(token:)`: `POST /me/player/previous`.
   - `devices(token:)`: `GET /me/player/devices`.
   - `transfer(deviceID:play:token:)`: `PUT /me/player` with body `{"device_ids":["<id>"],"play":true}`.
   - Every `PUT`/`POST` without a JSON body sends `Content-Length: 0` (Spotify rejects some empty `PUT`s otherwise).
   - Delete `trackURI(_:)` **only if** nothing else uses it. `openSpotifyApp` (step 3) uses the plain `spotify:` URL.
2. **Core, models:**
   - `public enum PlayContext: Hashable, Sendable { case none, playlist(id: String), likedSongs(userID: String) }`, with `var uri: String?`:
     - `.playlist` → `"spotify:playlist:<id>"`;
     - `.likedSongs` → `"spotify:user:<userID>:collection"`;
     - `.none` → `nil`.
   - `public struct SpotifyDevice: Decodable, Hashable, Sendable { id: String?; isActive: Bool; isRestricted: Bool; name: String; type: String }` (snake_case keys, tolerant: missing booleans → `false`). Add `SpotifyDecoder.devices(_:) -> [SpotifyDevice]`.
   - `public enum SpotifyDevicePick { static func pick(_ devices: [SpotifyDevice]) -> String? }`. Skip devices with a nil id or `isRestricted`. Then prefer, in order:
     1. `isActive`;
     2. `type == "Smartphone"` (this phone, normally);
     3. the first remaining device.
3. **`SpotifyClient`:**
   - `PlayOutcome` becomes `.playing`, `.noDevice`, `.notPremium`, `.failed(String)`. **`.openedSpotify` is removed**, and `play` never calls `openURL`.
   - `func play(trackID: String, context: PlayContext) async -> PlayOutcome`. At most **4 requests**:
     1. Play with the context.
     2. On `404` with reason `NO_ACTIVE_DEVICE` (or no reason): `devices` → `SpotifyDevicePick.pick`. With an id, play again with `device_id`. Without one → `.noDevice`.
     3. On `400`, or a `404` with another reason, **when the context isn't `.none`** (P-13): retry once with `.none`, keeping the device id if one was picked.
     4. `403` with reason `PREMIUM_REQUIRED` (or no reason) → `.notPremium`. Other errors → `.failed(message)`.
   - New controls, each `async -> PlayOutcome`, sharing one private `command(_:)` helper:
     - `pause()`
     - `resume()`: on `NO_ACTIVE_DEVICE`, use `devices` → `pick` → `transfer(deviceID:play: true)`, or `.noDevice`.
     - `next()`
     - `previous()`

     A `403` whose reason is **not** `PREMIUM_REQUIRED` (Spotify's "restriction violated", e.g. pausing something already paused) is treated as `.playing`, i.e. success. The caller refreshes the state anyway.
   - `func openSpotifyApp() async`: `openURL(URL(string: "spotify:")!)`. It's called **only** from the notice button (P-10).
4. **`NowPlayingMonitor` becomes the shared player** (both screens already use it):
   - New observable state:
     - `private(set) var notice: PlayerNotice?`, with `enum PlayerNotice: Equatable { case noDevice, notPremium, failed(String) }`;
     - `private(set) var commandInFlight = false`;
     - `private(set) var switching = false` (true after next or previous until the track changes or 3 s pass).
   - `func play(_ track: TrackInfo, context: PlayContext) async`, `togglePlayPause() async`, `skipNext() async`, `skipPrevious() async`, `dismissNotice()`.
   - **Optimistic update:**
     - Play/pause flips `isPlaying` in `state` at once.
     - Bump a `commandStamp`, so a `refresh()` that started **before** the command can't write its stale answer. Record the stamp at the start of `refresh` and drop the result if it changed.
     - Then call `refreshSoon(after: 0.8 s)`.
     - On failure, undo the flip and set `notice`.
     - Next and previous set `switching = true` and refresh after 0.8 s and again at 2 s. `switching` ends when the track id changes or after 3 s.
   - `commandInFlight` ignores taps while a command runs (no queue).
   - `reset()` also clears `notice` and `switching`.
5. **`LyricsHomeViewModel`:**
   - `open(_:play:)` → `open(_:play:context:)`. It pushes the reader first (unchanged), then `Task { await nowPlaying.play(track, context: context) }`.
   - Delete the `PlayOutcome` → `notice` mapping from the home VM. Notices now live in `NowPlayingMonitor.notice`, so the reader shows them too. Delete the strings "Opened in Spotify." and "…Press play in Spotify."
   - `context(for source:) -> PlayContext`:
     - Recent → `.none`;
     - search → `.none`;
     - Liked → `.likedSongs(userID:)` when `spotify.userID` is known, else `.none`;
     - an open playlist → `.playlist(id:)`.
6. **`LyricsHomeView` (one change):** `TrackList` gets a `context: PlayContext` property, and each call site passes `model.context(for:)` (the playlist screen passes `.playlist(id: playlist.id)`). Row taps call `model.open(track, play: true, context: context)`. PC2 owns the rest of the view.
7. **Docs:** in PLAN_M6 §4.9, replace "no active device → open the Spotify app" with P-10. Add the controls and the context rule.

**Acceptance (for the tester, with a stub `HTTPClient`):**
- **Request bodies:**
  - `.none` → `{"uris":[…]}`.
  - `.playlist("abc")` → `context_uri` `spotify:playlist:abc` with `offset.uri`.
  - `.likedSongs("u1")` → `spotify:user:u1:collection`.
  - Invalid ids → `nil`.
  - `device_id` is in the query only when given.
- **`SpotifyDevicePick`:**
  - `[restricted active phone, inactive computer]` → computer.
  - `[inactive computer, inactive Smartphone]` → Smartphone.
  - `[active computer, inactive Smartphone]` → computer.
  - `[nil-id device]` → `nil`.
- **`play`:**
  - 204 → `.playing` (1 request).
  - 404 `NO_ACTIVE_DEVICE`, then devices `[phone]`, then 204 → `.playing`, the last request has `device_id`, and `openURL` is **never** called.
  - 404 `NO_ACTIVE_DEVICE`, then devices `[]` → `.noDevice`, and `openURL` is never called.
  - Playlist context, then 400, then 204 → `.playing`, and the second body is `uris`.
  - 403 `PREMIUM_REQUIRED` → `.notPremium`.
  - Never more than 4 requests.
- **Controls:** `pause` → `PUT …/pause`. A `403` restriction-violated → `.playing`. `resume` with no active device → `transfer` with `play: true`.
- **`NowPlayingMonitor`:**
  - `togglePlayPause` flips `isPlaying` before the request completes.
  - A refresh that started before the command doesn't overwrite the flip.
  - A failed command restores the old state and sets `notice`.
  - A second tap while `commandInFlight` sends no request.
- **On device (owner):**
  - With Spotify running in the background but paused for a while, tap a song in Memorise. It plays and **Memorise stays on screen**.
  - Force-quit Spotify and tap a song. The notice "Spotify isn't open on any device" appears with **Open Spotify**, and nothing switches apps unless you tap it.
  - A song started from a playlist: **next** plays the playlist's next song.

---

### PC2 · H1 · Controls on the home card and the reader player bar

**Agent:** frontend. **After PC1.**

**Commit:** `R12-PC2: previous, play/pause and next on the Lyrics home card and in the reader`

**Files:**
- `App/Sources/Features/Lyrics/PlayerControls.swift` (**new**)
- `App/Sources/Features/Lyrics/LyricsHomeView.swift` (`NowPlayingCard`, the notice)
- `App/Sources/Features/Lyrics/ReaderNowPlayingBar.swift` (becomes `ReaderPlayerBar`; delete `ReaderPlayingChip`)
- `App/Sources/Features/Lyrics/LyricsReaderView.swift`

**Steps:**
1. **`PlayerControls` (new):** one row of three buttons: `backward.fill`, `play.fill`/`pause.fill`, `forward.fill`.
   - Each button is ≥ 44 × 44 pt. Play/pause is the largest (a 52 pt circle in `Subject.korean.gradient`, white glyph); previous and next are plain glyphs in `.primary`.
   - Inputs: `isPlaying: Bool`, `disabled: Bool` (= `commandInFlight`), `showsSkip: Bool`, and the actions.
   - The play/pause glyph switches with `.contentTransition(.symbolEffect(.replace))`.
   - Light haptic: `.sensoryFeedback(.impact(weight: .light), trigger:)` on each tap.
   - While `switching`, the next and previous glyphs are dimmed.
   - Accessibility labels "Previous", "Play"/"Pause", "Next". Identifiers `lyrics.player.previous`, `lyrics.player.toggle`, `lyrics.player.next`.
   - Add a `#Preview` (playing, paused, disabled).
2. **Home `NowPlayingCard`:**
   - In the loaded state with a track, add a `PlayerControls` row (with skip buttons) under the title row, centred.
   - **Delete the ↻ refresh button**: polling (LA4) and pull-to-refresh cover it. Keep **Open**.
   - Wire the actions to `env.nowPlaying.togglePlayPause()`, `.skipNext()` and `.skipPrevious()`.
   - "Nothing playing" shows no controls (nothing to resume).
   - While `switching`, the title shows a small `ProgressView` in place of the "Now playing" label.
3. **Player notice:** a shared `PlayerNoticeBanner` (reusing today's `NoticeBanner` look) shows `env.nowPlaying.notice`:
   - `.noDevice`: "Spotify isn't open on any device. Open it once, then tap ▶ here." with a button **Open Spotify** (calls `spotify.openSpotifyApp()`, identifier `lyrics.player.openSpotify`).
   - `.notPremium`: "Spotify needs Premium to control playback from here."
   - `.failed(text)`: `text`.

   The ✕ button calls `dismissNotice()`. It's shown under the home card and above the reader's player bar. Delete the old `model.notice` banner on Home if PC1 removed its source.
4. **Reader player bar (P-12):** rename `ReaderNowPlayingBar` → `ReaderPlayerBar`. It's always present in `.safeAreaInset(edge: .bottom)` while Spotify is connected and the monitor has loaded:
   - **The open song is playing or paused** (`model.isShowing(playback)`): a compact bar with `PlayerControls` (with skip), the title on one line to its left, and no artwork, so the bar stays short.
   - **Another song:** today's layout (artwork, "Now playing"/"Paused", title, artist, **Show lyrics**) plus a play/pause button (no skip) between the text and **Show lyrics**.
   - **Nothing playing:** a single button, **▶ Play this song** (identifier `lyrics.player.playThis`), that calls `env.nowPlaying.play(model.track, context: .none)`.
   - **Failed or loading:** hidden (as today).
   - Delete `ReaderPlayingChip` and its use in the header.
   - Keep the transitions and Reduce Motion handling from LA5. The toast still sits above the bar.
5. Previews: the home card playing and paused; the reader bar in all three states; the no-device notice.

**Acceptance (owner on device):**
- **In the reader:** tap ⏸. Spotify pauses within about 1 s, the icon flips at once, and Memorise stays on screen. Tap ▶ and it resumes.
- **⏭ and ⏮ on the home card:** the card shows the new song within about 2 s. In the reader, the bar then shows "another song" with **Show lyrics**, and it doesn't switch on its own.
- **In a reader with nothing playing:** **▶ Play this song** starts that song without leaving Memorise (while Spotify is running in the background).
- **Spotify force-quit:** any control shows the no-device notice. Only **Open Spotify** switches apps.
- Double-tapping ▶/⏸ quickly sends one command (no flip-flop).
- VoiceOver reads "Previous", "Pause", "Next".

---

## 5. Notes for the owner

- Memorise no longer switches to Spotify on its own. The one case it can't handle is Spotify not running anywhere; then you get an **Open Spotify** button, and after one trip you control everything from Memorise.
- Songs started from a playlist or from Liked keep playing through that list, so ⏭ goes to the next song in it.
