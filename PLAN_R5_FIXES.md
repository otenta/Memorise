# Memorise — Round 5 Review-Fix Plan

- **Date:** 2026-11-17
- **Source:** `CODE_REVIEW.md` Round 5 (R5-1 … R5-6), plus R3-2, which Round 5 groups into the performance segment.
- **Owner of this file:** the planner. Implementor agents run the segments in §3 and tick the tracker (§2).
- **Conventions:** `CLAUDE.md` and PLAN.md §16 still apply:
  - domain logic stays in `MemoriseCore` (Foundation only);
  - there are no wire-format changes in this plan;
  - never hand-edit the `.xcodeproj`;
  - record every deviation in PLAN.md §17.
- **Commits:** one segment = one commit, with the message `R5-<n>: <summary>`. The exception is S1, which is described in its own section.
- **Tests:** none in this plan. The tester agent owns R4-1. Each segment lists acceptance criteria and reference examples; the tester turns them into golden rows.

---

## 1. Coverage map

| Review item | Segment | Owner |
|---|---|---|
| R5-1 Typed vocab accepts the opposite word | **S1** | implementor (core) |
| R5-2 Home rebuilds every card pool on main | **S2** | implementor |
| R5-3 Pitch detector runs while not listening | **S3** | implementor |
| R3-2 Aurora renders continuously, including in sessions | **S4** | **frontend agent** |
| R5-6a/b/c Polish | **S5** | implementor |
| R5-4 PLAN body contradicts code (+ R3-7 README wording) | P1 | planner (after S1 is committed; see §4) |
| R5-5 M5 unreachable without K2 | **S6** (option b; K2 later) | **frontend agent** |
| R4-1 Tests / CI | none | tester |
| R4-6 Korean content verification | none | process / owner |

**Order:** S1 comes first and blocks the R4 commit. S2, S3, S4, S5 and S6 are independent and can run in parallel. They touch disjoint files, except `AppEnvironment.swift`, which S2 and S5a both touch; do S2 first.

## 2. Tracker

| Segment | Covers | Status | Notes |
|---|---|---|---|
| S1 Exclude negatives from typed predicate matching | R5-1 | ☐ | Blocks the R4-batch commit |
| S2 Home card-count cache + batched stats | R5-2 | ☐ | |
| S3 Gate the pitch detector on listening | R5-3 | ☐ | |
| S4 Freeze the aurora in sessions | R3-2 | ☐ | Frontend agent |
| S5 Polish: snippet tombstone, double haptic, Swift 6 warning | R5-6 | ☐ | |
| S6 "My snippet" on every vocab reveal | R5-5 (b) | ☐ | Frontend agent; owner approved 2026-11-17 |

---

## 3. Segments

### S1 · R5-1 · Typed vocab must not accept the negative form

**Problem:** `Conjugator.allAcceptedForms` iterates `ConjForm.allCases`, and that includes `.negativePolite`. `AnswerMatcher.hangulVerdict` therefore grades the following as *close*, which counts as correct for vocab:
- 몰라요 for 알다;
- 없어요 for 있다;
- 맛없어요 for 맛있다;
- 안 가요 and 가지 않아요 for 가다.

**Files:**
- `Packages/MemoriseCore/Sources/MemoriseCore/Korean/Conjugator.swift` (lines 78–88)
- `Packages/MemoriseCore/Sources/MemoriseCore/Korean/AnswerMatcher.swift` (line 101)

**Steps:**
1. In `ConjForm`, add a static list of the forms that keep the word's meaning:
   ```swift
   /// Forms that keep the word's meaning; typed vocab accepts these as close (R5-1).
   public static let affirmative: [ConjForm] = allCases.filter { $0 != .negativePolite }
   ```
2. Give `Conjugator.allAcceptedForms` a `forms:` parameter that defaults to every case, so existing callers keep their behaviour:
   ```swift
   public static func allAcceptedForms(_ dictionaryForm: String, class cls: ConjugationClass,
                                       isAdjective: Bool = false,
                                       forms: [ConjForm] = ConjForm.allCases) -> [String]
   ```
   Iterate `forms` instead of `ConjForm.allCases`.
