# Memorise — Round 7 Fix Plan (owner device test)

- **Date:** 2026-11-17
- **Sources:**
  1. The owner's on-device test (iPhone), 2026-11-17. There are 8 findings, listed in §1.
  2. `CODE_REVIEW.md` Round 6. Every R6 code item is already done (PLAN_R6_FIXES §2). Only **C1** (verification rows, content agent) and **R6-8a/b** (tester) are still open, and they stay tracked there. This plan adds nothing for them.
- **Owner of this file:** the planner. The implementor and frontend agents run the segments in §3 and tick the tracker (§2).
- **Conventions:** `CLAUDE.md` and PLAN.md §16 apply.
  - Domain logic stays in `MemoriseCore`, which imports only Foundation. Inject the RNG and clocks.
  - No `Codable` wire change unless a segment says so. New persisted properties get a default and a tolerant `init(from:)`.
  - Never change or reuse an entry `id` or `ItemKey`. Never delete deck entries from the JSON; hide them in code instead (F7).
  - Scheduling constants live in `SchedulerConstants`. If you tune them, update PLAN.md §10.
  - Never hand-edit the `.xcodeproj`.
  - Record every deviation in PLAN.md §17.
- **Commits:** one segment = one commit, with the message given in the segment. Stage **only** the files that segment touches, because other agents leave files uncommitted in the same tree.
- **Tests:** none in this plan. The tester agent owns tests. Each segment lists acceptance criteria and reference scenarios for the tester to turn into tests.

---

## 1. Coverage map

| # | Owner finding (paraphrased) | Root cause (verified in code) | Segment | Agent |
|---|---|---|---|---|
| 1 | "On one run I get the same cards over and over." | `IntroductionPolicy` admits only `newPerSession` (10) unseen ranks into a 20-card session, and this set is fixed at `SessionEngine.init`. So a fresh deck has 10 cards for 20 slots, and each card comes back about twice. The cooldown is only 3 cards, and once every eligible card has been shown, `alreadyShownFactor` (0.2) applies to all of them, so it no longer separates them. | **F1** | implementor (core) |
| 6 | "If I get a word right, it shouldn't re-throw it shortly after." | The same cause. In-session, a correct card is treated exactly like a wrong one (weight × 0.2), and the only spacing rule is the 3-card cooldown. | **F1** | implementor (core) |
| 5 | "When I abandon a session half way, it shouldn't say 'Flawless'. It should discard the session." | `SessionEngine.finish()` sets the status to `.completed` whenever `countedGraded > 0`. `SummaryView.hero` then says "Flawless!" at ≥ 95 % accuracy and shows confetti at ≥ 80 %, even after 2 cards. Stats and attempts are already saved card by card. | **F2** | implementor (core + app) |
| 2 | "The microphone doesn't work well in the notes section. The right note should register, it should say 'correct' or 'try again', and then move on." | A correct note grades and advances on the same frame, with only a haptic, so nothing is visibly confirmed. A wrong note shows only a small "Heard G♯" chip for 1.5 s. `FretboardNotesUI.micAccepts` rejects octave errors from YIN (the range check), so a correctly played low note can be ignored. | **F3** | implementor (app) |
| 3 | "The fretboard is vertical and smushed together. Redesign it." | `FretboardView` always draws the whole neck (0…12, up to 22) at `aspectRatio(3.2)`. On a portrait phone that is about 26 pt per fret and 18 pt between strings. The answer card stacks the title, board and fret text in a narrow column. | **F4** | frontend |
| 4 | "In the Korean section, if I scroll fast to the top I see 'Music' / 'Fretboard' headers above the Korean decks." | `HomeView` builds the sections in a `LazyVStack` with nested `ForEach`es whose group identity is `\.offset` (0, 1, 2 …). Music and Korean groups share those ids, so on a fast fling the lazy stack can reuse a recycled header with the other section's tiles. | **F5** | frontend |
| 8 | "The Korean font is fine, but the size is too large and cuts words in half." | The vocab prompt uses a fixed 72 pt with `lineLimit(2)`, and the answer uses 52 pt. SwiftUI wraps Hangul at **any syllable**, not at word boundaries, so a long word or phrase is split across lines before `minimumScaleFactor` shrinks it. Conjugation (64/52 pt), Particles (72/56 pt) and Hangul Reading (96–140 pt) have the same pattern. | **F6** | frontend |
| 7 | "The Korean categories should barely overlap. I don't want the same words in every category." | Two causes. (a) 12 headwords appear in two vocab decks, and **88 first glosses** are shared across decks (for example, "bag", "friend" and "I'm sorry" each exist in two decks under different Korean words). (b) The *derived* decks (Conjugation, Particles, Hangul Reading "real words") draw their words from the vocab decks and introduce them in Core 1 rank order, so all of them start with the same first words. | **F7** (code), **C2** (content) | implementor, content agent |

