# Memorise — M1.1 Review-Fix Plan

- **Date:** 2026-11-16
- **Source:** `CODE_REVIEW.md` (M1 review, 2026-11-16): 3 × P1, 8 × P2, 8 × P3, 4 × P4.
- **Owner of this file:** planner. Implementor agents execute segments **F0–F9** in order and tick the tracker (§4). Reviewer/tester agents report back against the acceptance criteria listed in each segment.
- **Conventions:** PLAN.md §16 and `CLAUDE.md` still apply. One segment = one commit, with the message `F<n>: <summary>`. Record any deviation in PLAN.md §17 Decision log.

---

## 1. Coverage map (review item → segment)

| Review item | Segment | | Review item | Segment |
|---|---|---|---|---|
| P1-1 Sharps behaves like Mixed | F2 | | P2-7 Stats tab reloads all attempts | F7 |
| P1-2 Sessions dropped on config decode fail | F5 | | P2-8 Closed deck-type sites | **F10 (M2-0, deferred)** |
| P1-3 No automated verification | F1 | | P3-1 Default max fret ignored | F9 |
| P2-1 Scheduler fallback ignores exclusions | F3 | | P3-2 Stale tag filters | F9 |
| P2-2 Double-tap grades the card | F4 | | P3-3 Timed progress bar stalls | F9 |
| P2-3 ModelActor on main thread | F6 | | P3-4 Pools regenerated in view bodies | F9 |
| P2-4 Silent degradations | F6 (store), F8 (decks, recorder) | | P3-5 Korean voice cached forever | F9 |
| P2-5 Keyboard focus not restored | F8 | | P3-6 No fetch indexes | **No action** (iOS 17 target; F7 removes the hot query) |
| P2-6 Killed sessions marked abandoned | F6 | | P3-7 `attempts(forDeck:)` order contract | F7 |
| | | | P3-8 Fire-and-forget launch sweep | F6 |
| | | | P4 (4 items) | F1 (CI name), F9 (rest) |

## 2. Order and dependencies

```
F0 ─► F1 ─┬─► F2 ─► F3 ─► F4      (core correctness, test-first)
          ├─► F5 ─► F6 ─► F7      (persistence / performance)
          └─► F8 ─► F9            (robustness, polish)
F10 = first task of M2 (after all of the above)
```

- **F1 must land first.** F2–F5 each start with a failing test that reproduces the review finding.
- **F5 must precede any change to a persisted `Codable` type**, including anything in F6/F7.
- The three branches after F1 can be done in parallel by separate agents. They touch disjoint files, except `AppEnvironment.swift`, which is touched by F6 and F8; do F6 before F8.

## 3. Owner decisions required before starting

| # | Decision | Planner recommendation |
|---|---|---|
| D1 | **Reverse the §17 "no tests" decision** for `MemoriseCore` (F1). | **Yes.** Core-only Swift Testing target, no UI tests. The review shows every P1/P2 core bug would have been a short test. |
| D2 | **Commit the M1 implementation** as a baseline (F0). It is currently untracked on `review/m1-code-review`. | Commit it on the default branch `claude/korean-music-flashcard-plan-ffx6z5`, then branch `fix/m1.1` for F1–F9, so every fix is a reviewable diff. |
| D3 | Pronunciation audio plays through the silent switch (`.playback`). Keep it? | Keep `.playback` (pronunciation is the point of tapping play). F9 only adds deactivation. |

If D1 is **No**, skip F1 and drop the "Tests" step of each segment. The fixes themselves still stand, but the acceptance criteria then become manual checks only.

---

## 4. Tracker

| Segment | Covers | Status | Notes |
|---|---|---|---|
| F0 Baseline commit & branch | D2 | skipped | no commits requested by owner |
| F1 Core test target + CI | P1-3, P4 (CI) | skipped | D1 = No (owner: no tests) |
| F2 Mixed-spelling fix | P1-1 | ☑ | |
| F3 Scheduler fallback | P2-1 | ☑ | |
| F4 Grade lockout | P2-2 | ☑ | |
| F5 Tolerant config decoding | P1-2 | ☑ | golden fixtures skipped (no tests) |
| F6 Store bootstrap off main | P2-3, P2-6, P3-8, P2-4 (store) | ☑ | step-1 measurement skipped |
| F7 Stats tab loading | P2-7 (phase A), P3-7 | ☑ | phase B deferred |
| F8 Robustness | P2-4 (decks, recorder), P2-5 | ☑ | |
| F9 Low / polish batch | P3-1..5, P4 | ☑ | P4-d n/a (F1 skipped) |
| F10 Deck extensibility (M2-0) | P2-8 | planned | → PLAN_M2_MUSIC.md M2-0a/0b/0c |

---

## 5. Segments

### F0 — Baseline commit & branch
**Goal:** a clean git baseline so every fix is a small diff.
1. Check out `claude/korean-music-flashcard-plan-ffx6z5` (carry the untracked files along).
2. Ensure `.build/` is ignored (it already is in `.gitignore`) and the `.xcodeproj` is not committed.
3. Commit `App/`, `Packages/`, `project.yml`, `README.md`, `CLAUDE.md`, `.github/` and `PLAN.md` with the message `M1: implementation (S0–S13)`.
4. Merge or cherry-pick `CODE_REVIEW.md` (commit `a848cf4`) and this file onto the default branch.
5. Create `fix/m1.1` from there.