3. In `AnswerMatcher.hangulVerdict`, pass `forms: ConjForm.affirmative`.
4. **Do not** add the review's optional "the form must still contain the stem" filter. Irregular verbs break it: 듣다 → 들어요, 돕다 → 도와요, 모르다 → 몰라요, 춥다 → 추워요. Excluding `.negativePolite` already covers every case the review found. Record this choice in §17.
5. Update the doc comment on `hangulVerdict` to say "a real affirmative conjugation".
6. Append a §17 entry: "R5-1: typed predicate matching accepts affirmative forms only (`ConjForm.affirmative`); the conjugation drill is unchanged."

**Acceptance (reference rows for the tester; the direction is en→ko typed vocab, so `isPredicate` is true):**

| Input | Expected | Verdict |
|---|---|---|
| 몰라요, 몰라 | 알다 | **wrong** |
| 없어요 | 있다 | **wrong** |
| 맛없어요 | 맛있다 | **wrong** |
| 안 가요, 가지 않아요 | 가다 | **wrong** |
| 가요, 갔어요, 가고 싶어요, 갈 거예요, 갑니다 | 가다 | close |
| 먹어, 먹어요 | 먹다 | close |
| 들어요 | 듣다 | close (irregular still accepted) |
| 가다 | 가다 | exact |

- The conjugation drill (`ConjugationUI`/`ConjugationDeck`) still grades a `negativePolite` card by its own answer and alternates. Example: 안 가요 is correct for "가다 · negative polite".
- `swift build` passes, and `xcodebuild` passes with no new warnings.

**Commit:** after S1, the uncommitted R4 batch and S1 go in **one** commit, as the review asks: `R4 fixes + R5-1: …`. The owner asked to review before commit, so commit only when the owner says so. Otherwise leave the working tree staged and report back.

---

### S2 · R5-2 · Home: stop rebuilding every card pool on the main actor

**Problem:** `HomeView.load()` (around line 356) runs on every `dataVersion` bump. For each of the 27 decks it:
- builds the deck's full `[Card]` only to read `.count`;
- decodes the saved config;
- makes a separate `store.stats(for:)` round trip.

That adds up to about 90 ms of main-thread work in Debug, landing on top of the Summary confetti.

**Files:**
- `App/Sources/AppEnvironment.swift`
- `App/Sources/Features/Home/HomeView.swift`
- `App/Sources/Features/SessionSetup/SessionSetupView.swift:43`
- `Packages/MemoriseCore/Sources/MemoriseCore/Persistence/StatsStore.swift`
- `Packages/MemoriseCore/Sources/MemoriseCore/Persistence/InMemoryStatsStore.swift`
- `App/Sources/Persistence/SwiftDataStatsStore.swift`
- `App/Sources/Persistence/DeferredStatsStore.swift`

**Steps:**
1. **Card-count cache in `AppEnvironment`:**
   - Add `@ObservationIgnored private var cardCountCache: [CardCountKey: Int] = [:]`, keyed by `(DeckID, DeckOptions)`. `DeckOptions` must be `Hashable`. If it isn't, key by `deck.id` plus the options' encoded `Data` from the existing `DeckOptions` encoder. Do **not** change the wire format.
   - Add `func cardCount(for deck: any Deck, options: DeckOptions) -> Int`. It returns the cached value or computes `deck.cards(options:).count` and stores it.
   - Clear the cache in `reloadCatalog()`, because user-deck saves and deletes go through it.
2. **Use the cache:**
   - In `HomeView.load()`, replace `deck.cards(options: …).count` with `env.cardCount(for: deck, options: env.initialConfig(for: deck).options)`.
   - In `SessionSetupView.swift:43`, replace `deck.cards(options: $0.options).count` with `env.cardCount(for: deck, options: $0.options)`.
   - Leave `WeakestWordsSection`, `SummaryView`, `TheoryControls` and `ChordsUI` alone; they need the cards themselves.