**Order and parallelism:**
1. **F1** and **F2** come first. They are core changes, they affect every deck, and they edit disjoint parts of `SessionEngine` (F1: selection; F2: `quit`/`finish`). Run them one after the other, F1 first, to avoid merge conflicts in the same file.
2. **F3** (app, mic) can start right after F2, because both touch `SessionViewModel`.
3. **F4, F5 and F6** are frontend-only and touch disjoint files. They can run in parallel at any time.
4. **F7** (core) is independent. **C2** (content) runs after F7, because F7's validator report lists what C2 must fix.

## 2. Tracker

| Segment | Covers | Status | Notes |
|---|---|---|---|
| F1 No repeats until the pool is used up; correct cards stay away; top up new cards | #1, #6 | ☑ | Core. Update PLAN.md §10.3 and §10.5. |
| F2 Ending a session early discards it | #5 | ☑ | Core + app. One new `SessionEffect` case and one new `StatsStore` requirement. |
| F3 Mic answer: "Correct" / "Try again", then move on | #2 | ☑ | App only. One new `AppSettings` field. |
| F4 Fretboard redesign | #3 | ☐ | Frontend. The owner checks it on device. |
| F5 Home: stable section identity | #4 | ☐ | Frontend. |
| F6 Korean text that fits | #8 | ☐ | Frontend. One shared component. |
| F7 One home per Korean word, and derived decks that don't mirror Core 1 | #7 | ☐ | Core. The validator report feeds C2. |
| C2 Distinct glosses across Korean decks | #7 | ☐ | Content agent, after F7. Edits existing glosses (the owner asked for this). |

---

## 3. Segments

### F1 · #1 + #6 · Card selection: no repeats until the pool is used up

**Commit:** `R7-F1: no-repeat card selection, correct cards stay away, new-card top-up`

**Files:**
- `Packages/MemoriseCore/Sources/MemoriseCore/Scheduling/Scheduler.swift`
- `Scheduling/IntroductionPolicy.swift`
- `Scheduling/SchedulerConstants.swift`
- `Session/SessionEngine.swift`
- `PLAN.md` §10.3, §10.5 and §17

**Target behaviour, in plain words:**
1. **No repeats until the pool is used up.** Within a session, a non-retry card is shown again only after every other *allowed* card has been shown once (a "round"). Wrong-answer retries (`retryWrongCards`) still come back after 3–5 cards; that is intended practice, and the owner's complaint is about correct cards.
2. **Correct cards stay away.** A card answered correctly in this session is not shown again in the current round *or the next one*. It can come back only when nothing else is left (a tiny pool). For vocab, the same entry's other direction (ko→en / en→ko) counts as the same word for this rule.
3. **Enough distinct cards for the session.** Introduction gating must give the session at least as many distinct cards as it will show, so it never has to repeat to fill its length.

**Steps:**
1. **`SchedulerConstants`:** add
   - `cardsPerMinuteEstimate = 8`, used to size minute-based sessions;
   - `correctRestRounds = 1`, the number of extra rounds a correct card sits out.

   Document both in PLAN.md §10.
