# Memorise — Round 8 Plan: coverage-first sessions, a coverage ring, and a bigger K-pop / K-drama deck

- **Date:** 2026-11-17
- **Source:** the owner's request on 2026-11-17 (quoted in §1).
- **Owner of this file:** the planner. The implementor, frontend and content agents run the segments in §3 and tick the tracker (§2).
- **Builds on:** PLAN_R7_FIXES F1. F1 stopped repeats **within** one session. This round deals with what happens **between** sessions.
- **Conventions:** `CLAUDE.md` and PLAN.md §16 apply.
  - Domain logic stays in `MemoriseCore`, which imports only Foundation. Inject the RNG and clocks. Hash with FNV-1a, never `hashValue`.
  - **No `Codable` wire change in this round.** Everything new is derived from data that is already stored (`ItemStats`, `SessionRecord`).
  - Never change or reuse an entry `id`, `rank` or `ItemKey`.
  - Scheduling constants live in `SchedulerConstants`. Update PLAN.md §10 when you add or tune one.
  - Never hand-edit the `.xcodeproj`.
  - Record every deviation in PLAN.md §17.
- **Commits:** one segment = one commit, with the message given in the segment. Stage **only** the files that segment touches, because other agents leave files uncommitted in the same tree.
- **Tests:** none in this plan. The tester agent owns tests. Each segment lists acceptance criteria and reference scenarios for the tester to turn into tests.

---

## 1. What the owner asked for, and why it happens today

| # | Owner request (paraphrased) | Today's behaviour (verified in code) | Segment | Agent |
|---|---|---|---|---|
| 1 | "When I pick Korean Core 1, I want to see X cards with no duplicates." | Fixed within a session by R7-F1. This round keeps that behaviour. | S1 | implementor |
| 2 | "If I continue, the next session should not show the cards from the first session. I want to work through the whole of Core 1." | `IntroductionPolicy` lets in only `newPerSession` (10) new ranks. Every seen card stays eligible, and `WeightCalculator.baseWeight` gives it a weight. So in session 2, about half of the 20 slots go back to session-1 words, including words answered correctly. | **S1** | implementor (core) |
| 3 | "Cards I got wrong should come back after a while, in a random later session, not in the very next one." | A wrong card gets the highest weight (`ewmaError`), so it is **most** likely to show up in the very next session. | **S1** | implementor (core) |
| 4 | "After a session, the tile shows 100 %. It should show **coverage**: 20 correct out of 100 cards means 20 %." | `DeckTile` and `DeckCard` draw `DeckRowInfo.accuracy` (lifetime correct ÷ attempts) in the ring. One perfect session gives 100 %. | **S2** (data), **F1** (UI) | implementor (app), frontend |
| 5 | "The K-pop & K-drama deck needs many more phrases: chorus phrases from songs, and everyday phrases from K-dramas." | `ko_media.json` has 169 entries. 95 song references, 15 drama/show references, 80 entries without a source. | **C1** (K-pop), **C2** (K-drama) | content agent |

**Order and parallelism:**
1. **S1** first (core). **S2** runs after S1, because both wire `SessionViewModel.start()`.
2. **F1** runs after S2, because it uses S2's `DeckRowInfo.coverage`. F1's "hide the new-per-session stepper" part can start at any time.
3. **C1** and **C2** are independent of the code. They both append to `ko_media.json`, so run them **one after the other** (C1, then C2) to keep ids and ranks consecutive.

## 2. Tracker

| Segment | Covers | Status | Notes |
|---|---|---|---|
| S1 Coverage-first session composer | #1, #2, #3 | ☐ | Core. New `SessionComposer`, `DeckHistory`. Update PLAN.md §10.5 and §10.6. |
| S2 Coverage numbers and session history wiring | #4 (data), #2/#3 (app wiring) | ☐ | App. Store extension, VM wiring and `DeckRowInfo.coverage`. |
| F1 Coverage ring on Home | #4 (UI) | ☐ | Frontend. Also hides the "New per session" steppers (D2). |
| C1 K-pop chorus phrases (+120) | #5 | ☐ | Content agent. Verified sources only. |
| C2 K-drama everyday phrases (+100) | #5 | ☐ | Content agent, after C1. |