3. **Batched stats:**
   - Add a protocol requirement to `StatsStore`, declared in the protocol body so that calls through `any StatsStore` dispatch dynamically:
     ```swift
     /// Stats for several decks in one round trip (Home). Decks with no rows map to [:].
     func stats(forDecks decks: [DeckID]) async throws -> [DeckID: [ItemKey: ItemStats]]
     ```
   - Add a default in the `public extension StatsStore` that loops over `stats(for:)`. `InMemoryStatsStore` can use the default.
   - **`SwiftDataStatsStore`:** do a single `FetchDescriptor<SDItemStats>` with predicate `decks.contains($0.deckID)`, where `decks` is a `[String]` of raw ids. Group the rows by `deckID` into the result.
   - **`DeferredStatsStore`:** forward to the wrapped store, like its other methods.
4. **Rewrite `HomeView.load()`:**
   ```swift
   let decks = env.catalog.decks
   let all = (try? await env.store.stats(forDecks: decks.map(\.id))) ?? [:]
   for deck in decks {
       let count = env.cardCount(for: deck, options: env.initialConfig(for: deck).options)
       result[deck.id] = .make(cardCount: count, stats: (all[deck.id] ?? [:]).values)
   }
   ```
   Keep the `withAnimation(Theme.softSpring)` assignment.
5. **Optional, only if it is still slow on device:** move the count computation into a `Task.detached`, because `Deck` is `Sendable`. Do not do this pre-emptively.

**Acceptance:**
- After a session ends, Home shows the same card counts, accuracy, median and last-seen as before for every deck. Compare against the pre-change build on the same data.
- After the first launch, `deck.cards(options:)` is not called from `HomeView.load()` until the options change or the catalog reloads. Check this with a breakpoint or the G5 timing log.
- `load()` makes exactly one store call.
- Editing a user deck (adding a word) updates that deck's count on Home. This proves the cache is invalidated.
- Changing a deck's options in Session Setup updates the pool count there. The new options are a new cache key.

---

### S3 · R5-3 · Run pitch analysis only while listening

**Problem:** `MicAnswerController.setListening(false)` gates only `MicFrameTracker`. The tap and YIN analysis (`PitchDetector.analyse`) keep running through reveal, pause, sheets and note playback. That is about 66 M multiply-adds per second wasted. PLAN §11.5b says "Detector is off during reveal".

**Files:**
- `App/Sources/Services/PitchDetector.swift`
- `App/Sources/Services/MicAnswerController.swift`

**Steps:**
1. **`PitchDetector`:** add a thread-safe flag.
   - `private let activeLock = NSLock()` and `private var _active = false`. `OSAllocatedUnfairLock<Bool>` is also fine.
   - `func setActive(_ on: Bool)`, callable from any thread.
   - `private var isActive: Bool`, read under the lock.
2. In `append(_:newestHostSeconds:)`:
   - **keep** shifting samples into the ring and updating `filled`/`sinceHop` unconditionally, so re-arming has a full frame and no start-up latency;
   - at the hop boundary, call `analyse` only when `isActive`.
3. **Optional:** in `process(_:time:)`, keep the sample copy. Skipping it would let the ring go stale. No change is needed there.
4. **`MicAnswerController`:**
   - In `setListening(_:)`, call `detector?.setActive(on)` next to `tracker.setListening(on)`.
   - In `start()`, after creating the detector, call `detector.setActive(isListening)`, so the state is right if listening was armed before start.
   - In `stop()`, call `setActive(false)`.
5. **Level meter:** it is published only while listening already, so stopping analysis while not listening loses nothing. After re-arming, the meter starts from the tracker's last smoothed level. That is acceptable, and no change is needed.
6. Do **not** do the review's optional `tauMax`/FFT work in this segment.
7. Update the §17 entry for R4-5 with one line: "R5-3: YIN runs only while listening; the ring keeps filling."

**Acceptance:**
- In a mic session, the time profiler shows `PitchDetector.analyse` only while the Listening chip is shown. During reveal and pause, the `memorise.pitch` queue's CPU drops to near zero apart from the memmove.
- After a reveal, the first note played on the next card is still detected with no extra delay you can notice. The ring is already full.
- Mic answers, the timeout, "Heard G♯" and the level meter behave as before.

