# Memorise — Round 9 Fix Plan (fixes for code review Round 8)

- **Date:** 2026-11-18
- **Source:** `CODE_REVIEW.md` **Round 8** (R8-1 … R8-10) and the Round 7 findings it lists as still open (R7-2 … R7-9).
  - The file is named R9 so it doesn't clash with `PLAN_R8_COVERAGE.md`, whose segments are also called S/F/C.
- **Owner of this file:** the planner. The implementor, frontend and content agents run the segments in §3 and tick the tracker (§2).
- **Conventions:** `CLAUDE.md` and PLAN.md §16 apply.
  - Domain logic stays in `MemoriseCore`, which imports only Foundation. Inject the RNG and clocks.
  - Persisted `Codable` types: every new property gets a default and is read in the hand-written tolerant `init(from:)`. Never rename keys or raw values.
  - **This plan has exactly one wire change:** a new `koreanTitleChecked` field in `LyricsCacheFile` (LF4). It is additive, and missing means `false`. `schemaVersion` stays `1`.
  - Scheduling constants live in `SchedulerConstants`. Update PLAN.md §10 when you add or tune one.
  - Never hand-edit the `.xcodeproj`.
  - Record every deviation in PLAN.md §17.
- **Commits:** one segment = one commit, with the message given in the segment. Stage **only** the files that segment touches. Other agents leave files uncommitted in the same tree. Right now the QA agent's test files and `.github/workflows/core-tests.yml` are uncommitted: **never stage them.**
- **Tests:** none in this plan, because the tester agent owns tests. Each segment lists acceptance criteria for the tester.
  - **Exception (LF1, LF2, SF3):** if a signature change breaks the build of an existing test target, update those call sites mechanically so `swift build --build-tests` still compiles. Don't add or change assertions.
  - **Known issues:** `LyricsTests.swift` (QA, uncommitted) wraps the R8-1 and R8-6 cases in `withKnownIssue`. Once LF1 and LF2 land, those blocks report "known issue did not occur". That is the tester's signal to remove them. The implementor leaves them alone.

---

## 1. Coverage map

| Review ID | Finding (short) | Segment | Agent |
|---|---|---|---|
| R8-1 | Genius returns another song by the same artist, and it's cached forever. `sameArtist` is too loose. | **LF1** | implementor (core + 1 app call site) |
| R8-6 | K-pop title suffixes aren't stripped, `(with …)` is over-stripped, and `+` isn't encoded | **LF2** | implementor (core) |
| R8-5 | 5-request budget too small for the two-title Genius path. A missing English page is cached forever. | **LF3** | implementor (core + app) |
| R8-4 | Opening a cached song still waits on Spotify `GET /tracks/{id}` | **LF4** | implementor (core + app) |
| R8-3 | Recent, Playlists and Liked never refresh, and they keep the old account's lists after a reconnect | **LF5** | implementor (app VM) |
| R8-7 | Playlists > 100 songs and > 50 playlists are cut off | **LF6** (client + VM), **UF1** (row) | implementor, frontend |
| R8-10 a b c e f h i j l | Keychain, refresh race, timeout message, 404 meaning, translation prompt, cache cap, preview defaults, id guard, cache clear | **LF7** | implementor |
| R8-10 d | `play` blocks before the reader opens | **LF5** | implementor |
| R8-10 k | Paused songs shown as "Now playing" | **LF5** (data), **UF1** (label) | implementor, frontend |
| R8-10 g | Single-word machine translation | — | No action unless the owner complains about gloss quality. |
| R8-8 | Lyric lines stored in user decks, which are exported; Genius scraping | — | **Already decided by the owner:** M6 decisions in PLAN.md §17 (personal use, Genius page-scrape accepted, L-D8 and L-D10 keep the line). The planner records this in §17. No code. |
| R8-2 / R7-1 | `HEAD` red, CI not running tests, no Lyrics tests | — | **Tester.** QA reports `HEAD` green (199 tests), with CI switched to `swift test` and a `LyricsTests` suite, waiting for the owner's commit. Not in this plan. |
| R7-2 | A new session can read stats before the previous flush | **SF1** | implementor (app) |
| R7-3 | Killed sessions count toward a missed card's gap | **SF2** | implementor (core) (planner decision P-1) |
| R7-6 | `history: nil` silently means "all due" | **SF3** | implementor (core) |
| R7-4 | 30 % review cap parks misses | **SF4** | implementor (core), owner decision O-1 (a) |
| R7-9 f | Mic "Correct" speech is still playing when the next prompt arms | **SF5** | implementor (app) |
| R7-7 | O(pool) per pick | **SF6** (optional) | implementor (core) |
| R7-5, R7-9 a b c d | Ring on every deck, "100 %" without ✓, unreachable identifier, mixed scopes, Stats coverage | **UF2** | frontend (planner decision P-2) |
| R7-9 e | PLAN_R8 tracker is stale | — | **Done by the planner in this commit** (S1, S2, C1, C2 ticked) |
| R8-9 / R7-8 | Verification rows lag behind the entries | **CF1** | content agent |

