# Memorise — Round 6 Review-Fix Plan

- **Date:** 2026-11-17
- **Source:** `CODE_REVIEW.md` Round 6 (R6-1 … R6-8).
- **Owner of this file:** the planner. Implementor agents run the segments in §3 and tick the tracker (§2).
- **Conventions:** `CLAUDE.md` and PLAN.md §16 still apply:
  - domain logic stays in `MemoriseCore` (Foundation only);
  - there are **no wire-format changes** in this plan: no new `VocabEntry` fields and no renamed keys;
  - never change or reuse an entry `id` or `ItemKey`;
  - never hand-edit the `.xcodeproj`;
  - record every deviation in PLAN.md §17.
- **Commits:** one segment = one commit. Use the message given in each segment. Stage **only** the files that segment lists, because other agents leave files uncommitted in the same tree.
- **Tests:** none in this plan. The tester agent owns `DeckContentTests`, `AnswerMatcherTests`, the engine tests and CI. Each segment lists acceptance criteria and reference rows; the tester turns them into golden rows.

---

## 1. Coverage map

| Review item | Segment | Owner |
|---|---|---|
| R6-1 K2 not in the catalog; `HEAD` red | **T1** (wire + commit K2), **T2** (commit Core 5 / AION extension) | implementor; owner approves T2 (D1) |
| R6-5a Guessed song locators shown as facts | **T1** step 1 | implementor (mechanical JSON edit) |
| R6-2 Polite 요 form graded wrong; shared glosses | **T3** (matcher), **T4** (glosses) | implementor |
| R6-3 Stale ring audio answers the next card at 0 ms | **T5** | implementor |
| R6-7a Home aurora may tick under the session cover | **T6** (measure first) | frontend agent |
| R6-4 284 new entries unplanned / unverified | T2 (commit) + P2 (planner §17) + content rows | planner, content agent, owner |
| R6-5 K2 misses its targets; spot-check | none (owner) | owner, D2 |
| R6-6 PLAN still contradicts the code; K5 unscheduled | P1, P3 | planner |
| R6-8a/b CI runs no tests; hard-coded counts | none | tester |
| R6-7b Saved-config decode per Home load | none | no action unless G5 timing shows it |
| R6-8c Media entries with no `register` | none | no action (intended) |

**Order:**
1. **T1 and T2 come first.** They make `HEAD` green and the media deck visible.
2. After that, **T3, T4 and T5** are independent and touch disjoint files. They can run in parallel. T4 edits `ko_media.json`, so it must start **after** T1 is committed.
3. **T6** is independent and can run at any time.

## 2. Tracker

| Segment | Covers | Status | Notes |
|---|---|---|---|
| T1 Wire `ko_media` + song locators → "lyrics" + commit K2 | R6-1, R6-5a | ☐ | First. Do not tick PLAN_M5 K2 / PLAN_R5 S7 until the owner's spot-check (D2) |
| T2 Commit the Core 5 + AION 2 extension | R6-1, R6-4 | ☐ | Waits for owner decision D1 |
| T3 Matcher: ±요 is close for non-predicate Hangul | R6-2 | ☐ | Core only |
| T4 Make the media deck's glosses unique | R6-2 | ☐ | After T1 is committed |
| T5 Ignore pre-arm audio; no 0 ms mic answers | R6-3 | ☐ | App + one core line |
| T6 Home aurora under the session cover | R6-7a | ☐ | Frontend agent; measure first |

---

## 3. Segments

### T1 · R6-1 + R6-5a · Wire `ko_media`, fix song locators, commit K2

**Problem:**
- `ko_media.json` and `docs/media-verification.md` exist only in the working tree.
- `DeckCatalog.bundledVocabFiles` still has `"ko_media"` commented out, so users never see the deck.
- Song references carry section locators ("verse 2", "chorus", …). The verification table admits these are guesses, because Bugs lyrics pages have no section markers, yet the app shows them to users as facts.

**Files:**
- `Packages/MemoriseCore/Sources/MemoriseCore/Decks/DeckCatalog.swift` (lines 66–73)
- `Packages/MemoriseCore/Sources/MemoriseCore/Resources/Decks/ko_media.json` (untracked)
- `docs/media-verification.md` (untracked)