2. **`IntroductionPolicy.eligibleNewKeys`:** add a parameter `targetDistinct: Int`.
   - The fill rule's minimum becomes `min(pool.count, max(constants.minEligiblePool, targetDistinct))`, instead of `min(minEligiblePool, pool.count)`.
   - `newPerSession` stays the number of new ranks admitted *before* the fill rule. The fill rule still adds whole ranks in rank order.
   - `targetDistinct` counts **entries (ranks)**, not cards, when the deck has two directions. Otherwise a 20-card both-directions session would be filled by 10 words shown twice, which is the complaint again.
3. **`SessionEngine.init`:** compute `targetDistinct`.
   - `.cards(n)` → `n`.
   - `.minutes(m)` → `m * cardsPerMinuteEstimate`.

   Pass it to the policy.
4. **`SessionEngine`:** keep two new pieces of state.
   - `shownThisRound: Set<ItemKey>`: non-retry cards shown in the current round.
   - `correctRestUntilRound: [ItemKey: Int]`: for a correct non-retry grade, set the key to `round + 1 + correctRestRounds`. For vocab, also set the sibling direction's key. Use `VocabDeck.itemKey(entryID:direction:)` through a new optional `Deck` hook, `siblingKeys(of: Card) -> [ItemKey]`; the default is `[]`.

   When the allowed set minus `shownThisRound` is empty, increment `round` and clear `shownThisRound`.
5. **`Scheduler.nextCard`:** add a parameter `blocked: Set<ItemKey>`. The engine passes the union of `shownThisRound` and the keys still resting.
   - Selection order:
     1. a weighted pick among allowed cards that are **not blocked**, with the cooldown;
     2. if none, a weighted pick among blocked keys that **aren't resting**, i.e. start a new round;
     3. only then, resting keys (tiny pools);
     4. then the existing uniform fallback.
   - Keep the existing cooldown, pattern penalty and `excluded` semantics. Remove the `alreadyShownFactor` multiplication; rounds replace it. Keep the constant so the wire and defaults are unchanged, and mark it "unused since R7-F1" in the doc comment.
6. **Retries:** unchanged, except that a due retry still respects the cooldown, as today.
7. **PLAN.md:**
   - §10.3: replace the "already shown ×0.2" text with the round and rest rules.
   - §10.5: add `targetDistinct`.
   - §17: add a dated decision-log line.

**Acceptance criteria and reference scenarios (for the tester):**
- **A fresh vocab deck**, Core 1, ko→en, 20 cards, `newPerSession` 10, `retryWrongCards` off: all 20 cards are **distinct**.
- **The same deck with both directions**: 20 cards cover ≥ 20 distinct *entries' first appearances* before any entry repeats. No entry's two directions appear within 3 cards of each other.
- **A pool of 8 cards** and a 20-card session, all answered correctly: each card appears in round 1 before any card appears twice. A card answered correctly does not reappear in round 2 unless every remaining card is also resting.
- **Wrong answer with retries on:** the retry appears 3–5 cards later, as before, and is not blocked by the round rule.
- **Music decks** (no gating, e.g. fretboard notes on 1 string = 12 cards) in a 20-card session: no card repeats before all 12 are shown.
- **Determinism:** the same `SplitMix64` seed gives the same sequence.
- **Persisted formats:** unchanged. `PersistedFormatCheck` passes untouched.

---

### F2 · #5 · Ending a session early discards it

**Commit:** `R7-F2: ending a session early discards it (stats restored, no summary)`

**Files:**
- `Session/SessionEngine.swift`
- `Persistence/StatsStore.swift` (+ `InMemoryStatsStore.swift`)
- `App/Sources/Persistence/SwiftDataStatsStore.swift`
- the deferred store (wherever `DeferredStatsStore` lives)
- `App/Sources/Features/Session/SessionViewModel.swift`
- `SessionView.swift`
- `Features/Summary/SummaryView.swift`

**Rule (owner):** a session ended with **End session** before its length is reached leaves **no trace**. That means:
- no session record;
- no attempts;
- per-word stats back to what they were when the session started.

A session that reaches its length finishes and is summarised exactly as today.