### Decisions

| ID | Decision | By | Status |
|---|---|---|---|
| **P-1** (R7-3) | A killed session counts as `.completed` (and so toward "sessions since a miss" and the baseline) only when it has **≥ 5 counted attempts** (`SchedulerConstants.minCountedForKilledSession = 5`). With fewer, it is closed as `.abandoned`. No wire change: it's the same `SessionStatus` values, set by a different rule. Sessions already closed under the old rule stay as they are. | planner | decided |
| **P-2** (R7-5) | The coverage ring is shown only for decks with `deck.usesCoverageSessions == true` (vocab, conjugation, Hangul reading). Every other deck (music, harmony, Particles) shows the old accuracy ring again. Particles keeping adaptive selection is recorded in §17 as a deviation from PLAN_R8 S1. | planner | decided |
| **O-1** (R7-4) | How should missed words come back when the learner falls behind? **Recommended: (a)** `reviewShare` scales with the backlog: `0.3 + 0.3 × min(1, dueCount ÷ targetEntries)`, so it tops out at 0.6. Alternatives: (b) pause new words while more than *k* misses are due; (c) keep the 30 % cap and document that the gap is only a minimum. | **owner** | ☑ **decided 2026-11-18: option (a).** |

---

## 2. Tracker

| Segment | Covers | Agent | Status | Notes |
|---|---|---|---|---|
| LF1 Genius and LRCLIB match the right song | R8-1 | implementor | ☐ | Core + `LyricsService` call site |
| LF2 Title normalisation and `+` encoding | R8-6 | implementor | ☐ | Core only |
| LF3 Request budget per phase; English gap retried | R8-5 | implementor | ☐ | After LF1 (same files) |
| LF4 Cache first, Korean title persisted | R8-4 | implementor | ☐ | After LF3. The plan's only wire change. |
| LF5 Picker lists refresh and reset; play doesn't block | R8-3, R8-10d, R8-10k | implementor | ☐ | App VM |
| LF6 Playlist and playlist-item paging | R8-7 | implementor | ☐ | After LF5 (same VM) |
| LF7 Lyrics robustness pass | R8-10 a b c e f h i j l | implementor | ☐ | App services |
| SF1 Await the previous flush before `start()` | R7-2 | implementor | ☐ | App |
| SF2 Short killed sessions are abandoned | R7-3 (P-1) | implementor | ☐ | Core |
| SF3 `DeckHistory` is required | R7-6 | implementor | ☐ | Core + app call sites |
| SF4 Review share grows with the backlog | R7-4 (O-1) | implementor | ☐ | Owner chose O-1 (a) |
| SF5 Stop speech before arming the mic | R7-9f | implementor | ☐ | App |
| SF6 Faster `Scheduler.select` | R7-7 | implementor | ☐ | Optional, last |
| UF1 Paging rows and the "Paused" label | R8-7, R8-10k | frontend | ☐ | After LF5 + LF6 |
| UF2 Rings and Home numbers | R7-5 (P-2), R7-9 a–d | frontend | ☐ | Independent |
| CF1 Verification rows | R8-9, R7-8 | content | ☐ | Independent |

**Order and parallelism:**
1. **LF1 → LF2 → LF3 → LF4** run one after another. LF1, LF3 and LF4 all edit `LyricsService.swift`. LF2 is independent but small, so it goes in this sequence too.
2. **LF5 → LF6 → LF7** (app) can run in parallel with step 1, because they touch different files. The exception is that LF7 also touches `LyricsService`/`LyricsCacheStore`, so run LF7 after LF4.
3. **SF1, SF2, SF3, SF5** are independent of the Lyrics work. Run SF2 → SF3 one after another, because both touch session history.
4. **UF1** goes after LF5 and LF6. **UF2** and **CF1** can run at any time.

---

## 3. Segments

### LF1 · R8-1 · Genius and LRCLIB match the right song

**Commit:** `R9-LF1: Genius hit must match the title; stricter artist match`

