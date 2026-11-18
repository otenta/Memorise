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
| **G3** | Words and cards that show text sometimes take a while to appear. | Not reproducible from the code alone, so **PA3 measures first** and fixes the main-thread work we can already see: **(a)** `GlossService.catalogDidChange` rebuilds `WordLookup` over every Korean entry (about 3,000) **on the main actor**. `AppEnvironment.reloadCatalog()` calls it after every Add to deck or user-deck edit. **(b)** `reloadCatalog()` empties `cardKeysCache` completely, so the next Home `load()` regenerates the cards of **every** deck on the main actor, derived conjugation decks included, before any tile number can show. Tiles then animate in with `softSpring`, which looks like "loading". **(c)** `WordFlowLayout` (`KoreanHeadline`, on every Korean session card) has no layout cache. Each `sizeThatFits` and `placeSubviews` call re-measures every word and then tries up to 12 scales; each try re-measures `minimumScaleFactor` texts, which is CoreText's slow path. SwiftUI calls these several times per pass, so a long headline can take tens of ms before the card's text shows. | **PA3** |

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
| G3 a b c (+ measurement) | **PA3** | implementor |

---

## 3. Tracker

| Segment | Covers | Agent | Status | Notes |
|---|---|---|---|---|
| PA1 Lyrics lists without a giant blur; static aurora | G1, P-7, P-8 | frontend | ☐ | Independent |
| PA2 Bubble sizes itself correctly and opens where there's room | G2, P-9 | frontend | ☐ | After PA1 (same agent); different files |
| PA3 Measure slow text; move catalog work off the main actor; cache the headline layout | G3 | implementor | ☐ | Independent of PA1/PA2 |
| PA4 Follow-up fixes from the owner's trace | G3 | planner → agent | ☐ | Planned after the owner sends the PA3 trace numbers |

**Order:** PA1 → PA2 (frontend), with PA3 (implementor) in parallel. PA4 is written once the owner reports the trace.

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

### PA3 · G3 · Measure slow text; move catalog work off the main actor; cache the headline layout

**Agent:** implementor.

**Commit:** `R11-PA3: perf signposts, off-main word lookup, keep card-key cache, cached headline layout`

**Files:**
- `App/Sources/Services/Perf.swift` (**new**)
- `App/Sources/AppEnvironment.swift`
- `App/Sources/Services/Lyrics/GlossService.swift`
- `App/Sources/Features/Lyrics/LyricsReaderViewModel.swift` (signposts only)
- `App/Sources/Features/Home/HomeView.swift` (signposts only, in `load()`)
- `App/Sources/Features/Session/SessionViewModel.swift` (signposts only)
- `App/Sources/Components/KoreanHeadline.swift` (`WordFlowLayout` only)

**Steps:**
1. **Signposts** (`Perf.swift`):
   - `enum Perf { static let signposter = OSSignposter(subsystem: <app bundle id>, category: "perf") }`, plus a helper `Perf.interval(_ name: StaticString, _ body: () throws -> T) rethrows -> T` and an `async` twin.
   - They're on in Release too (signposts cost almost nothing when not recorded).
   - Intervals:
     - `catalog.assemble` (in `reloadCatalog`)
     - `gloss.lookupBuild`
     - `home.load`, split into `home.stats` and `home.cardKeys`
     - `reader.cache`, `reader.network`, `reader.lines`, `reader.glossPrepare`
     - `session.nextPrompt` (from the grade to the next prompt state)
   - Add one `Perf.signposter.emitEvent("headline.layout")` per `WordFlowLayout.place` call.
2. **`WordLookup` off the main actor:**
   - `GlossService.catalogDidChange(_:)` captures `catalog.vocabDecks` (`[VocabDeck]`; confirm it's `Sendable`, and if it isn't, capture the decks' entries and titles as a `Sendable` snapshot). It builds `WordLookup(decks:)` in `Task.detached(priority: .userInitiated)`, then assigns `lookup` on the main actor.
   - A generation counter makes sure an older build never overwrites a newer one.
   - After the swap, post the existing `dataVersion` change (or call a new `onLookupChanged` closure) so an open reader re-tokenises with the new lookup. The reader already re-tokenises on `env.dataVersion`, so make sure that bump happens **after** the swap, not before.
   - `init` keeps the synchronous build (launch path, already measured as part of `catalog.assemble`).
3. **Keep the card-key cache:** `reloadCatalog()` no longer empties `cardKeysCache`. It removes only the entries for decks whose cards can change:
   - every user deck id;
   - every derived deck whose sources include a user deck. Check `DeckCatalog.assemble`: if derived decks are built from bundled decks only, this set is empty.

   Write the rule as a short comment that names the function the decision depends on.
4. **`WordFlowLayout` cache:**
   - Use `Layout`'s `Cache` with `ideal: [CGSize]` (computed in `makeCache` and refreshed in `updateCache`) and `placements: [CGFloat: Placement]`, the last few widths, keyed by width rounded to 0.5 pt.
   - `sizeThatFits` and `placeSubviews` reuse a cached placement for the same width.
   - Replace the linear 5 % scale walk with a **binary search** over `[0.4, 1]` to a 0.025 resolution (≤ 5 `flow` calls), taking the largest scale that fits `maxLines`. The result must equal the linear walk's within one 0.05 step. Check by eye on the existing "Korean headlines" preview.
5. **Docs:** add the interval names to README "Debugging performance" (one short list), so the owner can find them in Instruments under *os_signpost*, category `perf`.

**Acceptance:**
- Tester:
  - `WordFlowLayout` returns the same lines for the preview samples at widths 280, 320 and 390 as before the change (snapshot the line arrays through a small test-only helper if needed).
  - After `catalogDidChange`, `GlossService.wordLookup` contains a word added to a user deck, and an older detached build finishing late doesn't replace a newer one.
  - `reloadCatalog()` keeps the cached keys of a bundled deck (the same array instance or count, with no regeneration).
- Owner on device:
  - After saving a word from the reader, the reader and Home stay responsive. No freeze is visible.
  - The headline of a long Korean prompt (e.g. "새해 복 많이 받으세요") appears with the card, with no visible delay.
- **Owner trace for PA4:** one Instruments recording (template *Time Profiler*, plus the *os_signpost* and *Hitches* instruments) covering:
  1. open the app → Home;
  2. start a Korean session and answer 5 cards;
  3. finish → Home;
  4. Lyrics → open a song → add a word.

  Send the planner the durations of the `perf` intervals, or the trace file. Every interval > 100 ms becomes a PA4 fix.

---

### PA4 · G3 · Follow-up fixes from the trace

Planned after the owner sends PA3's trace. Placeholder only, nothing to implement yet.

---

## 5. Notes for the owner

- PA1 and PA2 are the direct fixes for the laggy picker and the clipped bubbles.
- For "text takes a while", PA3 removes the main-thread work visible in the code, but the exact screen wasn't certain. If you meant one specific place (Home tiles, session cards, the lyrics words, or the song rows), say which. The signposts will also show it in a trace.