**Done when:** `git status` is clean; `swift build` passes in `Packages/MemoriseCore`; `xcodegen generate` + an Xcode simulator build succeed.

---

### F1 — Core test target + CI (P1-3, P4 CI)
**Goal:** deterministic tests for core logic, run in CI on every push.

**Files:** `Packages/MemoriseCore/Package.swift`, new `Packages/MemoriseCore/Tests/MemoriseCoreTests/*.swift`, `.github/workflows/core-tests.yml`, PLAN.md §13/§17.

**Steps**
1. Add `.testTarget(name: "MemoriseCoreTests", dependencies: ["MemoriseCore"])`. Use **Swift Testing** (`import Testing`).
2. Add `Tests/MemoriseCoreTests/TestSupport.swift` with these helpers:
   - `makeEngine(deck:options:stats:seed:)` returning `(SessionEngine, ManualClock)`, with a fixed `wallClock` closure (e.g. `Date(timeIntervalSince1970: 1_800_000_000)`).
   - `fretboardCards(_ options: FretboardOptions) -> [Card]`.
   - `drive(_ engine:, clock:, grades: [Bool], step: Duration)`. For each grade it calls `promptDidAppear`, advances the clock, calls `ok`, advances the clock again, then calls `grade`. **Note:** after F4 the per-grade advance must exceed the lockout.
3. Add the baseline test files. Each must pass against the current code, except the ones marked *(red)*. Those reproduce review bugs and are marked `.disabled("F2")` / `.disabled("F3")` until their segment enables them.
   - `DeckContentTests`: `DeckValidator.validate` returns `[]` for every file in `DeckCatalog.bundledVocabFiles`; ids are unique **across** files; entry counts are 205 / 81.
   - `FretboardDeckTests`: `itemKey` is spelling-independent (C♯/D♭ → the same key); card count is 42 for naturals × 6 strings at 0…12 and 72 for all notes; *(red, F2)* with `.sharps`, `present` never yields a flat over 1 000 seeded draws.
   - `SchedulerTests`: the same seed gives the same sequence; no repeat within K over 10 000 draws; *(red, F3)* see the F3 test.
   - `EngineTests`: a wrong card is retried after 3–5 cards and does not update stats a second time; the session finishes at N counted cards; `quit` with 0 graded gives `.abandoned`.
4. CI: rename the workflow to `Core tests (Linux)` and change the step to `swift test`. Keep `swift build -c release` as a second step so release-only compile errors are still caught.
5. PLAN.md: in §17, mark the "no tests" decision as reversed (dated entry referencing D1). §13 is unchanged.

**Out of scope:** app/UI test targets. SwiftData store tests are optional; they can come later as an `App/Tests` XCTest target with an in-memory `ModelContainer`.

**Done when:** `swift test` passes locally and in CI, with the red tests showing as disabled.

---

### F2 — Mixed-spelling fix (P1-1)
**Goal:** `.sharps` always shows ♯, `.flats` always ♭, `.mixed` random per presentation. The `Deck` protocol is unchanged (the protocol change is F10).

**Files:** `Domain/Card.swift`, `Decks/FretboardNotesDeck.swift`, tests.

**Steps**
1. Add `public let randomizeSpelling: Bool` to `FretboardNotePrompt`. Give it an init parameter with default `false`, and have `respelled(_:)` preserve it.
2. In `FretboardNotesDeck.cards(options:)`, pass `randomizeSpelling: o.accidentalSpelling == .mixed`.
3. In `present(_:using:)`, add `p.randomizeSpelling` to the guard before the coin flip. Keep the existing `p.spelling.accidental == .sharp` condition.
4. Update the doc comment on `present` to match.

**Tests:** enable the F2 red test. Over 1 000 seeded draws for each spelling: `.sharps` → 0 flats; `.flats` → 0 sharps; `.mixed` → both spellings appear, with each between 35 % and 65 % of accidental draws. Item keys are identical across all three.

**Done when:** tests are green; on device, *All notes + Sharps* shows no ♭ prompts.

---

### F3 — Scheduler fallback respects exclusions and gating (P2-1)
**Goal:** the fallback never picks a pending-retry card or a gated unseen card. A pending retry is preferred over a cooldown-breaking fallback pick.

**Files:** `Scheduling/Scheduler.swift`, `Session/SessionEngine.swift`, tests. PLAN §10.6 has already been rewritten by the planner; implement it as written.

**Steps**
1. In `Scheduler.nextCard`, add `allowFallback: Bool = true`. When the cooldown loop finds nothing:
   - if `!allowFallback`, return `nil`
   - otherwise build candidates from the **allowed set**: not in `excluded`, and either seen or in `eligibleNew`. Exclude the previous card. If that is empty, use the allowed set including the previous card. If that is still empty, return `nil`.
   - pick uniformly from the candidates with `rng`.
   - Compute the allowed set once (the same predicate as the weight loop, without the weight).
2. Change `SessionEngine.presentNext()` to:
   1. take a due retry (unchanged)
   2. otherwise call `nextCard(... allowFallback: false)` and show the pick if there is one
   3. otherwise, if retries are pending, flush the earliest pending retry (smallest `dueAt`) whose key ≠ `history.last?.key`
   4. otherwise call `nextCard(... allowFallback: true)` and show the pick if there is one
   5. otherwise, flush any remaining retry, even back-to-back, rather than ending the session
   6. otherwise return `false`
