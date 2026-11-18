# Memorise — Round 10 Plan: Lyrics speed, Korean detection, every word translatable, live "Now playing"

- **Date:** 2026-11-18
- **Source:** the owner's device findings on 2026-11-18 (§1). There's no code review round behind this file. It is named R10 so it follows `PLAN_R9_FIXES.md`.
- **Owner of this file:** the planner. The implementor and frontend agents run the segments in §4 and tick the tracker (§3).
- **Conventions:** `CLAUDE.md` and PLAN.md §16 apply.
  - Pure logic stays in `MemoriseCore`, which imports only Foundation. Translation, networking and SwiftUI stay in the App target. Inject clocks.
  - Persisted `Codable` types: every new property gets a default and is read in the hand-written tolerant `init(from:)`. Never rename keys or raw values.
  - **This plan has two wire changes, both additive and both in `LyricsCacheFile`:** `koreanRule` (LA1) and `lineGlosses` (LA2). `schemaVersion` stays `1`.
  - Never hand-edit the `.xcodeproj`. Record every deviation in PLAN.md §17.
- **Commits:** one segment = one commit, with the message given in the segment. Stage **only** the files that segment touches. Other agents leave files uncommitted in the same tree. Right now the QA agent's test files and `.github/workflows/core-tests.yml` are uncommitted: **never stage them.**
- **Tests:** none in this plan. The tester agent owns tests. Each segment lists acceptance criteria for the tester.
  - **Exception:** if a signature change breaks the build of an existing test target, update those call sites mechanically so `swift build --build-tests` still compiles. Don't add or change assertions.

---

## 1. Findings and root causes