---

## 3. Segments

### S1 · #1 #2 #3 · Coverage-first session composer (implementor, core)

**Commit:** `R8-S1: coverage-first sessions; wrong cards return 2-4 sessions later`

**Files:**
- new `Packages/MemoriseCore/Sources/MemoriseCore/Scheduling/SessionComposer.swift`
- new `Scheduling/DeckHistory.swift` (or put it in the same file)
- `Scheduling/Scheduler.swift`
- `Scheduling/SchedulerConstants.swift`
- `Session/SessionEngine.swift`
- `PLAN.md` §10.5, §10.6 and §17

**Scope:** only decks that have introduction ranks, meaning `deck.introductionRank(of:)` is non-nil for the pool. That covers every Korean vocab deck and the derived decks (Conjugation, Particles, Hangul Reading). Music decks have no ranks and keep today's adaptive weighting unchanged.

**Target behaviour, in plain words:**
1. A session works through the deck **in order of new material**. Session 1 shows ranks 1–20, session 2 shows ranks 21–40, and so on. A word answered **correctly** is not shown again until every card in the deck has been covered.
2. A word answered **wrongly** waits a random **2, 3 or 4 sessions** of that deck, then comes back mixed in at a random position. It never comes back in the very next session.
3. Returning wrong words take at most **30 %** of a session's slots. The rest is new material, so coverage keeps moving forward.
4. When there is no new material left (the deck is 100 % covered), sessions fill up with wrong words first, then review the correctly answered words, **least recently seen first**.
5. Within a session, R7-F1 still applies: no repeats until the session's cards are used up, and retries (`retryWrongCards`) still come back 3–5 cards later.

**Definitions (put them in doc comments):**
- **Entry:** all pool cards that share one `introductionRank`. For vocab, these are the ko→en and en→ko cards of one word.
- **Card state**, from its `ItemStats`:
  - `new`: `attempts == 0` (or no stats row);
  - `wrong`: `attempts > 0` and the **last counted answer was wrong**, i.e. `lastWrongAt != nil && lastWrongAt == lastSeenAt`. `StatsUpdater.apply` sets both from the same `now`, so they are equal exactly when the last answer was wrong. In-session retries are not counted, so a word missed and then retried correctly stays `wrong`. That is what the owner wants.
  - `correct`: `attempts > 0` and not `wrong`.
- **Entry state:**
  - `wrong` if any of its cards is `wrong`;
  - `fresh` if all of its cards are `new`;
  - `partial` if some cards are `new` and the rest are `correct` (e.g. the ko→en direction is done but en→ko has never been shown);
  - `covered` if all of its cards are `correct`.
- **Sessions since a miss:** the number of **completed** sessions of this deck whose `startedAt` is after the card's `lastWrongAt`. The session in which the card was missed started *before* the miss, so it does not count. Discarded sessions (R7-F2) leave no record, and killed sessions are not `.completed`, so neither counts.
- **Wrong-card gap:** `gap = constants.wrongGapSessions.lowerBound + fnv1a("\(itemKey.raw)|\(lastWrongAt.timeIntervalSince1970)") % width`, giving 2, 3 or 4 by default. The gap is random per miss but **stable across launches**, so it needs no stored state. A `wrong` card is **due** when `sessionsSinceMiss >= gap - 1`. Example: missed in session 5 with gap 2 → not in session 6 → eligible from session 7.

**Steps:**
1. **`SchedulerConstants`:** add
   - `wrongGapSessions: ClosedRange<Int> = 2...4`;
   - `reviewShare = 0.3`, the maximum fraction of a session's entries that are returning wrong words while new material remains.

   Document both in PLAN.md §10.