3. Doc comments: update `nextCard`'s doc to describe the new fallback.

**Tests (enable the F3 red test)**
- The review's trace: a 4-card pool, K = 3, retries on, a deterministic seed; card 1 and card 2 are wrong. Assert the following over 200 seeds:
  - no card is shown as a counted pick while it is in `pendingRetries`
  - each wrong card's `ItemStats.attempts` increases by exactly 1 per counted show
- Gated vocab: a pool of 30 unseen entries with `newPerSession` = 2 and every eligible card blocked by cooldown. The fallback never returns a card outside `eligibleNew`.
- A 1-card pool with retries on: the session still reaches its length, with no infinite loop and no crash.

**Done when:** tests are green; the §10.7 tests from F1 are still green.

---

### F4 — Grade input lockout (P2-2)
**Goal:** a grade arriving less than 250 ms after reveal is ignored, with no haptic and no state change. This lives in the engine, so it applies to taps, swipes and keys alike.

**Files:** `Scheduling/SchedulerConstants.swift`, `Session/SessionEngine.swift`, `App/Sources/Features/Session/SessionViewModel.swift`, tests, PLAN §9.3.

**Steps**
1. Add `public var gradeLockoutMs = 250` to `SchedulerConstants`, with a doc comment.
2. Engine: add `public var canGrade: Bool`. It is true when the state is `.revealed` and `(clock.now() - revealedAt) >= .milliseconds(gradeLockoutMs)`. `grade(correct:)` returns `[]` and leaves the state unchanged when `!canGrade`. A pause/resume already shifts `revealedAt`, so that path needs no change.
3. VM `grade(correct:)`: guard on `engine.canGrade` **before** stopping speech or firing haptics.
4. PLAN §9.3: add one line describing the lockout. Add a §17 entry noting that `undoLastGrade` is still deferred.

**Tests:** `grade` at +100 ms after `ok` → no effects, still `.revealed`; at +300 ms → graded. A pause during reveal followed by a resume does not shorten the lockout.

**Device check:** rapid double-tap on OK → the reveal stays on screen.

---

### F5 — Tolerant decoding of persisted config (P1-2)
**Goal:** adding or changing a field on any persisted config type never hides history again, and a decode failure never drops a session.

**Files:** `Domain/SessionConfig.swift`, `Decks/FretboardNotesDeck.swift` (`FretboardOptions`), `Korean/Vocab.swift` (`VocabOptions`), `Domain/Deck.swift`, `App/Sources/Persistence/SwiftDataModels.swift`, tests, PLAN §16.

**Steps (in this order)**
1. **Golden fixtures first, before touching any type.** Write a test that encodes these with the *current* code:
   - one fretboard `SessionConfig` (non-default strings, `.all`, `.mixed`, `0...15`, `.minutes(5)`, `.strong`, retries off)
   - one vocab `SessionConfig` (`.both`, `newPerSession` 5, tags `["combat"]`)
   Paste the exact JSON output into `Tests/.../Fixtures.swift` as string literals, and add a test that decodes them and compares them to the originals. This pins the on-disk format: `DeckOptions` keeps its synthesised shape (`{"fretboard":{"_0":{…}}}`), so **do not hand-write `DeckOptions` coding**.
2. Hand-write `init(from:)` for `SessionConfig`, `FretboardOptions` and `VocabOptions` (keep synthesised `encode`):
   - every property uses `decodeIfPresent(...) ?? <init default>`
   - enum-typed properties (`noteSet`, `accidentalSpelling`, `direction`, `focus`, `length`) are wrapped in `(try? …) ?? default`, so an unknown future raw value doesn't fail the whole decode
   - `SessionConfig.deckID` stays required
   - `SessionConfig.options`: `(try? …) ?? DeckOptions.fallback(for: deckID)`
3. In `Domain/Deck.swift`, add `public static func fallback(for id: DeckID) -> DeckOptions`. It returns `.fretboard(FretboardOptions())` for `FretboardNotesDeck.deckID` and `.vocab(VocabOptions())` otherwise. *ASSUMPTION:* this closed switch is temporary; F10's registry absorbs it.
4. `SDSession.core(decoder:)` returns a non-optional `SessionRecord`. On decode failure it logs `.error` with the session id and uses `SessionConfig(deckID:, options: .fallback(for:))`. Then replace the `compactMap` calls in `SwiftDataStatsStore` with `map`.
5. PLAN §16: add the convention *"Persisted `Codable` types use hand-written tolerant `init(from:)`; every new property needs a default; never rename coding keys or enum raw values."* Mirror it in `CLAUDE.md`.

**Tests:**
- the golden fixtures round-trip
- the fixtures with an extra unknown key decode
- the fixtures with a property removed decode to the default
- `noteSet: "chromaticPlus"` decodes as `.naturals`
- a config whose `options` is garbage decodes with the fallback options

