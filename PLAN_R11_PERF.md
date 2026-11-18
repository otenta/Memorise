# Memorise — Round 11 Plan: Lyrics tab speed, bubble layout, slow text

- **Date:** 2026-11-18
- **Source:** the owner's device findings after R10 (§1). R10 (`PLAN_R10_LYRICS.md`) is fully landed (LA1–LA5).
- **Owner of this file:** the planner. The frontend and implementor agents run the segments in §4 and tick the tracker (§3).
- **Conventions:** `CLAUDE.md` and PLAN.md §16 apply.
  - Domain logic stays in `MemoriseCore`. Inject clocks.
  - Never hand-edit the `.xcodeproj`. Record every deviation in PLAN.md §17.
  - **No wire changes in this plan.**
- **Commits:** one segment = one commit, with the message given in the segment. Stage **only** the files that segment touches. Other agents leave files uncommitted in the same tree. Right now the QA agent's test files, `App/Tests/`, `project.yml`, `docs/TEST_COVERAGE.md` and `.github/workflows/core-tests.yml` are uncommitted: **never stage them.**
- **Tests:** none in this plan; the tester owns tests. Acceptance criteria are for the tester and the owner.

---

## 1. Findings and root causes

| ID | Owner finding | Root cause (from the code at `bb9891f`) | Segment |
|---|---|---|---|
| **G1** | The Lyrics tab (the song picker, not the reader) is extremely laggy. | **(a) One huge live blur.** `TrackList` and `PlaylistList` are a nested `LazyVStack` wrapped in **one** `.glassCard`. Its `.regularMaterial` background, gradient `strokeBorder` and shadow are sized to the **whole list**: 50 rows (Recent) is about 3,000 pt, and Liked after a few "load more" pages is 10,000–30,000 pt. A material is a live backdrop blur, so the GPU re-samples and re-blurs that whole layer every frame the content behind it changes. **(b) It changes every frame.** The tab's `AuroraBackground` animates at 30 fps whenever the list isn't being scrolled, and scrolling moves the blurred layer across it. So the blur work never stops, even while the screen is idle. The rest of the app uses glass cards only on small, fixed-size tiles, which is why only this tab feels slow. **(c)** `LoadingRows` runs a `repeatForever` opacity pulse on a material card (same cost while lists load). | **PA1** |
| **G2** | Some translation bubbles are cramped and the top is almost cut off. | **(a) Wrong size measured.** The popover sizes itself to the bubble's *ideal* size. The bubble is `.frame(minWidth: 220, maxWidth: 320)`, and most of its `Text`s have no vertical `fixedSize`. Their ideal size is therefore measured as **one line**, the width is then clamped to 320, the text needs 2–3 lines, and the popover height is too small. The content is squeezed, and because the stack is centred the top is clipped. **(b) It grows after it opens.** The meaning and the line arrive after the bubble is shown (`.pending` → text), and a presented popover doesn't reliably grow. **(c) Fixed arrow direction.** `arrowEdge: .bottom` always puts the bubble *above* the word. For words near the top of the screen there's no room, so iOS shrinks it further. | **PA2** |
| **G3** | **Session cards:** the Korean words take a while to appear (owner confirmed the screen, 2026-11-18). | It happens on Korean cards and not music ones, because only Korean cards speak. All the speech and audio work runs **synchronously on the main actor**, right when a card should render. **(a) Every grade blocks.** `SessionViewModel.grade` calls `env.speech.stop()` → `AVSpeechSynthesizer.stopSpeaking(at: .immediate)`. The pronunciation that auto-played on reveal is usually still speaking, and an immediate stop blocks the calling thread while the speech engine tears down (often 50–300 ms). Only then is the next prompt rendered. **(b) Every reveal does speech work before the answer card's frame.** `reveal` calls `ui.onReveal` → `speech.speak`, which on the main thread runs `audio.ensurePlayback()` (`AVAudioSession.setCategory` and `setActive`, which block, on the first reveal) and `synthesizer.speak`. The first utterance loads the Korean voice synchronously, a long stall on the first card. **(c) `syncState`** calls `speech.stop()` again before arming the mic (R9-SF5). That's harmless for Korean (no mic), but it's the same blocking call. **(d) Layout cost:** `WordFlowLayout` (`KoreanHeadline`, on every Korean prompt and answer) has no layout cache. It re-measures every word, and up to 12 scale steps of `minimumScaleFactor` text, on each of SwiftUI's several sizing passes. The answer puts it in an `HStack` next to the speaker button, which adds more probing passes. **Quick owner check that confirms (a)/(b):** turn **Auto-play pronunciation** off in the deck's session setup. If the cards become instant, speech is the cause. | **PA3** (session), **PA4** (other main-thread work) |

