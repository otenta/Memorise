# Memorise — Code Review

> Newest first: **Round 8** (M6 Lyrics + R8 content + R7 follow-up) → **Round 7** (R6 fixes + R7 owner fixes + R8 coverage sessions + spec comparison) → **Round 6** (R5 fixes + K2 content + performance + spec comparison) → **Round 5** (R4 fixes + performance + spec comparison) → **Round 4** (full review after M2–M5) → **Round 3** (G1–G5 + UI visual pass) → **Round 2** (F2–F9) → **Round 1** (original review). Older rounds are kept unchanged as the audit trail. IDs P1-x come from Round 1, N-x from Round 2, R3-x from Round 3, R4-x from Round 4, R5-x from Round 5, R6-x from Round 6, R7-x from Round 7, R8-x from Round 8 (not to be confused with PLAN_R8's S/F/C segment ids).

---

# Round 8 — M6 Lyrics (Spotify, LRCLIB, Genius, tap-to-translate), R8 content, and R7 follow-up

- **Date:** 2026-11-18
- **Scope:** 20 commits, `11e40ef..36b9c34` (50 files, +14,495/−25):
  - M6 L0–L9 and L8b (Lyrics tab);
  - R8-C1, C1b and C2 (K-pop / K-drama content, `ko_media` 169 → 418 entries);
  - the planning commits.
- **Read in full:**
  - app: `SpotifyAuth`, `SpotifyClient`, `LyricsService`, `LyricsCacheStore`, `KeychainStore`, `HTTPClient`, `GlossService`, `LyricsHomeViewModel`, `LyricsReaderViewModel`, `LyricsReaderView`, `AddToDeckSheet`;
  - core (`Lyrics/`): `SpotifyRequests`, `SpotifyModels`, `GeniusParser`, `LRCLIBParser`, `TrackQuery`, `LyricsCacheFile`, `LyricsModels`, `LyricsTokenizer`, `PhraseMatcher`, `WordLookup`, `TranslationAlignment`, `KoreanLyricsCheck`, `LyricsText`, `HTTPRequestSpec`;
  - diffs: `UserDecks`, `DeckValidator`, `AppEnvironment`, `MemoriseApp`, `project.yml`, `.gitignore`, xcconfig files.
- **Read selectively:** `LyricsHomeView` (state handling), `SettingsView` (Lyrics section), `docs/media-verification.md`.
- **Not reviewed:** the visual layout of `LyricsHomeView` / `WordBubble` / `WordFlowLayout` (needs the owner's device), and the live Spotify, LRCLIB and Genius endpoints (no network calls were made, and `Secrets.xcconfig` was never opened).
- **Verification actually run** (in a scratch copy made with `git archive HEAD`; the repo was not modified):
  - `swift test`: **154 tests, 34 issues in 5 failing tests. Identical to Round 7.** No test file mentions Lyrics, Spotify or LRCLIB.
  - `xcodegen generate` + `xcodebuild` (iOS Simulator, Debug, unsigned, no `Secrets.xcconfig`): **BUILD SUCCEEDED.**
  - **A scratch probe test** (deleted afterwards), run against the real core code:
    - `LyricsHTTP.url` encodes `&` and `#`, but leaves `+` literal (`A+B` stays `A+B`, which a server reads as `A B`).
    - `TrackQuery.normalise`: `"Eight (Prod.&Feat. SUGA of BTS)"`, `"Pop! (Prod. by Cha Cha Malone)"`, `"Stay (Inst.)"` and `"Hype Boy - Special Video"` come back **unchanged**. `"(feat. …)"`, `"- Live"`, `"- Remix"`, `"- Remastered 2023"` and `"[Official]"` are stripped correctly.
    - `TrackQuery.sameArtist("V","Seventeen")`, `("e","TWICE")`, `("Rain","Brain")`, `("Jin","Jinjin")` all return **true**.
    - `GeniusParser.lyricsHit([Dynamite by BTS], artists:["BTS"])` returns it for any track by BTS (there is no title parameter).
    - `GeniusParser.lyrics(fromHTML:)` handles nested `<div>`, `<br/>`, `&amp;`, an excluded child and `[Verse]` correctly.
  - Content scan (Python): ids and ranks are unique and contiguous in every `ko_*.json` (media 418, Core 5 664, Core 6 156, Slang 53). 294 of 418 media entries carry a source (**70 %, the K2 target is met**).
  - Secret scan: `git log --all -- App/Config/Secrets.xcconfig` is empty and no key-like string appears in tracked files.
  - Not run: device, Instruments, VoiceOver, any real network call. Claims that need these are marked *(plausible: measure)*.

## Verdict

**M6 is well structured and mostly sound.**
- All parsing and request building is pure and sits in core. Every `Codable` type uses tolerant decoding.
- Auth is correct: PKCE with a `state` check, the refresh token in the Keychain (`AfterFirstUnlockThisDeviceOnly`), and one shared refresh for concurrent callers.
- A missing translation, a missing credential and a stale cache degrade quietly. The Hangul check is based on the lyrics, not on Spotify's genre.
- The build is green, and no secret is in git.

**It still ships with the same two structural gaps as every round since R6:**
- `HEAD` still fails the same 5 tests, and CI still never runs `swift test`.
- M6 adds about 1,500 lines of core logic (parsers, tokenizer, matcher, lookup, cache) with **no tests at all**, although every one of those types is pure and trivial to test (R8-2).

**One correctness risk can show the learner the wrong song's lyrics and cache them forever** (R8-1). **One feature bug makes the picker lists stale for the whole app session** (R8-3).

## Status of Round 7 findings

No code in `Session*`, `Scheduler*` or the Home rings changed since `11e40ef`, so those findings carry over.

| ID | Status | Evidence |
|---|---|---|
| R7-1 · 5 failing tests, CI blind, no R7/R8 tests | 🔴 **Open, widened** | Same 5 failures. `core-tests.yml` still runs `swift build -c release` only. M6 added 14 untested core files (R8-2). |
| R7-2 · next session reads stats before the flush | 🔴 Open | No `pendingFlush` or equivalent in `App/Sources`. |
| R7-3 · killed sessions count toward a gap | 🔴 Open | Needs a planner decision. |
| R7-4 · 30 % cap parks misses | 🔴 Open | Needs an owner decision. |
| R7-5 · ring on every deck | 🔴 Open | Unchanged. |
| R7-6 · `history: nil` means all due | 🔴 Open | Unchanged. |
| R7-7 · O(pool) per pick | ⚪ Unchanged | Low priority. |
| R7-8 · entries without verification rows | 🟡 **Partly fixed** | R8-C1 / C2 rows were added to `docs/media-verification.md` (306 VERIFIED rows). Core 5 extension, Core 6, AION 2 `0141`–`0232` and Slang still have none, and `docs/core-verification.md` is untouched. 9 new sourced media entries have no row (R8-9). |
| R7-9 · polish | 🔴 Open | Unchanged. |
| R6-5 · K2 source target | ✅ **Met** | 294 of 418 media entries have a source (70 %). |

## New findings (Round 8)

### R8-1 · P2 (correctness) · Genius can return another song by the same artist, and the wrong lyrics are cached for good

**Where:**
- `GeniusParser.lyricsHit` (`GeniusParser.swift:78`) picks the first search hit whose artist matches. It takes **no title** and never compares it.
- `TrackQuery.sameArtist` (`TrackQuery.swift:31`) is a substring test on folded keys.

**Failure scenario:**
- LRCLIB has no record, so `LyricsService` falls through to Genius.
- Genius is a fuzzy search. For a track it doesn't hold, the top hit is another song by the same artist.
- That page passes `KoreanLyricsCheck` and is returned as `.available`.
- `LyricsCacheFile.isFresh` never expires an `available` entry, so the wrong lyrics stay until the user taps a force refresh, which nothing suggests.

**The artist test is also too loose** (probe): `"V"` matches `Seventeen`, `"e"` matches `TWICE`, `"Rain"` matches `Brain`, `"Jin"` matches `Jinjin`. The same helper drives `LRCLIBParser.bestMatch` and `translationHit`, whose artist test is `k.contains(key)`.

**Why it matters:** the learner is shown lyrics that don't match the song playing, and learns words from a different song. Nothing in the UI says so.

**Fix:**
- Make `lyricsHit` take `titles` and require `TrackQuery.sameTitle` (after `normalise`) for at least one of them. Also accept a hit whose title contains the track title as a whole word, for `"Title (Romanized)"` cases.
- Make `sameArtist` stricter: exact key match, or containment only when the shorter key has at least 4 characters (or is a whole word of the other name).
- Same rule in `translationHit`.
- Add tests for each of the cases above (R8-2).

### R8-2 · P2 (High for delivery) · M6 shipped about 1,500 lines of pure core logic with no tests, and `HEAD` is still red

**State on `HEAD`:**
- The 5 R7-1 failures are unchanged.
- Test count is still 154.
- CI still builds only.

**Untested files (all pure, all in core):**
- `LRCLIBParser`, `GeniusParser`, `SpotifyRequests` (PKCE, callback check, form body), `SpotifyModels`.
- `TrackQuery`, `LyricsTokenizer`, `PhraseMatcher`, `WordLookup`.
- `TranslationAlignment`, `KoreanLyricsCheck`, `LyricsText`, `LyricsCacheFile`.
- The new user-mode `DeckValidator.exampleErrors` (L-D10) and the `UserDecks` rank-preserving change.

**Why the plan's L-steps matter here:** each step lists acceptance cases "for the tester". They translate almost line for line into `@Test`s. My probe harness for this round was 30 lines.

**Fix:** *(tester)* first make `HEAD` green and switch CI to `swift test` (R7-1). Then add a `Lyrics` test suite covering at least the cases in R8-1, R8-6 and R8-7, plus `stripTimestamps`, `bestMatch` duration ties, the state-mismatch path, the `+` in the token body, tokenizer punctuation trimming, phrase merging and the cache round trip.

### R8-3 · P2 (functional) · "Recent", "Playlists" and "Liked" never refresh, and show the previous account's lists after reconnecting

**Where:** `LyricsHomeViewModel.refreshAll` (`LyricsHomeViewModel.swift:79-89`) calls `loadRecent()`, `loadPlaylists()` and `loadLiked()` **without `force: true`**. Each of those returns immediately when it already holds a value (`:102`, `:114`, `:126`).

**Effects:**
- **Pull-to-refresh** and the `.task(id: isConnected)` refresh update only *Now playing*. The song list stays as it was loaded the first time. A learner who plays a new song and returns to the Lyrics tab does not see it under Recent, and pulling down doesn't help.
- **Disconnect, then connect as another account** (Settings → Disconnect Spotify, then Connect): the view model keeps the old account's recent songs, playlists and liked songs, because the model lives as long as the tab (`@State` in `LyricsHomeView`) and `disconnect()` doesn't reset it.

**Fix:**
- `refreshAll` should pass `force: true` to all three loaders (keep the cached list on screen while loading).
- Reset the model's lists when `isConnected` turns false.

### R8-4 · P3 (performance / offline, *plausible: measure*) · Opening a song that is already cached still waits on a Spotify request

**Where:** `LyricsReaderViewModel.load` (`:83`) runs `spotify.withKoreanTitle(track)` **before** it asks `LyricsService` for lyrics. The cache is keyed by the Spotify id and does not need the Korean title.

**Effects:**
- Every open costs an extra token check and `GET /tracks/{id}`, even when the lyrics are on disk.
- When the Korean title equals the English one, `titleKo` stays `nil`, so that request repeats on **every** open.
- On a bad or no connection, `SpotifyClient.get` maps every transport failure to `.offline` and each request can wait up to the 10 s timeout, so cached lyrics open late. The offline message promises "Lyrics you've opened before still work".

**Fix:** look in the cache first (`lyrics.cache.load`). Call `withKoreanTitle` only on a cache miss, and persist the Korean title (or a "no Korean title" flag) in the cache entry so it is not fetched again.

### R8-5 · P3 (correctness, from the code trace) · The 5-request budget is too small for the two-title Genius path, so there is no English page, and the gap is cached for good

**Trace** for a track with a Korean title (the common case for K-pop, since `withKoreanTitle` sets `titleKo`), not on LRCLIB and found on Genius:
1. LRCLIB `get` (English title): 1.
2. LRCLIB `get` (Korean title): 2.
3. LRCLIB `search`: 3.
4. Genius `search`: 4.
5. Genius page: 5.
6. `englishLines()` → `fetch` returns `.exhausted` and the translation is skipped.

The result `.available` with `english == nil` is saved and **never expires**, so that song never shows an English page unless the user force-refreshes.

**Related:**
- `sendRetryingServerError` can double each counted request, so "at most 5 requests per song" is really up to 10.
- When a Genius hit is found for the first title but its page isn't Korean, the second title's search hits `.exhausted` and the song reports `.failed("Couldn't reach the lyrics sources")` instead of "not available", which wastes the user's retries.

**Fix:**
- Budget the two phases separately (for example 5 for Korean lyrics, 3 for English).
- Treat a cached `available` entry with `english == nil` as stale after the same TTL as "not available" (7 days), or when the Genius token appears.
- Count a retried 5xx as one budget unit.

### R8-6 · P3 (matching) · Common K-pop title suffixes are not stripped, and `+` is not encoded

**Verified by probe:**
- `normalise` leaves `(Prod.&Feat. …)`, `(Prod. by …)`, `(Inst.)` and `- Special Video` in place. IU's "Eight (Prod.&Feat. SUGA of BTS)" and every "(Prod. by …)" title will fail both `get` and `search` (`sameTitle` compares normalised keys on both sides, so the suffix breaks the match).
- The `with` branch is too greedy the other way: `"(with You)"` is deleted from a title that is really called that.
- `LyricsHTTP.url` leaves `+` literal in a query value, and servers decode it as a space (`"A+B"` → `"A B"`). The token request already handles this (`SpotifyRequests.swift`), the URL helper doesn't.

**Fix:**
- Extend the parenthesis pattern to `prod|inst|instrumental|ver|version|remix|acoustic|live` at the start of the group.
- Only strip `with` when the group starts with `with ` **and** contains an artist-like name (or drop that branch).
- Encode `+` as `%2B` in `LyricsHTTP.url`.
- Tests (R8-2).

### R8-7 · P3 (functional) · Playlists over 100 songs, and lists over 50 playlists, are cut off silently

**Where:**
- `SpotifyClient.playlistItems` (`:138`) requests `limit: 100` and ignores `next`.
- `SpotifyClient.playlists` (`:131`) requests `limit: 50`, offset 0, and ignores `next`. `liked` is the only list that pages.

**Why it matters:** the owner's K-pop playlists are likely to be longer than 100 songs. Songs past the 100th can't be picked, and nothing says so.

**Fix:** page with `next`, the way `liked` does (a "Load more" row, or loop up to a sane cap).

### R8-8 · P3 (business / legal, owner decision) · Lyrics are scraped, cached and then re-stored in user decks, which the export does include

**Facts:**
- The Genius path reads the lyrics page HTML (not the API), and `PLAN_M6` marks the cache "never exported (copyright)": `LyricsCacheStore` excludes it from backup, and the export skips it.
- `AddToDeckSheet` saves the **full lyric line** (up to 80 Hangul syllables) into a user deck as the card's example. User decks **are** part of the data export.
- The Genius access token is built into `Info.plist` (`GeniusAccessToken`), which anyone can read from the shipped app.
- Genius's terms restrict automated page access; Cloudflare may also block it (`.failed`, never cached, retried every open).

**Fix (owner):**
- Decide whether saved example lines are acceptable (one line per word is a reasonable quotation), and then say so in the PLAN.
- Or cap the saved example at the phrase around the word.
- If the app is ever shared beyond the owner, move the Genius call to a proxy, or drop the HTML path.

### R8-9 · P3 (content) · Verification rows still lag the entries

- 9 sourced media entries (`ko.media.0147`–`0155`) cite pages that have no row in `docs/media-verification.md`.
- The 131 media entries without any source are expected (dialogue-only), but the doc header still says "Entries: 105 (`0001`–`0105`)" and "66 %", while the data now holds 418 entries and 70 %.
- Core 5 `1320`–`1533`, Core 6, AION 2 `0141`–`0232` and Slang still have no rows (R7-8).

**Fix:** *(content agent)* add the 9 rows, refresh the header counts, and append rows for the remaining decks. *(owner)* spot-check 10 rows per deck.

### R8-10 · P4 (polish and robustness)

- **a. Keychain write result is ignored.** `SpotifyAuth.apply` (`:126`) calls `secrets.write(...)` and drops the `Bool`. `KeychainStore.write` is delete-then-add, so a failed add loses the old refresh token as well. The session then works until the app restarts, and the user has to sign in again with no explanation. Use `SecItemUpdate`, and surface a failure.
- **b. Refresh bookkeeping.** In `SpotifyAuth.refresh` (`:106`) every waiter runs `defer { refreshTask = nil }`. A late waiter can clear a newer refresh task, so two refreshes can run at once. Only the creator should clear it.
- **c. Timeouts read as "offline".** `SpotifyClient.get` turns every non-offline transport error, including a timeout, into `.offline` ("You're offline.").
- **d. `play` waits before the reader opens.** `LyricsHomeViewModel.open(play: true)` awaits the Spotify play call (up to 10 s, or an app switch to Spotify on a 404) before it pushes the reader. Push first, play in the background.
- **e. 404 means two things.** `SpotifyClient.play` treats every 404 as "no active device". A removed track also gives 404, and then the Spotify app opens for nothing.
- **f. Translation prompt on every open.** `GlossService.prepare` clears `failed`, and `runBatch` calls `prepareTranslation()`, so a learner who declined the Korean language pack sees the system download prompt each time they open a song.
- **g. Single-word machine translation.** Apple Translation gets isolated eojeol, which gives poor glosses for inflected forms. It is labelled "Auto-translated", which is honest enough. Consider batching the line's words with the whole line as context if quality is a complaint.
- **h. Cache grows without limit.** `LyricsCacheStore` has no cap or eviction. Add a simple LRU (for example the 200 most recent songs). *(plausible: measure)*
- **i. Default arguments reach real services.** `AppEnvironment.init` (`:70`) defaults `spotify: SpotifyClient()` and `lyrics: LyricsService()`, so previews and tests built with the default environment get the real Keychain, the real cache directory and a real `URLSession`. Use in-memory defaults for `preview()`.
- **j. Unvalidated ids in URLs and JSON.** `SpotifyRequests.playlistItems`, `track` and `play` interpolate ids from Spotify's responses straight into the path and the JSON body. Spotify ids are base-62, so this is safe today, but a guard (`id.allSatisfy(\.isLetter || \.isNumber)`) costs one line.
- **k. Paused songs show as "Now playing".** `SpotifyCurrentlyPlaying.isPlaying` is decoded and never used.
- **l. Settings.** "Clear lyrics cache" doesn't clear `GlossService`'s in-memory glosses, and "Disconnect" doesn't pop an open reader or reset the picker (see R8-3).

## What's good

- **Pure, injectable design.** Core builds `HTTPRequestSpec`s and parses responses; the app only sends them. `AnyRNG`, `now` and `SecretStore` are injected. That is exactly why R8-2 is cheap to fix.
- **Auth.** PKCE S256, a `state` check that fails closed, scope list limited to what is used, refresh token only in the Keychain with `ThisDeviceOnly`, and `signOut` on a refused grant.
- **No secrets in git.** `Secrets.xcconfig` is gitignored, `Base.xcconfig` uses `#include?`, and CI builds with empty values (verified: the scratch build succeeded without the file).
- **Honest degradation.** "Unknown" (a failed request) is never cached as "not available". Missing translation is not an error. The Hangul check uses the lyrics, not Spotify's genre. Playlists Spotify won't share get an explanation, not an empty list.
- **Cache hygiene.** Atomic writes, backup exclusion, tolerant decoding, deletion of unreadable files, and a sanitised file name.
- **Rank preservation fix.** `UserDecks` now keeps `register`, `dialogue` and `sources` when it renumbers entries.
- **Content.** The K2 source target is met (70 %), ids and ranks are contiguous, and the verification doc records dropped candidates for the audit trail.

## Suggested fix order

1. **R8-1** wrong-song matching (small, local, high impact), with its tests.
2. **R7-1 / R8-2** make `HEAD` green, switch CI to `swift test`, add the Lyrics and R7/R8 session suites.
3. **R8-3** refresh the picker lists (a two-line change plus a reset).
4. **R8-4, R8-5** cache first, then the budget and the English-gap rule.
5. **R8-6, R8-7** title normalisation, `+`, pagination.
6. **R7-2** flush before `start()` (still the most likely cause of the owner's "repeated cards" complaint).
7. **R8-8** owner decision on lyric lines and Genius.
8. **R8-9 / R7-8** verification rows.
9. R8-10 items as time allows.

---

# Round 7 — R6 fixes, R7 owner fixes, R8 coverage-first sessions, and spec (business-analysis) comparison

- **Date:** 2026-11-17
- **Scope:** 30 commits, `e478fba..11e40ef`, with 49 Swift/YAML files changed (+1873/−384):
  - the R6 fix commits;
  - R7-F1…F7 and C2;
  - the content batch C3 (`e842c39`);
  - R8-S1, S2 and F1.
  
  R8-C1 and C2 (content) have not been delivered yet.
- **Read in full:**
  - core: `SessionComposer`, `DeckHistory`, `DeckCoverage`, `SchedulerConstants`, `Scheduler`, `SessionEngine`, `SwiftDataStatsStore`, `DeferredStatsStore`, `StatsStore`, `VocabDeck`;
  - app: `SessionViewModel` (lifecycle, quit/discard, mic F3);
  - the R8-S2 and R8-F1 diffs.
- **Read selectively:**
  - `IntroductionPolicy` (diff), `Records.closedAfterInterruption`, `ConjugationDeck` / `HangulReadingDeck` ranks, `Particles`;
  - `HomeView` (load, tiles, accessibility), `SummaryView` (abandoned), `FretboardNotesUI` / `IntervalsUI` `micAccepts`, `SpeechService`, `AudioSessionCoordinator`;
  - the CI workflows, `README`, and PLAN.md §10.5/§10.6/§17.
- **Not re-reviewed in depth:**
  - R7-F4 (fretboard redesign, +434 lines in `FretboardView`) and R7-F6 (`KoreanHeadline`). Both build cleanly, but they need the owner's on-device visual check.
- **Verification actually run** (in a scratch copy; the repo was not modified):
  - `swift test` on `HEAD`: **154 tests, 34 issues in 5 failing tests** (R7-1).
  - `xcodegen generate` + `xcodebuild` (iOS Simulator, Debug, unsigned): **BUILD SUCCEEDED, 0 warnings from app sources.**
  - **A multi-session simulation probe** (a scratch test that carries stats and `DeckHistory` from session to session, on bundled Core 1). Results:
    - Session 1 shows ranks 1–20 and session 2 shows ranks 21–40.
    - Ranks 3 and 7 were missed in session 1 with FNV gaps 4 and 2. They returned in sessions 5 and 3, exactly as the formula predicts.
    - A missed card that was retried correctly keeps `lastAnswerWasWrong == true`.
    - Both directions: 20 distinct entries per session. The first second direction appears in session 11 (205 entries ÷ 20), and coverage reaches 100 % after 25 sessions.
    - All answers wrong: at most 6 returning cards per session (the 30 % cap holds).
    - With `history: nil`, a missed card returns in the very next session (R7-6).
    - A 30-minute Core 5 session with all three directions (1,992-card pool, 402 cards shown) ran in **1.4 s in Debug**, about 3.5 ms per card.
  - Content scan (Python): ranks and ids are unique and contiguous in every `ko_*.json`. I also counted the entries that have no verification row.
  - Not run: device, Instruments, VoiceOver. Claims that need these are marked *(plausible: measure)*.

## Verdict

**R8's core is correct and well built.** The composer is pure and deterministic. It uses the injected RNG, needs no wire change, and its gap is stable per miss. Every owner scenario I could simulate (#1–#4) behaves as the owner asked. The opt-in `usesCoverageSessions` flag is a better design than the plan's "decks with ranks" rule, and it is recorded in §17.

**The release isn't green, and the safety net has fallen behind the behaviour.**
- `HEAD` fails 5 tests.
- CI never runs `swift test`, so nothing flagged it.
- R7 and R8, the two biggest behaviour changes since M1 (session composition and discard), arrived with **no new tests**. The suite still has 154 tests, as it did in Round 6 (R7-1).

**There are two spec mismatches the owner would notice:**
- A killed session counts toward a missed card's gap (R7-3).
- Once a learner falls behind, missed words return much later than the promised "2–4 sessions" (R7-4).

**R8 #5, the K-pop / K-drama content, isn't started.** Meanwhile, 515 new Korean entries arrived through C3 and the Core 5 extension with no verification rows (R7-8).

## Status of Round 6 findings

| ID | Status | Evidence |
|---|---|---|
| R6-1 · K2 not wired / HEAD red | 🟡 **Wired, but HEAD is red again** | `ko_media` is in `DeckCatalog.swift:73`. The count tests went stale again (R7-1). |
| R6-2 · media polite forms / shared glosses | ✅ Fixed | `f3f7028` (the 요 rule) and `8790aed` (glosses). The catalog validator test passes with 0 issues. |
| R6-3 · stale audio answers the next card | ✅ Fixed | `abac376`. `SessionEngine.answerEvaluated` records a pre-prompt onset as untimed (`SessionEngine.swift:269-271`). |
| R6-4 · content without plan or rows | 🔴 **Recurring** | Rows were added for Core 5 226–450 (`b1d7575`), but 515 newer entries have none (R7-8). |
| R6-5 · K2 targets | 🔴 Open | 89 of 169 media entries have a source (53 %, target ≥ 70 %). It was 66 % in Round 6, so the share is falling as unsourced entries are added. |
| R6-6 · PLAN contradicts the code | ✅ Fixed | `8148f54`. `undoLastGrade` is recorded as dropped (PLAN.md:577, :868). |
| R6-7a · Home aurora under the cover | ✅ Fixed | `HomeView.swift:106` passes `running: launch == nil`. |
| R6-7b · config decode per load | ⚪ Unchanged | It is still low priority. `initialConfig` decodes on every load (`AppEnvironment.swift:260`). |
| R6-8a · CI runs no tests | 🔴 Open | `core-tests.yml` still runs `swift build -c release` only. |
| R6-8b · hard-coded counts | 🔴 Open, and **it bit** | 3 of the 5 failures are these assertions (R7-1). |
| R3-7 · README wording | ✅ Fixed | README now reads "prompt → Reveal". |

## New findings (Round 7)

### R7-1 · P2 (High for delivery) · HEAD fails 5 tests, CI can't see it, and R7/R8 shipped without tests

**Failures on `HEAD`:**

| Test | Why it fails | Kind |
|---|---|---|
| `SessionEngineTests.gatedVocabSessionNeverShowsGatedCards` (30 issues) | It asserts `newPerSession` gating for vocab. R8-S1 and D2 removed that gating on purpose. | Stale test |
| `IntroductionPolicyTests.twentyCardSessionIntroducesExactlyTenLowestRanks` | R7-F1's fill rule now admits `targetDistinct` entries. | Stale test |
| `DeckContentTests.entryCountsMatchTracker` | Core 5 is now 664 (the test expects 450) and AION 2 is 232 (it expects 140). | R6-8b |
| `DeckContentTests.mediaDeckIsValidAndSlotsBeforeAion2` | Media is now 169 (the test expects 105). | R6-8b |

**What's missing:**
- R7-F1, F2 and F3 and R8-S1 and S2 each list acceptance scenarios "for the tester". None of them is a test yet.
- The composer, the gap formula, `lastAnswerWasWrong`, `DeckCoverage`, `discard()` and the `SwiftDataStatsStore.discard` single-save path have no coverage at all.
- My probe shows these scenarios translate directly into tests. The probe harness is about 40 lines: a `Sim` that carries `stats` and `DeckHistory` between engines.

**Fix:**
- *(tester)* Rewrite the 2 stale tests to the new rules.
- Replace exact counts with floors plus id/rank contiguity (R6-8b).
- Add the R7 and R8 scenario tests.
- Switch CI to `swift test` (R6-8a).

Until this is done, every later round can regress R8 without anyone noticing.

### R7-2 · P3 (Medium, correctness, *plausible: measure*) · A new session can read stats before the previous session's writes are flushed

**Where:**
- `SessionViewModel.apply` (`SessionViewModel.swift:485-496`) closes the recorder in an unstructured `Task`.
- `start()` (`:153-160`) reads `stats`, `baseline` and `deckHistory` straight from the store, without waiting for that task.

**Most exposed path: discard.**
- `vm.discarded` dismisses the cover immediately (`SessionView.swift:69`).
- The `.discardSession` effect sits at the end of the recorder queue, behind the pending attempt and stats writes. Each write does its own `modelContext.save()`.

**What can go wrong** if the user re-opens the same deck before the queue drains:
- The new engine's `initialStats` contain the stats that are about to be discarded. The composer treats those cards as seen.
- If that session is then also discarded, it "restores" the stale values over the discard.

**After a normal finish:** the same race can make the next session repeat cards from the previous one. This is exactly the owner's complaint #2. The window is small because Summary sits in between.

**Fix:** keep the close task on `AppEnvironment` (for example, `pendingFlush: Task<Void, Never>?`) and `await` it at the top of `start()`.

### R7-3 · P3 (spec mismatch) · Killed sessions *do* count toward a missed card's gap

**Spec:** PLAN_R8 S1 says "killed sessions are not `.completed`, so neither counts", and the acceptance list says "Discarded **and killed** sessions don't advance 'sessions since a miss'".

**Code:** `SessionRecord.closedAfterInterruption` (`Records.swift:36-46`), run at launch, marks a killed session `.completed` whenever it has a counted attempt. `deckHistory(for:)` then counts it.

So a session with one answered card, after which the app was swiped away, advances every pending miss by one session. The plan's premise is wrong. R7-F2 §6 explicitly left `closeInterruptedSessions` unchanged.

**Fix (planner decision):**
- either accept this and correct the plan's acceptance line;
- or have `deckHistory` count only sessions whose `endedAt` came from a normal finish, or that reached ≥ N counted cards.

The second option needs a way to tell the two cases apart. `SessionRecord` has no such field, and adding one is a wire change.

### R7-4 · P3 (business, owner-facing) · Under the 30 % cap, "wrong words come back after 2–4 sessions" holds only while the learner keeps up

**Measured:** in the all-wrong probe, each 20-card session adds 14 new misses but returns at most 6 (`reviewSlots = floor(20 × 0.3)`).

**What happens:**
- The due backlog grows without bound while coverage keeps marching forward.
- A word missed in session 3 can wait dozens of sessions. The composer orders `head` (6 due) → fresh → partial → remaining due, so leftover due words are reached only after **all fresh and all partial** entries, which on Core 5 means hundreds of sessions.
- `wrongGapSessions` is therefore a *minimum*, not the promised window.

**Why it matters:** this matches D5 as written, but not the owner's request #3 ("come back after a while, in a random later session"). A learner who is struggling sees new words they keep failing, and their misses are effectively parked.

**Options for the owner and planner:**
- (a) Raise the cap when the backlog is large. For example, `reviewShare` could scale with `dueCount / targetEntries`, up to 0.6.
- (b) Pause new material when there are more than *k* due misses.
- (c) Accept it, and state in PLAN §10.5 that the gap is a minimum.

### R7-5 · P3 (business / UX) · The coverage ring now applies to every deck, including decks that aren't composed by coverage

**Scope of the ring:** `DeckRowInfo.coverage` is computed for **all** decks (`HomeView.load`), so music decks, Particles and the small default Hangul pool all show the ring. Only vocab, conjugation and Hangul reading use the composer.

**Effects:**
- **Particles:** PLAN_R8 S1 lists it in scope, but it has no `introductionRank`, so it keeps adaptive selection. That deviation isn't recorded in §17. Its pool is a dozen particle × ending cards with random nouns, so one good session shows ✓ "done" for a drill that is effectively endless.
- **Music decks:** the same happens on small pools such as fretboard notes on one string. The owner's complaint #4 ("one perfect session shows 100 %") comes back for these decks.
- **Hangul Reading:** the default pool is 20 cards (probe). One 20-card all-correct session shows ✓.

**Fix (planner/owner):**
- Decide whether non-coverage decks keep the accuracy ring.
- Record the Particles deviation in §17.

### R7-6 · P4 · `SessionEngine(history: nil)` silently means "every miss is due now"

**Context:** the §17 deviation (2) made `history` optional so that "no history given" can be told apart from "empty history". The app always passes a history, but any future caller that forgets it will bring misses back in the very next session. The probe confirms this: rank 3 returns in session 2.

**Fix:**
- Make the parameter non-optional (`DeckHistory`).
- Keep the "all due" behaviour behind an explicit `.allDue` value, or keep it test-only.

### R7-7 · P4 (performance) · Per-pick cost is O(pool), with a median sort, done once or twice per card

**Where:**
- `Scheduler.select` builds a `WeightCalculator` on every call (`Scheduler.swift:95`). That is a median over every seen card's EWMA, plus a full pass over the pool even when only about 20 keys are `allowed`.
- With top-up (`SessionEngine.swift:374-381`), `select` runs twice per card.

**Measured:** about 3.5 ms per card in Debug on the largest pool (1,992 cards). That's fine today *(plausible: measure in Release on device)*.

**Cheap win if it ever matters:** when `allowed != nil`, iterate only `allowed` (keep an index map `key → pool index`), and compute `referenceMs` once per session.

**Related:**
- `deckHistory(for:)` decodes every `SDSession.configData` JSON just to read `startedAt`.
- `start()` also calls `baselineOfLastCompletedSession`, which fetches the same sessions again.

A predicate on `statusRaw` plus `propertiesToFetch`, or one shared fetch, would halve the work. It is low priority: it grows linearly with sessions per deck.

### R7-8 · P3 (content integrity) · 515 Korean entries have no verification row, and 0 of all rows are ticked

| Deck | Entries without a row in `docs/*-verification.md` |
|---|---|
| Core 5 | 214 (`ko.core.1320`–`1533`, the 451→664 extension in `c34d745`) |
| Core 6 | 156 (new in C3) |
| AION 2 | 92 (`0141`–`0232`) |
| Slang | 53 (new in C3) |

- `docs/core-verification.md` still says "have not yet been checked", and no ✓ appears anywhere in it.
- C3 was done at the owner's request, which is fine because the owner may waive plan-first. But its §17 line doesn't schedule the rows.
- This is R4-6 and R6-4 again, and the gap keeps widening.

**Fix:** *(content agent)* append the rows, as `b1d7575` did. *(owner)* do a 10-row spot-check per deck before any external release.

### R7-9 · P4 (polish)

- **a. "100%" without a ✓.**
  - `CoverageRing` shows ✓ only at `coverage >= 0.9999` (`HomeView.swift:415`).
  - `Fmt.percent` rounds, so anything from 99.5 % up shows "100%" with no ✓. On Core 5 with all three directions, that is up to 9 uncovered cards.
  - Use `floor` for the coverage text, or show ✓ only when `coveredCount == cardCount`.
- **b. The ring's identifier is unreachable.** `deckCoverageRing` is set on a child of an element with `.accessibilityElement(children: .ignore)` (`HomeView.swift:430` vs `:502`, `:567`), so XCUITest can't find it. Move the identifier to the tile, or set it as a value.
- **c. Inconsistent scopes on Home.** `DeckRowInfo.make` computes accuracy, median and last-seen over **all** of the deck's stats rows (`HomeView.swift:25`), including F7-hidden entries and other option sets. Coverage uses the pool. Filter all four by `poolKeys` so the numbers on the card agree.
- **d. Stats screen.** `StatsOverview` still uses an accuracy ring, and it passes `Array(data.stats.keys)` as `poolKeys`, so its `coverage` would mean "covered ÷ attempted". It isn't displayed today. Either use the real pool or don't compute coverage there.
- **e. Stale tracker.** PLAN_R8 §2 still shows S1 and S2 as ☐, although both are committed (`669892e`, `3b68b8a`).
- **f. Mic "Correct" speech isn't stopped before the next prompt** *(plausible: measure)*. The correct-note path grades through `apply(engine.answerDetected…)`, not through `grade()`, so `env.speech.stop()` never runs. The next prompt arms the mic after 0.9 s while "Correct" may still be playing. R6-3's pre-arm filter doesn't cover audio *after* arming. If spoken feedback ever produces a phantom "Try again" on the next card, stop speech, or delay `setListening(true)` until it finishes.

## Spec comparison (business-analysis view)

**R8 (PLAN_R8_COVERAGE):**

| Item | Requirement | Delivered | Gap |
|---|---|---|---|
| #1 | X distinct cards per session | ✅ Verified (probe) | — |
| #2 | the next session continues through the deck | ✅ Verified: session 2 is ranks 21–40 | R7-2 (race) |
| #3 | misses return in a random session 2–4 later, never the next one | 🟡 Holds only while due misses ≤ 30 % of the session | R7-3, R7-4 |
| #4 | ring = coverage (20 of 100 = 20 %) | ✅ Data and UI | R7-5 (scope), R7-9a/b/c |
| #5 | +120 K-pop and +100 K-drama phrases | ❌ Not started (C1, C2 ☐; media is still 169, target ≥ 389) | — |
| S1 | composer, `DeckHistory`, `allowed`/top-up, constants, PLAN §10.5/§10.6/§17 | ✅ (Particles deviation not recorded) | R7-5 |
| S2 | `DeckCoverage`, `deckHistory`, `cardKeys` cache, `DeckRowInfo` | ✅ | R7-9c/d |
| F1 | ring, caption, accuracy chip, ✓, animation, steppers hidden, previews | ✅ | R7-9a/b |
| Acceptance: "music decks byte-identical" | | ✅ By construction: `usesCoverageSessions == false` returns before consuming the RNG, and `topUpQueue` stays empty | — |
| Acceptance: "killed sessions don't count" | | ❌ | R7-3 |
| Acceptance: `PersistedFormatCheck` untouched | | ✅ No wire change | — |

**R7 (PLAN_R7_FIXES):**
- F1, F2, F3, F5 and F7 meet their code-level requirements as read. The spoken feedback setting, the octave-tolerant `micAccepts`, the abandoned-summary defence, the discard dialog and the single-save discard are all present.
- F4 and F6 need the owner's device check.
- Every R7 acceptance scenario is still untested (R7-1).

**Product-level status:**

| Milestone | User-visible state | Blocking items |
|---|---|---|
| M1–M3 | complete | on-device QA (fretboard F4, mic F3) |
| M4 | complete; Core 6 and Slang added | R7-8 (verification) |
| M5 | media deck visible, 169 entries | R6-5 (53 % sourced), R8-C1/C2 |
| R8 | coverage-first sessions and coverage ring work | R7-1 (tests/CI), R7-3, R7-4 |

## What's good

- **The composer is a clean, pure function.** It needs no stored state: the FNV gap derives from `lastWrongAt`, and history derives from existing session rows. The plan's "no wire change" rule is fully met.
- **`lastAnswerWasWrong` lives in one place.** The composer and the coverage metric share it, as S2 asked. The "missed and then retried correctly stays wrong" rule falls out naturally.
- **The opt-in `usesCoverageSessions` was the right call over "has ranks".** Triads, scales, chords, theory and progressions keep their adaptive behaviour. The deviation is documented.
- **The top-up keeps minute-based sessions fresh** instead of falling back to repeats.
- **The discard is atomic.** It is one `discard(session:restore:delete:deck:)` with one `save()`, and its ordering is guaranteed by the serial recorder.
- **The R6 follow-ups landed promptly:** R6-2, R6-3, R6-6 and R6-7a, plus the README.
- **The app builds with 0 source warnings.**

## Suggested fix order

1. **R7-1** Green the suite: rewrite the 2 stale tests and switch the count asserts to floors. Add the R7/R8 scenario tests, and make CI run `swift test`. *(tester)*
2. **R7-2** Await the previous session's flush in `start()`. *(implementor)*
3. **R7-3 / R7-4 / R7-5** Owner and planner decisions: killed sessions, behaviour when the learner falls behind, and where the ring applies (plus the Particles §17 line). *(planner + owner)*
4. **R8-C1, then C2** Content. Also restore the media source share toward 70 %. *(content agent)*
5. **R7-8** Verification rows for the 515 entries, plus the owner spot-check. *(content agent + owner)*
6. **R7-9** Polish. **R7-6 / R7-7** when convenient. *(frontend / implementor)*

---

# Round 6 — R5 fixes, K2 content, performance pass, and spec (business-analysis) comparison

- **Date:** 2026-11-17
- **Scope:**
  1. Committed R5 work: `9339c46` (R4 fixes + R5-1/2/3/6), `74d9aa1` (R3-2 aurora), `37134f1` (R5-5 b snippet button), `c0e739d` (tests).
  2. **Uncommitted** content in the working tree: new `ko_media.json` (105 entries) and `docs/media-verification.md`; `ko_core_5.json` 225 → 450; `ko_aion2.json` 81 → 140.
  3. A performance pass over the changed paths (Home load, mic pipeline, aurora).
  4. A requirement-by-requirement comparison of PLAN_R5_FIXES (S1–S7, P1), PLAN_M5 (K2, K5) and the PLAN.md normative sections with the code.
- **Read in full:** `AppEnvironment`, `PitchDetector`, `MicAnswerController` (+ `MicFrameTracker`), `SwiftDataStatsStore`, `DeferredStatsStore`, `StatsStore`, `AnswerMatcher` (matching half), `SessionViewModel` (grading + mic), `DeckCatalog` (file list), and the diffs of `37134f1` and `74d9aa1`.
- **Read selectively:** `HomeView.load`, `SessionEngine.answerEvaluated/pause`, `FretboardNotesUI`/`IntervalsUI` `micAccepts`, `DeckUI.onReveal`, `VocabUI.typedAnswer`, the CI workflows, `project.yml`.
- **Verification actually run** (a scratch copy; the repo was not modified):
  - `swift build --build-tests`: **passes**. `swift test` with the working tree: **154 tests in 13 suites pass**.
  - `xcodegen generate` + `xcodebuild` (iOS Simulator, Debug, unsigned): **BUILD SUCCEEDED, 0 warnings from app sources** (R5-6c is confirmed fixed).
  - **Content diff (Python):** `ko_core_5` and `ko_aion2` only *add* entries. 0 existing ids were changed or removed, so the id-stability rule holds. Cross-deck duplicate Hangul and K2 statistics were also computed.
  - **Matcher probe** (scratch test): the polite forms of the media phrases, and duplicate glosses inside `ko_media`.
  - Not run: device or Instruments profiling. Claims that need it are marked *(plausible: measure)*. I did **not** re-fetch the K2 citations; that is the owner's 10-reference spot-check (R6-5).

## Verdict

**The R5 code fixes are good and complete.** S1 (R5-1), S2 (R5-2), S3 (R5-3), S4 (R3-2), S5 (R5-6 a/b/c) and S6 (R5-5 b) are implemented as specified, and the build is warning-free. The tests now compile and pass (R4-1 is largely resolved). The R5-1 must-reject rows (몰라요/알다, 없어요/있다) are in `AnswerMatcherTests`.

**The milestone is not finished from the user's point of view.**
- **The K2 deck is written but not shipped.** `ko_media.json` exists, but `DeckCatalog.bundledVocabFiles` still has `"ko_media"` commented out. The content is uncommitted, and committed `HEAD` is red without it (R6-1).
- **The media deck grades its own polite forms as wrong in en→ko typed mode** (R6-2).

**One mic correctness issue predates R5-3, but R5-3's design makes it explicit.** Stale audio from the previous card can answer the next card instantly, with a 0 ms response time (R6-3).

**Process gaps are growing.**
- 284 new Korean entries arrived with no plan segment, no verification rows and no §17 entry (R6-4).
- The planner's P1 follow-up (R5-4) is still not done, so PLAN.md still contradicts the code (R6-6).

## Status of Round 5 findings

| ID | Status | Evidence |
|---|---|---|
| R5-1 · typed vocab accepts the opposite word | ✅ Fixed | `ConjForm.affirmative` is passed via `allAcceptedForms(…, forms:)` (`AnswerMatcher.swift:102`). Tests: `AnswerMatcherTests.swift:76-77` reject 몰라요/알다 and 없어요/있다, while 몰라요/모르다 stays close (line 71). |
| R5-2 · Home rebuilds every pool on main | ✅ Fixed | `AppEnvironment.cardCount(for:options:)` (line 232) is cleared in `reloadCatalog()`. `stats(forDecks:)` is a protocol requirement; SwiftData makes one fetch (`SwiftDataStatsStore.swift:30-38`). `HomeView.load` makes one store call. |
| R5-3 · YIN runs while not listening | ✅ Fixed | `PitchDetector.active` is an `OSAllocatedUnfairLock`, and `append` analyses only `if filled == frameLength, isActive` (line 94). The ring keeps filling. See **R6-3** for a consequence. |
| R5-4 · PLAN body contradicts code | 🔴 **Open** | Planner P1 has not run. Details in R6-6. |
| R5-5 · M5 unreachable | 🟡 **Half** | (b) is done: `VocabUI` always embeds `MediaSnippetView`; plain entries get `AddSnippetButton`. (a) K2 content exists but is **not wired and not committed** (R6-1). |
| R5-6 · polish a/b/c | ✅ Fixed | (a) tombstones plus the delete-all flag (`AppEnvironment.swift:24-27, 195-229`); (b) `grade(correct:haptic:)`, with `gradeAutoAnswer` passing `false`; (c) the build has 0 app warnings. |
| R3-2 · aurora renders continuously | 🟡 **Mostly fixed** | `AuroraBackground(animated:)`, `SessionView` passes `false`, and every aurora pauses when the scene isn't active. Home's aurora behind the session `fullScreenCover` may still tick (R6-7a). |
| R3-7 · README wording | 🔴 Open | `README.md:24, 31` are unchanged. |
| R4-1 · tests / CI | 🟡 **Mostly fixed** | 154 tests pass with the working tree. Remaining: `HEAD` is red without the uncommitted content (R6-1); `.github/workflows/core-tests.yml` runs only `swift build -c release`, never `swift test`; there is still no App test target. |
| R4-6 · Korean content unverified | 🔴 **Open, and growing** | `docs/core-verification.md` still has no ✓ ticks, and the 225 new Core 5 entries have no rows at all (R6-4). |

## New findings (Round 6)

### R6-1 · P2 (High for delivery) · K2 is half-landed: the deck isn't in the catalog, and committed HEAD is red

**Files:**
- `Packages/MemoriseCore/Sources/MemoriseCore/Decks/DeckCatalog.swift:69-73` (`// "ko_media", // M5 K2`)
- `Packages/MemoriseCore/Tests/MemoriseCoreTests/DeckContentTests.swift:53-70`
- `PLAN_R5_FIXES.md` §2 (S7 ☐), `PLAN_M5_KOREAN_MEDIA.md:207` (K2 ☐)

**What's wrong:**
1. **Users never see the deck.** S7 says the `DeckCatalog` uncomment is *the only code change* of K2, and it wasn't made. `ko_media.json` is in the bundle but no code path loads it into the catalog. So the "In a scene" and "Heard in" panels are still dead in production, which was the whole point of R5-5 (a).
2. **The test codifies the gap instead of the goal.** `mediaDeckIsValidAndSlotsBeforeAion2` filters `"ko_media"` out of the list, re-inserts it by hand and asserts the order of the *simulated* list. Once the deck is wired, the test still passes, and today it passes while the deck is missing. It can't catch a regression either way.
3. **Committed `HEAD` (`c0e739d`) fails 3 checks.** The tests assert 450 Core 5 entries, 140 AION entries and that `ko_media` loads, but that content exists only in the working tree (confirmed by the tester's handoff). Anyone who checks out the branch, and CI if it ran tests, sees red.

**Fix direction (one commit, `K2: ko_media.json (105 entries, 88 verified refs)`):**
- Commit `ko_media.json` and `docs/media-verification.md`.
- Uncomment `"ko_media"` (before `"ko_aion2"`) and update the doc comment at `DeckCatalog.swift:67-68`.
- Change the test to assert the **real** `DeckCatalog.builtIn().catalog` order (`ko.media` before `ko.aion2`) and `report.loadFailures.isEmpty`.
- Commit the Core 5 and AION content **separately**, after R6-4's decision, so each content change has its own audit trail.
- Tick S7 and K2 only after the owner's 10-reference spot-check (R6-5).

### R6-2 · P2 (Medium-High) · Media deck, en→ko typed: the polite form of the phrase is graded *wrong*, and 7 glosses are shared by two entries

**Files:**
- `App/Sources/DeckUI/VocabUI.swift:40` (`expected: [e.hangul]`, `isPredicate` false for `pos: expression`)
- `Korean/AnswerMatcher.swift:110-113`
- `ko_media.json`

**Verified (probe, en→ko typed):**

| Input | Expected | Verdict |
|---|---|---|
| 미안해요 | 미안해 | **wrong** |
| 사랑해요 | 사랑해 | **wrong** |
| 괜찮아요 | 괜찮아 | **wrong** |
| 보고 싶어요 | 보고 싶어 | **wrong** |
| 고마워요 | 고마워 | **wrong** |
| 진짜 | 진짜? | exact (punctuation is stripped, as intended) |

- All 105 entries are `pos: expression`, so the R4-2 conjugation rule never applies to them.
- For 3+ syllables, adding 요 is a jamo distance of 2 (ㅇ + ㅛ), and for 1–2 syllables only a batchim slip is close. So the most natural learner answer is **wrong, not even close**.
- The entries' own `notes` teach these exact forms ("Polite: 사랑해요").

**Duplicate glosses inside the deck:**

| Gloss | Entries |
|---|---|
| cheer up | 힘을 내 / 힘내 |
| tell me | 말해줘 / 말해봐 |
| I don't care | 관심 없어 / 신경 안 써 |
| don't worry | 걱정하지 마 / 걱정 마 |
| trust me | 내 말 믿어 / 믿어 줘 |
| no way! | 대박 / 거짓말 |
| bye | 안녕 / 잘 가 |

For these, en→ko accepts only one entry, and the equally correct sibling is graded wrong.

**Why it matters:**
- PLAN_M5 §3 (line 113) allows en→ko for this deck. It only mitigates ambiguity with the register chip, which doesn't help grading.
- Wrong verdicts raise `ewmaError`, so the scheduler drills phrases the learner actually knows.
- This is the mirror image of R5-1: there, a wrong answer counted as correct; here, a correct answer counts as wrong.

**Fix direction:**
- **Matcher (core, smallest):** for non-predicate Hangul, treat `a == b + "요"` and `b == a + "요"` as **close**. This covers 해/해요, 아/아요 and 어/어요. It is safe for nouns, because a noun + 요 is still the same word. Add golden rows, including must-stay-wrong ones (사랑 vs 사랑해).
- **Content:** make the first glosses distinct ("cheer up (lit. 'find strength')", "cheer up (short)") or merge the near-duplicates. Then add a validator **warning** for a duplicate first gloss within one deck. This is additive and needs no wire change.
- **Alternative:** an optional `accepted: [String]` field on `VocabEntry`. It is additive (defaults to `[]`), but it is a schema touch, so the owner would decide. Not needed if the matcher rule lands.

### R6-3 · P2 (Medium) · Stale audio in the detector ring can answer the next card instantly, with a 0 ms response time

**Files:**
- `App/Sources/Services/PitchDetector.swift:77-99` (the ring keeps filling while inactive, by design since R5-3)
- `MicAnswerController.swift:104-110, 188-196`
- `SessionViewModel.swift:275-282`
- `SessionEngine.swift:222-228`

**Mechanism:**
1. During the reveal, `DeckUI.onReveal` plays the answer note through the speaker (`playNoteOnReveal`), and the user's own guitar note is still ringing.
2. The user grades and the next prompt appears. `setListening(true)` resets the tracker and re-activates YIN on a ring that holds the last **2,048 samples (≈ 43 ms) of pre-arm audio**.
3. The first 3 analysed frames, which is all `stableFrames` needs, are mostly pre-arm audio. A sustained note therefore becomes "stable" within about 32 ms of the prompt appearing.
4. If its pitch class matches the new card, the note is accepted. `FretboardNotesUI.micAccepts` accepts the pitch class anywhere on the card's string from 0 to 12+, so a different card with the same pitch class is common: roughly 1 in 12 for fretboard notes.
5. `answerEvaluated` clamps `max(at, start)`, so `responseMs = 0`. With `countsTime: true` it is written into `ewmaResponseMs` and `bestResponseMs`, and it drags the deck median down.
6. A non-matching stale note shows "Heard X" on the new card. This is cosmetic but confusing.

This existed before R5-3, because YIN ran continuously and the tracker reset on arm. However, R5-3's stated goal, "re-arming has a full frame at once", is exactly the stale frame. *(plausible: measure how often it happens on device with "Play note on reveal" on)*

**Fix direction:**
- In `MicFrameTracker.setListening(true)`, store `armHostSeconds` (pass `MicAnswerController.hostNowSeconds` in).
- In `process`, ignore every frame whose **window start** (`hostSeconds − (frameLength − hop)/sampleRate`) is before `armHostSeconds`. The first usable frame then arrives about 43 ms after arming, which is far below human reaction time, so nothing perceptible is lost.
- **Defence in depth (core):** in `answerEvaluated`, if `at < start`, record the answer with `countsTime: false` instead of clamping to a perfect 0 ms. Add a golden row for it.
- The ring can keep filling; that part of R5-3 is fine.

### R6-4 · P3 (Medium for content integrity) · 284 new Korean entries with no plan, no §17 entry and no verification rows

**Files:**
- `ko_core_5.json`: +225 entries, `ko.core.1095`–`ko.core.1319`, ranks 226–450
- `ko_aion2.json`: +59 entries, `ko.aion2.0082`–`0140`
- `docs/core-verification.md:687`: the header still says "Korean Core 5 (225 entries)"

**What's wrong:**
- No plan segment asked for these additions: PLAN.md §15, PLAN_M4 M4-1 and PLAN_R5_FIXES are all silent, and §17 has no entry. The owner's preference for large pools (memory) is a reason to do it, not a substitute for recording it.
- PLAN_M4 M4-1 *Accept* requires 0 validator errors (✅ verified by the tests), a POS and tag split in the PR, and an **owner spot-check of 15 random entries per deck**. Neither the split nor the spot-check exists for the new entries, and the new Core 5 entries have no verification rows.
- R4-6 already flagged that Core 2–5 were "authored from the author's own knowledge". This change doubles the unchecked surface of Core 5.

**What's fine (verified):**
- 0 existing ids were changed or removed, and ids are contiguous.
- Every verb and adjective has a `conj` class.
- The new Core 5 POS mix is varied: noun 67, verb 55, adverb 38, adjective 18 and others.
- The AION additions are all nouns. That is appropriate for game terms, but a sample like 장판 "ground AoE zone" and 기믹 "boss mechanic" is community slang that needs the owner's in-game confirmation.

**Fix direction:**
- **Planner:** add a §17 entry and a tracker line (e.g. "M4-1b Core 5 extension + AION 2 extension").
- **Content agent:** append verification rows for `ko.core.1095`–`1319`, and add an AION table (none exists).
- **Owner:** 15-entry spot-check per deck.
- **Then:** commit separately from K2 (R6-1).
- **Note:** six phrases also appear in core decks (어떡해, 안녕, 화이팅, 거짓말, 오빠, 언니). That's allowed, because the duplicate check is limited to `ko.core.*`. They will have separate stats; mention it in the §17 entry.

### R6-5 · P3 (business) · K2 misses its own acceptance targets and the owner's priorities

**Source:** `docs/media-verification.md` header and the `ko_media.json` statistics. The agent reported the misses honestly and did not pad, which is the right behaviour.

| Requirement (PLAN_R5_FIXES S7 / PLAN_M5 K2) | Target | Delivered |
|---|---|---|
| Entries | ≈ 80 | **105** ✅ |
| Entries with ≥ 1 VERIFIED reference | ≥ 70 % | **66 %** (69/105) ❌ |
| Split of verified references (song / show / drama) | ≈ 50 / 30 / 20 | **91 / 1 / 8** (80 / 1 / 7) ❌ |
| Owner priority shows: Kian's Bizarre B&B, The Devil's Plan | first among shows | **0 references** (1 PROPOSED, paywalled) ❌ |
| Priority artists: BTS, LE SSERAFIM, TWICE, NewJeans, ILLIT | first | TWICE 34, BTS 20, NewJeans 14, ILLIT 6, LE SSERAFIM 6 ✅ |
| Original 2–3-line dialogue containing the phrase | every entry | 105/105 ✅ (verified by script) |
| No `url` key, `context` ≤ 200 characters | every reference | ✅ |
| Owner spot-check of 10 references | before ticking K2 | **not done** |

**Concerns:**
- **a. Locators are guesses shown to users as facts.** The table says section labels are "best estimates, because Bugs lyrics have no section markers". "Heard in … verse 2" is user-visible, and a wrong one undermines the "every reference is verified" promise in PLAN_M5 §2. Use `locator: "lyrics"` (or omit the section) unless an official MV or subtitle confirms it.
- **b. Single-source songs.** 80 of 88 references cite only a Bugs track page whose lyrics are "registered by Bugs, not label-supplied". S7 lists Bugs as acceptable, so this is not a violation, but the owner's spot-check should prefer song rows.
- **c. Possible wrong track pages.**
  - The NewJeans citations use 7-digit Bugs ids (`6186207`, `6171084`, `6184997`) while every other artist has 8-digit ids.
  - FIRE (2016) cites `32563047`, which is newer than Life Goes On (2020, `32075135`). That may be a re-release page, not the original, so check the year.
  - *(plausible: verify during the spot-check)*

**Fix direction:**
- The **owner** decides whether 66 % and 91/1/8 are acceptable for shipping now, with K2b raising them, and records that in §17.
- The **content agent** changes the guessed locators to `"lyrics"` before the K2 commit.

### R6-6 · P3 (spec integrity) · The P1 planner follow-up has not run, so the PLAN still contradicts the code

Everything in R5-4 still applies, verified line by line today:

| Location | Says | Code / decision |
|---|---|---|
| PLAN.md §9.2 table, `choice` row (line 541) | time EWMA: **yes** | **no** (R4-4) |
| PLAN.md §9.2 paragraph (line 545) | "time is skipped for every card, including any card that falls back to touch" | a touch fallback counts; a mic-timeout reveal doesn't |
| PLAN_M4 M4-0 step 2 (line 83) | `countsTime` "derived from `config.inputMode == .typed`" | per answer, via `ok(countsTime:)` |
| PLAN.md §15 M4 status (line 935) | "Core 5 is still to do" | done, and now 450 entries |
| PLAN.md §9.3 (line 567), §12 S6 (line 842), §17 tracker (line 974) | `undoLastGrade` (stretch) | **dropped** by owner decision D2 |
| README.md:24, 31 | "= OK", "prompt → OK" | R3-7 |
| PLAN_R5_FIXES §2 S7, PLAN_M5 §6 K2/K5 | ☐ | K2 content exists (R6-1); K5 not started |

**Additional gaps:**
- **K5 (Integration and QA)** has no owner and no schedule.
  - Its step 2, the media deck defaulting to ko→en, is already satisfied by `VocabOptions.direction = .koToEn`.
  - Steps 1, 3 and 4 are not done: Home placement waits on R6-1, there are no README QA checks for K3/K4, and there is no M5 tracker row in PLAN.md §17.
- **G6 device checks** (PLAN_M1_FIXES:355) are still ☐. They are the only M1 item left.

**Fix direction:** run P1 now. Its trigger ("after the R4 batch + S1 commit lands") was met by `9339c46`. Then schedule K5 after R6-1.

### R6-7 · P3/P4 (performance)

**a. Home's aurora may keep ticking under the session cover** *(plausible: measure)*.
- `HomeView.swift:143` presents the session with `.fullScreenCover`, so Home stays in the hierarchy.
- Its `AuroraBackground` is `animated: true` and the scene is `.active`, so its `TimelineView(.animation(minimumInterval: 1/30))` is not paused. Whether SwiftUI skips redrawing a fully covered view is not guaranteed.
- **Check:** use Instruments (Core Animation FPS, or a `Self._printChanges()` breakpoint in the Canvas) during a session.
- **Fix if it ticks:** pass `animated: launch == nil` from Home, and do the same for any other presenter of `SessionView`. This is a one-line change.

**b. `HomeView.load` still decodes 27 saved configs per load.**
- `env.initialConfig(for:)` runs a UserDefaults JSON decode plus `sanitize` for every deck, on every `dataVersion` bump.
- Each decode is sub-millisecond, so this is low priority. If Home timing still shows up in the G5 log, cache the decoded config per deck in `SessionConfigStore` and invalidate it on `save`.

**c. Fine, no action:**
- `stats(forDecks:)` fetches every `SDItemStats` row in one go, which is the same rows the 27 calls fetched before, with one actor hop instead of 27.
- The `cardCount` cache is bounded by (decks × option sets actually used).
- YIN is gated, and the ring memmove is about 8 KB per hop.

### R6-8 · P4 (polish)

- **a. CI never runs the tests.** `core-tests.yml` runs `swift build -c release` only. Now that the tests compile, change it to `swift test`. Linux `swift:6.0` should work, because core is Foundation-only; confirm `precomposedStringWithCanonicalMapping` on Linux Foundation. The change is meaningful only after R6-1, because `HEAD` is red today.
- **b. `DeckContentTests` hard-codes the media count** (`#expect(media.entries.count == 105)`). Every K2b addition will break it. Assert `≥ 80` (the plan's floor) plus id contiguity instead. Core 5 (450) and AION (140) have the same problem.
- **c. Ten media entries have no `register`:** 쉿, 깐부, 무야호, 화이팅, 아이고, 영원히, 거짓말, 오빠, 언니, 제발. That's consistent with PLAN_M5 §7's "-" (register-neutral), so no action. It is noted here so the next reviewer doesn't re-flag it.

## Spec comparison (business-analysis view)

**R5 plan (PLAN_R5_FIXES):**

| Item | Requirement | Delivered | Gap |
|---|---|---|---|
| S1 | negatives not accepted in typed vocab; drill unchanged | ✅ | none |
| S2 | count cache, batched stats, one store call | ✅ | R6-7b (minor) |
| S3 | YIN only while listening | ✅ | R6-3 (consequence) |
| S4 | aurora frozen in sessions | ✅ | R6-7a (plausible) |
| S5 | tombstones, single haptic, 0 warnings | ✅ | none |
| S6 | snippet button on every vocab reveal | ✅ | device QA (K5) |
| S7 | K2 content + catalog line | 🟡 | R6-1, R6-5 |
| P1 | PLAN/README alignment, `undoLastGrade` removal | ❌ | R6-6 |
| Commit rule | "one segment = one commit, `R5-<n>:`" | 🟡 | S1, S2, S3 and S5 went into one commit (`9339c46`), and S4 is labelled `R3-2`. Acceptable, because the plan allowed bundling with the R4 batch, but the history no longer maps one-to-one to segments. |

**Product-level status (what a user can do today, on `HEAD` + the working tree):**

| Milestone | User-visible state | Blocking items |
|---|---|---|
| M1 / M1.1 | complete | G6 device checks |
| M2 / M3 | complete in code | R6-3 (mic accuracy), on-device QA |
| M4 | complete; Core 5 extended | R4-6 / R6-4 content verification |
| M5 | **"My snippet" works on every vocab card; the media deck is not visible** | R6-1, R6-2, R6-5, K5 |

## What's good

- **R5-2 is done properly.** It uses a protocol requirement (not an extension-only method), so `any StatsStore` dispatches dynamically. SwiftData does a single `IN` fetch, and the cache is cleared at the one place the catalog changes.
- **The R5-3 gating is minimal and thread-correct.** It uses an unfair lock, `setActive` at every lifecycle point (`start`, `stop`, `setListening`), and the ring stays warm.
- **The R5-6a tombstones cover delete-all too.** A later save correctly wins over an earlier delete.
- **The S6 compact button is a good product call.** One quiet affordance, VoiceOver label with the Hangul, Reduce-Motion aware, and it blur-morphs into the full section on save.
- **The tests are back.** 154 tests, and the R5-1 must-reject rows are encoded.
- **The content discipline is real.** Not a single existing id changed across 284 additions. K2 dropped references it couldn't verify, kept PROPOSED rows out of the JSON, quoted no lyrics, and reported its missed targets honestly.

## Suggested fix order

1. **R6-1** Wire `ko_media` and fix the media test. Commit the K2 content so `HEAD` is green; keep the Core 5/AION content in its own commit. *(implementor + owner)*
2. **R6-2** The matcher's 요 rule plus distinct glosses. *(implementor + content agent)*
3. **R6-3** Arm-time frame filter, plus `countsTime: false` for answers whose onset is before the prompt. *(implementor)*
4. **R6-5** Owner spot-check of 10 references; change the locators to `"lyrics"`; decide whether the 66 % coverage ships. *(owner + content agent)*
5. **R6-6 / P1** PLAN and README alignment, `undoLastGrade` removal, §17 entries for R6-4. Schedule K5. *(planner)*
6. **R6-4** Verification rows for the new Core 5 and AION entries, plus the owner spot-check. *(content agent + owner)*
7. **R6-8a/b** CI runs `swift test`; loosen the count assertions. *(tester)*
8. **R6-7a** Measure, then the one-line fix if needed. *(frontend)*

---

# Round 5 — Round 4 fixes, performance pass, and spec (business-analysis) comparison

- **Date:** 2026-11-17
- **Scope:**
  1. The **uncommitted** Round 4 fixes on `review/m1-code-review`: 19 files, +423/−143 (`git diff` against `d67db46`).
  2. A performance and optimisation pass over the launch path, the session hot path, Home/Stats loading and the microphone pipeline.
  3. A requirement-by-requirement comparison of PLAN.md and PLAN_M1_FIXES/M2/M3/M4/M5 with the code.
- **Read in full:**
  - The whole diff.
  - Core: `SessionEngine`, `Scheduler`, `WeightCalculator`, `IntroductionPolicy`, `DeckCatalog`, `BuiltInDecks`, `ConjugationDeck`.
  - App: `SessionViewModel`, `PitchDetector`, `MicAnswerController`, `SwiftDataStatsStore`, `AppEnvironment` (top half).
- **Read selectively (targeted greps):** `SessionView`, `HomeView.load`, `SettingsView` export, `Theme.AuroraBackground`, `HangulReadingUI`, `ChordsUI`, `StatsView`, `SummaryView`. I also ran a requirement grep matrix over `App/Sources` (45 spec items).
- **Verification actually run** (a scratch copy and a scratch probe package; the repo was not modified):
  - `swift build` (core): **passes**.
  - `swift build --build-tests`: **fails**, with the same compile errors as R4-1 (`DeckContentTests.swift:37,48,49`; `FretboardDeckTests.swift:52,85,96`; …).
  - `xcodegen generate` + `xcodebuild` (iOS Simulator, Debug, unsigned): **BUILD SUCCEEDED**, with 1 warning (R5-6c).
  - `PersistedFormatCheck.run()` and `TheoryCheck.run()` return `[]`, so R4-8 caused no wire change.
  - **AnswerMatcher probe:** 21 Hangul pairs and 9 English pairs. **Conjugator probe:** 21 verbs × 7 forms (alternates).
  - **Timing probe:** catalog build, validation and `cards(options:)` for every deck in the catalog, in Debug and Release, on an Apple-silicon Mac. Device numbers are not measured.

## Verdict

**The Round 4 fixes are good work.**
- R4-3, R4-4, R4-5, R4-7, R4-8, R4-9 and R4-11 are fixed as specified, and I verified them by probe or by build.
- The conjugation alternates are linguistically right in every row I checked (보아요, 주어요, 되어요, 마시어요, 놔요, 공부하지 않아요, 안 공부해요). Vowel-initial stems (오다, 배우다) correctly get no uncontracted alternate.

**One fix introduced a new grading bug of the same class it was fixing (R5-1).**
- The new "real conjugation of the expected word" rule includes the **negative** form.
- So the *opposite* answer is graded correct: 몰라요 for 알다 "to know", 없어요 for 있다, 맛없어요 for 맛있다, and 안 가요 for 가다. Fix this before committing.

**Performance is fine where it matters most.**
- The session hot path costs milliseconds.
- **Two avoidable costs remain:**
  - Home recomputes every deck's whole card pool on the main actor after every session (R5-2).
  - The pitch detector runs YIN at full rate while nobody is listening (R5-3).

**Spec coverage is high.** Of the 45 user-facing UI requirements I grepped, 44 are present; the missing one is the `undoLastGrade` stretch goal. The gaps outside that grep (see "Spec comparison" below) are:
- tests and CI, still the largest risk (R4-1);
- M5 content, which leaves the whole M5 snippet feature unreachable (R5-5);
- accessibility contrast (R3-3);
- PLAN text that now contradicts the code (R5-4).

## Status of Round 4 findings

| ID | Status | Evidence |
|---|---|---|
| R4-1 · tests don't compile, no M2–M5 tests | 🔴 **Open** | `swift build --build-tests` fails with the same errors. No new test files. |
| R4-2 · fuzzy matching accepts other words | 🟡 **Partly fixed, new regression** | Now **wrong**, as intended: 가방/가다, 하/하다, 의사/의자, there/three, angle/angel. Typos stay close: frend/friend, restaurnt/restaurant. **New:** antonyms are accepted (R5-1). |
| R4-3 · conjugation alternates | ✅ Fixed | Probe of 21 verbs: negatives accept `-지 않아요` and, for noun+하다, `안 X해요`. Uncontracted forms are accepted for ㅗ/ㅜ/ㅣ/ㅚ/ㅐ/ㅔ stems with an initial consonant. 놓다 ↔ 놔요. `ConjugationUI` passes `acceptedAnswers`. |
| R4-4 · EWMA mixes measurements | ✅ Fixed in code | `SessionEngine.ok(countsTime:)`. Choice, typed and mic-timeout reveals don't count; touch and a mic hit do. The PLAN body was not updated (R5-4). |
| R4-5 · mic floods main actor | ✅ Fixed | `MicFrameTracker` runs on the detector queue. Main gets stable notes (generation-checked) and a level at ≤ 20 Hz. The detector itself still runs at full rate (R5-3). |
| R4-6 · unverified Korean content | 🔴 Open | Process item; not code. |
| R4-7 · mic onset biased early | ✅ Fixed | `hostSeconds` is now the start of the newest hop. |
| R4-8 · `DeckOptions` rigidity | ✅ Fixed | One `payload` switch; `PersistedFormatCheck` = `[]`; `Deck.kind` defaults to the id. |
| R4-9 · snippets in backups | ✅ Fixed | `isExcludedFromBackup` is set after every atomic write. |
| R4-10 · robustness gaps | 🟡 Mostly fixed | The deck launch merge, delete order, mic-timeout snapping and POS guess are done. Snippets have no tombstone, so a delete made before the load finishes is revived (R5-6a). |
| R4-11 · polish | ✅ Fixed (code) | 러-irregular validator rule, the shape-id note and the dictionary lookup are in. The `ChordChoices` 2–3 option check is still with UI. |
| R3-2 · aurora renders continuously | 🔴 Open | `Theme.swift:63`: `TimelineView(.animation(minimumInterval: 1/30))` + full-screen `Canvas` blur, used by **13** screens including `SessionView.swift:109`. |
| R3-7 · README wording | 🔴 Open | `README.md:24, 31` are unchanged. |

## New findings (Round 5)

### R5-1 · P2 (Medium-High) · Typed vocab now accepts the *opposite* word as correct
**Files:**
- `Korean/Conjugator.swift`, `allAcceptedForms` (iterates `ConjForm.allCases`, which includes `.negativePolite`)
- `Korean/AnswerMatcher.swift`, `hangulVerdict` (predicate branch)
- `App/Sources/DeckUI/VocabUI.swift:40-41` (vocab is `exactRequired: false`, so close = correct)

**Verified (probe, en→ko typed):**

| Input | Expected | Verdict | Meaning of the input |
|---|---|---|---|
| 몰라요 / 몰라 | 알다 (to know) | **close → correct** | "I don't know" (a different verb, 모르다) |
| 없어요 | 있다 (to exist/have) | **close → correct** | "there isn't" (없다) |
| 맛없어요 | 맛있다 (tasty) | **close → correct** | "it's not tasty" |
| 안 가요, 가지 않아요 | 가다 | **close → correct** | "I don't go" |

**Why it matters:** this is the same failure class as R4-2, and arguably worse. A learner who mixes up 알다 and 모르다, or 있다 and 없다 (the classic beginner confusions), gets a green verdict, and `ewmaError` drops. The scheduler then shows those words *less*.

**Fix direction:**
- Give `allAcceptedForms` a parameter `forms: [ConjForm]`.
- Have the matcher pass every form except `.negativePolite`. Even better, keep only forms whose text still contains the stem, which also covers any future suppletive form.
- Keep the conjugation deck on the full set.
- Add must-reject rows to the R4-1 golden tests: 몰라요/알다, 없어요/있다, 맛없어요/맛있다, 안 가요/가다.
- Must-accept rows: 가요, 갔어요, 가고 싶어요/가다, and 먹어/먹다.

### R5-2 · P3 (Low-Medium, performance) · Home regenerates every deck's card pool on the main actor after every session
**Files:**
- `App/Sources/Features/Home/HomeView.swift:356-363` (`load()`, run by `.task(id: env.dataVersion)`)
- also `SessionSetupView.swift:43` and `WeakestWordsSection.swift:28` (same pattern, less often)

**What happens:**
- `load()` is main-actor code. For each of the 27 catalog decks it runs:
  - `deck.cards(options:)`, building every `Card` only to read `.count`;
  - `initialConfig(for:)`, a JSON decode from UserDefaults;
  - a separate `await store.stats(for:)` round trip, which fetches every `ItemStats` row of that deck.
- It reruns on every `dataVersion` bump: every finished session, reset, and user-deck save. A finished session is exactly when the Summary confetti is animating.

**Measured (Debug, Apple-silicon Mac, core only):**

| Deck | Time | Cards |
|---|---|---|
| `music.scales` | 31.5 ms | 936 |
| `music.progressions` | 27.6 ms | 157 |
| `ko.conjugation` | 11.3 ms (4.3 ms Release) | 2,336 |
| `music.chords.play` + `.name` | 9.1 ms | — |
| `music.triads` | 4.7 ms | — |
| `ko.particles` | 2.7 ms | — |

- **Sum: about 90 ms of main-thread work per `load()`**, before the 27 store hops.
- PLAN §14 installs from Xcode, so the owner runs **Debug** builds day to day.
- On an iPhone this is likely 100–250 ms, a visible hitch *(plausible: measure with the G5 timing log)*.

**Fix direction:**
- Card counts depend only on (deck id, options), and decks are immutable values. Memoise `cardCount(deck:options:)` in `AppEnvironment` and clear the cache in `reloadCatalog()`.
- Or compute the counts in a `Task.detached`, because every `Deck` is `Sendable`.
- Replace the 27 `stats(for:)` calls with one store method that returns per-deck row aggregates (count seen, accuracy, median, last seen) in a single fetch.

### R5-3 · P3 (Low-Medium, performance and battery) · The pitch detector runs at full rate while nobody is listening
**Files:**
- `App/Sources/Services/PitchDetector.swift:93-150` (`analyse` runs for every hop)
- `MicAnswerController.swift` (`setListening(false)` only gates the *tracker*)

**What's wrong:**
- PLAN §11.5b says *"Detector is off during reveal."*
- In code, the input tap and YIN keep running through reveal, pause, the snippet sheet and note playback. Their output is computed and then discarded in `MicFrameTracker.process` (`guard listening`).
- **Cost per hop at 48 kHz:**
  - `tauMax` ≈ 685 lags, each a 1,024-sample `vDSP_distancesq`, so about 0.7 M multiply-adds per frame;
  - about 94 frames/s, so **about 66 M multiply-adds/s**, plus one `Array` allocation per tap buffer.
- In a mic session the reveal can be most of the wall time, because the user reads the answer, listens to playback and grades.

**Fix direction:**
- Share the tracker's `listening` flag with the detector, behind the same lock or an atomic. Check it at the top of `append`: keep filling the ring, but skip `analyse` when not listening.
- Keep the engine running so re-arming has no start-up latency.
- Optional, *(plausible: measure)*:
  - bound `tauMax` by the card's lowest acceptable note (a guitar's lowest is E2, 82 Hz, so the 70 Hz floor is already close);
  - or move to an FFT-based difference function (`vDSP_fft_zrip`), which is O(N log N) instead of O(N·τ).

### R5-4 · P3 (Low, spec integrity) · The PLAN body now contradicts the code
The decisions are recorded in §17, but the normative sections that agents read first were not updated (CLAUDE.md: *"Record plan deviations in PLAN.md §17"*; §16: *"If the plan is ambiguous or wrong … record it"*). A future agent following §9.2 would undo R4-4.

| Location | Says | Code / decision |
|---|---|---|
| PLAN.md §9.2 table, `choice` row (line ~542) | updates time EWMA: **yes** | **no** (R4-4, `InputMode.countsTime`) |
| PLAN.md §9.2 paragraph (line ~545) | "In a typed session, time is skipped for every card, **including any card that falls back to touch**" | a touch fallback **counts**; a mic-timeout reveal doesn't |
| PLAN_M4 §4, M4-0 step 2 (line 83) | `countsTime` "derived from `config.inputMode == .typed`" | per answer, via `ok(countsTime:)` |
| PLAN.md §15, M4 status (line 935) | "Core 2–4 have been added, and Core 5 is still to do" | Core 5 is done (§17, 2026-11-17; `ko_core_5.json`, 225 entries) |
| PLAN.md §9.2 / PLAN_M4 §7 | vocab "close counts as correct" | still true, but "close" now has the R4-2 and R5-1 semantics, which aren't described outside §17 |
| README.md:24, 31 | "= OK", "prompt → OK" | R3-7, still open |

**Fix direction:** this is a planner task. Fold the R4 decisions into §9.2 and §11.5d, and into the PLAN_M4 §3.1 table and M4-0, then fix the §15 status line.

### R5-5 · P3 (Medium for product value) · M5 delivers no user-visible feature yet: snippets are unreachable without K2 content
**Files:**
- `DeckCatalog.swift`: `"ko_media"` is commented out of `bundledVocabFiles`
- `VocabUI.swift:204`: `MediaSnippetView` is embedded only when `dialogue`/`sources` is non-empty
- PLAN_M5 tracker: K2 and K5 are ☐

**Verified:** no bundled deck JSON contains a `dialogue` or `sources` key (grep over `Resources/Decks/*.json`).

**What follows:** the following are all **dead in production**, and only previews exercise them:
- the "In a scene" and "Heard in" panels;
- "My snippet" (K4), because its only entry point is that panel;
- the snippet store and its backup exclusion;
- the `personalSnippets` export key;
- the "Also delete my snippets?" reset prompt.

This matches PLAN_M5 K3 §2 to the letter ("only when … non-empty"). From a business point of view, though, the milestone's value has not shipped. About 900 lines of M5 UI and persistence carry maintenance cost and have zero reach.

**Options (owner decision):**
- **(a)** Schedule K2. It needs a web-capable agent for the citation verification (PLAN_M5 §2).
- **(b)** Show "+ Add your own snippet" on *every* vocab reveal, so K4 works now. This changes the "existing decks look unchanged" rule in K3, so it needs the owner's approval.
- **(c)** Explicitly park M5 in PLAN §15.

### R5-6 · P4 (Polish)
- **a. Snippet deletes can be revived at launch.** In `AppEnvironment.loadPersonalSnippets` (line 181), `snippets.merging(personalSnippets)` keeps a disk entry for any key missing from memory. A snippet deleted before the launch load completes therefore comes back. User decks got a tombstone set in R4-10; snippets need the same. The window is small: you would have to edit within the first moments after launch.
- **b. Double haptic on typed and choice answers.** `SessionViewModel.reveal(_:_:)` (line 240) fires `haptics.grade` at the reveal, and `gradeAutoAnswer → grade` (line 150) fires it again on Next. Keep the reveal one and skip the second when `autoAnswer != nil`.
- **c. New Swift 6 warning.** `ScreenshotImportView.swift:41` reads the main-actor-isolated `phase` from a `Sendable` closure. The segment DoD requires no new warnings.

## Performance: what's fine (measured, no action)

| Path | Debug | Release | Note |
|---|---|---|---|
| `DeckCatalog.builtIn()` (7 JSON files, about 1,100 entries + validation) | 19.7 ms | 13.2 ms | runs once at launch |
| `ChordShapeLibrary.shared` (67 shapes, all configurations validated) | 4.7 ms | 8.3 ms* | once, lazily |
| `DeckValidator.validate` (all files) | 5.5 ms | 2.0 ms | — |
| `PersistedFormatCheck` + `TheoryCheck` | 3.2 ms | 1.5 ms | DEBUG launch only |
| `SessionEngine.init` on the largest pool (`ko.conjugation`, 2,336 cards) | 14.3 ms | 4.4 ms | once per session |
| `Scheduler.nextCard` | O(pool) + one median sort per pick | — | under 1 ms at 2–3k cards; caching `referenceMs` isn't worth the complexity |
| `SwiftDataStatsStore.save(ItemStats)` | — | — | `itemKey` is `@Attribute(.unique)`, so the lookup is indexed |
| Typed matching (`allAcceptedForms` per submit) | — | — | about 30 strings per submit, negligible |

\* The library ran first in the Release probe, so that number includes the cold bundle and JSON load.

**Not fixable on iOS 17:** `SDAttempt.sessionID` and `deckID` have no index (`#Index` needs iOS 18). The table grows without bound, about 18k rows per year at 50 cards a day. `attempts(for:)` (every session start, via the baseline) and `trendPoints` (N5) scan it. This is fine for years *(plausible: measure; G5 numbers are still not taken)*.

## Spec comparison (business-analysis view)

Legend: ✅ implemented (checked in code) · 🟡 implemented with a recorded deviation, or partly · ❌ missing · ⏳ blocked on owner or content.

### M1 core loop (PLAN §1–§11)
| Requirement | Status | Notes |
|---|---|---|
| Timed prompt → OK → reveal → self-grade; monotonic clock; timer starts when the prompt is visible (§9.1) | ✅ | The prompt uses `.transition(.identity)`, and `promptDidAppear` runs from `.task(id: presentationID)`, so no animation is timed |
| Interruptions: interrupted attempt stored and excluded; same card, fresh timer (§9.1) | ✅ | `SessionEngine.pause/resume` |
| Clamp 150–30 000 ms for stats only (§9.1) | ✅ | |
| Retry queue: 3–5 cards later, once per card, not counted (§9.3) | ✅ | Cooldown-delayed; flushed when starved |
| Grade lockout 250 ms (§9.3) | ✅ | |
| **`undoLastGrade`** (§9.3, stretch) | ❌ | Never implemented (S6 note); not in any fix plan. Owner: keep it or drop it from the spec |
| Weighted scheduler, cooldown, pattern penalties, gating, fallback order (§10) | ✅ | Read in full; matches §10.2–§10.6 |
| Summary: tiles with Δ, chart with median rule, slowest 5, missed list, full list (§11.4) | ✅ | `RuleMark` present |
| Stats: trend, history → summary, fretboard heatmap + popover, weakest words, Learned/Seen/New (§11.6) | ✅ | The trend loads every attempt (N5; G5 unmeasured) |
| Settings list (§11.7): naming, Si/Ti, left-handed, string order, max fret, string hint, auto-play, speech rate, romanization, tap-anywhere, timer, haptics, export JSON + CSV, reset per deck or all | ✅ | |
| Keyboard and pedal map (§11.3), including Backspace = Wrong and Esc = pause | ✅ | `SessionView.swift:519-538` |
| Idle timer disabled in session, haptics, swipe-to-grade, Reduce Motion | ✅ | |
| TTS `ko-KR`, `.playback` + `.mixWithOthers`, one-time "install Korean voice" hint (§8.4) | ✅ | |
| Accessibility beyond Reduce Motion: contrast and Differentiate Without Color (§11, R3-3) | ❌ | R3-3 still open; no `colorSchemeContrast` handling |
| **Tests:** core `swift test`, AppTests, UI smoke test (§5, §13, segment DoD) | ❌ | R4-1. Owner deferred tests in M1, and later rounds hand them to the tester agent. Today **no automated check runs at all**, and the M2–M5 logic (about 7k lines) is untested |

### M2 music (PLAN_M2)
| Requirement | Status | Notes |
|---|---|---|
| Name the Note, Find All, Intervals, Ear decks; tunings with the key prefix rule | ✅ | |
| Note playback, "Play note on reveal", volume | ✅ | |
| Mic answers: Listening chip, level meter, "Heard G♯", 5/10/20 s timeout, 🎤 in history and summary | ✅ | `StatsView.swift:214`, `SummaryView.swift:20` |
| "Detector is off during reveal" (§11.5b) | 🟡 | Matching is off, but analysis still runs (R5-3) |
| Mic for Find All | ⏳ | Owner OPEN question (PLAN_M2 §6) |

### M3 harmony (PLAN_M3)
| Requirement | Status | Notes |
|---|---|---|
| 9 decks, card counts as in the tracker (369/369/540/144/936/60/210/157/48) | ✅ | Probe counts match exactly |
| Chord box, staff, circle views with VoiceOver labels; dot labels Notes/Degrees; shape hint | ✅ | |
| Shape verification table | ⏳ | Owner (M3-2) |
| Unwanted chord families or scale types? | ⏳ | Owner OPEN (PLAN_M3 §7) |

### M4 Korean (PLAN_M4)
| Requirement | Status | Notes |
|---|---|---|
| Core 2–5 (889 words), Patterns (87) | 🟡 | Content present; dictionary verification pending (R4-6, `docs/core-verification.md`) |
| Hangul reading (stages, gating, stats grid), listening, particles, conjugation | ✅ | `HangulStatsGrid` in `HangulReadingUI.swift:188` |
| Typed answers: Korean-keyboard hint, Don't know, override, diff highlight, auto-advance | ✅ | Grading semantics need R5-1 |
| Custom decks, AION screenshot → cards (PhotosPicker, ko-KR OCR, Already known, screenshot not stored) | ✅ | Real-screenshot device check pending (M4-9) |

### M5 media (PLAN_M5)
| Requirement | Status | Notes |
|---|---|---|
| K1 schema v2 and validator | ✅ | |
| K2 `ko_media.json` (about 80 verified entries) | ❌ | Not started; needs a web-capable agent |
| K3 snippet panel, K4 My snippet | 🟡 | Built, but **unreachable** without K2 (R5-5) |
| K5 integration and QA | ❌ | |

### Process items from PLAN_M1_FIXES still open
- G5: the `trendPoints` numbers were never taken.
- G6: the device checks (P2-2, P2-3, P2-5, P2-6) are still ☐.

## What's good (keep it)
- **R4-2 is a principled fix.** The matcher now generates the accepted forms instead of guessing from prefixes. The batchim-slip rule for short words has a clear linguistic rationale (의사/의자 wrong, 있다/잇다 close). The indel-only English distance removes exactly the real-word substitutions. R5-1 is a one-line scope fix on top of a sound design.
- **The conjugation alternates are carefully bounded.** Vowel-initial stems are excluded, 놓다 is special-cased, and the dedup sits in `Conjugation.init`.
- **The mic threading is now textbook.** The detector queue owns the per-frame state. Main gets only actionable events, guarded by a generation token so stale notes can't grade the next card.
- **R4-8 is done without touching the wire format,** and `PersistedFormatCheck` proves it.
- **The launch path is cheap** (about 20 ms Debug for the whole catalog), and the session hot path is O(pool) with small constants.

## Round 5 — Suggested fix order
1. **R5-1** before committing the R4 batch. It's a small change in `Conjugator.allAcceptedForms` and `AnswerMatcher`, plus the must-reject rows.
2. **Commit** the R4 batch with the R5-1 fix (the owner asked for review before commit).
3. **R4-1** (tester): compile fixes, then CI `swift test`, then the golden tables. The probe lists in Round 4 and in this round are ready-made seeds.
4. **R5-4** (planner): fold the R4 decisions into the PLAN §9.2 and PLAN_M4 tables, and fix the §15 status line.
5. **R5-2, R5-3, R3-2** as one performance segment: Home card-count cache and batched stats, detector gating, aurora freeze during sessions. Measure on device before and after with the G5 timing log.
6. **R5-5**: owner decision (a), (b) or (c).
7. **R5-6**: polish batch.

---

# Round 4 — Full review after M2 music, M3 harmony, M4 Korean, M5 media

- **Date:** 2026-11-17
- **Scope:** `b269937..427ef73`: commits `c404913` (M2–M4), `5952402`, `a67216a` and `427ef73` (M5). That is 116 files, about +35.7k lines, of which about 22k are deck/shape JSON.
- **Read in full:**
  - Core: `SessionEngine` (diff), `SessionConfig`/`StatsUpdater`/`StatsStore` (diff), `Deck.swift`, `Conjugator` (forms), `AnswerMatcher`, `PersonalSnippet`, `ChordDecks`, `ChordShapeLibrary`, `DeckValidator` (tail)
  - App: `SessionViewModel`, `MicAnswerController`, `PitchDetector`, `AudioSessionCoordinator`, `AppEnvironment`, `PersonalSnippetStore`, `UserDeckStore`
- **Read selectively (targeted greps):** the other deck generators, Particles, HangulReading, Theory, Scales, the OCR import, export, and the large SwiftUI screens (`SessionView`, `HomeView`, `MediaSnippetView`, `UserDeckEditorView`, `StatsView`). These views were **not** read line by line, so UI-level findings in this round are limited to the items below.
- **Verification actually run:**
  - `swift build` (MemoriseCore): passes.
  - `swift test`: **does not compile** (R4-1). In a scratch copy I applied the minimal compile patches: **127 tests ran, 118 passed and 9 failed**. All 9 failures are stale M1 expectations, not regressions.
  - **Probe runs (scratch only):**
    - `Conjugator`: 49 verbs/adjectives × 7 forms.
    - `AnswerMatcher`: 11 input pairs.
  - The repo was not modified.
  - The iOS app was not built or run locally (CI `ios-build.yml` covers the build).

## Verdict

**The domain core is in good shape. The conjugator in particular is impressive.**
- 48 of the 49 probe verbs conjugate correctly across all 7 forms. This includes ㄷ/ㅂ/ㅅ/ㅎ/르/ㅡ/ㄹ irregulars, 하다 splitting (공부 안 해요 vs 안 좋아해요), 있다→없다, and 알다→몰라요.
- The new persistence pieces follow the project rules. These are the personal-snippets store, the user deck store, `SessionConfig.inputMode`, and `PersistedFormatCheck`, which now covers all 15 option cases.
- The mic pipeline is carefully engineered: preallocated YIN, a queue-confined detector, and a host-time onset mapped onto the engine clock.

**Three systemic problems:**
1. **The safety net has rotted further.** The tests still don't compile and CI still doesn't run them. About 7k lines of new core logic have **zero** tests (R4-1).
2. **Automatic grading can store wrong grades.** Fuzzy matching accepts different words as "close", and close counts as correct (R4-2). Valid alternative conjugations are marked wrong (R4-3).
3. **The response-time statistic now mixes measurements that aren't comparable.** These include choice versus recall, typed fallbacks, and mic timeouts (R4-4).

Problems 2 and 3 feed straight into scheduling, which is the app's core purpose.

## Status of Round 3 findings

| ID | Status | Evidence |
|---|---|---|
| R3-1 · tests don't compile, CI doesn't run them | 🔴 **Open, worse** | See R4-1. It's now 4 files and 9 compile errors, up from 1 file and 3. |
| R3-2 · aurora renders continuously during sessions | 🔴 Open | `Theme.swift:63` is still paused only for Reduce Motion, and `SessionView.swift:109` still uses it. It now competes with mic frame traffic (R4-5). |
| R3-3 · contrast | 🔴 Open | No `colorSchemeContrast` / `accessibilityDifferentiateWithoutColor` handling anywhere in `App/Sources`. |
| R3-4 · Catmull-Rom overshoot | 🔴 Open | `StatsView.swift:158, 161`. |
| R3-5 · grade-button flicker | 🟡 Likely open | `SessionView.swift:42` `@State gradeEnabled = true` is unchanged. The task path was not re-traced. |
| R3-6 · `recoveredFields` misses inner fallbacks | ⚪ Not re-checked | It now applies to 13 more option structs, so the gap is wider if it's still open. |
| R3-7 · polish | 🔴 Open (README) | `README.md:24, 31` still say "= OK" / "prompt → OK". |

## New findings (Round 4)

### R4-1 · P1 (High) · The test suite rotted further, and M2–M5 core logic has no tests at all
**Files:**
- `Tests/MemoriseCoreTests/DeckContentTests.swift:37, 48, 49`
- `FretboardDeckTests.swift:52, 54, 85, 96`
- `MusicTheoryTests.swift:67`
- `SchedulerTests.swift:174`
- `SessionEngineTests.swift:361`
- `.github/workflows/core-tests.yml`

**What's wrong:**
- **Compile errors** (all from API changes in `c404913` with no test update):
  - `DeckLoadReport` (×3, as in R3-1)
  - `Deck.present(_:options:using:)` gained `options` (×3)
  - `Accidental` gained `doubleFlat`/`doubleSharp`, so the test's `switch` is no longer exhaustive
  - `Tuning.init` gained `id:`
  - `Deck` gained a required `kind`, which breaks the test doubles `UniformDeck` and `FixedDeck`
- **After the minimal compile patches (scratch copy): 118/127 pass.** The 9 failures are stale expectations, not regressions:
  - catalog deck list and counts (`["music.fretboard.notes","ko.core.1","ko.aion2"]`)
  - the `missingFile` deck list
  - vocab golden JSON (now has `inputMode` and `micTimeoutSeconds`, an additive and allowed change)
  - `unknownKeysAreIgnored` (uses `"tuning"`, which is now a real key)
  - `DirectionOption.allCases` (`listening` and `allThree` appended, which is allowed)
  - `Tuning.stringName` ("low D" / "high E")
  - export `schemaVersion` 1 → 2
  - the validator `"unsupported schemaVersion"` fragment

  I also checked that `mixedPresentsBothSpellingsRoughlyEvenly` passes once the test passes `.mixed` options. **P1-1 has not regressed.**
- **No tests exist for any of the following.** This is roughly 7k lines of pure, deterministic, Foundation-only code, the easiest code in the project to test:
  - `Conjugator`
  - `AnswerMatcher`
  - `HangulReading`
  - `Particles`
  - `Key` / `Scale` / `Chord` / `ChordShape` voicing
  - the 14 new deck generators
  - `UserDecks`
  - `PersonalSnippet` / `PersonalSnippetFile`
  - `DeckValidator` schema-2 rules
  - `SessionEngine.answerEvaluated` / `answerDetected`
- `TheoryCheck` (37 lines, DEBUG-launch `assert`) is not a substitute: it doesn't run in CI and stops at the first launch.

**Fix direction:**
1. Patch the 9 compile sites and update the 9 stale expectations. This is mechanical, about 30 minutes.
2. Make CI run `swift test`.
3. Add golden tests:
   - **Conjugator:** an entry × form table. The probe list in this round (49 verbs) is a ready seed, and every row except 푸르다 was hand-checked.
   - **AnswerMatcher:** must-accept and must-reject pairs (see R4-2 and R4-3).
   - **Every deck generator:** card count and key uniqueness per default options, plus `present` keeps the key.
   - **`answerEvaluated`:** clamps `at` < prompt start, and `gradeMs == 0`.
4. Add a rule to CLAUDE.md: *"API change in Core ⇒ `swift test` green before commit."*

### R4-2 · P2 (Medium-High) · Typed-answer fuzzy matching grades *different words* as correct
**Files:**
- `Korean/AnswerMatcher.swift:73-88` (hangul) and `:94-104` (English)
- `App/Sources/DeckUI/VocabUI.swift:34-40` (vocab uses `exactRequired: false`, so **close = correct**)

**Verified with probe runs:**

| Input | Expected | Verdict | Why |
|---|---|---|---|
| 가방 (bag) | 가다 (to go) | **close → correct** | The `isPredicate` branch only checks `conj.hasPrefix(stem)`, so any word starting with 가 passes. |
| 하 | 하다 | **close → correct** | A bare stem passes too. |
| 의사 (doctor) | 의자 (chair) | **close → correct** | Jamo distance 1 (ㅅ/ㅈ) on a 2-syllable word. Minimal pairs like this are common in Korean. |
| there | three | close → correct | OSA transposition = 1 |
| angle / quiet / dessert / later | angel / quite / desert / latter | close → correct | distance 1 at ≥ 5 letters |

**Why it matters:** these grades update `ewmaError` and drive the scheduler. A user can hold a word as "learned" while confusing it with its neighbour. That is exactly the failure a memorisation app exists to catch. The override button exists, but the default is wrong and users rarely contradict a green verdict.

**Fix direction:**
- **Predicate branch:** require `conj.count > stem.count`, and require that the remainder is a recognised ending. Better: generate the accepted conjugations with `Conjugator` (all 7 forms) and compare exactly.
- **Hangul distance:** don't auto-accept an edit that changes a *whole* jamo (initial or medial) in a ≤ 2-syllable word. Allowing only final-consonant (batchim) slips is a defensible middle ground.
- **English:** keep `close`, but **store it as wrong unless the user confirms** (an "I was right" override), or restrict close to distance-1 *insertions/deletions* (typos), excluding substitutions and transpositions that produce real words.
- Whatever is chosen, record it in PLAN §17 and lock it with must-accept / must-reject tests (R4-1).

### R4-3 · P2 (Medium) · Conjugation drill accepts exactly one spelling, so valid answers are graded wrong
**Files:**
- `App/Sources/DeckUI/ConjugationUI.swift:26` (`expected: [p.answer]`, `exactRequired: true`)
- `Korean/Conjugator.swift:34-43`. The doc says *"the form, any other accepted spellings"*, but `Conjugation` has only `text`.

**Verified:**
- 안 공부해요 and 공부하지 않아요 are **wrong** for 공부 안 해요. Both are standard, and `-지 않아요` is the textbook long negation.
- Uncontracted forms such as 보아요, 주어요, 되어요 and the contracted 놔요 (for 놓아요) are graded wrong because only one spelling is generated.

Spaces are already ignored (normalisation strips them), so this is purely about alternates.

**Fix direction:**
- Add `alternates: [String]` to `Conjugation`:
  - negative → also `안 X해요` and `-지 않아요`
  - contraction-optional stems → both spellings
- Pass `[text] + alternates` as `expected`. The first stays the displayed answer.

### R4-4 · P2 (Medium) · The response-time EWMA now mixes incomparable measurements
**Files:**
- `Domain/SessionConfig.swift` (`InputMode.countsTime`)
- `Session/SessionEngine.swift:178`
- `App/Sources/Features/Session/SessionViewModel.swift` (`activeMode`, `armMicTimeout`)

`grade()` decides whether time counts from **`config.inputMode`**, while the card was actually answered in **`activeMode`**:

1. **Mic timeout:** after `micTimeoutSeconds` (default 10 s), `ok()` reveals the card. `responseMs` ≈ 10 000. If the user then grades it correct, **a 10 s time enters `ewmaResponseMs` and can set `bestResponseMs`'s baseline** for that item. Mic sessions therefore systematically inflate time stats on the cards the mic missed.
2. **Typed sessions with touch fallback:** cards with no `typedAnswer` fall back to Reveal/self-grade. Because `config.inputMode == .typed`, `countsTime` is false, so legitimate recall times are dropped.
3. **Choice:** choosing among 4 options (recognition) is counted in the same EWMA as touch recall. That makes a deck look faster after a choice session and shifts the time-based weighting (`focus`) for the next touch session.

**Fix direction:**
- Compute `countsTime` from the per-answer mode (pass it into `grade`).
- Treat a mic-timeout reveal as `countsTime: false`.
- Decide in PLAN whether choice time counts at all. A simple option is not to count it, like typed.
- Consider recording the answer mode on `Attempt` (optional field, default `nil`). Today it can only be inferred from the session config, which is wrong for fallbacks.

### R4-5 · P2 (Medium) · Mic mode floods the main actor while the aurora animates (extends R3-2)
**Files:**
- `App/Sources/Services/MicAnswerController.swift:65-67, 100-101`
- `PitchDetector.swift`

Every analysed hop (512 samples, about **94 per second at 48 kHz**) creates a `Task { @MainActor … handle(frame) }`. `handle` always writes `levelDB`, an observed property, so the level meter re-renders up to 94 times per second, **including while not listening**. Stability matching also runs on the main actor. Together with the 30 fps blurred aurora (R3-2) and the `.regularMaterial` cards, this is sustained main-thread load during the exact window whose timing the app measures.

The onset itself is safe because it uses host time. The latency to auto-advance and of touch handling is not.

**(plausible: measure)** Use Instruments (SwiftUI + Time Profiler), with mic mode on, for 60 s of prompts.

**Fix direction:**
- Do run-tracking on the detector queue and only hop to main for a stable note.
- Publish `levelDB` at ≤ 20 Hz and only when it changes by more than 1 dB.
- Freeze the aurora during sessions (R3-2).

### R4-6 · P2 (Medium, process) · ~1,100 Korean entries are unverified, but typed grading treats them as ground truth
**File:** `docs/core-verification.md` (header: *"have not yet been checked against the dictionary"*; every row ☐)

Core 2–5 (about 890 entries) plus patterns were authored from memory. Typed romanization is an **exact** match (`AnswerMatcher.romanizationVerdict`), and typed meaning/Hangul feed grades. One wrong gloss or romanization becomes a card the user can never get "right".

**Fix direction:**
- Treat the verification table as a ship gate. Ticking can be split across sessions.
- Until it's done, consider labelling Core 2–5 as "beta" on Home.

### R4-7 · P3 (Low) · Mic onset is biased early by up to one analysis window
**File:** `PitchDetector.swift`, `analyse` (`hostSeconds` = the frame's **first** sample)

The detector reports a frame's time as the start of its 2048-sample window (≈ 43 ms at 48 kHz). The first stable frame's window usually *begins before* the note was struck. So mic `responseMs` is systematically **under**-estimated by 0 to about 40 ms compared with touch.

That's small, but it's a fixed bias in a timing app. It also compounds R4-4 (3) when comparing modes.

**Fix direction:** use the hop start (newest − hop) as the onset, or subtract half a window. Document the remaining uncertainty in PLAN §17.

### R4-8 · P3 (Low) · `DeckOptions` is now the main rigidity hotspot (P2-8 remainder)
**File:** `Domain/Deck.swift:43-218`

The UI registry (`DeckUIRegistry`) fixed most of P2-8. But each new deck still needs **6 coordinated edits** in one enum:
1. a case
2. a `CodingKeys` entry
3. a decode branch
4. an encode branch
5. an accessor
6. a `caseKey` branch

plus `PersistedFormatCheck`. That's about 175 lines of near-identical code for 15 cases. The encode switch is the risky part: a copy-paste slip (`forKey: .scales` inside `case .triads`) compiles and silently writes the wrong wire shape. `PersistedFormatCheck` would catch it only in DEBUG and only if a fixture exists for that case.

Separately, `Deck.kind` has no default, which is what broke both test doubles.

**Fix direction (no wire change):**
- Make one `private var payload: (key: CodingKeys, value: any Encodable)` switch, and write `encode` once from it. `caseKey` then becomes `payload.key`.
- Add a test that every case round-trips and that `caseKey`'s raw value equals the encoded top-level key.

### R4-9 · P3 (Low) · Personal snippets are described as "never leave the device", but iCloud backups include them
**Files:** `App/Sources/Persistence/PersonalSnippetStore.swift:4, 21-24`; `Korean/PersonalSnippet.swift:3`

`Application Support/personal_snippets.json` is included in iCloud/Finder device backups by default. The code comments, and probably the product promise (PLAN_M5 K4), say nothing leaves the device except through Export.

**Fix direction:**
- Either set `URLResourceValues.isExcludedFromBackup = true` after each write, or reword the promise to "not uploaded by Memorise".
- The same applies to `UserDecks/` if the same promise is made there.

### R4-10 · P3 (Low) · Small robustness gaps in the new persistence and environment code
- **Launch race** (`AppEnvironment.swift:84, 123-128`): `loadUserDecks()` replaces `userDeckFiles` wholesale. If the user saves a deck before the launch load resumes on main, the in-memory list drops it until relaunch. The file on disk is safe. Merge by `deckId` instead of replacing.
- **Delete order** (`deleteUserDeck`): the file is deleted first, then `store.reset`. If reset throws, the deck stays in the catalog with no file behind it. Reset first, or update the catalog in a `defer`.
- **`micTimeoutSeconds`** is decoded without bounds. A persisted `0` or a negative value reveals instantly. Clamp it to `micTimeoutPresets` in `sanitize`.
- **Screenshot import** (`ScreenshotImportView.swift:131-132`) stores every entry as `pos: .noun`. OCR'd verbs never get `conj`, never reach the conjugation deck, and skip the `isPredicate` matching path.

### R4-11 · P4 (Polish)
- **러-irregular** (푸르다 → 푸르러요, 이르다 "to arrive" → 이르러요) isn't modelled. As `.reu`, the probe produced 풀러요. None of these is in a deck today; the deck's 이르다 means "early", where 일러요 is correct. `DeckValidator` could reject those headwords until the class exists. The known 춤추다 gap is already logged in §17.
- **`ChordShapeLibrary.shape(id:)`** is a linear scan. That's fine now, but `ChordDiagramView` previews force-unwrap it (`:122-132`), and so does `ChordsUI` previews (`:179, 185`). A renamed shape id crashes previews, not tests. Shape ids are effectively `ItemKey` parts (`chord:<shape.id>`), so state in the JSON header that **shape ids are frozen**, like entry ids.
- **`ChordChoices.options`** can return fewer than 4 choices after 50 attempts with a narrow quality set. The UI should tolerate 2–3. This was not checked in the view.

## What's good (keep it)
- **Conjugator:** an ordered pipeline (stem → irregular → harmony → contraction → ending) with human-readable `rule` strings. The 하다 negative split, with bound-root (`원/변/피…`) and emotion-verb exceptions, is unusually thoughtful.
- **`PersonalSnippetStore`:** it uses an actor cache. An unreadable file is moved aside and never overwritten, and if that move fails, `writesBlocked` stops all writes. Writes are atomic and decoding is tolerant per snippet (`LossySnippet`). This is a model for the other stores.
- **`AudioSessionCoordinator`:** one owner of the category, and it never downgrades a mic session.
- **`PitchDetector`:** preallocated buffers, queue-confined state, vDSP, and a gate plus range limits. The host-time → engine-clock mapping in `micHeard` is correct.
- **`SessionEngine.answerEvaluated`:** it clamps onsets before the prompt and goes through the same `gradeRevealed` path, so retries and stats stay consistent.
- **`PersistedFormatCheck`** now pins every `DeckOptions` case plus the new `SessionConfig` fields. All new options use hand-written tolerant decoding with sorted `Set` encoding.
- **Snippet editing pauses the session through the same pause path**, so grade time isn't inflated.

## Round 4 — Suggested fix order
1. **R4-1:** compile and update the tests, make CI run `swift test`, and add Conjugator and AnswerMatcher golden tests. This is half a day and the highest-leverage item. Everything below should land with a test.
2. **R4-2 + R4-3:** fix grading correctness: tighter fuzzy rules, and conjugation alternates.
3. **R4-4:** per-answer `countsTime`, and mic-timeout reveals don't count time.
4. **R4-5 + R3-2:** measure, then throttle mic frames and freeze the aurora.
5. **R4-6:** start ticking the verification table, or label the decks as beta.
6. R4-7 to R4-10, then the open R3-3 to R3-7 items and R4-11.
7. Still open from earlier rounds: the G5 measurements (N5), the G6 device checks, and the branch/PR question.

---

# Round 3 — G1–G5 fixes and the UI visual pass

- **Date:** 2026-11-16
- **Scope:**
  - **G1–G5** (the Round 2 fixes). They are inside baseline commit `4383483`, so no separate diff exists; I read the affected files in full.
  - **UI pass** `b269937` (12 app files, +1040/−221), reviewed as a diff.
- **Verification actually run:**
  - `swift build` for `MemoriseCore`: passes.
  - `swift test`: **fails to compile** (R3-1). In a scratch copy with 3 test lines patched, **127/127 tests pass** in 11 suites. The repo itself was not modified.
  - The iOS app was not built or run in this round.

## Verdict

**The G1–G5 fixes are correct and close every Round 2 finding.** G1 in particular is done well: it uses a hand-written legacy wire shape, a DEBUG format self-check, and `recoveredFields`, which is excluded from encoding and equality.

The UI pass is careful about response timing in the places that matter:
- prompts still appear instantly
- the lockout and the engine guards are untouched
- Reduce Motion is respected in most places

It does add a **continuous rendering cost on every screen, including the timed prompt** (R3-2), and a few contrast and accuracy-of-display issues.

There's also a surprise: **a 127-test suite now exists, but it doesn't compile, and CI doesn't run it** (R3-1).

## Status of Round 2 findings

| ID | Status | Evidence |
|---|---|---|
| N1 · outer-enum coding unpinned | ✅ Fixed | Hand-written `DeckOptions` (`Domain/Deck.swift`) and `SessionLength` (`Domain/SessionConfig.swift`) coding, with the legacy `_0` shape and "frozen" doc comments. `PersistedFormatCheck` asserts the decoded value and byte-identical re-encoding at DEBUG launch (`AppEnvironment.swift:41-44`). The `Set` fields are encoded sorted, so the bytes are deterministic. `recoveredFields` is surfaced in the log (`SwiftDataModels.swift:138`), on the Summary (`SummaryView.swift:26`), and ignored for last-used configs (`AppEnvironment.swift:71`). See R3-6 for one gap. |
| N2 · deck-issue wording | ✅ Fixed | `DeckLoadReport` splits `loadFailures` from `validationWarnings`; Home shows them as separate rows, with validation first. |
| N3 · lockout feedback | ✅ Fixed | `gradeLockoutRemaining`, dimming plus `allowsHitTesting`, and `.ignored` for rejected keys. See R3-5 for a one-frame flicker. |
| N4 · zero-delta format/colour | ✅ Fixed | `Fmt.isZeroDelta`, "= 0 ms" / "= 0 pt", and `Palette.deltaColor` returns `.secondary` for zero. |
| N5 · `trendPoints` loads everything | 🟡 Instrumented, decision pending | The timing log is in `StatsView.swift:95-99`, and a DEBUG-simulator seeder is in `Support/DevSeeder.swift`. **No numbers are recorded yet**, so the Phase B decision is still open. |
| N6 · history error state | ✅ Fixed | Error view with Retry. |
| N7 · PLAN wording | ✅ Fixed | §9.3 / S6 updated by the planner. |

## New findings (Round 3)

### R3-1 · P1 (High) · The committed test target doesn't compile; CI doesn't run it; PLAN says it doesn't exist
**Files:**
- `Packages/MemoriseCore/Tests/MemoriseCoreTests/DeckContentTests.swift:37, 48, 49`
- `Packages/MemoriseCore/Package.swift` (`.testTarget`)
- `.github/workflows/core-tests.yml` (`swift build -c release` only)
- `PLAN_M1_FIXES.md` §4 ("F1 skipped, D1 = No")

**What's wrong:**
- Baseline `4383483` adds `MemoriseCoreTests`: 12 files, about 1,750 lines.
- G3 changed `DeckCatalog.builtIn()` to return `DeckLoadReport` instead of `[String]`, but this test file was not updated. So `swift test`, the plan's own Definition-of-Done command, **fails to build**: "binary operator '==' cannot be applied to 'DeckLoadReport' and '[Any]'", plus "no member 'count'" and "no member 'first'".
- Because CI only builds the library, nobody saw it.
- The plan documents still say tests were skipped, so the repo and the docs disagree about whether a safety net exists.

**Verified:** with the three assertions changed to `issues.isEmpty`, `issues.loadFailures.count == 1` and `issues.loadFailures.first?…` in a scratch copy, **all 127 tests in 11 suites pass in about 1 s**. These include the starved-pool scheduler, the gated vocab session, the retry timing, the launch sweep, and Codable tolerance.

**Fix direction:**
- Fix the three lines.
- Change the CI step to `swift test`, keeping `swift build -c release` as a second step.
- Update the D1 / F1 tracker rows to say what actually exists.

This is the cheapest high-value change left in the project. The suite already exists and is green.

### R3-2 · P2 (Medium) · The animated aurora renders continuously on every screen, including during timed prompts
**Files:**
- `App/Sources/Components/Theme.swift:62-89`
- used at `SessionView.swift:105`, `HomeView.swift:92`, `StatsView.swift:79`, `SummaryView.swift:75` and `SettingsView.swift:169`

`AuroraBackground` is a `TimelineView(.animation(minimumInterval: 1/30))` around a full-screen `Canvas` with a blur filter of radius ≈ 18 % of the short side (about 70 pt on a phone). It is paused only for Reduce Motion. On top of it sit `.regularMaterial` glass cards, which must re-blur every frame because the content behind them is moving. During a session that means:
- **About 30 view updates per second for as long as the session screen is visible**, including while `.prompting`. SwiftUI drives `TimelineView` body updates and `Canvas` drawing from the main thread. Main-thread work during the prompt competes with touch delivery for OK and with the `.task` that calls `promptDidAppear`. The plan treats exactly those two as the timing endpoints.
- **Sustained GPU and battery cost with the screen forced on.** `isIdleTimerDisabled` is set for sessions, so a 10-minute session keeps two full-screen blurs animating for 10 minutes.

**(plausible: measure)** Use Instruments (SwiftUI + Time Profiler + Energy) for one 20-card session with Reduce Motion off versus on, and compare the spread of `responseMs` for an identical tapping pattern.

**Fix direction (pick one):**
- Freeze the aurora in `SessionView`: pass a `paused` flag that is true for the whole session, or at least while `.prompting`.
- Render the blobs once into an image and animate only its offset (cheap compositing).
- Drop to about 10 fps.

Keep the motion on Home if wanted; it's the session screen that matters.

### R3-3 · P3 (Low) · Colour contrast of the most-used controls is below WCAG large-text minimum
**Files:**
- `SessionView.swift` (Wrong `[rose, amber]`, Correct `[mint, teal]` with white labels)
- `Theme.swift:15-22`
- `HomeView.swift` `DeckCard` (white text and white-on-20 % chips over the Korean `coral→pink` gradient)

Approximate contrast against white text:

| Colour | Contrast vs white |
|---|---|
| mint | ≈ 1.9 : 1 |
| teal | ≈ 2.7 : 1 |
| amber | ≈ 1.9 : 1 |
| rose | ≈ 3.1 : 1 |
| coral | ≈ 2.8 : 1 |
| pink | ≈ 3.0 : 1 |

WCAG AA needs **3 : 1** for large bold text and **4.5 : 1** for the `.subheadline` / `.caption` text on the deck cards. The previous system green was also weak (≈ 2.2 : 1), so this isn't a regression for the grade buttons. It *is* a regression for the Korean deck card text. "Increase Contrast" is not handled anywhere.

**Fix direction:**
- Darken the gradient stops for button fills, or use dark label text on mint/amber.
- Add an `accessibilityDifferentiateWithoutColor` / `colorSchemeContrast == .increased` variant with solid, darker fills.

### R3-4 · P3 (Low) · The trend chart's smoothing misrepresents data
**File:** `App/Sources/Features/Stats/StatsView.swift` (`trendMarks`: `.interpolationMethod(.catmullRom)` on `AreaMark` + `LineMark`)

Catmull-Rom splines overshoot between points. An accuracy series of 100 % → 60 % → 100 % draws a curve **above 100 %** and a dip below the real minimum between sessions. A median-time series can similarly show values that never happened. This is a stats screen, so the curve should not invent data.

**Fix direction:** use `.monotone`, which doesn't overshoot, or `.linear`.

### R3-5 · P3 (Low) · The grade buttons flicker opaque → dim → opaque on every reveal
**File:** `App/Sources/Features/Session/SessionView.swift:42, 287-296`

`gradeEnabled` starts `true` and is only set to `false` inside `.task(id: phaseKey)`, which runs **after** the reveal's first frame. Each reveal therefore renders Wrong/Correct at full opacity and hit-testable for a frame, then animates to 0.55, then back to 1 after about 250 ms. It is functionally safe, because the engine still rejects early grades. Visually it is a flicker on every card, which is what G2 meant to avoid.

**Fix direction:** set `gradeEnabled = false` synchronously in the same action that calls `vm.ok()` (Reveal button, tap-anywhere, keys), or derive the initial value from `vm.gradeLockoutRemaining > .zero` at render time.

### R3-6 · P3 (Low) · `recoveredFields` misses fallbacks *inside* the options structs
**Files:** `Decks/FretboardNotesDeck.swift` (`FretboardOptions.init(from:)`), `Korean/Vocab.swift` (`VocabOptions.init(from:)`)

`SessionConfig` records a recovered field only when the whole `options` value fails. The inner tolerant decoders fall back silently, field by field. For example, an unknown `noteSet` raw value becomes `.naturals`, and `recoveredFields` stays empty. The Summary caption doesn't appear, and `initialConfig` re-uses the altered config as if it were valid.

**Fix direction:** have the inner decoders report recovered keys too, for example via a `userInfo`-provided collector or by returning a `(value, recovered)` pair through a small helper. Then merge them as `"options.noteSet"` and so on.

### R3-7 · P4 (Polish) — small items
- **README out of date** (`README.md:24, 28`): it still documents the prompt key as "= OK" and the QA step as "prompt → OK". The button is now **Reveal**; the identifier `okButton` is unchanged, which is fine.
- **Reduce Motion gaps:** the paused-overlay transition always scales (`.scale(scale: 0.94)` in `SessionView`), and the Home and Settings springs (`Theme.spring` on dismiss and expand) are not gated. The flip, tilt, aurora and heatmap animations are gated.
- **Force-unwrap / index assumptions on colour arrays:**
  - `GradientProgressBar` uses `colors.last!` (`Theme.swift:195`)
  - `AuroraBackground` and `RingGauge` use `colors[0]`
  - `subjectColors[0]` is used in several places
  All callers pass two colours today. An empty array would crash. Use non-empty types, or fall back.
- **Summary hero headline** judges on accuracy alone, so 1 of 1 correct reads "Flawless!". Consider requiring at least 5 counted cards before the superlatives.
- **`DevSeeder`** (DEBUG simulator only) writes into the *current* store and **overwrites** existing Fretboard `ItemStats` with seeded values. It also does about 29k individual `save()` calls, which is slow. Consider a dedicated seeded store, or at least a confirmation dialog.

## Process notes
- **Branch:** the M1 baseline, all fixes and the UI pass now live on `review/m1-code-review`. The default branch `claude/korean-music-flashcard-plan-ffx6z5` still has only the plan. A PR from this branch would mix 13k lines of implementation with the review documents. Decide whether to merge it as-is or move the implementation to its own branch (the handoff flags this as unconfirmed).
- **Still pending from the plan:** the G5 measurements (N5) and the G6 device checks (P2-2, P2-3, P2-5, P2-6).

## Round 3 — Suggested next steps
1. **R3-1:** fix the three test lines, switch CI to `swift test`, and fix the docs. About 10 minutes, and it restores a 127-test safety net.
2. **R3-2:** measure, then freeze the aurora during sessions. This protects the app's core measurement.
3. Run the G5 measurements and G6 device checks, and record them in PLAN §17.
4. R3-5, R3-4, R3-3, R3-6 (all small), then the R3-7 polish.
5. Settle the branch question before opening a PR.

---

# Round 2 — Re-review of M1.1 fixes

- **Date:** 2026-11-16
- **Scope:** the 28 Swift files changed since Round 1, as listed by the implementor's handoff and `PLAN_M1_FIXES.md` (F2–F9). Unchanged files were not re-read.
- **Method:** static read again. `swift build` for `MemoriseCore` passes. Nothing was executed on device or simulator, and there are still no tests, so every "fixed" below means **fixed by inspection**. Items marked *unverified* need the device checks listed in `PLAN_M1_FIXES.md`.

## Verdict

Good fix round. The fixes are targeted, they match the fix plan, and none of them introduces a regression I could find.
- **Both functional P1 bugs are fixed.** All the P2 items in scope are fixed; one of those, P2-3, still needs a runtime check.
- **What remains open is by owner decision:** P1-3 (no tests) and P2-8 (deferred to M2 as F10).
- **This round found 7 new issues.** One is Medium; the rest are Low or Polish.

## Status of Round 1 findings

| ID | Finding | Status | Evidence / remark |
|---|---|---|---|
| P1-1 | Sharps behaves like Mixed | ✅ Fixed | `FretboardNotePrompt.randomizeSpelling` is set only for `.mixed` (`FretboardNotesDeck.swift:84`) and checked in `present` (`:95`). `respelled` preserves it (`Card.swift:42-46`). Retries and resumed cards re-use the presented card, so their spelling stays stable. |
| P1-2 | Sessions dropped on config decode failure | ✅ Fixed | Tolerant `init(from:)` on `SessionConfig`, `FretboardOptions` and `VocabOptions`. `SDSession.core` is non-optional, logs failures, and uses `DeckOptions.fallback` (`SwiftDataModels.swift`). `compactMap` is replaced by `map` in `SwiftDataStatsStore.swift:36, 56`. **Gap:** the F5 golden-fixture step was skipped, so the persisted shape of `DeckOptions` / `SessionLength` (synthesised `_0` coding) is still unpinned. See P1-3. |
| P1-3 | No automated verification | ⚠️ Open: owner declined (D1 = No) | Partly mitigated: `DeckValidator` now runs in every configuration, and its results show on Home (`DeckCatalog.swift:42-43`). CI is still build-only. Risk is unchanged for the scheduler, the engine and decoding compatibility. |
| P2-1 | Scheduler fallback ignores exclusions / gating | ✅ Fixed | The `allowed[]` mask mirrors the weight predicate (`Scheduler.swift:58-63`), and the fallback chooses only from allowed cards (`:88-95`). The engine order is due retry → weighted pick → earliest non-adjacent retry → allowed fallback → any retry (`SessionEngine.swift:248-278`). I re-traced the Round 1 4-card case: card 1 now comes back as a *retry* at position 5 and is never counted twice. RNG use stays deterministic, because a failed weighted pass consumes no randomness. |
| P2-2 | Double-tap grades | ✅ Fixed (*unverified on device*) | `canGrade` with `gradeLockoutMs = 250`, enforced in the engine (`SessionEngine.swift:163-171`), so taps, swipes and keys are all covered. The VM guards before firing haptics or speech (`SessionViewModel.swift:83`). Pause/resume shifts `revealedAt` correctly. See new N3 for UX. |
| P2-3 | ModelActor on main thread | ✅ Fixed (*unverified*) | The store is now constructed inside `Task.detached` (`DeferredStatsStore.swift:14-20`). The F6 step-1 measurement (`Thread.isMainThread` in `save`) was **skipped**, so neither the original problem nor the fix has been observed. Do the measurement once. |
| P2-4 | Silent degradations | ✅ Fixed | In-memory fallback → red banner on Home (`HomeView.swift:73-75, 93-104`). Each deck file loads on its own (`DeckCatalog.swift:35-41`). Recorder failures are counted and shown on the Summary (`SessionViewModel.swift:58-61`, `SummaryView.swift:18-24`). See new N2 for wording. |
| P2-5 | Keyboard focus not restored | ✅ Fixed (*unverified*) | Focus is re-asserted on `phaseKey`, on `scenePhase == .active`, on dialog dismissal and on alert dismissal (`SessionView.swift`, `running` modifiers). |
| P2-6 | Killed sessions marked abandoned | ✅ Fixed | `SessionRecord.closedAfterInterruption` → `.completed` with ≥ 1 counted attempt and an `endedAt` derived from the attempts (`Records.swift:36-46`). Applied in both stores. |
| P2-7 | Stats tab reloads all attempts | 🟡 Partly fixed → downgraded to **P3** (see N5) | Raw attempts no longer live on the main actor, the load is gated on visibility and staleness (`StatsView.swift:83-99`), and history detail loads one session at a time. However, `trendPoints` still fetches **every** attempt of the deck on each stale load (`StatsStore.swift:36-47`). Phase B was deferred by design. |
| P2-8 | Closed deck-type sites | ⏸ Deferred (F10, M2-0) | `DeckOptions.fallback` adds one more closed switch (`Deck.swift:23-25`). It is acknowledged in code. |
| P3-1 | Default max fret ignored | ✅ Addressed | Relabelled "Max fret for new setups", with an explanatory footer (`SettingsView.swift:50-58`). Behaviour is unchanged, by design. |
| P3-2 | Stale tag filters | ✅ Fixed | `VocabOptions.sanitized(allTags:)` is applied in `initialConfig` (`AppEnvironment.swift:68-70`). |
| P3-3 | Timed progress bar stalls | ✅ Fixed | The bar is wrapped in a 1 s `TimelineView` for `.minutes` sessions. |
| P3-4 | Pools regenerated in bodies | ✅ Fixed | Setup: `poolCount` is computed in `.task(id: config?.options)`. Weakest words: the model is `@State` behind `.task(id:)`. Home: the pool count is computed in the async `load()`, outside `body`. |
| P3-5 | Korean voice cached forever | ✅ Fixed | `refreshVoices()` runs on `scenePhase == .active` (`MemoriseApp.swift:29-31`). The one-time hint flag remains; that is acceptable. |
| P3-6 | No fetch indexes | ➖ No action (accepted) | iOS 17 target. |
| P3-7 | `attempts(forDeck:)` order contract | ✅ Fixed | The doc and both stores now order by `shownAt`, then `index`. |
| P3-8 | Fire-and-forget launch sweep | ✅ Fixed | The sweep runs inside `ready`, and every store call awaits `ready` first. |
| P4 | Polish (4) | ✅ 3 fixed, 1 n/a | Audio session deactivated on session exit, `fastest` / `slowest` clamped with a stable sort, zero deltas formatted without an arrow (see N4). The CI rename is n/a because F1 was skipped. |

## New findings (Round 2)

### N1 · P2 (Medium) · The persisted-format guarantee for history rests on untested synthesised coding
**Files:** `Packages/MemoriseCore/Sources/MemoriseCore/Domain/Deck.swift:7` (`DeckOptions`), `Domain/SessionConfig.swift:2` (`SessionLength`), and F5 step 1 (skipped).

P1-2's fix makes history survive *field* changes inside the options structs. The outer enums still use **synthesised** `Codable`: `{"fretboard":{"_0":{…}}}` and `{"cards":{"_0":20}}`. If one of them changes shape, `SessionConfig.init(from:)` silently replaces the stored options with `DeckOptions.fallback` and the length with `.cards(20)`. That can happen by labelling an associated value, renaming a case, or changing the payload type. History then survives, but **shows the wrong configuration for every past session**, with nothing in the UI to say so. The F5 golden fixtures were the guard against this, and they were skipped together with the tests.

**Failure scenario:** M2 adds `case fretboard(FretboardOptions, tuning: Tuning)` or relabels `_0`. Every stored session decodes with fallback options. The History summaries' labels (`buildLabels` uses `summary.config.options`) and the Setup "last used" config quietly reset.

**Fix direction:** either
- pin the two outer enums with hand-written coding now (keyed `"kind"` + `"value"`, decoding the current `_0` shape as legacy), or
- add a code comment on both enums plus a `CLAUDE.md` rule: never change their case names or associated-value shapes without a migration.

The first is cheaper than it sounds (about 30 lines) and removes the dependency on tests.

### N2 · P3 (Low) · The deck-issues banner says "couldn't be loaded" when the decks did load
**Files:** `App/Sources/Features/Home/HomeView.swift:109`, `Packages/MemoriseCore/Sources/MemoriseCore/Decks/DeckCatalog.swift:42-43`

`issues` mixes two kinds of message: load failures (deck skipped) and validation errors (deck **still loaded**). Both produce "Some decks couldn't be loaded". A validation-only issue, such as a duplicate cross-file id, is the more dangerous one, because stats merge silently. It gets the less accurate message.

**Fix direction:** return two lists (`loadFailures`, `validationWarnings`) and word them differently. For example: "Some decks couldn't be loaded" and "Deck data has problems; stats for affected words may be mixed".

### N3 · P3 (Low) · The grade lockout gives no feedback
**Files:** `App/Sources/Features/Session/SessionViewModel.swift:83`, `SessionView.swift` (Wrong/Correct buttons, `handleKey`)

A tap or key arriving within 250 ms is dropped silently, and the buttons look enabled the whole time. Pedal users who press OK→Correct in one quick double press will find the second press ignored and the card still on screen. The press looks lost, and that is easy to read as the pedal failing. `handleKey` also returns `.handled` for the dropped press.

**Fix direction:**
- Visually disable or dim Wrong/Correct until `canGrade` is true (a one-shot 250 ms timer, or derive it from `revealedAt`).
- Return `.ignored` from `handleKey` when the grade was rejected.

### N4 · P4 (Polish) · Zero-delta format is inconsistent
**File:** `App/Sources/Support/Formatters.swift:36, 43`

`"= 0.00 s"` doesn't match `Fmt.seconds`, which renders "850 ms" / "2.3 s"; that format would say "= 0 ms". In addition, the zero case is colored green by `SummaryView.swift:76, 83`, because `<= 0` / `>= 0` counts as an improvement.

**Fix direction:** use `"= " + seconds(0)`, and use `.secondary` for an exact zero.

### N5 · P3 (Low) · `trendPoints` still loads every attempt of a deck (P2-7 remainder)
**File:** `Packages/MemoriseCore/Sources/MemoriseCore/Persistence/StatsStore.swift:36-47`

This is now off the main actor and runs only when the Stats tab is visible and stale, so the user impact is small. The cost still grows linearly with all-time attempts, though: about 30k rows per year is ~30k `SDAttempt` → `Attempt` mappings per stale load. Phase B (persist baselines on `SDSession` via `SchemaV2`) remains the real fix. The trigger the plan defined (> 150 ms measured) is reasonable; just make sure someone actually measures it.

### N6 · P3 (Low) · History detail turns a fetch error into an empty summary
**File:** `App/Sources/Features/Stats/StatsView.swift:185`

`(try? await env.store.attempts(for:)) ?? []` shows "No cards answered" for a session that has cards, whenever the fetch fails. Show an error state instead (`ContentUnavailableView` + log).

### N7 · P4 (Polish) · PLAN contradicts itself on retry timing
**Files:** `PLAN.md:524` (§9.2: "after **3–5** further cards") vs `PLAN.md:617-624` (§10.6: in a starved pool the engine flushes the earliest pending retry, possibly sooner) and `SessionEngine.swift:262-266`

The code follows §10.6, which is the right call. §9.2 and the S6 acceptance line (`PLAN.md:769`) should say "3–5 cards later, or earlier when the pool is exhausted". Otherwise a future test written from §9.2 will fail on a correct engine.

## Round 2 — Suggested next steps

1. **N1**: pin the `DeckOptions` / `SessionLength` coding, or at least document the freeze, **before** starting M2/F10, since F10 is exactly the change that would trip it.
2. **Device checks** for the *unverified* items: P2-2 (double-tap), P2-3 (`Thread.isMainThread` log), P2-5 (pedal focus after the dialog, alert and background), and P2-6 (kill mid-session → completed).
3. N2, N3, N6 (each is small).
4. Reconsider D1 (tests). The cheapest high-value set is still: validator over the bundled decks, `present` spelling per option, the starved-pool scheduler trace, and decoding fixtures for N1.
5. Commit the work. The implementation, the fixes and `PLAN_M1_FIXES.md` are still **uncommitted**, so none of the M1.1 changes has a reviewable diff or a rollback point.

---

# Round 1 — Original review

- **Date:** 2026-11-16
- **Scope:** everything under `Packages/MemoriseCore/` and `App/`, plus `project.yml` and the CI workflows. That is about 5k lines of Swift and the 2 bundled deck JSON files (205 + 81 entries).
- **Reviewed against:** `PLAN.md` (spec + §17 decision log).
- **Focus:** correctness against purpose, rigidity / extensibility, optimisation.
- **Method:** a static read of every source file, with the trickier paths traced by hand. Nothing was executed and no tests exist. Items marked **(plausible)** depend on runtime or framework behaviour I could not observe; confirm them on a device.

## Overall verdict

The architecture is solid. All domain logic lives in a Foundation-only core, with the clock and RNG injected. The engine is a synchronous state machine that emits ordered persistence effects. SwiftData sits behind a protocol. The code is small, readable and well documented.

The problems are concentrated in three places:
1. **One user-visible feature bug** in the main fretboard setting.
2. **Latent data-integrity traps** that fire on the next schema change or on edge-case pools.
3. **Zero automated verification.** Every bug below would have been caught by the acceptance tests the plan specified.

| Priority | Count | Meaning |
|---|---|---|
| **P1 – High** | 3 | Wrong behaviour now, or silent data loss on the next ordinary change. Fix before relying on the app. |
| **P2 – Medium** | 8 | Wrong in reachable edge cases, plus measurement-accuracy risk, silent failure, or rigidity that will slow M2. |
| **P3 – Low** | 8 | UX inconsistencies, wasted work, minor contract drift. |
| **P4 – Polish** | 4 | Cosmetic / housekeeping. |

---

## P1 — High

### P1-1 · The "Sharps" accidental setting behaves exactly like "Mixed"
**Files:** `Packages/MemoriseCore/Sources/MemoriseCore/Decks/FretboardNotesDeck.swift:78-81`, called from `Session/SessionEngine.swift:255`

`present(_:using:)` flips every sharp-spelled card to its flat spelling with 50 % probability. It never checks whether the user chose `.mixed`, and it can't, because the `Deck.present` signature receives no options. Cards are generated sharp for both `.sharps` and `.mixed` (`preferFlat` is only true for `.flats`), so:

- **Sharps** → random ♯/♭ (wrong)
- **Mixed** → random ♯/♭ (correct)
- **Flats** → always ♭ (correct, only because the guard requires `.sharp`)

**Failure scenario:** a user picks *All notes + Sharps*. About half of the accidental prompts appear as D♭, E♭ and so on. This contradicts PLAN §7 (line 312) and the §17 decision-log entry ("random ♯/♭ choice for `.mixed`").

**Fix direction:** the presentation step needs to know the option. Either carry a "randomise spelling" flag on `FretboardNotePrompt`, set at generation time only for `.mixed`, or pass `DeckOptions` into `present`. The first option keeps the protocol unchanged and is simpler. See also P2-8 for the root cause in the protocol design.

### P1-2 · Session history silently disappears when `SessionConfig` cannot be decoded
**Files:** `App/Sources/Persistence/SwiftDataModels.swift:128-129`, `App/Sources/Persistence/SwiftDataStatsStore.swift:36, 55-56`

`SDSession.core(decoder:)` returns `nil` if the stored `configData` JSON fails to decode, and every read path `compactMap`s those sessions away. `SessionConfig`, `FretboardOptions`, `VocabOptions` and `DeckOptions` all use **synthesised** `Codable`, so adding any non-optional property in the future makes **every historical session** undecodable. `VocabEntry` already uses the safe `decodeIfPresent` pattern, but these types don't.

**Failure scenario:** M2 adds `FretboardOptions.tuning`. After the update:
- the History list is empty
- the Trend chart is empty
- `baselineOfLastCompletedSession` returns `nil`, so there are no "vs. last session" deltas
- **Export writes attempts whose sessions are missing** (orphaned rows)

Nothing is logged.

**Fix direction:**
- Give the persisted config types hand-written `init(from:)` with `decodeIfPresent` + defaults, or a versioned DTO.
- On decode failure, still return a `SessionRecord`, with a fallback config or an optional config, rather than dropping it.
- At minimum, log the failure.

### P1-3 · No automated verification anywhere
**Files:** `.github/workflows/core-tests.yml`, `Packages/MemoriseCore/Package.swift`, `Decks/DeckCatalog.swift:27-30`

The owner chose implementation only, without tests, and that is recorded in §17. The cost should still be explicit:
- The workflow named *core-tests* only runs `swift build -c release`.
- `DeckValidator` runs only inside a `#if DEBUG` `assert` at app launch, so CI (release build) and any Release/TestFlight build **never validate the deck JSON**.
- A duplicate entry id in a future JSON edit would merge two words into one `ItemKey`, mixing their stats permanently, and nothing would catch it.
- P1-1 and P2-1 are each a few-line test that the plan's S3/S5 acceptance criteria already describe.

**Fix direction (minimum viable):** add a test target containing a handful of tests: validator over the bundled files, the key spelling-stability and `present` spelling behaviour, the small-pool scheduler fallback, and the engine retry flow with `ManualClock` + seeded `SplitMix64`. Then switch the core CI step to `swift test`. The engine was designed for exactly this kind of deterministic testing, so the cost is low.

---

## P2 — Medium

### P2-1 · The scheduler fallback ignores exclusions and introduction gating
**Files:** `Scheduling/Scheduler.swift:76-79`, `Session/SessionEngine.swift:248-256`

When every weight is zero after relaxing the cooldown once, the fallback picks uniformly from the **whole pool**, minus the previous card. That pool includes:
- cards in `excluded` (pending retries the engine will inject itself)
- unseen cards outside `eligibleNew` (gated by `IntroductionPolicy`)

The plan's §10 wording has the same gap, so this is a spec bug as well as a code bug.

**Failure scenario (traced):** a pool of 4 cards (for example a tiny tag filter), K = 3, retries on.
1. Card 1 is wrong (retry due at 5–7). Card 2 is wrong (retry due at 6–8). Cards 3 and 4 are shown.
2. At history = 4, no retry is due. Cards 1 and 2 are excluded and cards 2–4 are blocked, so the total is 0. Relaxing to K = 2 still gives 0, so the fallback runs.
3. The fallback can pick card 1 **as a normal counted card**. Its stats update a second time within a few cards, and it is *still* in `pendingRetries`, so it appears a third time as a retry.

With a gated vocab deck, the same path can surface a random never-seen high-rank word.

**Fix direction:**
- The fallback should first flush the earliest pending retry (the engine already does this when `nextCard` returns `nil`).
- Otherwise it should pick only among non-excluded, eligible cards.
- Return `nil` rather than violate those sets.

### P2-2 · A fast double-tap on OK can record a grade
**Files:** `App/Sources/Features/Session/SessionView.swift:79-82, 176-180, 202-206`

The full-width **OK** button is replaced in the same spot by **Wrong | Correct**. The reveal has an opacity insertion transition but no input lockout, and SwiftUI views accept hits during a transition. A quick double-tap on OK, or a tap-anywhere followed by a stray tap, therefore grades the card with a `gradeMs` of about 100 ms. That corrupts the item's stats. There's no undo, because `undoLastGrade` was deferred (§17).

**(plausible: confirm on device)**

**Fix direction:**
- Ignore grade input for about 250–300 ms after `ok()`. The engine already tracks `revealedAt`, so the guard can live in the engine or the view model.
- Alternatively, implement the planned `undoLastGrade`.

### P2-3 · The SwiftData actor probably executes on the main thread
**Files:** `App/Sources/AppEnvironment.swift:39`, `App/Sources/MemoriseApp.swift:5`

`SwiftDataStatsStore` is a `@ModelActor` but is constructed inside `AppEnvironment.live()` on the main actor. A `@ModelActor` created on the main thread is widely reported to bind its `ModelContext` / executor to the main queue. If that happens here:
- every per-grade `fetch` + `save()` (2–3 per grade) runs on the main thread
- it runs exactly while the next prompt is rendering
- this adds jitter to `promptDidAppear` and therefore to the **response time, which is the app's core measurement**

The Stats tab's full-deck attempt fetch (P2-7) would also block the UI.

**(plausible: verify with Instruments or a `Thread.isMainThread` log in `save`)**

**Fix direction:** construct the store off the main actor, for example inside a detached task, and inject it once it is ready.

### P2-4 · Silent degradations with no user-facing signal
**Files:**
- `App/Sources/AppEnvironment.swift:31-36` and `37-43`
- `Decks/DeckCatalog.swift:26`
- `Features/Session/SessionViewModel.swift:56-58`

- **SwiftData container fails** → falls back to `InMemoryStatsStore`, with only a `log.fault`. The user practises normally and **loses everything at the next launch** without ever being told.
- **One vocab JSON fails to decode** → `bundledVocabFiles.map(loadBundledVocabFile)` throws for the whole set, so **all** Korean decks vanish, not just the bad one.
- **Persistence errors during a session** → logged only.

**Fix direction:**
- Surface a persistent banner or alert when running on the in-memory fallback.
- Load deck files independently so a single failure only drops that deck.
- Count recorder errors and show them on the summary.

### P2-5 · Keyboard / pedal focus is not restored after interruptions
**Files:** `App/Sources/Features/Session/SessionView.swift:92-96, 97-107`

`keyboardFocused = true` is set once, in `onAppear`. The confirmation dialog, the "No Korean voice" alert, and a background/foreground cycle can all move focus away, and nothing re-asserts it. A page-turner pedal user (a README-documented feature) can lose input mid-session with no visible cause.

**(plausible)**

**Fix direction:** re-assert focus when `vm.state` changes and when `scenePhase` returns to `.active`.

### P2-6 · Killed sessions are recorded as "abandoned" even when cards were graded
**Files:** `App/Sources/AppEnvironment.swift:45`, `App/Sources/Persistence/SwiftDataStatsStore.swift:99-105`, compare `Session/SessionEngine.swift:294`

If the app is killed mid-session, the launch sweep sets the status to `.abandoned` and leaves `endedAt` as `nil`. The engine's own rule for quitting is the opposite: *completed if anything was graded*. As a result:
- the item stats from that session are counted
- the session is excluded from the trend, from "last session" baselines, and from history numbers (it shows "Abandoned")
- its duration shows as 0

**Fix direction:** the launch sweep should mark a session `.completed` when it has counted attempts, with `endedAt` = the last attempt's `shownAt`. Also run the sweep before the first session can start: it is currently an unstructured `Task`, so there is a theoretical race with a very early start.

### P2-7 · The Stats tab reloads every attempt of a deck on each data change
**Files:** `App/Sources/Features/Stats/StatsView.swift:19-31, 80`

`DeckStatsData.load` fetches **all** attempts of the deck, groups them, and recomputes every session baseline. It runs on every `dataVersion` bump, which happens after every session, even while the tab isn't visible. The cost grows linearly forever: roughly 2 sessions × 40 attempts × 365 days ≈ 30k rows per year. Combined with P2-3, that would happen on the main thread.

**Fix direction:**
- Persist the session's baseline numbers (median, accuracy, counted cards) on `SDSession` when it finishes.
- Load attempts only for the session the user opens.

### P2-8 · Rigidity: adding a deck type means touching about 8 closed switch / downcast sites
**Files:**
- `Domain/Card.swift:16` and `Domain/Deck.swift:7` (closed enums)
- `Session/SessionEngine.swift:97` (`config.options.vocab?.newPerSession`)
- `App/Sources/AppEnvironment.swift:63-66` (fretboard special case)
- `Components/CardViews.swift:12, 26`
- `Support/Formatters.swift:49-56`
- `Features/SessionSetup/SessionSetupView.swift:68-79`
- `Features/Stats/StatsView.swift:66-72` (`is FretboardNotesDeck` / `as? VocabDeck`)

The `Deck` protocol looks open, but the payload, the options and the UI are all closed sets. Most importantly, `present(_:using:)` gets no options, which is the direct cause of P1-1.

The app UI also hard-codes standard tuning and 6 strings in several places:
- `CardViews.swift:38` (a static `FretboardNotesDeck()` ignores the real deck's tuning)
- `FretboardView.swift:26`
- `FretboardHeatmap.swift:21`
- `SessionSetupView.swift:127`

That is acceptable for M1. It will be the main friction point for M2 (chords/scales, alternate tunings), which `FretMark`'s doc comment already anticipates.

**Fix direction (before M2):**
- Give `Deck` the hooks the engine needs: `present(card, options, rng)` and `newPerSession(options)`.
- Route per-kind UI through a small registry keyed by `CardContent` case / deck kind, instead of downcasts.
- Pass the deck's `Tuning` to the views.

---

## P3 — Low

| # | Issue | Location | Notes / fix direction |
|---|---|---|---|
| P3-1 | **Default max fret** in Settings has no effect once a deck has a saved last-used config | `AppEnvironment.swift:59-61` | Saved config always wins. Either apply the setting only when it was changed after the save, or label it "for new decks". |
| P3-2 | Saved vocab **tag filters for tags that no longer exist** keep filtering invisibly | `AppEnvironment.swift:59`, `SessionSetupView.swift:184` | Intersect `options.tags` with `deck.allTags` when loading the saved config. A pool can otherwise shrink to 0 with Start disabled and no explanation. |
| P3-3 | Timed-session progress bar only moves on card transitions | `SessionViewModel.swift:28`, `SessionView.swift:137` | `engine` is `@ObservationIgnored`. Wrap the bar in the existing 1 s `TimelineView`, as the label already is. |
| P3-4 | Card pools regenerated inside view bodies | `SessionSetupView.swift:43, 82` (twice per render), `WeakestWordsSection.swift:17-30` (cards + median + sort per render), `HomeView.swift:102` | Cheap at today's sizes (≤ 410 cards), but wasteful. Cache in `@State` keyed on options / stats. |
| P3-5 | Korean voice availability cached for the app's lifetime; the hint shows only once ever | `SpeechService.swift:8-11`, `SessionViewModel.swift:123-128` | A voice installed mid-run isn't detected until relaunch. Re-query on `scenePhase` `.active`. |
| P3-6 | Fetch predicates on `deckID` / `sessionID` / `statusRaw` have no indexes | `SwiftDataModels.swift` | Full scans. Fine now. Add `#Index` if the deployment target moves to iOS 18, or rely on the P2-7 denormalisation. |
| P3-7 | `attempts(forDeck:)` ordering contract differs between stores | `StatsStore.swift:13` vs `SwiftDataStatsStore.swift:50` (by `shownAt`) vs `InMemoryStatsStore.swift:43` (by session) | Harmless today because results are regrouped, but the protocol doc and the implementations disagree. |
| P3-8 | Launch "abandon" sweep is fire-and-forget | `AppEnvironment.swift:45` | See P2-6. Await it before enabling Start, or make it part of store initialisation. |

## P4 — Polish

- `core-tests.yml` / "Core (Linux)" only builds. Rename it, or fix it via P1-3.
- `SpeechService` activates a `.playback` audio session once and never deactivates it. It also plays through the silent switch; confirm that's intended.
- `SessionSummary.fastest` / `slowest` use raw `responseMs`, while all other timing maths uses clamped values. That's inconsistent, though it is display only.
- `Fmt.delta(ms:)` renders an exact 0 as "▼ 0 ms".

---

## What's good (keep it)

- **Separation:** the core is Foundation-only, so it builds on Linux and is fully deterministic through `MonotonicClock` + `SplitMix64` injection.
- **Engine design:** a pure state machine returning `SessionEffect`s, applied in order by `SessionRecorder`. It avoids non-Sendable state crossing actors and makes replay testing trivial.
- **Stable identity:** `ItemKey` is spelling-independent (`canonicalSharpName`), and the "never change" rules are documented at the source.
- **Timing hygiene:** response time is measured from `promptDidAppear` on a monotonic clock. Interrupted attempts are excluded from stats, and paused time is excluded from timed sessions.
- **Persistence:** the schema is versioned from day one (`SchemaV1` + migration plan), and each effect is saved immediately.
- **Accessibility:** identifiers and labels are on all interactive controls, Reduce Motion is respected, and there's a landscape layout.

## Suggested fix order

1. **P1-1** (one-line-scale fix, user-visible).
2. **P1-3**: add the minimal test target; then write tests that reproduce P1-1 and P2-1 *before* fixing P2-1.
3. **P2-1**, **P2-2**: protect stats integrity.
4. **P1-2**: before *any* change to a `Codable` config type.
5. **P2-3**, then **P2-7**: performance and timing accuracy, verified with Instruments.
6. **P2-4**, **P2-5**, **P2-6**: robustness.
7. **P2-8**: as the first task of M2.
8. P3 / P4 opportunistically.
