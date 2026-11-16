# Memorise — Code Review (M1)

> **Round 2 (re-review after fixes F2–F9)** is directly below. **Round 1** (the original review) follows it unchanged, as the audit trail. Item IDs (P1-1 …) refer to Round 1.

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