**Files:**
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/TrackQuery.swift`
- `Lyrics/GeniusParser.swift`
- `Lyrics/LRCLIBParser.swift` (only if `bestMatch` needs a change to use the new helper)
- `App/Sources/Services/Lyrics/LyricsService.swift` (call site of `lyricsHit`)

**Steps:**
1. **`TrackQuery.sameArtist(_:_:)`:** let `ka = key(a)`, `kb = key(b)`, and `short` = the shorter of the two keys.
   - **Rule 1:** an exact key match → true.
   - **Rule 2:** otherwise, containment counts only when `short.count >= 4`. Count characters (`Character`s), so a Hangul syllable counts as one.
   - **Rule 3:** otherwise, a whole-word match counts. Split each **original** name (before key folding) into words on non-letters and non-digits (spaces, parentheses, `&`, `,`, `/`, `-`). If one name's word list, lowercased, contains the whole other name as a word, the names match. This covers `"BTS"` vs `"BTS (방탄소년단)"`, `"V"` vs `"V (BTS)"` and `"IU"` vs `"IU (아이유)"`.
   - Update the doc comment.
2. **New `TrackQuery.titleMatches(_ hitTitle: String, any titles: [String]) -> Bool`:**
   - **Rule 1:** `sameTitle(hitTitle, t)` for at least one `t` → true.
   - **Rule 2:** otherwise, true when `normalise(hitTitle)` contains `normalise(t)` as a **whole word sequence**, compared on lowercased words split as in step 1. This allows `"Love wins all (Romanized)"` and `"사랑은 늘 도망가 (Love Always Runs Away)"`.
   - **Rule 3:** require `key(t).count >= 2`, so a one-letter title can't match everything.
3. **`GeniusParser.lyricsHit(_:artists:titles:)`:** add a `titles: [String]` parameter. A hit qualifies only when:
   - the artist isn't excluded;
   - `sameArtist` holds for one of the track's artists;
   - **and** `TrackQuery.titleMatches(hit.title, any: titles)` holds.

   Keep the first qualifying hit in Genius's order.
4. **`GeniusParser.translationHit`:** replace `artistKeys.contains { k.contains($0) }` with a whole-word check of each artist's name inside the hit title, using the same word split as step 1. Keep the title check as it is (substring on keys). Translation-page titles are of the form `"Artist - Title (English Translation)"`.
5. **`LRCLIBParser.bestMatch`:** it already requires `sameTitle` and `sameArtist`. No change is needed beyond what step 1 changes in `sameArtist`. Leave the file untouched unless it doesn't compile.
6. **`LyricsService.Run.geniusLyrics`:** pass `titles: titles` to `lyricsHit`.

**Acceptance (for the tester):**
- `sameArtist` returns false for `("V","Seventeen")`, `("e","TWICE")`, `("Rain","Brain")` and `("Jin","Jinjin")`.
- It returns true for `("BTS","BTS (방탄소년단)")`, `("V","V (BTS)")`, `("IU","아이유 (IU)")`, `("TWICE","twice")` and `("Stray Kids","Stray Kids")`.
- `lyricsHit` on hits `[Dynamite · BTS]` for the track "Butter" by BTS returns `nil`. With `[Dynamite · BTS, Butter · BTS]` it returns the "Butter" hit.
- `lyricsHit` accepts `"Love wins all"` by IU, and `"Love wins all (Live)"` by IU, for the titles `["Love wins all"]`. It rejects any hit whose artist is "Genius Romanizations".
- `translationHit` for the artist "V" doesn't pick `"Genius English Translations - SEVENTEEN - …"`.

---

### LF2 · R8-6 · Title normalisation and `+` encoding

**Commit:** `R9-LF2: strip Prod./Inst./Special Video suffixes; encode + in query values`

**Files:**
- `Lyrics/TrackQuery.swift`
- `Lyrics/HTTPRequestSpec.swift`

**Steps:**
1. **Bracket groups in `normalise`:** strip a `(…)` or `[…]` group when its first word (case-insensitive, after optional spaces) is one of these:
   - `feat`, `ft`, `featuring`, `prod`, `produced`;
   - `inst`, `instrumental`, `ver`, `version`;
   - `remix`, `acoustic`, `live`, `remaster`, `remastered`;
   - `sped`, `slowed`, `english`, `japanese`, `chinese`, `korean`.

   The pattern must accept a `.` directly after the word, and `&` or `/` directly after that. So `(Prod.&Feat. SUGA of BTS)` is stripped, as are `(Prod. by Cha Cha Malone)` and `(Inst.)`.
   - Group names are case-insensitive.
   - Keep the existing rule that strips every `[…]` group.
2. **The `with` branch:** strip `(with …)` **only** when the text after `with` contains one of `&`, `,`, ` x ` or ` and `, or it is followed by an uppercase-initial name. The simpler, accepted alternative is to **drop `with` from the pattern entirely**, which means `(with You)` stays. **Take the alternative.** Spotify puts collaborators in `artists`, so search doesn't need them stripped.
3. **The dash suffix:** add `video`, `special`, `performance`, `mv`, `ost`, `prod` to `suffixWords`, so `"Hype Boy - Special Video"` → `"Hype Boy"`. Keep the rule that it applies only after `" - "`.
4. **`LyricsHTTP.url`:** after building `URLComponents` with `queryItems`, set `c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")`. `URLComponents` encodes everything else already. Update the doc comment.

**Acceptance (for the tester):**
- `normalise` maps:
  - `"Eight (Prod.&Feat. SUGA of BTS)"` → `"Eight"`;
  - `"Pop! (Prod. by Cha Cha Malone)"` → `"Pop!"`;
  - `"Stay (Inst.)"` → `"Stay"`;
  - `"Hype Boy - Special Video"` → `"Hype Boy"`.
- `"(with You)"` titles are unchanged.
- The existing cases still pass: `"Seven (feat. Latto) - Clean Ver."` → `"Seven"`, `- Live`, `- Remix`, `- Remastered 2023`, `[Official]`, and `"Love wins all"` unchanged.
- `LyricsHTTP.url` with the value `"A+B"` produces `A%2BB` in the query string.