---

### S4 · R3-2 · Freeze the aurora during sessions (frontend agent)

**Problem:** `AuroraBackground` (`App/Sources/Components/Theme.swift:55`) runs a 30 fps `TimelineView` with a full-screen blurred `Canvas` on 13 screens. That includes `SessionView.swift:109`, where it competes with the timed prompt and with mic delivery.

**Steps:**
1. Add `var animated: Bool = true` to `AuroraBackground`. Pass `paused: reduceMotion || !animated` to the `TimelineView`. When it is not animated, use `t = 0`, the same as Reduce Motion, so the frame is static and identical every time.
2. Pass `animated: false` in `SessionView.swift:109`.
3. Leave the other screens animated. Optionally pause the aurora when the scene is not `.active` (`@Environment(\.scenePhase)`).
4. Keep `#Preview`s compiling.

**Acceptance:**
- In a session, Instruments' Core Animation / GPU track shows no continuous 30 Hz redraw from the background.
- Home, Settings and the other screens still animate.
- With Reduce Motion on, nothing changes compared with today.

---

### S5 · R5-6 · Polish batch

**a. Snippet delete tombstone** (`App/Sources/AppEnvironment.swift`, lines 176–201). Mirror the user-deck pattern from R4-10:
- add `@ObservationIgnored private var snippetsLoaded = false` and `@ObservationIgnored private var snippetsDeletedBeforeLoad = Set<String>()`;
- in `deletePersonalSnippet`, if `!snippetsLoaded`, insert `entryID`;
- in `deleteAllPersonalSnippets`, if `!snippetsLoaded`, set a `deleteAllBeforeLoad = true` flag, or insert every key that loads later;
- in `savePersonalSnippet`, remove `entryID` from the set. A later save wins;
- in `loadPersonalSnippets`, drop disk entries whose key is in the set (or drop all of them if the delete-all flag is set) before the merge, then set `snippetsLoaded = true` and clear the set.

*Acceptance:* a snippet deleted before the launch load completes stays deleted after the load. A snippet saved before the load keeps the in-memory version, as today.

**b. Double haptic on typed and choice answers** (`App/Sources/Features/Session/SessionViewModel.swift`):
- give `grade(correct:)` a parameter, `grade(correct: Bool, haptic: Bool = true)`, and fire `env.haptics.grade` only when `haptic` is true;
- in `gradeAutoAnswer()`, call `grade(correct: autoAnswer.correct, haptic: false)`, because `reveal(_:_:)` already fired it.

*Acceptance:* one haptic per typed or choice card, at the reveal. Touch and mic self-grades still fire one haptic on grade.

**c. Swift 6 warning** (`App/Sources/Features/MyDecks/ScreenshotImportView.swift:41`). The `PhotosPicker` label closure is `Sendable` and reads the main-actor `phase`. Before the `PhotosPicker`, compute `let pickerTitle = phase == .idle ? "Choose a screenshot" : "Choose another screenshot"`, and use `pickerTitle` in the label.

*Acceptance:* `xcodebuild` (iOS Simulator, Debug) reports **0** warnings from app sources.

---

### S6 · R5-5 (b) · "My snippet" on every vocab reveal (frontend agent)

**Decision (owner, 2026-11-17):** option (b) now, and K2 content later. The K3 rule "existing decks look unchanged" is relaxed. A vocab reveal may now show the "My snippet" section, but the "In a scene" and "Heard in" sections still appear only when the entry has that data.

**Problem:** `VocabUI.swift:203` embeds `MediaSnippetView` only when `MediaSnippetView.shouldShow(for:)` is true, meaning the entry has dialogue or sources. No bundled deck has either, so K4 ("My snippet"), its store, its export key and the reset prompt can't be reached.

**Files:**
- `App/Sources/DeckUI/VocabUI.swift` (around line 203)
- `App/Sources/Components/MediaSnippetView.swift`