**Steps:**
1. **Locators.** In `ko_media.json`, set `locator` to `"lyrics"` on every source with `kind: "song"`. Today these are "verse 1", "chorus", "verse 2", "verse", "pre-chorus", "bridge", "outro" and "intro", about 80 references in total.
   - Leave `drama` and `show` locators unchanged ("E5", "E6", "series", "title").
   - The validator only requires `locator` to be non-empty, so `"lyrics"` is valid.
   - In `docs/media-verification.md`, change the locator column of the same rows to `lyrics`. Add one line to the header: "Song locators are `lyrics`: Bugs pages have no section markers, so sections were not verified (R6-5a)."
   - Change nothing else in either file: no ids, ranks, meanings or citations.
2. **Catalog.** In `DeckCatalog.swift`:
   - change `// "ko_media", // M5 K2` to `"ko_media",` and keep it before `"ko_aion2"`;
   - replace the doc comment at lines 66–68 with: `/// Bundled vocab files in display order. The media deck (M5 K2) sits before AION 2.`
3. Build: `swift build` in `Packages/MemoriseCore`, then `xcodegen generate` and an iOS Simulator `xcodebuild`.
4. **Commit:** `K2: ko_media.json (105 entries, 88 verified refs)`.
   - Stage only these three files: `DeckCatalog.swift`, `ko_media.json` and `docs/media-verification.md`.
   - In the commit body, state the targets that were missed: 66 % of entries have a verified reference (target 70 %), and the song/show/drama split is 91/1/8 (target ≈ 50/30/20).
5. **Do not** tick K2 in PLAN_M5 §6 or S7 in PLAN_R5_FIXES §2. They wait for the owner's spot-check (D2).

**Acceptance:**
- `DeckCatalog.builtIn().catalog` contains `ko.media`, directly before `ko.aion2`, and `report.loadFailures` is empty.
- The DEBUG launch shows no deck-issues banner. Home's Korean section lists the media deck between Core/Patterns and AION 2.
- Reveal a media card:
  - "Heard in" rows for songs read "… · lyrics", not a section name;
  - "In a scene" bubbles each have a 🔊 button that speaks;
  - "My snippet" works.
- `grep -c '"locator" : "verse\|chorus\|bridge\|intro\|outro' ko_media.json` returns 0. Allow for the file's JSON spacing.
- **For the tester:** `mediaDeckIsValidAndSlotsBeforeAion2` should assert the **real** catalog order, not a simulated list (R6-1 point 2). That change is the tester's, not part of this commit.

---

### T2 · R6-1 + R6-4 · Commit the Core 5 + AION 2 extension

**Blocked on owner decision D1.** Until this lands, committed `HEAD` still fails the 450 and 140 count assertions.

**Files:**
- `Packages/MemoriseCore/Sources/MemoriseCore/Resources/Decks/ko_core_5.json` (+225 entries, `ko.core.1095`–`ko.core.1319`)
- `Packages/MemoriseCore/Sources/MemoriseCore/Resources/Decks/ko_aion2.json` (+59 entries, `ko.aion2.0082`–`0140`)

**Steps:**
1. Do not edit the content. The reviewer verified that the change is additive only, ids are contiguous, and every verb and adjective has a `conj` class.
2. Run `swift build` and the iOS build.
3. **Commit:** `M4-1b: extend Core 5 to 450 and AION 2 to 140 entries (unverified, R6-4)`.
   - Stage only the two JSON files.
   - In the commit body, give the POS split for the new Core 5 entries: noun 67, verb 55, adverb 38, adjective 18, other 47. Note that the AION additions are all nouns.
   - Also state: "Verification rows and the owner's 15-entry spot-check are still to do (R6-4)."

**Acceptance:**
- `HEAD` passes `swift test` in `Packages/MemoriseCore`. This is the tester's check; the implementor only reports whether it passed.
- No existing id changed. Check with `git diff --stat`, which should show additions only in the two JSON files, and the reviewer's id diff still holds.

---

### T3 · R6-2 · Matcher: the polite 요 form is close for non-predicate Hangul

**Problem:**
- All 105 media entries are `pos: expression`, so `isPredicate` is false and the conjugation rule never applies to them.
- In en→ko typed mode, the natural polite answer is therefore graded **wrong**: 미안해요 for 미안해, 사랑해요 for 사랑해, 고마워요 for 고마워.
- For 1–2-syllable words only a batchim slip is close. For longer words, adding 요 is a jamo distance of 2.

**File:** `Packages/MemoriseCore/Sources/MemoriseCore/Korean/AnswerMatcher.swift`, `hangulVerdict` (around line 99).