| ID | Owner finding | Root cause (verified in code / with real data) | Segment |
|---|---|---|---|
| **F1** | The Lyrics screen is very laggy compared with the rest of the app. | **(a) Re-render fan-out in the reader.** Every `LyricTokenView.body` calls `model.isKnown(token)` → `GlossService.meaning` → reads the observable `glosses` dictionary and runs a `WordLookup` (NFC + particle strip + normalise) per token. `GlossService.runBatch` calls `store` **once per translated word**, and each call mutates `glosses`. So every word that arrives invalidates **every token view in the song**: about 150 words × 400 tokens, all on the main thread, while the user scrolls. **(b) A disk write per word.** Each `store` starts `cache.mergeGlosses`, which reads the JSON, writes it back and lists the cache folder (prune). That's about 150 read/write/list cycles per song. **(c) The Lyrics home aurora keeps animating under the pushed reader.** Its `TimelineView` (30 fps blurred `Canvas`) is never paused while a reader or playlist is on top, so it competes with the reader for the frame budget. **(d) List cost on the home screen.** `GlassCard` puts `.shadow(radius: 18)` on the *whole content*, so a 50–500-row `TrackList` is shadowed as one big layer. `AsyncImage` keeps no image cache, so artwork reloads and flashes every time a row scrolls back in. | **LA2** (a, b), **LA3** (a, c, d) |
| **F2** | Some Korean songs, e.g. *ANTIFRAGILE*, show "Lyrics not available". | `KoreanLyricsCheck.isKorean` needs `Hangul ÷ (Hangul + Latin letters) ≥ 0.25`. The ratio counts **letters**, and an English word has about 5 letters where a Korean word has 2–3 syllables, so the rule is biased against mixed K-pop. Real LRCLIB data (2026-11-18, best Hangul record per song): *ANTIFRAGILE* 274 syllables / 1,166 letters = **0.19** ✗; *Hype Boy* 0.20 ✗; *ETA* 0.23 ✗; *Magnetic* 0.16 ✗ (the M6 mock-up's own example song); *Pink Venom* 0.13 ✗; *EASY* 0.18 ✗; *Shut Down* 0.09 ✗; *Super Shy* 0.07 ✗. English-only songs (*Dynamite*, *Butter*, *Seven*, *The Feels*) have **0** Hangul. **Second cause:** LRCLIB `search` has user-uploaded **romanised** copies (for *ANTIFRAGILE*, record 2269145 has 0 Hangul and the same duration). `bestMatch` ignores the text, so it can pick the romanised copy over the Hangul one. | **LA1** |
| **F3** | Many words aren't underlined. All words should be translatable (English translation or auto-translation), so I can see the whole meaning. | Only words found in a deck are underlined (`underline(known, …)`). Auto-translated words look like plain text. Apple's word translation also fails or echoes Hangul for many conjugated lyric forms, which ends in "Meaning unavailable", and the bubble never shows what the line means. Without a Genius page, the English page shows nothing (old L-D6). | **LA2** (data), **LA3** (UI) |
| **F4** | "Now playing" doesn't update on its own. | `refreshNowPlaying()` runs only on connect, pull-to-refresh, the ↻ button and the return to foreground. Nothing polls, and starting a song from the picker doesn't refresh the card either. | **LA4** |
| **F5** | The reader should show what's playing now. | The reader has no now-playing UI, and polling (LA4 as first planned) stopped as soon as a reader opened. | **LA4** (shared monitor), **LA5** (reader UI) |

### Decisions

| ID | Decision | By | Status |
|---|---|---|---|
| **O-2** | **Replaces M6 L-D6.** When Genius has no English page, the English page shows Apple's on-device translation **line by line**, clearly labelled "Auto-translated". Genius stays first whenever it has a page. | **owner** | ☑ decided 2026-11-18 |
| **O-3** | Words written only in Latin letters ("ANTIFRAGILE", "Look at me") stay plain: not underlined, not tappable. Every token that contains a Hangul syllable is tappable and underlined. | **owner** | ☑ decided 2026-11-18 |
| **P-3** | **Replaces the M6 §4.3 share rule.** Lyrics count as Korean when they have **≥ 20 Hangul syllables** and **≥ 4 lines that contain Hangul**. There is no share threshold. A song that is mostly English but has real Korean verses is a Korean song for this app. The English-only songs above still fail, because they have 0 Hangul. An English song with one short Korean line still fails, on the line count. | planner | decided |
| **P-4** | The word bubble always shows the **line's meaning** under the word's meaning. It uses the aligned Genius line when `TranslationAlignment` pairs the song, and the auto-translated line otherwise. This is how "see the whole meaning" works for words whose single-word translation is weak. | planner | decided |
| **P-6** | The reader shows Spotify's now playing as a **bottom bar**. When Spotify plays the song that's open, there's a small "Playing" or "Paused" chip in the header and no bar. When it plays **another** song, the bar shows that song with a **Show lyrics** button. The button swaps the open reader for the new song; it doesn't push. The reader **never switches on its own** (no auto-follow), so you don't lose your place while studying, and it never changes playback. | planner, **confirmed by owner** | ☑ decided 2026-11-18 |
| **P-5** | Underline styles: a deck word gets a **pink dotted** underline (as today). Every other Hangul word gets a **dotted underline in `Color.secondary`**. A phrase keeps its pink pill. | planner | decided |

---

## 2. Coverage map

| Finding | Segment | Agent |
|---|---|---|
| F2 (Korean check, LRCLIB pick, stale "not Korean" cache) | **LA1** | implementor (core + `LyricsService`) |
| F1a, F1b, F3 data (batched glosses, word fallback, line glosses, precomputed tokens) | **LA2** | implementor (core + `GlossService` + reader VM) |
| F4, F5 data (shared now-playing monitor that polls) | **LA4** | implementor (core + `NowPlayingMonitor` + home VM + one `.task` line in the home view) |
| F5 (now playing in the reader) | **LA5** | frontend (+ one small home VM method) |
| F1a views, F1c, F1d, F3 UI (underlines, bubble line, English fallback page) | **LA3** | frontend |

---

## 3. Tracker

| Segment | Covers | Agent | Status | Notes |
|---|---|---|---|---|
| LA1 Korean check by content; LRCLIB picks the Hangul record | F2, P-3 | implementor | ☐ | Wire change 1 (`koreanRule`) |
| LA2 Glosses: batched, cached once, word fallback, line glosses | F1a, F1b, F3, O-2, P-4 | implementor | ☐ | After LA1 (same `LyricsCacheFile`). Wire change 2 (`lineGlosses`) |
| LA4 "Now playing" refreshes itself (shared monitor) | F4, F5 | implementor | ☐ | Independent of LA1/LA2 |
| LA3 Reader and home rendering; underline every word; English fallback page | F1, F3, O-2, O-3, P-4, P-5 | frontend | ☐ | After LA2 (uses its VM API) **and** LA4 (both edit `LyricsHomeView.swift`) |

| LA5 Now playing in the reader | F5, P-6 | frontend | ☐ | After LA3 (both edit `LyricsReaderView.swift`) |

**Order:** LA1 → LA2 → LA3 → LA5. LA4 can run in parallel with LA1/LA2, but must be committed before LA3 starts.

---

## 4. Segments

### LA1 · F2 · Korean check by content; LRCLIB picks the Hangul record

**Commit:** `R10-LA1: count lyrics as Korean by Hangul content, prefer Hangul LRCLIB records`

**Files:**
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/KoreanLyricsCheck.swift`
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/LyricsModels.swift` (`LyricsConstants`)
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/LRCLIBParser.swift`
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/LyricsCacheFile.swift`
- `App/Sources/Services/Lyrics/LyricsService.swift`
- `PLAN_M6_LYRICS.md` §4.3 and §4.7 (wording)

**Steps:**
1. **`LyricsConstants`:**
   - Delete `minHangulShare`. Keep `minHangulSyllables = 20`.
   - Add `public static let minHangulLines = 4`, documented as "lines (not section headers) that contain at least one Hangul syllable".
   - Add `public static let koreanRuleVersion = 2`. The rule before this segment is version `0`/`1`.
2. **`KoreanLyricsCheck.isKorean(_:)`:** returns `hangulSyllables ≥ minHangulSyllables && hangulLines ≥ minHangulLines`. Section headers are ignored, as today. Keep `hangulShare(_:)` as a public diagnostic, because tests may use it, but nothing in the lookup calls it any more.
3. **`LRCLIBParser`:** add `public static func rankedMatches(_ records: [LRCLIBRecord], titles: [String], artist: String, durationMs: Int) -> [LRCLIBRecord]`.
   - Same filter and the same duration scoring as `bestMatch`.
   - Returns **all** qualifying records, best first.
   - Ties keep their order from LRCLIB.
   - `bestMatch` becomes `rankedMatches(…).first`.
4. **`LyricsService.Run.execute` step 2 (search):** walk `rankedMatches` in order:
   - An `instrumental` record (when no lyrics have been accepted yet) sets `instrumental = true` and stops.
   - Otherwise take the **first record whose lines pass `accept`**.
   - No extra requests: this is the same single search response.
   - Step 1 (`/get`) is unchanged. If `/get` returns a romanised copy, `accept` rejects it and step 2 now finds the Hangul copy.
5. **`LyricsCacheFile`:** add `public var koreanRule: Int`.
   - New coding key `koreanRule`. Missing → `0`. Always encode it. Add an `init` parameter with the default `LyricsConstants.koreanRuleVersion`.
   - `isFresh(now:)`: an entry with `result == "notAvailable"`, `reason == .notKorean` and `koreanRule < LyricsConstants.koreanRuleVersion` is **never fresh**. Songs rejected under the old share rule are looked up again the next time they're opened, with no wait for the 7-day TTL.
   - `LyricsService.fetch` saves `koreanRule: LyricsConstants.koreanRuleVersion`.
6. **Docs:** in PLAN_M6 §4.3, replace the share rule with P-3. In §4.7, add `koreanRule` to the field list. Mark L-D7's "Hangul share below the threshold" as "too little Hangul (§4.3, R10 P-3)".

**Acceptance (for the tester):**
- `isKorean` reference cases (build the lines in the test):
  - 274 syllables over 24 Hangul lines plus a lot of English (ANTIFRAGILE shape) → **true**.
  - 81 syllables over 14 lines (Super Shy shape) → **true**.
  - 0 Hangul, all English (Dynamite shape) → **false**.
  - 3 lines with 30 syllables, all other lines English → **false** (line rule).
  - 5 lines with 15 syllables in total → **false** (syllable rule).
  - Hangul only inside section headers (`[정국]`) → **false**.
- `rankedMatches` with two same-duration hits, the first romanised and the second Hangul: the service accepts the **second**, and the document source is `"LRCLIB"`.
- A cache file with `notAvailable` + `notKorean` and no `koreanRule` key → `isFresh == false` at any `now`. The same file with `koreanRule: 2` → fresh inside 7 days. `notFound` and `instrumental` entries are unaffected.
- An old cache file without the key decodes with `koreanRule == 0`.
- **On device (owner):** ANTIFRAGILE (LE SSERAFIM), Hype Boy, Magnetic (ILLIT) and Pink Venom open with Hangul lyrics, even if they were opened before this build. Dynamite (BTS) still shows "Lyrics not available for this track".

---

### LA2 · F1a, F1b, F3 · Glosses: batched, cached once, word fallback, line glosses

**Commit:** `R10-LA2: batch glosses, fall back to word stems, translate lines, precompute reader tokens`

**Files:**
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/LyricsCacheFile.swift`
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/GlossText.swift` (**new**, pure helpers)
- `App/Sources/Services/Lyrics/GlossService.swift`
- `App/Sources/Services/Lyrics/LyricsCacheStore.swift`
- `App/Sources/Services/Lyrics/LyricsService.swift` (keep `lineGlosses` on refetch)
- `App/Sources/Features/Lyrics/LyricsReaderViewModel.swift`
- `PLAN_M6_LYRICS.md` §2 (L-D6 → "replaced by R10 O-2"), §4.7, §4.8

**Steps:**

1. **Core, `GlossText` (new, pure):**
   - `public static func isUsableGloss(_ gloss: String, for source: String) -> Bool`. False when the trimmed gloss is empty, contains **any Hangul syllable**, or equals the source ignoring case and whitespace. Use it everywhere a machine gloss is accepted. Apple sometimes returns the Hangul word unchanged, or a romanisation that is still Hangul-free. Only the Hangul and echo cases are rejected.
   - `public static func fallbackForm(_ word: String) -> String?`. Returns `ScreenshotWords.stripParticle(word)` when it differs from `word`, else `nil`. It's used for the second translation pass (step 3), so 사랑을 is retried as 사랑.
   - `public static func lineKey(_ text: String) -> String`. Returns the NFC text, trimmed. It's the cache key for line glosses, so a refetch that renumbers lines still hits.

2. **`LyricsCacheFile`:** add `public var lineGlosses: [String: String]` (machine translation by `lineKey`).
   - New coding key `lineGlosses`. Missing → `[:]`. Always encode it. Add an `init` parameter with the default `[:]`.
   - `LyricsService.fetch` carries `cached?.lineGlosses ?? [:]` into the saved file, the same way it carries `glosses`.
   - `LyricsCacheStore`: replace `mergeGlosses(_:for:)` with `mergeGlosses(words: [String: String], lines: [String: String], for:)`. One load and one save per call. Nothing is written when both dictionaries are empty.

3. **`GlossService`. Batching, fallback and lines:**
   - **State:**
     - `wantedWords[track]` (as today's `wanted`).
     - New `wantedLines[track]: [String]` (unique non-header Korean line texts that contain Hangul, first-seen order).
     - `lineGlosses[track]: [String: String]`.
     - `failed` split into `failedWords` and `failedLines`.
     - The dictionaries the reader reads become **`@ObservationIgnored`** storage. Add one observable `private(set) var revision = 0`, bumped **once per applied chunk** (below). Views never observe the dictionaries directly.
   - **`prepare(document:track:needsLines:)`:**
     - Collect words (as today) and, when `needsLines` is true, lines.
     - Load cached `glosses` and `lineGlosses` in **one** `cache.load`.
     - `needsLines` is false only when the document has Genius English **and** `TranslationAlignment.pairs` succeeds. Then every bubble already has its Genius line and the English page is Genius.
   - **`runBatch(session:track:)`:** keep the availability check, the `prepareTranslation` handling and `translationDeclined` exactly as today. Then do three passes with the same session:
     1. **Words:** `translate(batch:)` over pending words.
     2. **Fallback:** for each word now failed or rejected by `isUsableGloss`, if `fallbackForm` gives a stem, translate the stems in one batch. A usable stem gloss is stored **under the original word's key**.
     3. **Lines:** `translate(batch:)` over pending lines (only if `needsLines`).
   - **Applying results:**
     - Buffer the responses.
     - Apply the buffer to the dictionaries and bump `revision` **every 40 results or every 0.25 s, whichever comes first**, and once at the end of each pass. Use an injected clock, with a default of `ContinuousClock`.
     - Write the cache **once per pass** with `mergeGlosses(words:lines:for:)`, so there are at most 3 writes per song visit. On `CancellationError`, apply and write what is buffered, then return.
     - Whatever is still missing after a pass is marked failed (as today), so no spinner spins forever.
   - **Meanings API (replaces today's `meaning(for:track:)`):**
     ```swift
     enum GlossState: Equatable {
         case deck(VocabEntry, deckTitle: String, matchedForm: String)
         case auto(String)
         case pending
         /// The language pack is missing or was declined.
         case needsLanguagePack
         /// Translated, but no usable single-word meaning; the bubble leans on the line.
         case noWordMeaning
     }
     enum LineGloss: Equatable { case genius(String), auto(String), pending, needsLanguagePack, unavailable }
     func meaning(for token: LyricToken, track: String) -> GlossState      // unchanged lookup order
     func lineMeaning(_ text: String, track: String) -> LineGloss?          // nil when lines weren't requested
     ```
     `.unavailable` (words) is split as shown. Use `.needsLanguagePack` when `translationDeclined` or availability is `.unavailable`, and `.noWordMeaning` otherwise.
   - `retryFailed` and `clearAll` reset the new state too.

4. **`LyricsReaderViewModel`. Precompute everything the token views draw:**
   - Replace `ReaderLine.tokens: [LyricToken]` with `tokens: [ReaderToken]`:
     ```swift
     struct ReaderToken: Identifiable, Equatable {
         let id: Int              // index within the line
         let token: LyricToken
         let text: String
         let isTappable: Bool     // contains a Hangul syllable (O-3); .plain → false
         let isDeckHit: Bool      // WordLookup hit, computed once here
     }
     ```
   - `tokenise()` computes `isDeckHit` with **one** `WordLookup` instance. It runs at load and on catalog change only. If a song has more than 80 lines, do the work in a detached task over a `Sendable` snapshot (`WordLookup` and `LyricLine` are `Sendable`), then assign on the main actor.
   - Remove `isKnown(_:)`. Views use `token.isDeckHit`.
   - `prepareGlosses` passes `needsLines` (step 3). It sets `translation` when **words or lines** are pending, which today checks words only.
   - New `func lineMeaning(for line: ReaderLine) -> LineGloss`:
     - the aligned Genius English line → `.genius`;
     - else `glosses.lineMeaning(line.text)`;
     - else `.unavailable`.
     Cache the Genius alignment **once per load** (`[Int: String]`), not per call.
   - New `var englishPage: EnglishPage` for LA3:
     ```swift
     enum EnglishPage { case genius([LyricLine]), auto([AutoLine]), unavailable(needsLanguagePack: Bool) }
     struct AutoLine: Identifiable { let id: Int; let isHeader: Bool; let korean: String; let english: LineGloss }
     ```
     - `.genius` when the document has English.
     - Otherwise `.auto`, built from the Korean lines: headers pass through, lines without Hangul show as they are (`.auto(text)`), and Hangul lines carry their `LineGloss`.
     - `.unavailable(needsLanguagePack: true)` when the language pack is missing or declined.
   - `footer`: when the English page is `.auto`, the second part is `"Translation: Apple (auto)"`.
   - Anything that reads gloss dictionaries (`lineMeaning`, `englishPage`, the bubble's `meaning`) must read `glosses.revision` first, so observation is wired through that **one** property. `ReaderToken` views must not touch it.

5. **Docs:** PLAN_M6 L-D6 row → "~~…~~ Replaced by R10 O-2 (auto-translated English page, labelled)." Add `lineGlosses` to §4.7. Add line context, `.noWordMeaning` and `.needsLanguagePack` to §4.8.

**Acceptance (for the tester):**
- `GlossText.isUsableGloss`: `("love", "사랑")` → true. `("사랑", "사랑")` → false. `("Saranghae 사랑", "사랑해")` → false (contains Hangul). `("  ", "너")` → false. `("LOVE", "love")` → false (echo, ignoring case).
- `GlossText.fallbackForm("사랑을") == "사랑"`. `fallbackForm("사랑") == nil`.
- `LyricsCacheFile` without `lineGlosses` decodes with `[:]`. It round-trips with the key present.
- `LyricsCacheStore.mergeGlosses(words: [:], lines: [:], for:)` doesn't write (the file's modification date is unchanged).
- With a fake session that returns 150 word results: `revision` is bumped **≤ 6 times** for that pass (not 150), and the cache is written **once** for it.
- `ReaderToken.isTappable` is false for `"ANTIFRAGILE"`, `"(Look"` and `"…"`, and true for `"ANTIFRAGILE이"` and `"사랑해"`.
- A document with aligned Genius English: `needsLines == false`, no line is requested, and `lineMeaning` returns `.genius` for every Hangul line. A document without English: `englishPage` is `.auto`, and every Hangul line is requested once.

---

### LA4 · F4, F5 · "Now playing" refreshes itself (shared monitor)

**Commit:** `R10-LA4: shared now-playing monitor that polls while the Lyrics home is on screen`

**Files:**
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/SpotifyModels.swift`
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/NowPlayingPoll.swift` (**new**)
- `Packages/MemoriseCore/Sources/MemoriseCore/Lyrics/LyricsModels.swift` (`LyricsConstants`)
- `App/Sources/Services/Lyrics/NowPlayingMonitor.swift` (**new**)
- `App/Sources/AppEnvironment.swift` (owns `nowPlaying`; the preview environment too)
- `App/Sources/Features/Lyrics/LyricsHomeViewModel.swift`
- `App/Sources/Features/Lyrics/LyricsHomeView.swift` (**only** the `.task` hook and the VM `init` call in step 5. LA3 owns the rest of this file.)
- `PLAN_M6_LYRICS.md` §4.9 (one line)

**Steps:**
1. **`SpotifyPlayback`:** add `public var progressMs: Int?` (init parameter default `nil`). It's not persisted, so this isn't a wire change. `SpotifyDecoder.playback` reads `progress_ms` from the currently-playing body. Equality for the card (step 3) ignores progress.
2. **Core, `NowPlayingPoll` (new, pure):**
   ```swift
   public enum NowPlayingPoll {
       public enum Last: Sendable { case playing(remainingMs: Int?), pausedOrNothing, failed, rateLimited(retryAfter: Int?) }
       public static func delaySeconds(after last: Last) -> Double
   }
   ```
   - `playing(remainingMs: r)` → `clamp((r ?? ∞) / 1000 + 1, nowPlayingMinPollSeconds, nowPlayingPollSeconds)`, so a song that ends in 4 s is checked at about 5 s.
   - `pausedOrNothing` → `nowPlayingPollSeconds`.
   - `failed` → `nowPlayingErrorPollSeconds`.
   - `rateLimited(retryAfter:)` → `max(retryAfter ?? 60, nowPlayingErrorPollSeconds)`.
   - New `LyricsConstants`: `nowPlayingPollSeconds = 10.0`, `nowPlayingMinPollSeconds = 2.0`, `nowPlayingErrorPollSeconds = 30.0`.
   - `remainingMs = track.durationMs − progressMs`, or `nil` when either is unknown or ≤ 0.
3. **New `NowPlayingMonitor`** (`App/Sources/Services/Lyrics/NowPlayingMonitor.swift`, `@MainActor @Observable`, owned by `AppEnvironment` as `env.nowPlaying`, built from `env.spotify`). The Lyrics home **and** the reader (LA5) both show what Spotify is playing, so the state lives here and not in a view model.
   - `private(set) var state: LyricsLoad<SpotifyPlayback?> = .idle`. This moves the `LyricsLoad` enum's use, not its definition.
   - `@discardableResult func refresh() async -> NowPlayingPoll.Last`:
     - It skips the request and returns `.pausedOrNothing` when a refresh is already in flight (`@ObservationIgnored var inFlight`), so the poll loop, the ↻ button and a post-play refresh never overlap.
     - It assigns `state` **only when the visible state changes**: track id, `isPlaying`, nothing↔something, or failed↔loaded. Progress alone never triggers a re-render.
     - Map `SpotifyError` 429 to `.rateLimited` (use the `Retry-After` value if `SpotifyClient` already surfaces it, otherwise `nil`). Map other errors to `.failed`.
     - Keep today's `generation` guard: a response for an older generation is dropped.
   - `func watch() async`: `while !Task.isCancelled { let last = await refresh(); try? await Task.sleep(for: .seconds(NowPlayingPoll.delaySeconds(after: last))) }`. Exit on cancellation. Only one screen is visible at a time (home root **or** reader), so only one watch loop runs. If two ever overlap during a push animation, `inFlight` keeps it to one request.
   - `func refreshSoon()`: waits 1.5 s, then `refresh()`. It's used after a song is started.
   - `func reset()`: bumps the generation and sets `.idle`.
4. **`LyricsHomeViewModel`:**
   - Delete `nowPlaying`, `refreshNowPlaying()` and their generation handling. Take a `NowPlayingMonitor` in `init` and expose `var nowPlaying: LyricsLoad<SpotifyPlayback?> { monitor.state }`, so `NowPlayingCard` keeps compiling. The ↻ button calls `monitor.refresh()`.
   - `refreshAll()` calls `monitor.refresh()` in place of `refreshNowPlaying()`. `reset()` calls `monitor.reset()`.
   - `open(_:play:)`: when the background `play` returns `.playing`, call `monitor.refreshSoon()`, so the card and the reader strip show the song just started.
   - `previewNowPlaying(_:)` moves to `NowPlayingMonitor` (DEBUG only).
5. **`LyricsHomeView`, the hook only:** on the **root `ScrollView` inside the `NavigationStack`** (not on the stack itself, so a pushed reader or playlist cancels it), add
   ```swift
   .task(id: NowPlayingWatchKey(connected: env.spotify.isConnected, active: scenePhase == .active)) {
       guard env.spotify.isConnected, scenePhase == .active else { return }
       await env.nowPlaying.watch()
   }
   ```
   `NowPlayingWatchKey` is a small `Hashable` struct, internal so LA5 can reuse it.
   - Delete the existing `.onChange(of: scenePhase)` now-playing refresh, because the task restarts and refreshes immediately on `.active`.
   - Keep the `.task(id: isConnected) { refreshAll() }` for the lists.
   - Switching tabs or backgrounding the app makes the root disappear, so polling stops on its own. Pushing the reader stops the home loop, and the reader starts its own (LA5).
   - Update the `LyricsHomeViewModel(spotify:)` call site and the previews.
6. **Docs:** PLAN_M6 §4.9: "Now playing refreshes every 10 s while the Lyrics home or a reader is visible (sooner when the song is about to end), and stops when neither is."

**Acceptance (for the tester):**
- `NowPlayingPoll.delaySeconds`:
  - `.playing(remainingMs: 4_000)` → 5.
  - `.playing(remainingMs: 500)` → 2.
  - `.playing(remainingMs: 120_000)` → 10.
  - `.playing(remainingMs: nil)` → 10.
  - `.pausedOrNothing` → 10.
  - `.failed` → 30.
  - `.rateLimited(retryAfter: 90)` → 90.
  - `.rateLimited(retryAfter: nil)` → 60.
- `SpotifyDecoder.playback` reads `progress_ms`. A body without it gives `progressMs == nil`.
- With a stub client, two `NowPlayingMonitor.refresh()` calls that return the same track with different progress cause **no** change to `state` (observation isn't triggered). A different track id does change it.
- Two overlapping `refresh()` calls send one request.
- After `reset()`, a response from before the reset doesn't fill `state`.
- **On device (owner):** with the Lyrics home open, change the song on another device or in the Spotify app. The card updates within 10 s, and within about 2 s of a song ending on its own. Pause shows "Paused" within 10 s. While another tab is selected, or the app is in the background, Spotify gets no now-playing requests (check with the Xcode network gauge or the Console log).

---

### LA3 · F1, F3 · Reader and home rendering; underline every word; English fallback page

**Agent:** frontend. **Runs after LA2 and LA4.**

**Commit:** `R10-LA3: fast lyrics reader, every Hangul word underlined, line meaning in the bubble, auto English page`

**Files:**
- `App/Sources/Features/Lyrics/KoreanLyricsPage.swift`
- `App/Sources/Features/Lyrics/WordBubble.swift`
- `App/Sources/Features/Lyrics/EnglishLyricsPage.swift`
- `App/Sources/Features/Lyrics/LyricsReaderView.swift`
- `App/Sources/Features/Lyrics/LyricsHomeView.swift`
- `App/Sources/Features/Lyrics/ArtworkView.swift` (**new**, moved out of `LyricsHomeView.swift`)
- `App/Sources/Components/Theme.swift` (`GlassCard` shadow only)

**Steps:**
1. **Token views read nothing observable** (`KoreanLyricsPage`):
   - `ForEach(line.tokens)` uses `ReaderToken.id`. No `Array(enumerated())`.
   - `LyricTokenView` takes a `ReaderToken`. Non-tappable tokens render as today's `.plain` text.
   - Tappable tokens get the underline per **P-5**: `isDeckHit` → `.underline(true, pattern: .dot, color: Theme.pink)`; else `.underline(true, pattern: .dot, color: .secondary)`. Phrases keep their pink pill.
   - The token view must not call `model.meaning`, `model.lineMeaning` or anything on `GlossService` in its `body`. Only the popover **content** may.
   - Keep the per-token `.popover`, but move its state out of the token. The page holds `@State private var selected: SelectedToken?` (line id + token id), and each token binds `isPresented` to `selected == mine`. Delete `@State shown` from the token view.
2. **Bubble** (`WordBubble`):
   - It takes `state: GlossState` and `line: LineGloss`.
   - Under the word meaning, add a divider and a **"Line"** section: the line's English (`.genius` → caption "Translation: Genius"; `.auto` → caption "Auto-translated"; `.pending` → small spinner "Translating line…"; `.needsLanguagePack` → today's language-pack message; `.unavailable` → hide the section).
   - `.noWordMeaning` shows "No single-word meaning: see the line below." in secondary text (never the language-pack message).
   - The bubble's max width goes to 320. The line text wraps (`fixedSize(horizontal: false, vertical: true)`).
   - Previews: add one bubble with a Genius line and one with `.noWordMeaning` + an auto line.
3. **English page** (`EnglishLyricsPage`), switching on `model.englishPage`:
   - `.genius` → today's layout.
   - `.auto(lines)` → a banner at the top, "Auto-translated by Apple: no official translation was found", with identifier `lyrics.english.autoBanner`. Then for each line, the English text in `.title3` with the Korean line under it in `.footnote` secondary. `.pending` lines show a one-line shimmer placeholder. Headers and spacing are as today.
   - `.unavailable(needsLanguagePack:)` → today's "English translation not available". When `needsLanguagePack` is true, add "Download Korean in Settings → Apps → Translate."
4. **Stop the hidden aurora** (`LyricsHomeView`):
   - Root: `.auroraBackground(colors:intensity:running: model.path.isEmpty)`.
   - `PlaylistTracksView`: `running: model.path.last == .playlist(playlist)`.
   - The reader already uses `animated: false`. Leave it.
5. **Cheaper list cards:**
   - `GlassCard` (Theme): move `.shadow(…)` from the content onto the **background shape** (`shape.fill(.regularMaterial).shadow(…)` inside `.background`), so the shadow is drawn from one rounded rectangle, not from every row. This applies app-wide, and the look must stay the same. Compare Home, Stats and Lyrics before and after in light and dark mode.
   - `TrackList`: use `ForEach(tracks.indices, id: \.self)`, or ids `track.spotifyID` when they're unique. Don't allocate `Array(tracks.enumerated())` per body.
6. **Artwork cache** (`ArtworkView.swift`, new):
   - Move `ArtworkView` here, out of `LyricsHomeView.swift`.
   - Back it with a `@MainActor` shared `NSCache<NSURL, UIImage>` (count limit 300).
   - Load through `URLSession.shared` in `.task(id: url)`. Downsample to `size × displayScale` with `UIGraphicsImageRenderer`, or `CGImageSourceCreateThumbnailAtIndex` off the main actor.
   - A cache hit draws synchronously on first render, so it never flashes the placeholder.
   - Same placeholder and clipping as today. Add a `#Preview`.
7. Keep every existing accessibility identifier. New identifiers: `lyrics.bubble.line`, `lyrics.english.autoBanner`.

**Acceptance (for the tester / owner on device):**
- Every token with a Hangul syllable is underlined. Deck words are pink and the rest grey. Latin-only tokens are not underlined and not tappable.
- Tapping any underlined word shows a meaning, or "No single-word meaning", **and** the line's English. "Meaning unavailable. Download Korean…" appears only when the language pack is actually missing.
- A song without a Genius translation shows the auto-translated English page with the banner. A song with Genius shows Genius, as before.
- **Performance (owner, iPhone, Release build, Instruments → SwiftUI template), on a song opened for the first time with the Korean pack installed:**
  - While the translation batch runs, `LyricTokenView` body evaluations total **≤ 2 × the number of tokens**. Today it is about words × tokens.
  - Scrolling the reader during the batch shows no hitches longer than 1 frame in the Hitches track.
  - With the reader open, the Lyrics home `AuroraBackground` timeline doesn't tick.
  - Scrolling a 200-song Liked list back and forth doesn't re-request artwork already seen (network gauge) and shows no placeholder flash.
- Home, Stats, Session Setup and Lyrics cards look the same as before the `GlassCard` change (owner glance, light and dark).

---

### LA5 · F5 · Now playing in the reader

**Agent:** frontend. **Runs after LA3** (same reader file) and needs LA4's `NowPlayingMonitor`.

**Commit:** `R10-LA5: show Spotify now playing in the lyrics reader`

**Files:**
- `App/Sources/Features/Lyrics/LyricsReaderView.swift`
- `App/Sources/Features/Lyrics/ReaderNowPlayingBar.swift` (**new**)
- `App/Sources/Features/Lyrics/LyricsHomeView.swift` (the `navigationDestination` call only)
- `App/Sources/Features/Lyrics/LyricsHomeViewModel.swift` (one method: `showLyrics(for:)`)

**Steps:**
1. **Polling in the reader:** `ReaderContent` gets the same hook as the home root:
   ```swift
   .task(id: NowPlayingWatchKey(connected: env.spotify.isConnected, active: scenePhase == .active)) {
       guard env.spotify.isConnected, scenePhase == .active else { return }
       await env.nowPlaying.watch()
   }
   ```
   Popping or swapping the reader cancels it, and the home root starts its own loop again.
2. **Same song?** Add `func isShowing(_ playback: SpotifyPlayback) -> Bool` on `LyricsReaderViewModel`. It's true when the `spotifyID` is equal, **or** `TrackQuery.sameTitle(track.title, playback.track.title) && TrackQuery.sameArtist(track.primaryArtist, playback.track.primaryArtist)`. The second test covers Spotify's relinked ids, where the same song has another id per market or album.
3. **Header chip (same song):** when `env.nowPlaying.state` holds a playback for the open song, show a small capsule under the artist line, "▶ Playing" (`waveform`) or "⏸ Paused" (`pause.fill`), in `Theme.pink`, with identifier `lyrics.reader.playingChip`. Nothing else changes.
4. **Bottom bar (another song)** (`ReaderNowPlayingBar`, new):
   - It's shown with `.safeAreaInset(edge: .bottom)` on the reader, so it never covers the last lyric line.
   - Layout: a glass capsule card with 16 pt side padding, an `ArtworkView` (LA3's cached one, size 40), "Now playing" or "Paused" caption in pink, the title and artist on one line each (`lineLimit(1)`), and a **Show lyrics** button (Korean gradient capsule, min height 44, identifier `lyrics.reader.showNowPlaying`). Bar identifier: `lyrics.reader.nowPlayingBar`.
   - It appears and disappears with `Theme.spring` and a `.move(edge: .bottom).combined(with: .opacity)` transition. With Reduce Motion on, use opacity only.
   - Hidden when the state is `.idle`, `.loading`, `.failed` or nothing is playing, and when Spotify isn't connected. Never show an error in the reader; the home card already does that.
   - The toast overlay moves up by the bar's height when the bar is visible, so they don't overlap.
5. **Show lyrics:** `LyricsReaderView` takes `onShowLyrics: (TrackInfo) -> Void`.
   - `LyricsHomeViewModel.showLyrics(for track: TrackInfo)` replaces the **last** path element with `.reader(track)` when it's a reader, and otherwise appends it. It never starts playback.
   - The home `navigationDestination` passes `{ model.showLyrics(for: $0) }`. Because the route value changes, SwiftUI builds a fresh `LyricsReaderView` (new `@State` model) for the new song. Back still returns to where the first reader came from (Home or the playlist).
   - Previews pass `{ _ in }`.
6. **Previews:** the bar for another song (playing and paused) and the reader header with the chip. Use `NowPlayingMonitor.previewNowPlaying`.

**Acceptance (for the tester / owner on device):**
- `isShowing`: same id → true. Different id but the same title and artist → true. Different title → false.
- `showLyrics(for:)`: path `[.reader(A)]` → `[.reader(B)]`. Path `[.playlist(P), .reader(A)]` → `[.playlist(P), .reader(B)]`. Path `[]` → `[.reader(B)]`.
- **On device:** open a song that's playing → the header shows "▶ Playing" and there's no bar. Skip to the next song in Spotify → within 10 s (about 2 s at a natural song end) the bar appears with the new song. Tap **Show lyrics** → that song's lyrics replace the reader, playback is untouched, and Back returns to the list. Pause in Spotify → the chip or the bar says "Paused" within 10 s. Leave the reader open with the screen on for 1 minute → it never switches songs by itself. Pop the reader → the home card is up to date.
- No now-playing requests while the app is in the background (network gauge or Console).

---

## 5. Notes for the owner

- The first time an old song is opened after LA1, it's looked up again once (old "not Korean" cache entries are stale). After that it's cached as before.
- The auto-translated English page and the bubble's line meaning use Apple's on-device Translation. Nothing is sent off the phone. The first song may show the system prompt to download Korean, as it does today.
- The decisions O-2, O-3 and P-3 to P-5 are already in PLAN.md §17.