**Steps:**
1. **Engine:**
   - Keep `initialStats` (the dictionary passed to `init`).
   - Add `public func discard() -> [SessionEffect]`. It sets `state = .finished(...)` with `record.status = .abandoned`, so the UI leaves the running state, and returns **one** new effect:
     `case discardSession(id: UUID, restore: [ItemStats], delete: [ItemKey])`.
     - `restore`: the initial stats of every key whose stats changed.
     - `delete`: keys that had no stats row at the start.
   - `quit()` stays for API compatibility but is no longer called by the app.
   - `SessionEffect` is not persisted, so the new case is not a wire change.
2. **`StatsStore`:** add a protocol requirement (not an extension-only method, as in R5-2):
   `func discard(session: UUID, restore: [ItemStats], delete: [ItemKey], deck: DeckID) async throws`.
   It deletes the session row and all its attempts, writes `restore` and deletes the `delete` rows, **in one save**. Extend `apply(_ effect:)` for the new case. Implement it in the in-memory, SwiftData and deferred stores. The deferred store must flush pending writes for this session *before* applying the discard, so a late write can't resurrect it.
3. **`SessionViewModel.quit()`:**
   - If the length was not reached, call `engine.discard()`, apply the effects, close the recorder, call `env.dataDidChange()` and set a flag `discarded = true`.
   - If the length was already reached, which can't happen through the button today, finish normally.
4. **`SessionView`:** when `discarded` is true, dismiss the cover straight away instead of showing `SummaryView`. Optionally show a brief "Session discarded" toast on Home; a toast is enough, no alert.
   - Change the confirmation dialog message to: "This session won't be saved."
   - Change the buttons to "Discard session" (destructive) and "Keep going".
5. **`SummaryView` (defence in depth):** if `summary.status == .abandoned`, never show "Flawless!", "Great run!" or the confetti. Use the title "Session ended" (already there) and a neutral headline.
6. **Interrupted sessions (app killed mid-session):** out of scope. `closeInterruptedSessions` keeps its current behaviour. Trends and the baseline already ignore everything except `.completed` (`StatsStore.swift:50, 60`).
7. **PLAN.md §9.3 and §17:** "End session" now means discard.

**Acceptance criteria:**
- Play 5 of 20 cards, all correct, then **Discard session**:
  - no summary appears;
  - Home shows the deck's previous accuracy, median and "last seen";
  - Stats → history has no new session;
  - the 5 words' `attempts`, `ewmaError`, `ewmaResponseMs` and `lastSeenAt` equal their values before the session.
- Do the same on a **brand-new** deck: the deck still shows "New", and no `ItemStats` rows exist.
- A session played to its full length behaves exactly as today (summary, confetti rule, trend point).
- Kill the app mid-session, then relaunch: same behaviour as today (no regression).

---

### F3 · #2 · Mic answer: "Correct" / "Try again", then move on

**Commit:** `R7-F3: mic answers confirm with Correct / Try again before moving on`

**Files:**
- `App/Sources/Features/Session/SessionViewModel.swift`
- `SessionView.swift` (the mic chip area)
- `Services/MicAnswerController.swift`
- `DeckUI/FretboardNotesUI.swift`
- the `AppSettings` file
- `Features/Settings/SettingsView.swift`

**Target flow** (fretboard notes, and every deck with `supportsMicAnswer`):

| Event | What the user sees and hears | Then |
|---|---|---|
| A stable note that the card accepts | A large **"Correct ✓"** banner over the card (mint), the success haptic, and the spoken word "Correct" if spoken feedback is on | After **0.9 s**, grade correct and show the next card |
| A stable note that the card does not accept | A **"Try again · heard G♯"** banner (rose), the error haptic, and the spoken words "Try again" if spoken feedback is on | Keep listening on the same card |
| The 3rd wrong note on the same card | "Not quite: it's A, fret 5" (the reveal) | Reveal the answer. The card is graded **wrong** automatically after 1.5 s. The user can tap to skip the wait. |
| Timeout (`micTimeoutSeconds`) | Same as today: reveal for manual grading | Unchanged |