**Steps:**
1. **`VocabUI` answer view:** remove the `shouldShow` condition and always embed `MediaSnippetView(entry: e, onEditSnippet: onEditSnippet)`. Keep `.padding(.top, 8)`. This covers every vocab entry: bundled core, patterns, user and AION decks, in every direction including listening.
2. **`MediaSnippetView`:**
   - Rename `shouldShow(for:)` to `hasMedia(for:)` (same logic). Its only caller was `VocabUI`.
   - The "In a scene" and "Heard in" sections keep their own `isEmpty` checks, which already exist.
   - **Compact form for non-media entries.** When `!hasMedia(for: entry)` **and** the entry has no saved snippet, show only the existing `addButton`. Leave out the `PanelSection` header, so plain decks gain one quiet dashed button and not a whole titled panel.
   - When the entry has a saved snippet, show the full "My snippet" `PanelSection` with the saved card, the same as for media entries.
   - Make `addButton` reachable from the compact path. Either expose `MySnippetCard` with a `compact` flag, or lift the button out into a small private view. Keep the identifier `addSnippetButton`.
3. **Keep the session wiring as it is:** opening the editor goes through `onEditSnippet`, which pauses the session timer (K4). Nothing changes there.
4. **Identifiers:** the outer container keeps `mediaSnippet`. If a VoiceOver label is missing, add `Add your own snippet for <hangul>` on the compact button.
5. **`#Preview`s:**
   - a plain core entry with no snippet (compact button only);
   - a plain entry with a saved snippet;
   - the existing media previews, unchanged.
6. **Check entry-id uniqueness:** snippets are keyed by `VocabEntry.id` alone. Confirm that user-deck entry ids can't collide with bundled ids; read `UserDecks.newDeck` and the entry-id generation. If they can collide, **stop and report to the planner**. Don't change id schemes; CLAUDE.md forbids it.
7. Update the doc comment in `VocabUI` ("M5: only media phrases get the panel …") to describe the new rule.

**Acceptance (device or simulator):**
- Reveal a Core 1 card. Below the examples and notes there is one dashed "Add your own snippet" button, with no "In a scene" or "Heard in" sections.
- Tap the button. The editor sheet opens and the session timer is paused. Save the snippet. The reveal now shows the "My snippet" section with the saved text, and the next time this card comes up the snippet is still there.
- The Wrong/Correct controls stay reachable, and long reveals scroll, as in PLAN_M5 §K3.
- Settings → Export JSON contains the `personalSnippets` key with the saved entry. Reset all asks "Also delete my snippets?".
- User/AION deck cards and listening-direction reveals show the button too.
- Non-vocab decks (music, Hangul reading, particles, conjugation) are unchanged.

---

## 4. Planner follow-up (not implementor work)

**P1 · R5-4 + R3-7 + D2:** fold the R4 decisions into the normative sections:
- PLAN.md §9.2 table (the `choice` row should say "time EWMA: no") and the paragraph below it (a touch fallback counts; a mic-timeout reveal doesn't);
- §11.5d;
- the PLAN_M4 §3.1 table and M4-0 step 2 (`countsTime` per answer via `ok(countsTime:)`);
- the §15 M4 status line (Core 5 is done);
- the definition of "close" for vocab (R4-2 + R5-1);
- README.md lines 24 and 31.

The same pass also removes `undoLastGrade` from the spec, as the owner decided under D2:
- PLAN.md §9.3 (line ~567);
- the S6 scope line (line ~842);
- the S6 tracker note (line ~974);
- plus a §17 entry.

The planner does this **after** the R4 batch + S1 commit lands. PLAN.md currently holds the code-writer's uncommitted §17 entries, and the planner commits only plan files.

## 5. Owner decisions

| # | Decision | Outcome (2026-11-17) |
|---|---|---|
| D1 | R5-5: how to make M5 reachable | **(b) now:** "+ Add your own snippet" on every vocab reveal (S6). K2 content follows later and needs a web-capable agent. The K3 "existing decks look unchanged" rule is relaxed accordingly (PLAN_M5 §K3 updated). |
| D2 | `undoLastGrade` (PLAN §9.3 stretch goal) | **Dropped** from the spec. The implementor builds nothing for it; the planner removes it from PLAN.md in P1. |