---

### LF3 · R8-5 · Request budget per phase; English gap retried

**Commit:** `R9-LF3: separate Korean/English request budgets; retry missing English after 7 days`

**Files:**
- `App/Sources/Services/Lyrics/LyricsService.swift`
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/LyricsCacheFile.swift`
- `Lyrics/LyricsModels.swift` (`LyricsConstants`)
- `PLAN_M6_LYRICS.md` §4.4 (the wording of the request budget)
- PLAN.md §17

**Steps:**
1. **Constants:** in `LyricsConstants`, add:
   - `koreanRequestBudget = 7` (2 × LRCLIB get + 1 search + 2 × (Genius search + page));
   - `englishRequestBudget = 3` (search + page + 1 spare);
   - `missingEnglishTTLDays = 7`.
2. **`LyricsService.Run`:** replace the single `requestsLeft` with a budget per phase.
   - `execute()` runs the Korean phase with `koreanRequestBudget`.
   - `englishLines()` resets the counter to `englishRequestBudget` before its first fetch.
   - Remove `LyricsService.maxRequests`.
3. **Retries:** a `sendRetryingServerError` retry is part of the same budget unit (no change in counting). Say so in the doc comment: "a unit may include one retry after a 5xx".
4. **`.exhausted` in the Korean phase:** it can no longer happen on the planned path. If it does, keep treating it as `incomplete`. This is safe: the error isn't cached.
5. **`LyricsCacheFile.isFresh(now:)`:** an `available` entry whose `document?.english == nil` is fresh only for `missingEnglishTTLDays`, measured from `fetchedAt`. An `available` entry with English never expires (unchanged).
6. **Refreshing a stale entry:** `LyricsService.lyrics(for:)` needs no change in its control flow. On `.failed` or `.offline` it already returns the cached `available` result.
   - **Add:** when the refetched result is `available` with `english == nil` but the stale cached document had English, keep the cached document. A new failure must never lose an English page.
7. **Docs:** in PLAN_M6 §4.4, replace "at most 5 requests per song" with "at most 7 requests for the Korean lyrics and 3 for the English page; each may include one retry after a server error". Add a §17 line.

**Acceptance (for the tester):**
- In the trace from R8-5 (Korean title set, not on LRCLIB, found on Genius under the first title, translation page present), the English page is fetched, so the document has `english != nil`.
- When the first-title Genius page isn't Korean and the second title's page is Korean, the result is `available` (not `.failed`).
- A cached `available` entry without English, 8 days old, isn't fresh. With English it's fresh at any age. Without English at 6 days, it's fresh.
- A refetch that returns no English doesn't replace a cached document that has English.

---

### LF4 · R8-4 · Cache first, Korean title persisted

**Commit:** `R9-LF4: open cached lyrics without a Spotify call; persist the Korean-title lookup`

**Files:**
- `Lyrics/LyricsCacheFile.swift`
- `App/Sources/Services/Lyrics/LyricsService.swift`
- `App/Sources/Services/Lyrics/SpotifyClient.swift`
- `App/Sources/Features/Lyrics/LyricsReaderViewModel.swift`
- `PLAN_M6_LYRICS.md` §4.7 (the cache file fields)

**Steps:**
1. **`LyricsCacheFile`:** add `public var koreanTitleChecked: Bool`.
   - It's a new coding key, `koreanTitleChecked`.
   - Decode it tolerantly: missing → `false`. Always encode it.
   - Add an `init` parameter with the default `false`.
   - `schemaVersion` stays `1`.
2. **`SpotifyClient`:** add `func koreanTitle(of track: TrackInfo) async -> KoreanTitleLookup`, where `enum KoreanTitleLookup { case found(String), same, unknown }`.
   - `.unknown` means the request failed.
   - `.same` means the `ko-KR` title equals `title`.
   - Keep `withKoreanTitle` as a thin wrapper, or delete it if nothing else uses it.
3. **`LyricsService.lyrics`:** new signature:

   ```swift
   func lyrics(for track: TrackInfo, forceRefresh: Bool = false,
               koreanTitle: @Sendable (TrackInfo) async -> KoreanTitleLookup) async -> (outcome: LyricsOutcome, track: TrackInfo)
   ```

   Flow:
   1. Load the cache.
   2. If it's fresh and `!forceRefresh`, return the cached result with `cached.track`. Fill `titleKo` from the cache when the incoming track has none. **No Spotify call.**
   3. Otherwise, resolve the Korean title only if `track.titleKo == nil` **and** `cached?.koreanTitleChecked != true`. `.found(s)` sets `titleKo = s`. `.found` or `.same` → `checked = true`. `.unknown` → `checked = false`.
   4. If the title isn't looked up again because it was checked before, copy `cached.track.titleKo`.
   5. Run the lookup with the resolved track.
   6. Save with `koreanTitleChecked: checked || cached?.koreanTitleChecked == true`.
   7. Return the outcome and the resolved track.
4. **`LyricsReaderViewModel.load`:**
   - Remove the `withKoreanTitle` call.
   - Pass `{ await spotify.koreanTitle(of: $0) }`, then set `track = returned.track`.
   - Keep the rest of `load` as it is.
5. **Docs:** in PLAN_M6 §4.7, add the field to the cache file description.

**Acceptance (for the tester, with a stub `HTTPClient` and a temp cache directory):**
- A fresh cached entry: `lyrics(for:)` returns without calling `koreanTitle` and without any HTTP request.
- A cache miss: `koreanTitle` is called once. On `.same`, the saved file has `koreanTitleChecked == true` and `titleKo == nil`. The next stale refetch doesn't call `koreanTitle` again.
- On `.unknown`, `koreanTitleChecked == false` is saved, so the lookup runs again next time.
- An old cache file without the key decodes with `koreanTitleChecked == false`.

---

### LF5 · R8-3, R8-10d, R8-10k · Picker lists refresh and reset; play doesn't block

**Commit:** `R9-LF5: Lyrics home refreshes all lists, resets on disconnect, opens before play`

**Files:**
- `App/Sources/Features/Lyrics/LyricsHomeViewModel.swift`
- `App/Sources/Features/Lyrics/LyricsHomeView.swift`, **only** the `.task(id:)` / `onChange` wiring for the reset (no layout changes)
- `Lyrics/SpotifyModels.swift` (only if `isPlaying` must be carried on `TrackInfo`'s wrapper, see step 4)

**Steps:**
1. **`refreshAll()`:**
   - Call `loadRecent(force: true)`, plus `loadPlaylists(force: true)` or `loadLiked(force: true)` for the visible source.
   - Mark the sources that aren't visible as stale (`var staleSources: Set<Source>`), so switching to one later loads it with `force: true` once.
2. **A forced load keeps the list on screen:** in each `load…(force:)`, set `.loading` only when there is no value yet. On a forced reload, keep the `.loaded` value until the new one arrives. On failure with an existing value, keep the value and set a transient `listError` instead of replacing the list with `.failed`.
3. **Reset on disconnect:**
   - Add `func reset()`. It sets `nowPlaying`, `recent`, `playlists` and `liked` to `.idle`, sets `likedNextOffset = nil`, clears the paging state from LF6, the open playlist and `query`, and empties `staleSources`.
   - Call it when `spotify.isConnected` turns false. Wire it in `LyricsHomeView` with `onChange(of: isConnected)`.
4. **Paused (R8-10k):**
   - `nowPlaying` keeps the track, plus `isPlaying: Bool`. Change the stored type to a small struct, `NowPlaying { track: TrackInfo; isPlaying: Bool }`, built from `SpotifyCurrentlyPlaying.isPlaying`.
   - `SpotifyClient.nowPlaying()` returns that struct (or `nil`).
   - The frontend picks the label in UF1. Until then, keep the existing label and read `.track`.
5. **Open before play (R8-10d):** in `open(_:play: true)`, push the reader first, then start the play call in a `Task` that doesn't block navigation. If the play call fails, show its message in the existing error slot. Keep the "open Spotify on no active device" behaviour, which LF7 narrows.

**Acceptance (for the tester or the owner on device):**
- Pull to refresh after playing a new song in Spotify: the song appears at the top of Recent.
- Disconnect in Settings, then connect as another account: no list from the first account is shown at any point.
- "Play" opens the reader at once, even with Spotify slow or unreachable.
- A paused song can be told apart from a playing one in the VM (`isPlaying == false`).

---

### LF6 · R8-7 · Playlist and playlist-item paging

**Commit:** `R9-LF6: page playlists and playlist items`

**Files:**
- `App/Sources/Services/Lyrics/SpotifyClient.swift`
- `App/Sources/Features/Lyrics/LyricsHomeViewModel.swift`

**Steps:**
1. **`SpotifyClient.playlists(offset:)`:** return `SpotifyPlaylistPage(playlists:, nextOffset:)`, with `limit = 50` and `nextOffset = rows.next == nil ? nil : offset + limit`, the way `liked(offset:)` already does it.
2. **`SpotifyClient.playlistItems(id:offset:)`:** return `.tracks([TrackInfo], nextOffset: Int?)` with `limit = 100`. `.notShared` is unchanged. This is a change to the `PlaylistContents` enum, which is app-only and not persisted.
3. **VM:**
   - Add `playlistsNextOffset`, `loadMorePlaylists()`, `itemsNextOffset` (for the open playlist) and `loadMoreItems()`. They follow `loadMoreLiked()` exactly: a guard against concurrent loads, append, and dedupe by id.
   - Don't auto-loop. Load the next page when the frontend's "Load more" row appears (UF1).

**Acceptance:**
- A playlist with 250 songs shows all 250 after two "load more" calls.
- An account with 120 playlists shows all of them.
- No duplicate rows appear when "load more" fires twice quickly.

---

### LF7 · R8-10 a b c e f h i j l · Lyrics robustness pass

**Commit:** `R9-LF7: lyrics robustness (keychain update, refresh race, timeouts, 404s, cache cap)`

**Files:**
- `App/Sources/Services/Lyrics/KeychainStore.swift`
- `SpotifyAuth.swift`
- `SpotifyClient.swift`
- `GlossService.swift`
- `LyricsCacheStore.swift`
- `App/Sources/AppEnvironment.swift` (`preview()` only)
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/SpotifyRequests.swift`
- `App/Sources/Features/Settings/SettingsView.swift`: the "Clear lyrics cache" action only, one line