### Decisions

| ID | Decision | By | Status |
|---|---|---|---|
| **P-7** | Long scrolling lists (Lyrics songs and playlists) use **no material blur and no shadow**. Each row draws its own segment of a rounded card on an opaque surface colour, so the look stays a single card. Glass (material) stays on the small fixed cards (Now playing, search field, messages). | planner | decided |
| **P-8** | The Lyrics home and the playlist screen use a **static** aurora (`animated: false`), as the reader and sessions already do. A moving background behind a long list costs a frame budget the list needs. | planner | decided |
| **P-9** | A word bubble opens **below** the word when the word was tapped in the top 45 % of the window, and above it otherwise. Its width is fixed at 300 pt, and it never resizes after it opens: pending states reserve the space of their final text. | planner | decided |

---

## 2. Coverage map

| Finding | Segment | Agent |
|---|---|---|
| G1 a b c | **PA1** | frontend |
| G2 a b c | **PA2** | frontend |
| G3 a–d (session cards) | **PA3** | implementor |
| Other main-thread catalog work | **PA4** | implementor |

---

## 3. Tracker

| Segment | Covers | Agent | Status | Notes |
|---|---|---|---|---|
| PA1 Lyrics lists without a giant blur; static aurora | G1, P-7, P-8 | frontend | ☑ | Independent |
| PA2 Bubble sizes itself correctly and opens where there's room | G2, P-9 | frontend | ☑ | After PA1 (same agent); different files |
| PA3 Session cards: speech and audio off the main thread; cached headline layout; signposts | G3 a–d | implementor | ☑ | Independent of PA1/PA2. **Do this first:** it's the owner's main complaint. |
| PA4 Catalog work off the main actor | G3 (related) | implementor | ☑ | After PA3. Lower priority: stalls after Add to deck or editing a deck. |

**Order:** PA3 → PA4 (implementor), in parallel with PA1 → PA2 (frontend).

---

## 4. Segments

### PA1 · G1 · Lyrics lists without a giant blur; static aurora

**Agent:** frontend.

**Commit:** `R11-PA1: Lyrics lists draw per-row cards without material; static aurora`

**Files:**
- `App/Sources/Features/Lyrics/LyricsHomeView.swift`
- `App/Sources/Components/Theme.swift` (new `ListCardRow` modifier and one surface colour)

**Steps:**
1. **`Theme`:**
   - Add `static let listSurface = Color(uiColor: .secondarySystemBackground).opacity(0.92)` and a stroke colour matching `GlassCard`'s light/dark edge (one flat colour, no gradient).
   - Add a `ListCardRow` view modifier, `func listCardRow(position: ListRowPosition, radius: CGFloat = Theme.smallRadius)`, with `enum ListRowPosition { case only, first, middle, last }`.
     - It draws its background as an `UnevenRoundedRectangle`, with the corners rounded only on the card's outer edges, filled with `listSurface`.
     - It adds a 1 pt hairline on the outer edges only, so the stacked rows read as one card.
     - **No material and no shadow.**
     - `func listRowPosition(index: Int, count: Int) -> ListRowPosition` is a static helper.
2. **Flatten the lists.** `TrackList`, `PlaylistList` and the songs of `PlaylistTracksView` no longer wrap a nested `LazyVStack` in `.glassCard`.
   - Each list is a plain `LazyVStack(spacing: 0)` with **no background, overlay, shadow or clip on the stack itself**. It sits inside the screen's outer `LazyVStack(spacing: 16)` as before. The requirement is that **no single view's background, material or shadow spans the whole list**; only rows draw.
   - Each row applies `.listCardRow(position:)`. The divider moves inside the row: a bottom hairline, inset by 68, on every position except `.last` and `.only`.
   - `TrackList` keeps `ForEach(tracks.indices, id: \.self)`.
   - `PlaylistList` uses `ForEach(playlists.indices, id: \.self)` instead of `Array(enumerated())`.