**Steps:**
1. In `hangulVerdict`, after `if a == b { return .exact }` and **before** the `isPredicate` block, add:
   ```swift
   // R6-2: the polite 요 added or dropped (미안해요 for 미안해, 진짜요 for 진짜) is the same phrase.
   if !isPredicate, a == b + "요" || b == a + "요" { return .close }
   ```
   `a` and `b` are already NFC-normalised, with spaces and punctuation stripped, so `"보고 싶어요"` vs `"보고 싶어"` compares as `보고싶어요` vs `보고싶어`.
2. Do not add any other suffix rules, such as 해 → 해요 or 요 → 니다. Exactly one trailing 요 only.
3. Extend the `hangulVerdict` doc comment with one bullet: "Non-predicates: the same phrase with the polite 요 added or dropped is close (R6-2)."
4. Append to PLAN.md §17: "R6-2: for non-predicate Hangul, ±요 is close (typed vocab). Exact-required modes (conjugation drill) still grade close as wrong."

**Acceptance (reference rows for the tester; direction en→ko typed vocab, `isPredicate` false):**

| Input | Expected | Verdict |
|---|---|---|
| 미안해요 | 미안해 | close |
| 사랑해요 | 사랑해 | close |
| 괜찮아요 | 괜찮아 | close |
| 보고 싶어요 | 보고 싶어 | close |
| 고마워요 | 고마워 | close |
| 진짜요 | 진짜? | close |
| 고마워 | 고마워요 (if an entry's hangul ends in 요) | close |
| 진짜 | 진짜? | exact (unchanged) |
| 사랑 | 사랑해 | **wrong** (must stay wrong) |
| 미안해요 | 미안 | **wrong** (해요 is two syllables, not one 요) |
| 사랑해요요 | 사랑해 | **wrong** |
| 요 | 진짜 | **wrong** |

- **Predicates are unchanged.** Every R5-1 row still holds: 몰라요/알다 and 없어요/있다 are wrong, 먹어요/먹다 is close.
- **The conjugation drill is unchanged**, because its specs are `exactRequired: true`, so close still grades wrong.
- `swift build` passes.

---

### T4 · R6-2 · Make every gloss in the media deck unique

**Prerequisite:** T1 is committed.

**Problem:** seven pairs of entries share a meaning string, so in en→ko the equally correct sibling is graded wrong, and the prompt itself is ambiguous.

**Fix approach:** add a short parenthetical to the colliding meanings.
- `AnswerMatcher.englishVerdict` strips parentheticals (`stripParentheticals`), so ko→en grading still accepts the plain gloss: "don't worry" stays exact for 걱정 마.
- The en→ko prompt now tells the two entries apart.

**File:** `Packages/MemoriseCore/Sources/MemoriseCore/Resources/Decks/ko_media.json`. Change only `meanings`; never change `id`, `hangul` or `rank`.

**Steps:**
1. Replace the `meanings` arrays exactly as follows:

   | id | hangul | new `meanings` |
   |---|---|---|
   | ko.media.0028 | 안녕 | `["hi (casual)", "bye (casual)"]` |
   | ko.media.0041 | 잘 가 | `["bye (to someone leaving)", "take care (to someone leaving)"]` |
   | ko.media.0030 | 걱정하지 마 | `["don't worry (full form)"]` |
   | ko.media.0080 | 걱정 마 | `["don't worry (short)"]` |
   | ko.media.0031 | 말해줘 | `["tell me (please)"]` |
   | ko.media.0032 | 말해봐 | `["tell me (go ahead)", "go on, say it"]` |
   | ko.media.0036 | 관심 없어 | `["I'm not interested", "I don't care (no interest)"]` |
   | ko.media.0045 | 신경 안 써 | `["I don't care (not bothered)", "I'm not bothered"]` |
   | ko.media.0046 | 내 말 믿어 | `["trust me (take my word)", "believe what I say"]` |
   | ko.media.0078 | 믿어 줘 | `["believe me", "trust me (please)"]` |
   | ko.media.0062 | 힘을 내 | `["cheer up (lit. find strength)", "keep your strength up"]` |
   | ko.media.0099 | 힘내 | `["cheer up (short)", "hang in there"]` |
   | ko.media.0072 | 대박 | `["awesome", "no way! (amazed)"]` |
   | ko.media.0093 | 거짓말 | `["lie", "liar!", "no way! (disbelief)"]` |

2. Run a one-off check, a Python one-liner that is not committed: lower-case and trim every meaning in the deck, including its parenthetical, and confirm that no string appears in two entries. If any other collision turns up, resolve it the same way and list it in the commit body.
3. **No validator change.** `DeckValidator` has no warning severity, and core decks legitimately share glosses. Uniqueness is a media-deck content rule that the tester encodes. Record this in §17 with one line: "R6-2: media-deck gloss uniqueness is a content test, not a validator rule."
4. **Commit:** `R6-2: unique glosses in the media deck`. Stage only `ko_media.json`.

**Acceptance:**
- No two `ko.media.*` entries share a meaning string (case-insensitive, trimmed, parenthetical included). This is a reference rule for the tester.
- ko→en typed: "don't worry" is **exact** for both 걱정하지 마 and 걱정 마, and "cheer up" is exact for both 힘을 내 and 힘내.
- en→ko prompts show the parenthetical, for example "cheer up (short)".
- The DEBUG launch shows no deck-issues banner.

---

### T5 · R6-3 · Ignore audio from before the prompt; never record a 0 ms mic answer

**Problem:**
- Since R5-3, the ring keeps filling while the detector is inactive.
- On arming, the first analysed frames are mostly audio from before the prompt: the reveal playback or the still-ringing previous note. A sustained note becomes stable about 32 ms after the prompt appears.
- If its pitch class fits the new card, the note answers it. `answerEvaluated` clamps the onset to the prompt start, so the answer is recorded as `responseMs = 0`, which feeds `ewmaResponseMs` and `bestResponseMs`.

**Files:**
- `App/Sources/Services/PitchDetector.swift` (the `PitchFrame` struct, and around lines 95–110)
- `App/Sources/Services/MicAnswerController.swift` (`setListening`, `MicFrameTracker`)
- `Packages/MemoriseCore/Sources/MemoriseCore/Session/SessionEngine.swift` (`answerEvaluated`, line 222)

**Steps:**
1. **`PitchFrame`:** add `let windowStartSeconds: Double`, documented as "Host-clock seconds of the oldest sample in the analysed window."
   - In the analysis path, compute it from the same newest-sample time that `hostSeconds` uses: `newest − Double(Self.frameLength − 1) / sampleRate`.
   - Fill it in **both** `PitchFrame(...)` initialisers: the silent/no-pitch one (line ~110) and the pitched one.
   - Leave `hostSeconds` (the onset estimate) unchanged.
2. **`MicFrameTracker`:**
   - add `private var armedAt = -Double.infinity`;
   - change `setListening(_ on: Bool)` to `setListening(_ on: Bool, at hostSeconds: Double)`, and inside the lock set `armedAt = on ? hostSeconds : -.infinity`;
   - in `process`, **after** the level smoothing and the level-publish block, and **before** the pitch/run logic, add:
     ```swift
     // R6-3: a window that starts before arming holds the previous card's audio.
     guard f.windowStartSeconds >= armedAt else { return out }
     ```
     It returns without touching `runMidi`, `runCount` or `reportedMidi`, so the run starts fresh on the first clean frame.
3. **`MicAnswerController.setListening`:** call `tracker.setListening(on, at: Self.hostNowSeconds)`. `hostNowSeconds` and the tap's `AVAudioTime` host time share the same base. Keep `detector?.setActive(on)`, and let the ring keep filling: that part of R5-3 is correct.
4. **`SessionEngine.answerEvaluated` (defence in depth, core):**
   ```swift
   let start = promptShownAt ?? cardSelectedAt
   // R6-3: an onset before the prompt is not a real response time; record the answer untimed.
   let timed = countsTime && at >= start
   let ms = (max(at, start) - start).wholeMilliseconds
   ...
   return gradeRevealed(correct: correct, gradeMs: 0, countsTime: timed)
   ```
   - The answer still counts as correct.
   - Only the time update to `ewmaResponseMs` and `bestResponseMs` is skipped.
   - The saved `Attempt.responseMs` stays at 0. Adding an "untimed" flag to `Attempt` would be a persisted-schema change and is **out of scope**. Note this in §17.
5. Update the `MicFrameTracker` doc comment ("stale stable notes are dropped on main") to mention the arm-time filter.
6. Append to PLAN.md §17, under the R4-5/R5-3 entry: "R6-3: frames whose window starts before arming are ignored; an onset before the prompt is recorded untimed (`countsTime: false`)."

**Acceptance:**
- **Engine reference rows (for the tester):**

  | Case | Result |
  |---|---|
  | `answerEvaluated(correct: true, at: start − 50 ms, countsTime: true)` | the attempt is correct, `responseMs == 0`, and `ItemStats.ewmaResponseMs` and `bestResponseMs` are **unchanged** |
  | the same call with `at: start + 800 ms` | the time is recorded as today |

- **Device, Fretboard Notes, mic mode, "Play note on reveal" on:**
  - let the reveal note or your own note ring through into the next card;
  - the next card is **not** answered instantly, and no "Heard X" appears in the first instant;
  - a note played after the prompt appears is detected with no delay you can notice (the first clean frame arrives about 43 ms after arming).
- The mic timeout, the level meter and touch fallback behave as before.
- The iOS build has 0 new warnings. Adding the `PitchFrame` field must not break any `Sendable` conformance.

---

### T6 · R6-7a · Home aurora under the session cover (frontend agent)

**Measure first. Do not change code unless the measurement shows ticking.**

1. Start a session from Home. `HomeView.swift:143` presents it with `.fullScreenCover`.
2. Check whether Home's `AuroraBackground` keeps redrawing behind the cover:
   - use Instruments (the Core Animation FPS / GPU track); **or**
   - set a temporary `Self._printChanges()` or breakpoint inside the aurora `Canvas` closure.
3. **If it ticks:** in `HomeView`, pass `animated: <no session presented>` to its `AuroraBackground`, using whichever state drives the `fullScreenCover` (e.g. `launch == nil`). Do the same for any other screen that presents `SessionView` over an animated aurora; grep for `SessionView(`.
4. **If it doesn't tick:** change nothing. Report "R6-7a: measured, no redraw under cover" to the planner for §17.

**Acceptance:**
- During a session, there is no 30 Hz redraw from Home's background.
- After the session is dismissed, Home's aurora resumes animating.
- With Reduce Motion on, nothing changes.
- **Commit (only if there was a code change):** `R6-7a: pause Home aurora under the session cover`.

---

## 4. Planner follow-ups (not implementor work)

- **P1 · R6-6 (carried over from PLAN_R5_FIXES P1).** The trigger has been met (`9339c46`). Fold the R4/R5/R6 decisions into the normative sections:
  - PLAN.md §9.2: the `choice` row should say "time EWMA: no"; also the paragraph below the table;
  - PLAN.md §11.5d;
  - PLAN_M4 M4-0 step 2: `countsTime` is per answer, via `ok(countsTime:)`;
  - the PLAN.md §15 M4 status line (Core 5 is done, at 450 entries);
  - the definition of "close" for vocab (R4-2, R5-1, R6-2);
  - remove `undoLastGrade` from §9.3, §12 S6 and the §17 tracker (D2);
  - README.md:24 and :31 (R3-7).
- **P2 · R6-4.** Add a §17 entry and a tracker line for "M4-1b: Core 5 extension (226–450) + AION 2 extension (82–140)". Mention the six phrases shared with core decks (어떡해, 안녕, 화이팅, 거짓말, 오빠, 언니) and that they have separate stats. Also assign the content agent to:
  - add verification rows for `ko.core.1095`–`1319` in `docs/core-verification.md`, and fix its "225 entries" header;
  - create an AION table.
- **P3 · R6-6.** Schedule **K5** (integration and QA) after T1. Step 2 (ko→en default) is already met. Steps 1, 3 and 4 remain: Home placement, the README QA checks for K3/K4, and an M5 tracker row in PLAN.md §17.

## 5. Owner decisions

| # | Decision | Recommendation |
|---|---|---|
| D1 | Commit the Core 5 / AION 2 extension (T2) **before** its verification rows and spot-check exist? | **Yes.** It makes `HEAD` green; the ids are already stable and the change is additive; verification follows as P2. If no, the tester must lower the count assertions to 225 and 81 until then. |
| D2 | K2 ships with 66 % verified coverage and a 91/1/8 split (targets: 70 % and ≈ 50/30/20)? | Do the 10-reference spot-check first, preferring song rows and checking the NewJeans 7-digit Bugs ids and the FIRE page year (R6-5c). If at most 1 failure, tick K2 and S7, and raise coverage in K2b. Record the decision in §17. |