**Steps:**
1. **(a) Keychain write:**
   - `KeychainStore.write` first tries `SecItemUpdate` with `kSecValueData`. Only on `errSecItemNotFound` does it `SecItemAdd`, with the same accessibility attribute. **No delete first.**
   - In `SpotifyAuth.apply`, check the `Bool`. On `false`, log at the error level and set `@Published`/observable `var keychainWriteFailed = true`. The UI hookup is part of UF1.
2. **(b) Refresh race:** in `SpotifyAuth.refresh()`, only the task's creator clears it, and only if it is still the same task:

   ```swift
   if let refreshTask { return try await refreshTask.value }
   let task = Task { try await self.performRefresh() }
   refreshTask = task
   defer { if refreshTask == task { refreshTask = nil } }   // compare by identity
   ```

   `Task` is `Equatable`, so the comparison works.
3. **(c) Timeouts:** in `SpotifyClient.get`, map `HTTPError.timedOut` to its own client error, with the message **"Spotify didn't respond. Try again."** It must no longer map to `.offline`. Do the same in `LyricsService.Run.fetch`: a timeout is `.failed`, not `.offline`.
4. **(e) Play 404:** parse the error body `{"error":{"reason":"NO_ACTIVE_DEVICE"}}`.
   - Only that reason (or a 404 with no parsable body) opens the Spotify app.
   - Any other 404 shows "This song can't be played on Spotify."
   - Put the decoding helper in core, as `SpotifyDecoder.playerErrorReason(_ data: Data) -> String?`.