3. **`LoadingRows`:** same per-row surfaces (5 placeholder rows using `listCardRow`). The pulse animates only the placeholder shapes' opacity, not a material card.
4. **Aurora (P-8):** the Lyrics home root and `PlaylistTracksView` pass `animated: false`. Delete the `running:` arguments added in R10 LA3, which are no longer needed.
5. Keep every accessibility identifier and the `PressableStyle` on rows. `NowPlayingCard`, `SearchField`, `MessageCard`, `NoticeBanner` and the connect cards keep `.glassCard` (small, fixed size).
6. Previews: the rows preview shows 1 row, 3 rows and the loading rows, in light and dark mode.

**Acceptance (owner on device, Release build):**
- Liked list loaded to ≥ 200 songs: fling scrolling up and down shows no visible stutter. In Instruments (Animation Hitches), there are no hitches > 1 frame during a 10 s fling test.
- With the tab idle and nothing scrolling, the GPU is near idle: Xcode's debug gauge **GPU** shows < 10 % (today it stays busy because of the animated aurora under a blurred list).
- The list still looks like one rounded card with dividers, in light and dark mode.

---

### PA2 · G2 · Bubble sizes itself correctly and opens where there's room

**Agent:** frontend. **After PA1.**

**Commit:** `R11-PA2: word bubble measures its full height, reserves space, opens on the roomy side`

**Files:**
- `App/Sources/Features/Lyrics/WordBubble.swift`
- `App/Sources/Features/Lyrics/KoreanLyricsPage.swift`

**Steps:**
1. **A fixed width and the full height** (`WordBubble`):
   - Replace `.frame(minWidth: 220, maxWidth: 320, alignment: .leading)` with `.frame(width: 300, alignment: .leading)`, then apply `.fixedSize(horizontal: false, vertical: true)` to the whole bubble. Its ideal height is then measured at 300 pt with every line wrapped.
   - Every `Text` that can wrap gets `.fixedSize(horizontal: false, vertical: true)` and no `lineLimit`. That covers the meaning, the deck meaning, "In: …", the language-pack message, "No single-word meaning…" and the line text.
   - The word headline uses `.lineLimit(2)` with `.minimumScaleFactor(0.7)` for long phrases.
2. **No growth after opening (P-9):**
   - `.pending` (word) renders a **placeholder of the same shape as the result**: one `Text("Translating this word")` with `.redacted(reason: .placeholder)`, plus its caption line.
   - `.pending` (line) renders two redacted lines plus a caption.
   - The real text replaces the placeholder in place, with `.animation(.easeOut(duration: 0.15), value: state)`. A meaning longer than the placeholder may still grow the bubble by a line. That's acceptable, because the popover then has the correct ideal size.
3. **Open on the side with room** (`KoreanLyricsPage`):
   - The token's `Button` gets `.simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { … })`. It records the tap's `y` in the page state (`@State private var tapY: CGFloat`) before the button action sets `selected`.
   - The window height comes from a single `GeometryReader` or `onGeometryChange` on the **page** (not per token).
   - `SelectedToken` gains `edge: Edge`: `.top` (popover arrow on top, bubble **below** the word) when `tapY < 0.45 × pageHeight`, otherwise `.bottom`.
   - `.popover(isPresented:attachmentAnchor:arrowEdge:)` uses `selected.edge` for the selected token. Other tokens pass `.bottom`; their popover isn't presented, so the value doesn't matter.
   - If the spatial gesture didn't fire (VoiceOver activation), use `.bottom`.
4. Previews: a long deck meaning (3 lines) with a long Genius line, a pending word with a pending line, and `.noWordMeaning` with an auto line, all at the default size and at Dynamic Type XL.

**Acceptance (owner on device):**
- Tap a word in the **first** visible lyric line and in the **last** visible line: both bubbles are fully visible, nothing is clipped, and the first opens below the word.
- A word whose deck meaning and line wrap to 3+ lines each shows every line in full, at the default text size and at Larger Text XL.
- Opening a word whose translation is still pending: when the meaning arrives, the text replaces the grey placeholder without the bubble jumping or the top being cut off.