**Done when:** the tests are green and existing on-device history still shows after installing the build (manual check on the owner's phone).

---

### F6 — Store bootstrap off the main thread; launch sweep fix (P2-3, P2-6, P3-8, P2-4 store part)
**Goal:**
- SwiftData work never runs on the main thread
- the launch sweep finishes before any read or write
- killed sessions that have graded cards count as completed
- the user is told when data is not being persisted

**Files:** new `App/Sources/Persistence/DeferredStatsStore.swift`, `AppEnvironment.swift`, `SwiftDataStatsStore.swift`, `Persistence/StatsStore.swift`, `Persistence/InMemoryStatsStore.swift`, `Features/Home/HomeView.swift`, tests.

**Steps**
1. **Measure first (P2-3 is "plausible").** In a scratch build, log `Thread.isMainThread` inside `SwiftDataStatsStore.save(_ attempt:)` and run one session on device or simulator. Record the result in the PR description. Implement steps 2–5 regardless: they also fix P3-8 and P2-4.
2. Core: rename `markInProgressSessionsAbandoned()` to `closeInterruptedSessions()`. The rule for each `.inProgress` session:
   - with ≥ 1 attempt where `isCounted`: set the status to `.completed` and `endedAt` = the max over its attempts of `shownAt + (responseMs + gradeMs) ms`
   - otherwise: set the status to `.abandoned` and `endedAt` = the last attempt's `shownAt`, or `startedAt` if there are no attempts
   Implement this in both `InMemoryStatsStore` and `SwiftDataStatsStore` (one `fetch` of attempts per session; the expected number of such sessions is 0–1).
3. App: add `final class DeferredStatsStore: StatsStore, Sendable`:
   - It holds `let ready: Task<(store: any StatsStore, persistent: Bool, error: String?), Never>`, created with `Task.detached(priority: .userInitiated)`.
   - Inside the task: make the container, construct `SwiftDataStatsStore` **inside the detached task**, `try await closeInterruptedSessions()` (log on failure), then return it.
   - On a container failure, return an `InMemoryStatsStore` with `persistent: false` and the error text.
   - Every protocol method forwards: `try await ready.value.store.<method>(…)`.
   - Expose `var status: (persistent: Bool, error: String?) { get async }`.
4. `AppEnvironment.live()` wraps the store in `DeferredStatsStore` and removes the fire-and-forget `Task`. Add `private(set) var persistenceWarning: String?`, set in a `Task` that awaits `status`.
5. `HomeView`: when `persistenceWarning != nil`, show a non-dismissible banner at the top: "Progress isn't being saved this session. Restart the app; if this persists, export your data from Settings." Give it an accessibility identifier.

**Tests (core):** `InMemoryStatsStore.closeInterruptedSessions`:
- a session with 2 counted attempts becomes `.completed`, with the correct `endedAt`
- a session with only interrupted attempts becomes `.abandoned`

**Done when:**
- the measurement from step 1 is recorded
- after F6, the same log shows `false`
- killing the app mid-session and relaunching shows the session as completed in History, with a non-zero duration

---

### F7 — Stats tab loading (P2-7 phase A, P3-7)
**Goal:** the Stats tab never pulls every attempt onto the main actor; it reloads only when visible and stale; history summaries load one session at a time.

**Files:** `Persistence/StatsStore.swift`, `Persistence/InMemoryStatsStore.swift`, `Stats/SessionSummary.swift` (or a new `Stats/SessionTrendPoint.swift`), `App/Sources/Features/Stats/StatsView.swift`, tests.

**Steps**
1. Core: add `public struct SessionTrendPoint: Sendable, Identifiable { session: SessionRecord; baseline: SessionBaseline; graded: Int }`.
2. Add `func trendPoints(for deck: DeckID) async throws -> [SessionTrendPoint]` as a protocol requirement, with a **default implementation in the extension**. It fetches sessions and `attempts(forDeck:)`, groups them, and builds points for `.completed` sessions. This runs in a nonisolated async context, so it runs off the main actor. `SwiftDataStatsStore` uses the default.
3. P3-7: change the protocol doc of `attempts(forDeck:)` to "ordered by `shownAt`, then `index`", and make `InMemoryStatsStore` sort the same way.
4. `DeckStatsData`: drop `attemptsBySession`. It loads `sessions`, `stats` and `trendPoints` concurrently.
5. History detail: the `navigationDestination` shows a new private `SessionHistoryDetail(session:, previous:)` view. That view `.task`-loads `store.attempts(for: session.id)` and then renders `SummaryView`, with a `ProgressView` while loading. `previous` = the last point before that session.
6. Visibility gating: track `isVisible` (`onAppear`/`onDisappear`) and `loadedKey`. The `.task(id:)` key includes `isVisible`; `load()` returns early unless `isVisible && loadedKey != (deck, dataVersion)`.

**Phase B (deferred, not in this batch):** store the baseline numbers on `SDSession` through `SchemaV2` and a lightweight migration. Trigger: a measured `trendPoints` time above 150 ms on device, or the first SchemaV2 change for any other reason. Must follow F5.

**Tests:** for `trendPoints` on `InMemoryStatsStore`: abandoned sessions are excluded, `graded` counts only `isCounted`, and the order is by `startedAt`.

**Done when:**
- finishing a session while on the Practice tab triggers no stats load (verify with a log)
- opening the Stats tab loads once
- tapping a history row shows the correct summary

---

### F8 — Robustness: deck loading, recorder errors, keyboard focus (P2-4 rest, P2-5)
**Files:** `Decks/DeckCatalog.swift`, `AppEnvironment.swift`, `Features/Home/HomeView.swift`, `Features/Session/SessionViewModel.swift`, `Features/Session/SessionView.swift`, `Features/Summary/SummaryView.swift`.

**Steps**
1. **Per-file deck loading.** Replace `builtIn() throws` with `public static func builtIn() -> (catalog: DeckCatalog, issues: [String])`:
   - each file is loaded in its own `do/catch`; a failure adds `"<file>: <error>"` to `issues` and skips only that deck
   - `DeckValidator` runs in **all** configurations; its errors are appended to `issues`, but the deck is still loaded
   - the `#if DEBUG assert` is kept
   - update `live()` and `preview()`
2. `AppEnvironment` gains `startupIssues: [String]`. `HomeView` shows a dismissible warning row ("Some decks couldn't be loaded") when it is non-empty, with the details in a disclosure.
3. **Recorder errors.** `SessionViewModel` gains `private(set) var saveFailures = 0`. The `SessionRecorder` `onError` closure keeps the log and also does `Task { @MainActor [weak self] in self?.saveFailures += 1 }`. `SummaryView` gains `saveFailures: Int = 0` and shows a warning row "N answers couldn't be saved" when > 0. History detail passes 0.
4. **Focus (P2-5).** In `SessionContent`, re-assert `keyboardFocused = true`:
   - `.onChange(of: phaseKey)`
   - `.onChange(of: scenePhase)` when the phase becomes `.active`
   - `.onChange(of: confirmQuit)` when it becomes `false`
   - `.onChange(of: vm.showVoiceHint)` when it becomes `false`
   Keep the existing `onAppear`.

**Tests (core):** with a missing file name injected (add an internal `builtIn(files:)` overload for testability), `builtIn` returns the other decks plus one issue.

**Device check:** with a Bluetooth keyboard: open the End-session dialog, choose *Keep going*, press Space → OK is accepted. Background and foreground the app, press Space → it resumes.

---

### F9 — Low-priority and polish batch (P3-1…P3-5, P4)
One commit, or one per bullet if preferred. Each fix is small.

| Item | Change |
|---|---|
| P3-1 | Settings: rename the picker label to "Max fret for new setups". Add a footer: "Decks you've already practised keep their last settings." (Behaviour unchanged: the saved config wins. *ASSUMPTION:* simpler than tracking edit timestamps.) |
| P3-2 | `initialConfig(for:)`: when the deck is a `VocabDeck`, intersect `options.tags` with `deck.allTags` before returning a saved config. |
| P3-3 | `SessionView.topBar`: for `.minutes` sessions, wrap `ProgressView(value: vm.progress)` in `TimelineView(.periodic(from: .now, by: 1))`. |
| P3-4 | `SessionSetupView`, `WeakestWordsSection`, `HomeView`: compute pools, medians and sorted lists once in `@State`, refreshed by `.onChange` / `.task(id:)` keyed on options or stats. No `deck.cards(...)` call inside `body`. |
| P3-5 | `SpeechService`: make `koreanVoice` re-queryable (`func refreshVoices()`). Call it from `RootView` on `scenePhase == .active`. |
| P4-a | `SpeechService.deactivate()`: `setActive(false, options: .notifyOthersOnDeactivation)`. Call it from `SessionView.onDisappear`. Keep `.playback` (D3). |
| P4-b | `SessionSummary`: `fastest` / `slowest` sort by `constants.clamp(responseMs)`, consistent with the rest. |
| P4-c | `Fmt.delta(ms:)`: exact 0 (after rounding to display precision) renders as `"= 0.00 s"` with no arrow. Apply the same rule to `delta(percentPoints:)`. |
| P4-d | The CI rename is already done in F1. |

**Tests:** P4-b ordering with one attempt at 40 000 ms (clamped to 30 000). P3-2 is covered by a small helper test if the intersection is moved into core (`VocabOptions.sanitized(for:)`, recommended).

---

### F10 — Deck extensibility (P2-8) · **first task of M2, design only here**
> **Superseded by [PLAN_M2_MUSIC.md](PLAN_M2_MUSIC.md) M2-0a/0b/0c** (2026-11-16). The outline below is kept for history.
Do not implement in M1.1. Outline for the M2 planner pass:
1. `Deck` gains:
   - `func present(_ card: Card, options: DeckOptions, using rng: inout SplitMix64) -> Card`; F2's prompt flag can then be removed
   - `func newPerSession(options: DeckOptions) -> Int?`, replacing `config.options.vocab?.newPerSession` in the engine
2. An app-side `DeckUIRegistry` keyed by deck kind supplies the setup form, the prompt/answer views, the stats section and the label formatter. This replaces the switches and downcasts in `CardViews`, `Formatters`, `SessionSetupView`, `StatsView` and `AppEnvironment`, plus F5's `DeckOptions.fallback`.
3. Pass the real deck's `Tuning` into `CardViews`, `FretboardView`, `FretboardHeatmap` and `SessionSetupView`. Remove the hard-coded 6 strings / standard tuning.
4. `DeckOptions` stays an enum, because its persisted shape is pinned by F5. New kinds add cases with tolerant decoding.

---

## 6. Assumptions / open questions
- **ASSUMPTION:** a 250 ms grade lockout does not hinder fast keyboard/pedal users; the realistic minimum read-the-answer time is above 300 ms. It is tunable via `SchedulerConstants`.
- ~~**ASSUMPTION:** `DeckOptions` synthesised coding is stable across Swift versions for unlabeled single associated values (`_0`). The F5 golden test guards this.~~ Superseded: the golden test was skipped (D1 = No), so G1 pins the coding by hand instead.
- **OPEN:** whether to add an `App/Tests` XCTest target for `SwiftDataStatsStore` (F6 sweep, F5 fallback mapping). Recommended after F9 if D1 = Yes.

---

# Round 2 — Fix plan for re-review findings N1–N7

- **Date:** 2026-11-16
- **Source:** `CODE_REVIEW.md` Round 2 (commit `7aed4d1`). All Round 1 items are fixed or closed by owner decision, except P2-8 (F10, deferred) and P1-3 (D1 = No).
- **Constraint:** D1 = No, so there is no test target. Each segment's acceptance is **manual or inspection-based**. G1 adds a DEBUG-only launch self-check, which follows the existing `DeckValidator` DEBUG-assert pattern; it is not a test target.
- **Commits:** the owner has asked for none so far (F0 skipped). If commits are wanted, use `G<n>: <summary>`, one per segment.

## 7. Coverage map and order

| Finding | Severity | Segment | Notes |
|---|---|---|---|
| N1 Outer-enum coding unpinned | P2 | **G1** | Must land before F10 / any M2 work |
| N3 Grade lockout has no feedback | P3 | G2 | Pedal users |
| N2 Deck-issues banner wording | P3 | G3 | |
| N6 History detail hides fetch errors | P3 | G3 | |
| N4 Zero-delta format and color | P4 | G4 | |
| N5 `trendPoints` loads all attempts | P3 | G5 | Measure, then decide on Phase B |
| N7 PLAN retry-timing contradiction | P4 | **Done by planner** | PLAN §9.3 and S6 updated in this pass |
| Round-2 step 2: device checks | — | G6 (owner) | P2-2, P2-3, P2-5, P2-6 |

Order: **G1 → G2 → G3 → G4 → G5**. G6 can run any time after a build. Each of G2–G4 touches different files and can be done in parallel.

## 8. Tracker (Round 2)

| Segment | Covers | Status | Notes |
|---|---|---|---|
| G1 Pin `DeckOptions` / `SessionLength` coding | N1 | ☑ | sets encoded sorted for deterministic bytes |
| G2 Grade-lockout feedback | N3 | ☑ | |
| G3 Deck-issue wording + history error state | N2, N6 | ☑ | |
| G4 Zero-delta format/color | N4 | ☑ | |
| G5 Measure `trendPoints` | N5 | code ☑ | log + DEBUG simulator seeder added; numbers not yet measured |
| G6 Device checks | P2-2, P2-3, P2-5, P2-6 | ☐ | owner, on device |
| N7 PLAN wording | N7 | ☑ | planner, 2026-11-16 |

## 9. Segments

### G1 — Pin the persisted shape of `DeckOptions` and `SessionLength` (N1)
**Goal:** the on-disk JSON of the two outer enums is written by hand, not synthesised by the compiler. Editing the enum declarations (labels, payloads, new cases) can then never silently change or break stored history. When a fallback *is* used, it is visible rather than silent.

**Key decision (planner):** keep the **existing** synthesised wire shape exactly, and reimplement it by hand. No new format means no migration and no mixed-format data.
- `DeckOptions`: `{"fretboard":{"_0":{…}}}` / `{"vocab":{"_0":{…}}}`
- `SessionLength`: `{"cards":{"_0":20}}` / `{"minutes":{"_0":5}}`

**Files:** `Domain/Deck.swift`, `Domain/SessionConfig.swift`, new `Domain/PersistedFormatCheck.swift` (core), `App/Sources/Persistence/SwiftDataModels.swift`, `App/Sources/AppEnvironment.swift`, `App/Sources/Features/Summary/SummaryView.swift`, `CLAUDE.md`, PLAN §16.

**Steps**
1. **Capture the current shape before editing.**
   - Temporarily add a DEBUG `print` in `AppEnvironment.live()` that prints `JSONEncoder` output (`.sortedKeys`) for these values, run once in the simulator, and copy the output:
     - `SessionConfig(deckID: FretboardNotesDeck.deckID, options: .fretboard(FretboardOptions(strings: [1,6], noteSet: .all, accidentalSpelling: .mixed, fretRange: 0...15)), length: .minutes(5), focus: .strong, retryWrongCards: false)`
     - a vocab config with `.both`, `newPerSession` 5, tags `["combat"]`, `.cards(30)`
   - Also print one config read back from an existing on-device `SDSession.configData` if any exist.
   - Remove the print. Paste the strings into step 4.
2. **`DeckOptions`:** hand-write `init(from:)` and `encode(to:)`.
   - Outer `CodingKeys`: `fretboard`, `vocab`. Inner `PayloadKeys`: `_0`.
   - Decode: exactly one outer key must be present. Decode the payload from the nested container at `_0`. An unknown or missing key throws `DecodingError.dataCorrupted`.
   - Encode: write the same shape.
   - Doc comment: "**Persisted format — frozen.** Do not rename cases or change payloads without adding a legacy decode path."
3. **`SessionLength`:** do the same, with keys `cards` / `minutes` and payload `_0: Int`.
4. **DEBUG self-check:** in `PersistedFormatCheck.swift`, add `public enum PersistedFormatCheck { public static func run() -> [String] }`.
   - It decodes the captured JSON literals from step 1, checks them against the expected values, and checks that re-encoding gives byte-identical `.sortedKeys` JSON.
   - It returns error strings.
   - Call it from `AppEnvironment.live()` inside `#if DEBUG` with `assert(errors.isEmpty, …)`, mirroring the `DeckValidator` pattern.
   - It is a guard, not a test target, so it stays within D1. *If the owner objects, drop step 4 and rely on steps 2–3 plus the freeze comments.*
5. **Make fallbacks visible.**
   - `SessionConfig` gains `public private(set) var recoveredFields: Set<String> = []`. It is **not** encoded: keep the explicit `CodingKeys` without it.
   - The tolerant `init(from:)` inserts `"options"`, `"length"`, `"focus"` or `"retryWrongCards"` whenever it used a fallback for that field. A missing *optional-by-design* key does not count; only a present-but-undecodable key does. Use `c.contains(key)` to tell the two apart.
   - `SDSession.core(decoder:)`: when `recoveredFields` is non-empty, log `.error` with the session id and the fields.
   - `AppEnvironment.initialConfig(for:)`: ignore a saved config with non-empty `recoveredFields` and use defaults instead.
   - `SummaryView`: when `summary.config.recoveredFields` is non-empty, show a caption under the title: "Some settings of this session couldn't be read; defaults are shown."
6. **Conventions:** in `CLAUDE.md` and PLAN §16, add: "`DeckOptions` and `SessionLength` have a frozen, hand-written wire format. New cases are fine; renaming cases or changing payload types needs a legacy decode path plus an update to `PersistedFormatCheck`."

**Acceptance (manual/inspection)**
- A DEBUG launch passes the self-check.
- Existing history on the owner's phone still shows the same settings per session as before the build: compare 2–3 sessions before and after.
- Experiment, then revert: temporarily rename the `_0` key in the encoder. The DEBUG launch must assert.
- Read the code to confirm `recoveredFields` never appears in the encoded JSON.

---

### G2 — Grade-lockout feedback (N3)
**Goal:** during the 250 ms lockout the grade controls look inactive. A rejected key/pedal press returns `.ignored`. Nothing is buffered, because buffering would distort `gradeMs`.

**Files:** `Session/SessionEngine.swift`, `App/Sources/Features/Session/SessionViewModel.swift`, `App/Sources/Features/Session/SessionView.swift`.

**Steps**
1. Engine: add `public var gradeLockoutRemaining: Duration`. It is `.zero` unless the state is `.revealed`; otherwise `max(.zero, .milliseconds(gradeLockoutMs) - (clock.now() - revealedAt))`. Paused time is already excluded, because `resume` shifts `revealedAt`.
2. VM: make `grade(correct:)` return `@discardableResult Bool`: `false` when rejected, `true` when applied. Add `var gradeLockoutRemaining: Duration` that forwards to the engine.
3. `SessionContent`:
   - Add `@State private var gradeEnabled = true`.
   - In `revealState`, add `.task(id: phaseKey)`: set `gradeEnabled = false`, sleep for `vm.gradeLockoutRemaining`, then set `gradeEnabled = true`. A resume from pause changes `phaseKey`, so it re-arms with the remaining time.
   - Wrong/Correct: `.opacity(gradeEnabled ? 1 : 0.55)` and `.allowsHitTesting(gradeEnabled)`. Animate with `.easeIn(duration: 0.15)`, or none under Reduce Motion.
   - **Do not use `.disabled`.** The bordered-prominent grey would flash on every card.
   - Swipe-to-grade: no change, because the engine guard covers it.
4. `handleKey`, `.revealed` branch: return `vm.grade(...) ? .handled : .ignored`.

**Acceptance (device):**
- After OK, Wrong/Correct visibly fade in over roughly 0.25 s.
- A double-tap on OK leaves the reveal on screen.
- A pedal double-press: the second press is ignored, and a third press after the fade grades the card.
- With Reduce Motion on: no animation, but the lockout still applies.

---

### G3 — Accurate deck-issue messages and a history error state (N2, N6)
**Files:** `Decks/DeckCatalog.swift`, `App/Sources/AppEnvironment.swift`, `App/Sources/Features/Home/HomeView.swift`, `App/Sources/Features/Stats/StatsView.swift`.

**Steps**
1. Core: add `public struct DeckLoadReport: Sendable { public var loadFailures: [String]; public var validationWarnings: [String]; public var isEmpty: Bool }`. `builtIn()` / `builtIn(files:)` return `(catalog, report)`. Load errors go to `loadFailures` and validator output goes to `validationWarnings`.
2. `AppEnvironment`: replace `startupIssues: [String]` with `deckReport: DeckLoadReport`, and log both lists.
3. `HomeView`: show up to two rows, each dismissible for the current launch, each with its own details disclosure:
   - `loadFailures` non-empty: orange, "Some decks couldn't be loaded".
   - `validationWarnings` non-empty: red, "Deck data has problems — stats for affected words may be mixed". It is shown above the load-failure row, because it is the more dangerous of the two (see N2).
4. `SessionHistoryDetail` (`StatsView.swift`):
   - Add `@State private var loadError: String?`.
   - Replace `try?` with `do/catch`. On error: log with `AppEnvironment.log.error` and set `loadError`.
   - Render `ContentUnavailableView("Couldn't load this session", systemImage: "exclamationmark.triangle", description: Text(loadError))` with a **Retry** button that re-runs the load (use a `@State` retry counter in the task id).

**Acceptance (inspection plus a temporary experiment):**
- Temporarily add a bogus file name to `bundledVocabFiles`: only the orange row appears, and the other decks are present.
- Temporarily duplicate an entry id in a JSON copy: only the red row appears. (In DEBUG the assert fires first, so run this in a Release build or comment out the assert for the check.)
- Revert both experiments.

---

### G4 — Zero-delta format and color (N4)
**Files:** `App/Sources/Support/Formatters.swift`, `App/Sources/Features/Summary/SummaryView.swift`, and any other `deltaColor` call sites (grep `Fmt.delta`).

**Steps**
1. `Fmt`: add `static func isZeroDelta(ms: Double?) -> Bool` (`abs(ms).rounded() == 0`) and `isZeroDelta(percentPoints:)` (`Int((abs(p)*100).rounded()) == 0`). These are the single source of the rounding rule.
2. `delta(ms:)`: the zero case returns `"= " + seconds(0.0)`, which renders `"= 0 ms"`. `delta(percentPoints:)` keeps `"= 0 pt"`.
3. Add `static func deltaColor(_ v: Double?, lowerIsBetter: Bool, zero: (Double?) -> Bool) -> Color`:
   - `.secondary` when `nil` or zero
   - otherwise green or red according to `lowerIsBetter`
   (Put it in `Palette` if that is where colors live.) Use it for the accuracy tile (`lowerIsBetter: false`) and the median tile (`true`), and at any other `Fmt.delta` call site found by grep.

**Acceptance:**
- A summary with identical median to the previous session shows grey "= 0 ms".
- An identical accuracy shows grey "= 0 pt".
- Non-zero deltas are unchanged.

---

### G5 — Measure `trendPoints` (N5) and decide on Phase B
**Goal:** a real number, so the deferred Phase B (store baselines on `SDSession` via `SchemaV2`) is triggered by data, not guesswork.

**Files:** `App/Sources/Features/Stats/StatsView.swift`; optional `App/Sources/Features/Settings/SettingsView.swift` (DEBUG only).

**Steps**
1. In `StatsView.load()`, time the `DeckStatsData.load` call with `ContinuousClock` and log `.info`: "Stats load <deck>: <ms> ms, <n> sessions". Keep this permanently; it is cheap.
2. *Optional, DEBUG + simulator only* (`#if DEBUG && targetEnvironment(simulator)`): add a Settings → Developer button, "Seed 1 year of synthetic history". It writes 730 completed sessions × 40 attempts to the **current store** through the normal `StatsStore` API, using a seeded RNG, for the Fretboard deck. **Never compile this into device builds.**
3. Measure on the simulator with the seeded data and on the owner's device with real data. Record both numbers in the PLAN §17 decision log.
4. Decision rule:
   - if the seeded-year load is **> 150 ms** on the simulator, or **> 150 ms** on device at any point, schedule Phase B as segment G7 (the planner will write it; it must follow G1)
   - otherwise close N5 as "measured, acceptable", with the numbers

**Acceptance:** the log line is present, and the two numbers are recorded in §17.

---

### G6 — Device checks for items marked *unverified* (owner)
This is a manual run on the owner's iPhone with a DEBUG build. Record each result (pass/fail plus a note) in PLAN §17.

| Item | Steps | Expected |
|---|---|---|
| P2-3 | Temporarily add `AppEnvironment.log.debug("save main=\(Thread.isMainThread)")` in `SwiftDataStatsStore.save(_ attempt:)`. Run one session and watch Console (filter "Memorise"). Remove the log afterwards. | `main=false` for every save |
| P2-2 / G2 | Double-tap OK quickly, ten times over ten cards | The reveal never auto-grades |
| P2-5 | With a Bluetooth keyboard or pedal: (a) tap ✕, choose *Keep going*, press Space; (b) background and foreground the app, press Space; (c) trigger the no-Korean-voice alert and dismiss it, press → | Every press is accepted |
| P2-6 | Start a 20-card session, grade 5 cards, then kill the app from the app switcher and relaunch | History shows the session as *completed* with 5 cards and a non-zero duration |

If any check fails, report it to the planner with the observed behaviour; it becomes a new G-segment.

## 10. Round 2 — Assumptions / open questions
- **ASSUMPTION (G1):** keeping the legacy `_0` wire shape is preferable to a cleaner `{"kind","value"}` shape, because it needs no migration and old builds can still read new data.
- **ASSUMPTION (G2):** dimming plus hit-test blocking is clear enough feedback; no haptic is added on rejection, to avoid buzzing during normal fast use.
- **OPEN (D1, re-ask):** the reviewer recommends reconsidering tests. The cheapest high-value set is the bundled-deck validator, `present` spelling per option, the starved-pool scheduler trace, and the G1 decoding fixtures. G1's DEBUG self-check covers the last one in the meantime.
- **OPEN (D2, re-ask):** all M1 and M1.1 work is still uncommitted, so there is no rollback point. The planner recommends committing a baseline before G1, because G1 touches the persisted format.