2. **`DeckHistory`** (new, `Sendable`, `Hashable`): `completedSessionStarts: [Date]`, sorted ascending, with `static let empty`. Add a helper `sessionsSince(_ date: Date) -> Int` that uses binary search.
3. **`SessionComposer`** (new, pure): a function
   `static func queue(pool: [Card], stats: [ItemKey: ItemStats], deck: any Deck, history: DeckHistory, targetEntries: Int, constants: SchedulerConstants, rng: inout SplitMix64) -> [[ItemKey]]?`
   - It returns `nil` when the pool has no ranks (music decks). The engine then uses today's path unchanged.
   - Otherwise it returns an **ordered queue of entries**. Each element is the keys of the cards of that entry that may be shown this session, best first. The engine uses the first `targetEntries` and draws more from the queue only when it needs a top-up (step 5).
   - **Card choice inside an entry:** one card per entry per session (F1's sibling rule).
     - For a `wrong` entry, use its wrong card(s).
     - For a `partial` entry, use its `new` card(s).
     - For a `fresh` entry, use one direction, picked with `rng`. When the deck has a single direction, use that card.
     - For a `covered` entry, use the card with the oldest `lastSeenAt`.
   - **Queue order:**
     1. `reviewSlots = floor(targetEntries × reviewShare)`. Take up to `reviewSlots` **due** `wrong` entries, chosen at random with `rng` (a shuffle, then take the first ones). This is the "random later session" behaviour.
     2. `fresh` entries in **rank order**. Keep R7-F7's derived-deck interleave, because it lives in `introductionRank`.
     3. `partial` entries in rank order. They come after fresh ones, so a word's second direction isn't shown in the session straight after its first.
     4. The remaining **due** `wrong` entries (shuffled).
     5. `wrong` entries that are **not due yet**, soonest-due first. These are reached only when everything above is used up (a tiny or fully covered deck).
     6. `covered` entries, oldest `lastSeenAt` first (the review pass).
   - The **slots** are then shuffled into session order by the scheduler's weighted pick (step 4), so returning wrong words appear at random positions, not as a block at the start.
   - `newPerSession` is **no longer used** as a cap for ranked decks (owner decision D2). Leave the option in the wire format. `IntroductionPolicy` stays in the code for API compatibility and is no longer called by the engine for ranked decks; mark it "unused since R8-S1" in its doc comment.
4. **`Scheduler`:** add an init parameter `allowed: Set<ItemKey>?` (default `nil`). When it is non-nil, a card is selectable **iff** its key is in `allowed`, and that replaces the `eligibleNew`/seen test. The tiers, cooldown, `blocked`/`resting` handling and fallback are unchanged. The engine re-creates the allowed set when it tops up, so make `allowed` a `var` set through a `mutating func extendAllowed(_ keys:)`. Alternatively, pass it into `select` per call; choose whichever is simpler, and note the choice in §17.
5. **`SessionEngine`:**
   - New init parameter `history: DeckHistory = .empty`. Callers that don't pass it keep compiling and get today's behaviour, with every wrong card counted as due.
   - `targetEntries` uses the existing `targetDistinct` computation (`n`, or `m × cardsPerMinuteEstimate`).
   - Call `SessionComposer.queue(...)` with the engine's `rng`. If it returns non-nil, build `allowed` from the first `targetEntries` entries and keep the rest as `topUpQueue`.
   - **Top-up:** when the engine would otherwise start a new round (F1: allowed minus `shownThisRound` minus resting is empty) **and** the session length is not reached **and** `topUpQueue` is non-empty, move the next entry from `topUpQueue` into `allowed` instead of starting a new round. Typically this happens in minute-based sessions that run longer than the estimate. Only when the queue is empty does F1's round logic repeat cards.
   - Nothing else changes: retries, grading, F2 discard and timing.
6. **PLAN.md:**
   - §10.5: replace the gating text for ranked decks with the composer rules above (entry states, queue order, gap, `reviewShare`). Keep the old text marked "music decks / unranked".
   - §10.6: mention `allowed` and top-up.
   - §17: add a dated decision-log line (D1–D3 below).

**Acceptance criteria and reference scenarios (for the tester):**
- **Session 2 doesn't repeat session 1.** Core 1, ko→en only, 20-card sessions, a fresh store. Session 1: answer all correctly. Session 2: its 20 cards are all distinct and **none** was shown in session 1. They are ranks 21–40 in rank order of introduction.
- **The wrong-card gap.** In session 1, answer ranks 3 and 7 wrong and the rest correct. Ranks 3 and 7 are **not** in session 2. Each appears in session 3, 4 or 5 (the 2nd–4th session after the miss), and the session number matches the FNV gap formula. The same seed and store give the same sessions on a second run.
- **The cap.** If 15 wrong entries are due and the session has 20 entries while fresh entries remain: at most 6 (`floor(20 × 0.3)`) are wrong entries, and the other 14 are fresh.
- **Random positions.** Over many seeds, the returning wrong cards are not always in the first slots of the session.
- **Retried correctly.** A card that was wrong and then retried correctly in the same session is still `wrong` (the retry isn't counted) and follows the gap.
- **Both directions.** Core 1, both directions, 20 cards: 20 distinct entries, one card each. Session 2 shows 20 *other* entries while fresh ones remain. Each entry's second direction appears only after all fresh entries are used up.
- **Fully covered deck.** If every card is `correct`, a session shows the least recently seen entries first and has no duplicates.
- **Tiny deck.** A 5-entry deck in a 20-card session: falls back to F1 rounds after the 5 entries, with no crash and no empty session.
- **Discarded and killed sessions** don't advance "sessions since a miss".
- **Music decks** (no ranks): the selection sequence is byte-identical to before S1 for the same seed.
- **Persisted formats:** unchanged. `PersistedFormatCheck` passes untouched.

---

### S2 · #4 data, #2/#3 wiring · Coverage numbers and session history (implementor, app + core helper)

**Commit:** `R8-S2: deck coverage metric and session-history wiring`

**Files:**
- new `Packages/MemoriseCore/Sources/MemoriseCore/Stats/DeckCoverage.swift`
- `Persistence/StatsStore.swift` (extension only)
- `App/Sources/Features/Session/SessionViewModel.swift`
- `App/Sources/AppEnvironment.swift`
- `App/Sources/Features/Home/HomeView.swift` (**only** `DeckRowInfo` and `load()`; the views are F1's)

**Steps:**
1. **`DeckCoverage`** (core, pure): `static func fraction(poolKeys: [ItemKey], stats: [ItemKey: ItemStats]) -> Double?`.
   - The result is the number of pool cards whose state is `correct` (S1's definition: attempted, and the last counted answer was correct), divided by `poolKeys.count`.
   - It returns `nil` when no pool card has been attempted, so the deck is still "New".
   - Also expose `coveredCount` for accessibility text.
   - **Cards, not entries:** for a both-directions vocab deck, a word with only ko→en done counts as half. That matches the "N cards" chip.
   - Stats rows outside the current pool (hidden F7 duplicates, other option sets) are ignored.
   - Put the card-state classification in one shared place (`ItemStats.lastAnswerWasWrong`, a computed property, so no wire change). S1 and S2 must both use it.
2. **`StatsStore` extension:** `func deckHistory(for deck: DeckID) async throws -> DeckHistory`. It builds the history from `sessions(for:)`, keeping `status == .completed`, and sorts by `startedAt`. This is an extension method, not a protocol requirement, so the in-memory, SwiftData and deferred stores all get it for free.
3. **`SessionViewModel.start()`:** fetch `deckHistory(for:)` concurrently with `stats` and `previous` (one more `async let`), and pass it to `SessionEngine(... history:)`.
4. **`AppEnvironment`:** add `cardKeys(for:options:) -> [ItemKey]`, cached exactly like `cardCount` (same key type, same invalidation). Implement `cardCount` on top of it so the two caches cannot disagree.
5. **`DeckRowInfo`:** add `coverage: Double?` and `coveredCount: Int`.
   - `make(...)` takes `poolKeys` instead of `cardCount`; `cardCount` becomes `poolKeys.count`.
   - Keep `accuracy`. F1 still shows it, but smaller.
   - In `HomeView.load()`, pass `env.cardKeys(for:options:)`.
   - Update `DeckRowInfo.text` to: `"\(cardCount) cards · \(coverage) covered · \(accuracy) accuracy · median … · last: …"`. It is used for VoiceOver.
6. **PLAN.md §9.5/§17:** define "coverage" in a single sentence.

**Acceptance criteria:**
- A fresh 100-card deck. After one 20-card session with 20 correct: coverage = **20 %**. Accuracy is still 100 % (it's still there, just not in the ring).
- The same deck with 18 correct and 2 wrong: coverage = 18 %. When those 2 come back and are answered correctly, it rises to 20 %.
- A covered card answered wrong in a later review drops out of coverage until it is answered correctly again.
- Changing deck options (e.g. a tag filter) recomputes coverage against the new pool.
- `PersistedFormatCheck` is untouched.

---

### F1 · #4 UI · Coverage ring on Home (frontend)

**Commit:** `R8-F1: Home rings show deck coverage`

**Files:**
- `App/Sources/Features/Home/HomeView.swift` (`DeckTile`, `DeckCard`)
- `App/Sources/DeckUI/VocabUI.swift`
- `DeckUI/ConjugationUI.swift`
- `DeckUI/HangulReadingUI.swift`

**Steps:**
1. **Ring = coverage.** In `DeckTile` and `DeckCard`, the `RingGauge` value and its centre text become `info.coverage` instead of `accuracy`. Show the ring whenever `coverage != nil`. A started deck with 0 % covered shows a "0%" ring, not the "New" chip.
2. **The ring needs a label.** Under the ring on `DeckCard`, add a tiny caption "covered" (`.caption2`, white 0.8). On the small `DeckTile`, there is no room, so the accessibility label carries it.
3. **Accuracy moves to a chip** on `DeckCard`: `chip("checkmark.circle", "92%")`, next to the median chip. Leave it out of the small tile.
4. **At 100 % coverage**, the ring shows a `checkmark` instead of "100%", in the same style. The tile reads as "Done", and sessions then review (S1, rule 4).
5. **Animation:** when Home reloads after a session, animate the ring from its old value to its new value with the existing `Theme.softSpring`. Under Reduce Motion, no animation.
6. **Hide the "New per session" steppers** in `VocabUI` (line ~240), `ConjugationUI` (~130) and `HangulReadingUI` (~186). This is decision D2: the composer fills sessions with new material, so the setting no longer does anything for these decks. Delete the `Stepper` rows only; leave the option fields in place (wire format).
7. Accessibility identifiers: `deckCoverageRing` (tile and card). Update the `#Preview`s with three states: New, 20 % covered, 100 % covered.

**Acceptance criteria:**
- After one 20-card all-correct session on a 100-card deck, the Core 1 tile shows **20%**, not 100 %.
- The hero card shows "20%" with "covered", and the accuracy chip shows 100 %.
- VoiceOver on a tile reads "… 20 percent covered, 100 percent accuracy …".
- A fully covered deck shows a ✓ ring.
- The deck setup sheets no longer show "New per session".

---

### C1 · #5 · K-pop chorus phrases, +120 entries (content agent)

**Commit:** `R8-C1: +120 K-pop chorus phrases`

**Files:**
- `Packages/MemoriseCore/Sources/MemoriseCore/Resources/Decks/ko_media.json` (append only)
- `docs/media-verification.md` (append rows)

**What to add:** 120 new entries, `ko.media.0170` onwards, with consecutive `rank`. Each one is a **short Korean phrase taken from a song's chorus or hook** that a learner can actually use in conversation.

**Picking phrases:**
1. **Artists, in priority order:** BTS, LE SSERAFIM, TWICE, NewJeans, ILLIT, then newer and popular groups (e.g. IVE, aespa, RIIZE, BABYMONSTER, KISS OF LIFE, BOYNEXTDOOR, TWS, ZEROBASEONE, NMIXX, SEVENTEEN, Stray Kids, TXT, (G)I-DLE, IU, Jung Kook / Jimin solo songs). Use at least 15 artists. No artist gets more than 15 % of the 120.
2. **From the chorus only.** The phrase must sit in the song's repeated hook. Because Bugs lyrics have no section markers (R6-5a), "chorus" means: the phrase appears **at least twice** on the lyrics page, inside the block of lines that repeats. Set `locator: "chorus"` only when that holds. Otherwise skip the song; don't fall back to `lyrics`.
3. **A phrase, not a lyric line (copyright, PLAN_M5 §2).** The bundled text is the phrase itself: **2–6 words**, a common expression (e.g. "너무 좋아", "나만 봐", "다시 한번 더", "괜찮다고 말해줘"). Never a full line longer than that, never two lines, and never a lyric quoted in `context`, `notes` or `dialogue`.
4. **Korean only.** Skip English hooks, chants and onomatopoeia ("ooh-ahh", "la la la").
5. **Useful in daily life.** Prefer phrases with a clear everyday meaning and a natural register (casual, polite). Skip poetic fragments that make no sense on their own.

**Each entry must have:**
- `hangul`, `romanization` (Revised Romanization, same style as the existing entries), `meanings` (a first gloss that is distinct across **all** `ko_*` decks; R7-C2 style parentheticals when needed), `pos: "expression"`, `register`, and 1–2 theme `tags` from the existing set (`romance`, `conflict`, `encouragement`, `daily`, `friendship`, `exclamation`, `feelings`, `slang`).
- An **original** 2-line `dialogue` (A/B, ko + en), written by you in an everyday setting, **not** the song's lyrics.
- ≥ 1 `sources` entry: `kind: "song"`, `title`, `by`, `year`, `locator: "chorus"`, an original 1-sentence `context` about the song's mood (no lyrics), and `citation`. The citation is the Bugs track page (`music.bugs.co.kr/track/<id>`) or another accepted lyrics source from PLAN_R5 S7.
- **Verification:** open the cited page and check that the phrase occurs verbatim at least twice, ignoring spacing and punctuation. **Never invent a reference.** If you can't verify it, drop the phrase. Don't add it without a source, because this segment is specifically about songs.

**Dedup rules (before adding each phrase):**
- Search every `ko_*.json` for the same headword (NFC, trailing `?!.~` stripped). If it already exists **in `ko_media`**, add the new song as an extra `sources` item on the existing entry instead of a new entry. This is the only edit to existing entries allowed in C1. These extra references don't count toward the 120 new entries.
- If it exists in another deck (Core 1–6, Patterns, AION 2, Slang), skip it: F7 would hide it in Media anyway.
- No two new entries with the same first gloss.

**Then:**
- Append one row per verified reference to `docs/media-verification.md`, and update the counts at the top.
- Run `swift test --filter DeckContentTests`. Leave the hard-coded count assertions to the tester.

**Acceptance criteria:**
- ≥ 120 new entries, all with ≥ 1 `chorus` song reference verified by reading the page.
- ≥ 15 artists, and no artist has more than 18 entries.
- Every new headword is 2–6 words, Korean only, and has an original dialogue.
- F7's validator report shows **0** new cross-deck duplicate headwords or shared first glosses.
- Ids and ranks are consecutive from `0170`, and no existing id or rank has changed.

---

### C2 · #5 · K-drama and reality-show everyday phrases, +100 entries (content agent, after C1)

**Commit:** `R8-C2: +100 everyday K-drama phrases`

**Files:** same as C1 (append only).

**What to add:** 100 new entries, continuing the ids and ranks after C1. Each one is an **everyday phrase that characters really say in K-dramas and Korean reality shows**: things a viewer hears every episode, not famous one-off catchphrases.

**Picking phrases:**
1. **Sources, in the owner's priority order:**
   - reality shows first: Kian's Bizarre B&B (대환장 기안장), The Devil's Plan (데블스 플랜), I Live Alone, Running Man, Earth Arcade, Physical: 100;
   - then popular dramas, e.g. When Life Gives You Tangerines, Queen of Tears, Lovely Runner, Crash Landing on You, Extraordinary Attorney Woo, Reply 1988, Hospital Playlist, Business Proposal, Squid Game, The Glory, Moving, Twenty-Five Twenty-One, Our Beloved Summer, Goblin.
2. **Everyday categories to cover**, with roughly 10–15 each:
   - greetings and goodbyes (e.g. 밥 먹었어?, 조심히 가);
   - reactions (e.g. 말도 안 돼, 그럴 리가);
   - comfort (e.g. 다 잘될 거야);
   - arguments (e.g. 너 지금 뭐 하는 거야?);
   - asking for things (e.g. 한 번만 봐줘);
   - food and drink (e.g. 한잔할래?);
   - work and school (e.g. 수고하셨습니다);
   - romance (e.g. 데려다줄게);
   - family and friends (e.g. 철 좀 들어).
3. **Length and register:** 1–7 words, spoken Korean. Mark the register honestly: `casual`, `polite` or `formal`. Include a mix: at least 25 `polite` or `formal`.

**Verification, which is harder than for songs:** dramas have no public transcripts.
- A **source** may be attached only when the phrase is confirmed by one of:
  - reputable Korean press quoting the line (as in PLAN_M5 K2);
  - the broadcaster's or Netflix Korea's **official** clip on YouTube, whose Korean title or description contains the phrase;
  - an official episode page.
- Use `kind: "drama"` or `"show"`, the `title`, `by` = the network or platform, `year`, `locator` = `S1 E4` or `series` when no episode is given, an original `context` sentence, and the `citation` you used.
- When it can't be verified, **still add the phrase** as a dialogue-only card **with no `sources`**, which the M5 rules allow. These phrases are everyday speech, so the card is valid without a reference. **At least 30 of the 100** must have a verified source.
- **Never invent a reference.**

**Each entry also needs:** the same fields and dedup rules as C1, including the check against every `ko_*` deck and a distinct first gloss. The original 2-line dialogue is set in a scene typical of that genre (e.g. an office, a family dinner, a date), **not** a transcript of the show.

**Then:** append verification rows (verified ones only) to `docs/media-verification.md`, update the counts, and run `DeckContentTests`.

**Acceptance criteria:**
- ≥ 100 new entries, all categories in step 2 represented, and ≥ 25 polite or formal.
- ≥ 30 entries with a verified drama or show reference, with reality shows among them if any are verifiable. List the reality-show phrases you looked for but couldn't verify in the doc's "Not used" list.
- The validator report shows 0 new duplicates or shared first glosses.
- After C1 and C2, `ko_media` has ≥ 389 entries (169 + 120 + 100).

---

## 4. Owner decisions

**Confirmed by the owner on 2026-11-17: all defaults below apply.** Implementors should treat them as final.

| ID | Question | Decision (confirmed) |
|---|---|---|
| D1 | How long does a wrong card wait? | A random **2–4 sessions** of the same deck (it never returns in the next session), stable per miss. It counts sessions, not days, so a long break doesn't flood the next session. |
| D2 | What happens to the "New per session" setting? | **Hidden** for Korean decks. Sessions are filled with new material up to the session length. The stored value is kept (wire format) but ignored. |
| D3 | What does "coverage" count? | **Cards** in the deck's current pool whose **last** answer was correct. A both-directions word counts as 2 cards. A covered card answered wrong later drops out until it's answered correctly again. |
| D4 | One K-media deck or split it into "K-pop" and "K-drama" tiles? | **One deck** (`ko_media`, append only). Splitting would need new deck ids and moving entries, which the id rules forbid. Can be revisited later as two *filtered* tiles over the same deck. |
| D5 | How many returning wrong words per session? | At most **30 %** of the session while new material remains (`reviewShare`). |