---

### PA3 · G3 · Session cards: speech and audio off the main thread; cached headline layout

**Agent:** implementor.

**Commit:** `R11-PA3: speech and audio session off the main thread, cached headline layout, perf signposts`

**Files:**
- `App/Sources/Services/SpeechService.swift`
- `App/Sources/Services/AudioSessionCoordinator.swift` (wherever `AudioSessionCoordinator` lives)
- `App/Sources/Features/Session/SessionViewModel.swift`
- `App/Sources/Features/Session/SessionView.swift` (session start hook only)
- `App/Sources/Components/KoreanHeadline.swift` (`WordFlowLayout` only)
- `App/Sources/Services/Perf.swift` (**new**)
- README "Debugging performance" (short list)

**Steps:**
1. **`SpeechService`: the main actor only enqueues.**
   - Keep the class's public API (`speak`, `speakEnglish`, `stop`, `hasKoreanVoice`, `refreshVoices`) so no call site changes, except the one in step 4.
   - Move the `AVSpeechSynthesizer` and every call on it (`speak`, `stopSpeaking`, `isSpeaking`) onto **one private serial `DispatchQueue`** (`qos: .userInitiated`), owned by a small `nonisolated final class SpeechEngine: @unchecked Sendable` that also is the delegate.
   - The `@MainActor` facade:
     - creates the `AVSpeechUtterance` on the main actor (cheap);
     - records `pending` (the utterance plus `onFinish`) as today;
     - `queue.async`'s the work and returns at once.
   - Ordering is kept, because one serial queue runs every speak and stop in call order.
   - Delegate callbacks (`didFinish` / `didCancel`) hop to the main actor as today. `finishPending` semantics are unchanged: `onFinish` runs on finish, on cancellation by a later `speak`/`stop`, or immediately with no voice.
   - Use `stopSpeaking(at: .immediate)` on the queue as today.
   - The voice objects (`AVSpeechSynthesisVoice`) are looked up once (as today), and `refreshVoices()` stays on the main actor.