5. **(f) Translation prompt:**
   - In `GlossService`, add `private var translationDeclined = false`. Set it when `runBatch` fails because the language pack isn't installed or the user cancelled the download. Catch that `TranslationError` case, or any error raised from `prepareTranslation()`.
   - `prepare` no longer resets it.
   - While it is `true`, `runBatch` returns at once and marks the words as unavailable.
   - It resets only on `retryFailed` (the reader's force refresh) and at the next launch.
6. **(h) Cache cap:**
   - After each `save`, `LyricsCacheStore` keeps at most `LyricsConstants.cacheMaxEntries = 200` files and deletes the oldest by `contentModificationDate`. Add the constant to core.
   - A `load` that hits touches the file's modification date, which makes it an LRU.
   - Run the prune off the main actor.
7. **(i) Preview defaults:** `AppEnvironment.preview()` passes:
   - `spotify: SpotifyClient(auth: …InMemorySecretStore…)`, using the existing initialiser parameters (add them if they are missing);
   - `lyrics: LyricsService(http: <offline stub>, cache: LyricsCacheStore(directory: nil))`.

   Leave the production `init` defaults unchanged.
8. **(j) Id guard:** in `SpotifyRequests.playlistItems`, `track` and `play`, return `nil` when an id is empty or isn't all ASCII letters and digits.
9. **(l) Clear cache:**
   - "Clear lyrics cache" also calls `glosses.clearAll()`. Add it if it's missing: it empties the in-memory gloss dictionaries and the `failed` sets.
   - Disconnect handling is LF5 step 3, and popping an open reader is UF1.

**Acceptance:**
- Refreshing the token twice concurrently, then a third time after the first finishes, performs exactly 2 token requests.
- When the Keychain write fails, the old refresh token stays readable.
- A timeout shows "Spotify didn't respond", not "You're offline".
- A 404 with reason `NO_ACTIVE_DEVICE` opens Spotify. A 404 with another reason doesn't.
- After declining the language download once, opening another song doesn't prompt again in the same launch.
- The cache directory never holds more than 200 files.
- `SpotifyRequests.track(id: "../me", …)` returns `nil`.

---

### SF1 · R7-2 · Await the previous flush before `start()`

**Commit:** `R9-SF1: new session waits for the previous session's writes`

**Files:**
- `App/Sources/AppEnvironment.swift`
- `App/Sources/Features/Session/SessionViewModel.swift`

**Steps:**
1. **`AppEnvironment`:** add `var pendingFlush: Task<Void, Never>?`, on the main actor like the rest of the environment.
2. **`SessionViewModel.apply`, at the `.finished` branch (`:485-496`):**
   - Chain the close onto the pending flush: `let previous = env.pendingFlush`.
   - Then: `env.pendingFlush = Task { await previous?.value; await recorder.close(); env.dataDidChange() }`.
   - Do the same wherever a recorder is closed for a discard, if that's a separate path.
3. **`start()`:** await the flush first, before the three store reads: `await env.pendingFlush?.value`.

**Acceptance:**
- Quit a session (discard), then immediately reopen the same deck. The new engine's `initialStats` don't include the discarded session's writes.
- Finish a session, then reopen at once. The new session sees all of the previous session's stats.

---

### SF2 · R7-3 (P-1) · Short killed sessions are abandoned

**Commit:** `R9-SF2: killed sessions under 5 counted cards close as abandoned`

**Files:**
- `Packages/MemoriseCore/Sources/MemoriseCore/Domain/Records.swift`
- `Scheduling/SchedulerConstants.swift`
- `PLAN.md` §10 (the constant) and §17
- `PLAN_R8_COVERAGE.md`: the S1 acceptance line about killed sessions

**Steps:**
1. **`SchedulerConstants`:** add `minCountedForKilledSession = 5`, with a doc comment: "a killed session with fewer counted attempts is closed as abandoned, so it doesn't advance 'sessions since a miss' or become the baseline".
2. **`SessionRecord.closedAfterInterruption(attempts:minCounted:)`:**
   - Add the parameter, with the default `SchedulerConstants.standard.minCountedForKilledSession`.
   - `.completed` requires `attempts.filter(\.isCounted).count >= minCounted`. Otherwise the session is `.abandoned`, with the existing `endedAt` rule for abandoned sessions.
   - The callers (`SwiftDataStatsStore.closeInterruptedSessions`, `InMemoryStatsStore`) need no change, because they use the default.
3. **Docs:**
   - In PLAN_R8_COVERAGE S1, change the acceptance line to "discarded sessions, and killed sessions with fewer than 5 counted cards, don't advance 'sessions since a miss'".
   - Add a §17 line.

**Acceptance:**
- A killed session with 4 counted attempts becomes `.abandoned`. With 5, it becomes `.completed`, with `endedAt` as before.
- `deckHistory` ignores the 4-attempt session.
- The per-card stats written during the killed session are kept in both cases. Only the session's status changes.

---

### SF3 · R7-6 · `DeckHistory` is required

**Commit:** `R9-SF3: SessionEngine and SessionComposer require a DeckHistory`

**Files:**
- `Scheduling/DeckHistory.swift`
- `Scheduling/SessionComposer.swift`
- `Session/SessionEngine.swift`
- the app call site in `SessionViewModel.start()` (it already passes a value)
- existing test call sites: mechanical edits only (see Conventions)

**Steps:**
1. **`DeckHistory`:**
   - Add `public static let allDue`. It's a value whose `sessionsSince(_:)` returns `Int.max`. Implement it with a private `isAllDue: Bool` flag (default `false`).
   - Keep `empty` meaning "no completed sessions" (nothing is due yet).
2. **Signatures:**
   - Change `history: DeckHistory?` to `history: DeckHistory` in `SessionComposer.queue` and in `SessionEngine.init`.
   - In SessionEngine, give it **no default**, so a caller must choose.
   - Replace the internal `nil` checks with `history.isAllDue` / `sessionsSince`.
3. **Tests:** existing tests that pass `history: nil` get `history: .allDue`. Tests that omit the argument get `history: .empty`, unless the test relies on "all due". In that case use `.allDue` and leave a `// R9-SF3` comment for the tester to check.

**Acceptance:**
- A miss with `history: .empty` isn't due in the next session.
- With `.allDue` it is due.
- The behaviour on every existing test is unchanged after the mechanical rewrite.

---

### SF4 · R7-4 (O-1 = a) · Review share grows with the backlog

**Commit:** `R9-SF4: review share scales with the due backlog`

**Files:**
- `Scheduling/SessionComposer.swift`
- `Scheduling/SchedulerConstants.swift`
- PLAN.md §10.5 and §17

**Steps (owner chose option (a) on 2026-11-18):**
1. **`SchedulerConstants`:** add `reviewShareMax = 0.6`. Keep `reviewShare = 0.3` as the floor.
2. **In `SessionComposer.queue`:**
   - `share = reviewShare + (reviewShareMax - reviewShare) * min(1, Double(dueCount) / Double(max(1, targetEntries)))`.
   - `reviewSlots = Int((Double(targetEntries) * share).rounded(.down))`.
   - Leave the rest of the ordering unchanged.
3. **Docs:** in PLAN §10.5, state the formula, and that `wrongGapSessions` is the *minimum* gap.

**Acceptance:**
- 0 due → 6 review slots of 20.
- 10 due → 9.
- ≥ 20 due → 12.
- In the all-wrong probe from R7-4, the due backlog stops growing without bound.

---

### SF5 · R7-9f · Stop speech before arming the mic

**Commit:** `R9-SF5: stop spoken feedback before the next prompt listens`

**Files:**
- `App/Sources/Features/Session/SessionViewModel.swift`

**Steps:**
- In the mic-detected grading path (the one that goes through `apply(engine.answerDetected…)`), call `env.speech.stop()` before `syncState()` arms the next prompt.
- Alternatively, in `syncState`, call `env.speech.stop()` right before `mic?.setListening(true)`. **Prefer this alternative:** it covers every path.

**Acceptance (owner, on device):** with spoken feedback on, a correct note says "Correct", and the next card never logs a phantom "Try again".

---

### SF6 · R7-7 · Faster `Scheduler.select` (optional)

**Commit:** `R9-SF6: scheduler iterates only allowed keys; reference time once per session`

**Files:**
- `Scheduling/Scheduler.swift`

**Steps:**
- **Compute once:** build `WeightCalculator` (its `referenceMs` median) once in `Scheduler.init`. Rebuild it only when stats change in a way that matters. A recomputation every 10 grades is acceptable; note it in the doc comment.
- **Fewer cards:** when `allowed != nil`, iterate `allowed` through a `[ItemKey: Int]` pool-index map instead of the whole pool.
- **Determinism:** the same seed must give the same picks as before for `allowed == nil`. With `allowed != nil`, keep the iteration in pool order, so the existing seeded tests stay stable: sort the indices.

**Acceptance:** the seeded session tests give identical results before and after. Release per-pick time on the 1,992-card pool is ≤ 1 ms *(measure)*.

---

### UF1 · R8-7, R8-10k, R8-10a, R8-10l · Paging rows, "Paused" label, sign-in warning

**Commit:** `R9-UF1: Lyrics load-more rows, paused label, keychain warning, pop reader on disconnect`

**Files:**
- `App/Sources/Features/Lyrics/LyricsHomeView.swift`
- `LyricsReaderView.swift`, only to pop the reader on disconnect
- `App/Sources/Features/Settings/SettingsView.swift`, only the Lyrics section

**Steps:**
1. **Load more rows:** add a "Load more" row at the end of the playlists list and of an open playlist's songs. It is shown while `nextOffset != nil` and calls `loadMorePlaylists()` / `loadMoreItems()` on appear, matching the existing liked-songs row exactly (style, spinner, accessibility identifier pattern `lyricsLoadMorePlaylists`, `lyricsLoadMoreItems`).
2. **Paused label:** the Now-playing card says **"Paused"** when `nowPlaying.isPlaying == false`, and "Now playing" otherwise.
3. **Sign-in warning:** in Settings → Lyrics, when `keychainWriteFailed` is true, show a footnote: "Couldn't save your Spotify sign-in. You'll need to reconnect after restarting the app."
4. **Pop the reader:** when `isConnected` turns false, the navigation path pops back to the Lyrics home.
5. **Previews:** keep `#Preview`s compiling, and add a paused-state preview.

**Acceptance (owner on device):**
- The rows load more items.
- The label switches when Spotify is paused.
- Disconnecting while a reader is open returns to the home.

---

### UF2 · R7-5 (P-2), R7-9 a b c d · Rings and Home numbers

**Commit:** `R9-UF2: coverage ring only on coverage decks; consistent Home numbers`

**Files:**
- `App/Sources/Features/Home/HomeView.swift`
- the Stats overview view (`StatsOverview`), for item d

**Steps:**
1. **(R7-5) Which ring:** `DeckRowInfo.make` takes `usesCoverage: Bool` (from `deck.usesCoverageSessions`). It sets `coverage = nil` when the deck isn't a coverage deck. The tiles already fall back to the accuracy layout when `coverage == nil`; confirm that path still renders the accuracy ring.
2. **(a) ✓ and 100 %:**
   - `CoverageRing` gets `coveredCount` and `cardCount`. Show ✓ only when `coveredCount == cardCount`.
   - The text uses the floor: `Int((coverage * 100).rounded(.down))`. So 99.6 % reads "99%".
3. **(b) Identifier:** move `deckCoverageRing` onto the tile element that has `.accessibilityElement(children: .ignore)`, as an `accessibilityValue` ("\(n)% covered") plus a tile identifier, so XCUITest can find it.
4. **(c) Scope:** in `DeckRowInfo.make`, iterate only `poolKeys` (`for key in poolKeys { guard let s = stats[key] … }`) for accuracy, median and last seen.
5. **(d) Stats:** `StatsOverview` either passes the real pool keys or stops computing `coverage`. **Prefer stopping:** it isn't displayed.

**Acceptance:**
- Music and Particles tiles show an accuracy ring. Vocab, Conjugation and Hangul Reading show coverage.
- At 659 of 664 covered, the ring reads "99%" with no ✓.
- The tile's numbers ignore hidden entries and other option sets.

---

### CF1 · R8-9, R7-8 · Verification rows

**Commit:** `R9-CF1: verification rows for media 0147-0155 and backlog decks`

**Files:**
- `docs/media-verification.md`
- `docs/core-verification.md`

**Steps:**
1. Add rows for `ko.media.0147`–`0155`, the 9 sourced entries.
2. Refresh the media header: entry count (418), source share (70 %).
3. Append rows for:
   - Core 5 `ko.core.1320`–`1533`;
   - Core 6 (all 156);
   - AION 2 `0141`–`0232`;
   - Slang (all 53).

   Use the same row format as `b1d7575`.
4. Leave the ✓ column empty. The owner ticks it during the 10-row spot-check per deck.

**Acceptance:** every sourced media entry has a row, and every Korean deck entry appears in a verification doc.
