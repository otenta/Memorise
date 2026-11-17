# Memorise — Code Review

> Newest first: **Round 4** (full review after M2–M5) → **Round 3** (G1–G5 + UI visual pass) → **Round 2** (F2–F9) → **Round 1** (original review). Older rounds are kept unchanged as the audit trail. IDs P1-x come from Round 1, N-x from Round 2, R3-x from Round 3, R4-x from Round 4.

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