2. **Audio session activation off the main thread:** `AudioSessionCoordinator.ensurePlayback()` does `setCategory` and `setActive` on its own serial queue. Keep `mode` bookkeeping on the main actor, set optimistically before dispatch, and log failures as today.
   - **Mic paths keep their order:** `beginRecording()` stays synchronous and `throws`, because the mic must know the session is ready. It must run after any queued playback activation, so it does `queue.sync` (it's called at session start, not per card).
   - `deactivate()` dispatches to the same queue.
3. **Warm up at session start** (`SessionView` `.task` at start, or `SessionViewModel.start`): when the deck is Korean **and** a Korean voice exists, call a new `speech.prewarm()`. It does `ensurePlayback()`, then on the speech queue speaks a single-space utterance with `volume = 0`, so the voice is loaded before the first reveal. It must not show up as speech or delay the first prompt. Run it after the first prompt is on screen, using `Task { await Task.yield(); … }`.
4. **Mic arming waits without blocking** (keeps R9-SF5):
   - Add `func stopAndWait() async` to `SpeechService`. It enqueues the stop and resumes when the queue has run it (a `CheckedContinuation` resumed from the queue).
   - In `syncState`, the `.prompting` + mic branch becomes `Task { await env.speech.stopAndWait(); guard <still prompting the same presentationID> else { return }; mic.setListening(true) }`. The stale-presentation guard is needed because the state may have moved on during the await.
   - All other `stop()` calls (grade, quit, pause) stay fire-and-forget.
5. **`WordFlowLayout` cache:**
   - Use `Layout`'s `Cache` with `ideal: [CGSize]` (computed in `makeCache` and refreshed in `updateCache`) and `placements: [CGFloat: Placement]`, the last few widths, keyed by width rounded to 0.5 pt.
   - `sizeThatFits` and `placeSubviews` reuse a cached placement for the same width.
   - A proposal width ≤ 1 (an `HStack` probing with 0) returns the single-line ideal at once, **without** running the scale search.
   - Replace the linear 5 % scale walk with a **binary search** over `[0.4, 1]` to a 0.025 resolution (≤ 5 `flow` calls), taking the largest scale that fits `maxLines`. The lines must match the old walk's within one 0.05 step. Check by eye on the "Korean headlines" preview.
6. **Signposts** (`Perf.swift`):
   - `enum Perf { static let signposter = OSSignposter(subsystem: <bundle id>, category: "perf") }`, with `interval` helpers (sync and async). They're on in Release.
   - Intervals:
     - `session.reveal`: from `ok()`/`choose`/`submitTyped` until `syncState` returns, plus a `.task` in the revealed view that ends a `session.revealVisible` interval;
     - `session.nextPrompt`: from `grade` until the next prompt's `.task(id: presentationID)` runs;
     - `speech.speak`, `speech.stop` (on the queue);
     - `audio.activate`.
   - One `emitEvent("headline.layout")` per placement computed (not per cache hit).
   - README: list the names, and where to find them in Instruments (*os_signpost*, category `perf`).

**Acceptance:**
- Tester:
  - `SpeechService` with a stub engine: `speak` then `stop` from the main actor return without waiting on the engine. `onFinish` is called exactly once for a speak that's cancelled by `stop`, by a later `speak`, or that finishes normally. With no voice it's called immediately.
  - `stopAndWait` resumes after the queued stop has run.
  - `WordFlowLayout`: the same line arrays as before for the preview samples at widths 280, 320 and 390. Width 0 returns a single line without searching.
- Owner on device (Release build, **Auto-play pronunciation on**):
  - Korean vocab session: tap **Reveal**, and the answer card with the Korean headline flips in immediately, even on the first card.
  - Grade while the pronunciation is still speaking: the next Korean word appears immediately and the speech cuts off.
  - In Instruments, `session.revealVisible` and `session.nextPrompt` are < 50 ms, and Xcode reports no hangs.
  - Music mic decks: a spoken "Correct" is still never heard as the next answer (R9-SF5 is unchanged).

---

### PA4 · G3 (related) · Catalog work off the main actor

**Agent:** implementor. **After PA3** (it reuses `Perf`).

**Commit:** `R11-PA4: build the word lookup off the main actor, keep the card-key cache`

**Files:**
- `App/Sources/AppEnvironment.swift`
- `App/Sources/Services/Lyrics/GlossService.swift`

**Steps:**
1. **`WordLookup` off the main actor:**
   - `GlossService.catalogDidChange(_:)` captures `catalog.vocabDecks` (`[VocabDeck]`; confirm it's `Sendable`, and if it isn't, capture a `Sendable` snapshot of entries and titles). It builds `WordLookup(decks:)` in `Task.detached(priority: .userInitiated)`, then assigns `lookup` on the main actor.
   - A generation counter makes sure an older build never overwrites a newer one.
   - Bump `env.dataVersion` (or call an `onLookupChanged` closure) **after** the swap, so an open reader re-tokenises with the new lookup.
   - `init` keeps the synchronous build.
   - Signpost: `gloss.lookupBuild`.
2. **Keep the card-key cache:** `reloadCatalog()` no longer empties `cardKeysCache`. It removes only:
   - user deck ids;
   - derived decks whose sources include a user deck. Check `DeckCatalog.assemble`: if derived decks use bundled decks only, this set is empty.

   Write the rule as a comment naming the function it depends on. Signposts: `catalog.assemble`, `home.load`.

**Acceptance:**
- Tester:
  - After `catalogDidChange`, `wordLookup` finds a word just added to a user deck.
  - A late, older build doesn't replace a newer one.
  - `reloadCatalog()` keeps a bundled deck's cached keys.
- Owner: saving a word from the reader, or editing a user deck, causes no visible freeze. Home deck numbers appear without a delay after a session.

---

## 5. Notes for the owner

- PA1 and PA2 are the direct fixes for the laggy picker and the clipped bubbles.
- PA3 is the fix for slow Korean session cards. Before it lands, you can confirm the cause: turn **Auto-play pronunciation** off in the deck's session setup. If the cards become instant, it's the speech work blocking the screen.
- If session cards are still slow after PA3, send an Instruments trace with the `perf` signposts (README "Debugging performance"), and the planner will add a follow-up.