**Steps:**
1. **Feedback state in the VM:** add `micFeedback: MicFeedback?` (`.correct`, `.tryAgain(heard: String)`) and `wrongNoteCount` (reset per presentation).
2. **On a correct note** (`micHeard`):
   - Call `mic.setListening(false)` and record the onset on the engine clock.
   - Set `micFeedback = .correct`, play the haptic and speak.
   - Start a task that sleeps 0.9 s, checks that the same `presentationID` is still prompting, then calls `engine.answerDetected(at: onset)`.
   - Because the onset was captured first, the 0.9 s does **not** inflate `responseMs`.
   - Cancel the task on pause. On resume, the card is re-shown unanswered (today's pause semantics).
   - **Graded correct only if `wrongNoteCount == 0`.** If the user hit wrong notes first, still say "Correct" and move on, but grade the card **wrong**, so it is retried later and the stats stay honest. Use `answerEvaluated(correct: false, at: onset, countsTime: false)`. This is owner decision **D1** in §4.
3. **On a wrong note:** `MicAnswerController.deliver` already calls `showWrong`. Route it through the VM instead (`onWrongNote` callback), so the VM sets `.tryAgain`, increments `wrongNoteCount`, plays the haptic and speaks.
   - While speaking, call `setListening(false)`, and set it back to `true` after the utterance (or 0.6 s), so the phone's own speaker is not heard as a note. The R6-3 arm filter already discards pre-arm frames.
   - Clear the banner after 1.2 s.
4. **Speech:**
   - Use `env.speech` with an English voice at the normal rate. Don't use the Korean voice that vocab uses.
   - Add `AppSettings.spokenMicFeedback: Bool = true`. It is a new persisted property, so it needs a default plus a tolerant decode, per CLAUDE.md.
   - Add a toggle in Settings → Music: "Say Correct / Try again".
   - Haptics and banners always run.
5. **Octave tolerance:** in `FretboardNotesUI.micAccepts`, accept the right pitch class anywhere in the guitar range (`open(lowest string)` … `open(string 1) + 24`), not only the target string's range.
   - The string can't be told from the pitch anyway.
   - YIN octave errors on low strings were making correctly played notes fail silently.
   - Make the same change in `IntervalsUI.micAccepts` if it has the same range check.
6. **Banner UI:**
   - A capsule overlay centred over the prompt with SF Symbols `checkmark.circle.fill` / `arrow.uturn.backward.circle.fill`.
   - Spring in, fade out. Under Reduce Motion, use opacity only.
   - Accessibility identifier `micFeedbackBanner`, and post a VoiceOver announcement with the same text.
   - It replaces the small "Heard G♯" text; the level meter stays.

**Acceptance criteria:**
- On device, fretboard notes with mic input:
  - play the right note: "Correct" is visible and heard, and the next card appears about 1 s later;
  - play a wrong note: "Try again · heard X" appears and the card stays;
  - play 3 wrong notes: the answer is revealed and the card is graded wrong.
- The app's own speech never triggers a "heard" note.
- The response time recorded for a correct note equals onset − prompt time, not onset + 0.9 s.
- With spoken feedback off: the banners and haptics remain, and there is no speech.
- Typed, choice and touch modes are unchanged.

---

### F4 · #3 · Fretboard redesign

**Commit:** `R7-F4: roomy horizontal fretboard with a zoomed fret window`

**Files:**
- `App/Sources/Components/FretboardView.swift`
- `DeckUI/FretboardControls.swift` (`board(...)`)
- `DeckUI/FretboardNotesUI.swift`
- `FretboardNamesUI.swift`
- `IntervalsUI.swift`
- other `settings.board(maxFret:)` callers (grep for them)

**Interpretation:** the owner finds the current board cramped. "Vertical and smushed" means the board sits small inside a tall, narrow stacked card, with the whole neck squeezed into the phone width. The board stays **horizontal**, like a real guitar held in front of you. If the owner meant a different screen, they will say so after F4's device check.

**Design:**
1. **Zoomed fret window by default.**
   - Draw only the frets that matter, with padding:
     - **Answer and reveal:** from the lowest answer fret − 2 to the highest answer fret + 2, at least 5 frets wide, clamped to the neck.
     - **Prompts that show the board** (intervals): the window around the root, +5 frets.
   - Start at the nut when the window's lower bound is ≤ 2, so open-string answers keep the nut.
   - `FretboardView` already supports `fretWindow` and labels the first fret when it doesn't start at the nut. Use the existing `board(window:)` overload.
2. **Two answers far apart** (e.g. fret 5 and fret 17): show two small windows side by side in portrait, or one window per answer in a horizontal `ScrollView` with paging dots. Pick the side-by-side option if both fit at ≥ 44 pt per fret; otherwise use the pager.
3. **Size rules:**
   - At least **28 pt between strings** and at least **44 pt per fret**, which is a comfortable touch target.
   - Replace the fixed `aspectRatio(3.2)` with a height derived from the string count: `(stringCount − 1) × stringSpacing + 2 × margin`.
   - The board uses the full card width, edge to edge inside the card's padding.
   - Fret numbers sit under the board, not inside it.
4. **Layout of the answer card:** a horizontal header (note name + ▶ play button), then the board, then a single caption line ("fret 5 · also 17"). Remove the separate stacked third text block. In landscape, the board takes 100 % width and the header sits to its left.
5. **Optional "Whole neck" toggle** (a small button on the card) that shows 0…max frets in a horizontal `ScrollView`, scrolled to the answer. Keep the same size rules, so the board scrolls instead of shrinking.
6. **Stats heatmaps** (`FretboardHeatmap`) are out of scope; they are a separate grid component.
7. Keep left-handed and high-E-on-top support, the accessibility label text, and the `#Preview`s. Add a preview for a two-window answer.

**Acceptance criteria:**
- On iPhone portrait, for a fret-5 answer on string 6: the board shows frets 3–7 (or 0–7 if the nut rule applies), with strings ≥ 28 pt apart and dots ≥ 24 pt.
- No horizontal page scroll.
- For answers 5 and 17: both are visible without shrinking below the size rules.
- Landscape works.
- Left-handed mirroring still works.
- The owner confirms on device that it "no longer looks smushed".

---

### F5 · #4 · Home: headers always match their decks

**Commit:** `R7-F5: Home sections use stable identity`

**File:** `App/Sources/Features/Home/HomeView.swift`

**Steps:**
1. **Reproduce it first:** in the simulator, scroll to the Korean section and fling to the top. Note what you see in the §17 entry.
2. Give every section and group a **stable, unique id**.
   - Sections: `subject.rawValue`.
   - Groups: `"\(subject.rawValue).\(group.title)"`.
   - Replace `ForEach(Array(groups.enumerated()), id: \.offset)` with an id-based `ForEach`. Keep the index for `appearAnimation` by computing it separately.
3. Change the outer `LazyVStack` to a plain `VStack`. Home has about 27 tiles, so eager layout is cheap. This removes cell recycling as a cause. Keep each `LazyVGrid`, or change it to `Grid`, whichever renders identically.
4. Check that `appearAnimation` doesn't re-trigger on every scroll after the change. It must only animate the first appearance.
5. **Performance:** measure Home's first-render time before and after in the existing G5 timing log. If eager layout adds more than 16 ms, keep the `LazyVStack` and rely on the stable ids alone. Record which you kept in §17.

**Acceptance criteria:**
- A fast fling from the Korean section to the top never shows a Music header (or the Fretboard group title) above Korean tiles, or the reverse. Try at least 10 flings.
- Scrolling stays smooth at 120 Hz on device.

---

### F6 · #8 · Korean text that fits

**Commit:** `R7-F6: Korean headlines size to fit and never split a word`

**Files:**
- a new `App/Sources/Components/KoreanHeadline.swift`
- `DeckUI/VocabUI.swift`
- `ConjugationUI.swift`
- `ParticlesUI.swift`
- `HangulReadingUI.swift`
- `Components/MediaSnippetView.swift`, if it shows headword Hangul

**Component:** `KoreanHeadline(text: String, role: .prompt | .answer)`.
1. **Base size by length** (count characters, excluding spaces):

   | Characters | Prompt | Answer |
   |---|---|---|
   | ≤ 3 | 60 pt | 46 pt |
   | 4–6 | 50 pt | 40 pt |
   | 7–10 | 40 pt | 32 pt |
   | > 10 | 32 pt | 28 pt |

   Today's sizes are 72 and 52. Scale with Dynamic Type using `@ScaledMetric(relativeTo: .largeTitle)`.
2. **Never break inside a word.**
   - Split the text on spaces into words, and lay the words out with a small wrapping layout (a custom `Layout` that flows words onto lines and centres them).
   - Each word is a `Text` with `.lineLimit(1)` and `.minimumScaleFactor(0.5)`, so a single word shrinks to fit the width instead of wrapping mid-syllable.
   - Allow at most 3 lines. Beyond that, scale everything down uniformly with `ViewThatFits` over decreasing sizes.
3. Keep the gradient, shadow and accessibility label exactly as now. The label is the whole string, and VoiceOver reads it as one element.
4. Replace the Hangul `Text`s in:
   - the vocab prompt (ko→en, listening reveal) and the vocab answer;
   - the conjugation prompt and answer;
   - the particles noun;
   - the Hangul Reading word prompt and answer (single-syllable jamo prompts keep their large 140 pt; apply the component only when `text.count > 1`).
5. Do **not** change the English text sizes or the typed field.
6. Add a `#Preview` with: 사랑해, 보고 싶어, 괜찮아요, 어떡해, 공부하다, 기억이 안 나요, 처음 뵙겠습니다, and the longest headword in each Korean deck. Find them with a one-off script; don't commit the script.

**Acceptance criteria:**
- On the smallest supported iPhone width, with the default text size, the longest headword in every Korean deck shows with no word split across lines and nothing truncated (no "…").
- Single words fit on one line.
- Typical words (2–4 syllables) are visibly smaller than today's 72 pt, but still the dominant element on the card.
- At accessibility text sizes, the text scales and still never splits a word.

---

### F7 · #7 · One home per Korean word; derived decks don't mirror Core 1

**Commit:** `R7-F7: each Korean headword belongs to one deck; derived decks interleave sources`

**Files:**
- `Packages/MemoriseCore/Sources/MemoriseCore/Decks/DeckCatalog.swift`
- `Decks/VocabDeck.swift`
- `Korean/DeckValidator.swift`
- `Korean/ConjugationDeck.swift`
- `Korean/Particles.swift`
- `Korean/HangulReading.swift`

**Part A: one home per headword** (12 headwords today, 1 of them duplicated *inside* Core 1: 일).
1. In `DeckCatalog.builtIn()`, after loading the bundled vocab files, build a set of **owned headwords**. The key is the NFC Hangul with trailing `?!.~` stripped, plus `pos`.
   - **Priority:** Core 1 → Core 5 → Patterns → AION 2 → Media. The earliest deck wins, so the general-frequency decks keep the general words.
   - A later deck **hides** its duplicate entries: pass a `hiddenEntryIDs: Set<String>` into `VocabDeck`, and `cards(options:)` skips them.
   - The JSON is untouched, and ids are never removed or reused.
   - Stats of hidden entries stay in the store, unused. Reset and export still work.
2. **Same-word, different-sense pairs** (e.g. 일 "one" and 일 "work") are allowed when `pos` or the first gloss differs. The `pos` part of the key handles most of these. Inside Core 1, 일/일 needs to stay as two entries if the senses differ. The validator reports it; don't hide it.
3. **`DeckValidator`:** add a **warning** (not an error, so nothing fails to load) listing:
   - every cross-deck duplicate headword (all `ko.*` decks, not only `ko.core.*`);
   - every **first gloss** shared by two Korean decks (88 today).

   Show the warnings in the existing debug load report only, not on Home.
4. **User decks** (`user.*`) are never hidden. Owners may add whatever they like.

**Part B: derived decks don't all start with the same words.**
1. Conjugation (`.allCore`), Particles (`.allKorean` / `.coreOnly`) and Hangul Reading "real words" currently introduce words in the source deck's rank order. Their first sessions are therefore Core 1's top words, the same ones the owner just practised in Core 1.
2. Change each derived deck's `introductionRank` to a **deterministic interleave**:
   - take the source words grouped by source deck;
   - order them round-robin across source decks (Core 1 #1, Core 2 #1, Core 3 #1, …, Core 1 #2, …);
   - within each source deck, use a **fixed per-deck shuffle** seeded from the derived deck's id with `SplitMix64(seed: stableHash(deck.id))`. Hash it with FNV-1a, never `hashValue`, which is randomised per launch.

   The order must be stable across launches, so introduction gating stays consistent.
3. **Hangul Reading** keeps "shortest first" as its primary sort and applies the interleave within each length.
4. **Conjugation `.core1`** stays in rank order. The owner asked for Core 1 explicitly there.

**Acceptance criteria:**
- `DeckCatalog.builtIn()`: no `(headword, pos)` pair appears in two bundled Korean vocab decks' `cards(...)`.
- Ids, JSON and `ItemKey`s are unchanged, and `PersistedFormatCheck` passes.
- The first 10 introduced words of Conjugation, Particles and Hangul Reading (real words) share **≤ 2** words with the first 10 of Core 1, and ≤ 2 with each other. Record the before/after numbers in §17.
- The order is identical across two launches (no `hashValue`).
- Validator warnings list the shared first glosses. The count is the input to C2.

---

### C2 · #7 · Distinct glosses across Korean decks (content agent)

**Commit:** `R7-C2: distinct glosses across Korean decks`

**Files:** `Resources/Decks/ko_*.json` (gloss text only)

1. Run the app, or the validator in a scratch copy, after F7. Take the list of shared first glosses (88 today; for example, "bag", "friend", "I'm sorry", "it's okay", "really", "to change").
2. For each pair, edit the **later** deck's first gloss, using F7's priority order, to name its specific sense. Use the R6 T4 parenthetical style, which `stripParentheticals` already ignores when grading:
   - "bag (backpack)"
   - "friend (old friend)"
   - "I'm sorry (formal apology)"
3. If two entries are true synonyms with no useful difference, say so in a list for the owner instead of inventing a difference. The owner decides whether to keep both.
4. **Never** change an `id`, `rank` or `hangul`. Change only `meanings[0]` (and add a `notes` line if the sense needs explaining).
5. This edits existing entries, which the content-agent rule normally forbids. The owner's request ("very little overlap between categories") is the waiver. Record it in §17.

**Acceptance criteria:**
- F7's shared-first-gloss warning count drops to 0, or to the owner-approved synonym list.
- `DeckContentTests` id/rank checks still pass. The tester updates any hard-coded gloss rows.

---

## 4. Owner decisions

**Confirmed by the owner on 2026-11-17: all defaults below apply.** Implementors should treat them as final.

| ID | Question | Decision (confirmed) |
|---|---|---|
| D1 | Mic: a card answered correctly after one or more "Try again"s: is it graded correct or wrong? | **Wrong** (it is retried later, and the stats stay honest). It still says "Correct" and moves on. |
| D2 | Discard: also discard sessions ended by a mic/typed timeout or by the app being killed? | **No.** Only the "End session" button discards. Killed sessions keep today's behaviour. |
| D3 | Duplicate headwords: which deck keeps a shared word? | **The earliest deck:** Core 1 → Core 5 → Patterns → AION 2 → Media. |
| D4 | F3 spoken feedback default | **On**, with a Settings toggle. |
| D5 | F4 "vertical": does the owner mean the fretboard *session card* (the deck "Fretboard notes")? | **Yes.** The redesign covers every session screen that draws `FretboardView`. Stats heatmaps are not included. |
