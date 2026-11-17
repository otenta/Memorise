# Memorise — M4: Korean beyond words

- **Date:** 2026-11-16
- **Owner of this file:** planner. Implementor agents execute segments in order and tick the tracker (§5). PLAN.md §16 and `CLAUDE.md` apply, including the frozen persisted-coding rule (G1) and "never change or reuse an `ItemKey` or entry `id`".
- **Prerequisites:** **M2-0a and M2-0b** (core deck hooks + app `DeckUI` registry). M4 adds five deck kinds and must not reintroduce downcasts. M2-0c, M2-1…M2-8 are not required.
- **Relation to M5:** both milestones extend the vocab deck file schema. **Whichever lands first bumps `VocabDeckFile.currentSchemaVersion` to 2**; the other adds its optional fields under v2 without a further bump. All new fields are optional and tolerant, so the order doesn't matter.
- **Testing:** out of scope for this plan; the tester agent owns it. Segments list **reference examples** (expected input → output) for the tester to use; the implementor does not write test code.
- **Owner direction (2026-11-16):** **large, varied pools**, so sessions don't get repetitive quickly. Content segments aim high, and generated decks default to the widest sensible sources.

---

## 1. Scope

| # | Feature | Kind | Roadmap item |
|---|---|---|---|
| 0 | Infrastructure: dynamic catalog, answer modes, schema additions | refactor | — |
| 1 | **Korean Core 2–5** decks (next frequency bands, ~800 words) | content, `VocabDeck` | Core 2/3 (expanded) |
| 2 | **Hangul reading** (jamo → syllables → batchim), generated | new deck kind | Hangul reading deck |
| 3 | **Listening mode**: TTS plays, you recall the meaning | vocab direction | Listening cards |
| 4 | **Typed answers** with a fuzzy check (Hangul + English) | answer mode | Typed answers |
| 5 | **Particles** (은/는, 이/가, 을/를, 와/과, (으)로, 이에요/예요), generated | new deck kind | Particles |
| 6 | **Verb conjugation** drills, generated from Core verbs/adjectives | new deck kind | Conjugation |
| 7 | **Grammar patterns & short sentences** deck | content, `VocabDeck` | Sentences & patterns |
| 8 | **Custom decks** (create/edit in-app; no import) | user content | Custom decks |
| 9 | **AION 2 screenshot → cards** (on-device OCR) | user content | AION OCR |

## 2. Order and dependencies

```
M4-0 ─┬─► M4-1 (content)          ─┐
      ├─► M4-2 (Hangul reading)    │
      ├─► M4-3 (listening)         │
      ├─► M4-4 (typed + fuzzy) ─┬──┼─► M4-10 (integration & QA)
      │                         └► M4-5 (particles), M4-6 (conjugation)
      ├─► M4-7 (patterns content)  │
      └─► M4-8 (custom decks) ─► M4-9 (AION OCR)
```

M4-1 is the largest segment (≈ 800 entries). Split it into four content PRs, one per deck (Core 2, 3, 4, 5); each is independently shippable.

The recommended single-agent order is 0 → 3 → 4 → 2 → 5 → 6 → 1 → 7 → 8 → 9 → 10. The early features are cheap and immediately useful on existing decks. Content segments (1, 7) can run in parallel with a web-capable agent at any point after M4-0.

---

## 3. Shared design decisions

### 3.1 Answer modes (one concept for M2 and M4)
`SessionConfig.inputMode` (introduced by M2-7; **M4-0 introduces it if M2-7 hasn't landed**) becomes:

| `InputMode` | How the user answers | Grading | Time updates the time-EWMA? |
|---|---|---|---|
| `touch` (default) | OK → reveal → self-grade | self | yes |
| `microphone` (M2-7) | play the note | auto (correct only) | yes |
| `choice` | tap one of 2–4 options | auto | yes |
| `typed` | type the answer, press Return | auto + override | **no** (typing speed would distort recall time; the error EWMA still updates) |

- Each `DeckUI` provider declares `supportedInputModes`. Setup shows a segmented "Answer by" control only when there is more than one mode.
- **Engine API (core):** `answerEvaluated(correct: Bool, at: Duration, countsTime: Bool) -> [SessionEffect]`. It performs `ok` at `at`, then grades with `gradeMs = 0`. M2-7's `answerDetected(at:)` becomes a thin wrapper with `correct: true`. Whichever of M2-7 or M4-0 lands first defines the API.
- `StatsUpdater.apply` gains `updateTime: Bool = true`. When false, `ewmaResponseMs`/`bestResponseMs` are unchanged and `ewmaError`/attempt counts update. The `Attempt` still stores the raw `responseMs`. **No `Attempt` schema change.**
- **Typed flow:** Return → `ok()` (records the time) → reveal shows the verdict pre-selected ("✓ Correct", "≈ Close: check spelling", "✗") with the expected answer and the user's input diffed → **Next** grades with the verdict. "I was right" / "I was wrong" overrides are available. "Close" defaults to correct. The normal 250 ms lockout applies. Auto-advance after 0.8 s only when exactly correct (setting, default on).

### 3.2 Vocab schema additions (all optional, tolerant)

| Field | On | Purpose |
|---|---|---|
| `conj` | verb/adjective entries | Irregular class for the conjugator: `"regular"` (default when missing), `"ha"`, `"b"`, `"d"`, `"s"`, `"reu"`, `"eu"`, `"l"`, `"h"`, `"copula"`. Bundled files: **required** for every verb/adjective (validator). |
| `examples` | any entry | Up to 3 `{ko, en}` pairs (patterns deck); the existing single `example` stays. |
| `pos` value `"pattern"` | patterns deck | Added to `PartOfSpeech` (additive raw value). |

User decks (M4-8) have relaxed rules; see §M4-8.

### 3.3 Dynamic catalog
`AppEnvironment.catalog` becomes an observable `private(set) var`, rebuilt by `reloadCatalog()` as bundled decks + generated decks + user decks. Views already read `env.catalog` through the observable environment. Saved configs for deleted user decks are ignored, because `initialConfig` falls back to defaults.

---

## 4. Segments

### M4-0 — Infrastructure
**Files:** `Domain/SessionConfig.swift`, `Session/SessionEngine.swift`, `Stats/StatsUpdater.swift`, `Korean/Vocab.swift`, `Korean/DeckValidator.swift`, `Domain/PersistedFormatCheck.swift`, `App/Sources/AppEnvironment.swift`, `App/Sources/DeckUI/DeckUI.swift`.

1. `InputMode` with the four cases; `SessionConfig.inputMode` decoded tolerantly; a `PersistedFormatCheck` fixture (legacy JSON → `.touch`).
2. Engine `answerEvaluated(correct:at:countsTime:)`; engine `grade` gains an internal `countsTime` derived from `config.inputMode == .typed` (false); `StatsUpdater.apply(updateTime:)`.
3. Schema additions from §3.2 in `VocabEntry` / `PartOfSpeech`, plus the `conj` enum `ConjugationClass` (tolerant: unknown → `.regular`, logged by the validator).
4. `DeckUI` gains `supportedInputModes: [InputMode]` (default `[.touch]`) and `typedAnswer(for card) -> TypedAnswerSpec?`, which is the expected answers plus a matcher kind (`.hangul`, `.english`, `.romanization`).
5. Dynamic catalog (§3.3): `reloadCatalog()` and `DeckCatalog.init(decks:)` reuse.
6. `SpeechService`: a completion callback via `AVSpeechSynthesizerDelegate` (`speak(_:rate:onFinish:)`), needed by M4-3.

**Accept:** existing decks behave identically; a legacy config decodes `.touch`; `PersistedFormatCheck` passes in a DEBUG build.

### M4-1 — Korean Core 2–5 content (large pool)
**Files:** `Resources/Decks/ko_core_2.json` … `ko_core_5.json`, `DeckCatalog.bundledVocabFiles`.
**Requires:** a web-capable agent; a verification table in the PR description.

1. Deck ids `ko.core.2` … `ko.core.5`, **~200 entries each (~800 total)**. Entry ids **continue the `ko.core.` sequence** (Core 1 ends at `ko.core.0205`, so Core 2 starts at `0206`). The validator already enforces cross-file uniqueness.
   - **Variety targets per deck:** ≥ 40 % nouns spread across ≥ 10 themes (food, places, body, time, weather, feelings, people, school/work, travel, home, shopping, hobbies), ≥ 25 % verbs/adjectives, and the rest adverbs, expressions, counters and connectors. Every deck has ≥ 30 example sentences.
   - Tags come from a fixed theme list, so the Setup topic filter is useful on large decks.
2. Source: the next frequency bands of a public learner list (e.g. the National Institute of Korean Language "한국어 학습용 어휘 목록"), excluding anything already in Core 1. Add a new validator **warning**: the same `hangul` + `pos` appearing in two bundled files.
3. The same authoring rules as Core 1 (PLAN §8.3), plus `conj` on every verb/adjective.
4. Verification table: hangul | meaning | dictionary URL checked | conj class source.

**Accept:** the validator shows 0 errors and 0 cross-file duplicates; the variety targets are met (POS and tag counts listed in the PR); the owner spot-checks 15 random entries per deck; display order is Core 1 → Core 5, then the others.

### M4-2 — Hangul reading deck (generated)
**Deck:** `ko.hangul` · kind `.hangulReading` · "Hangul Reading" · "Letters to sounds". **New options case** `.hangulReading(HangulReadingOptions)`, with `stages: Set<Stage>` (default `[.basicVowels, .basicConsonants]`) and a `PersistedFormatCheck` fixture.

1. Stages and card sets, all generated from Unicode composition (`0xAC00 + (initial*21 + medial)*28 + final`):

   | Stage | Cards | Key |
   |---|---|---|
   | `basicVowels` | ㅏ ㅓ ㅗ ㅜ ㅡ ㅣ ㅑ ㅕ ㅛ ㅠ (10, shown as 아, 어 …) | `hangul:v:<jamo>` |
   | `basicConsonants` | ㄱ ㄴ ㄷ ㄹ ㅁ ㅂ ㅅ ㅇ ㅈ ㅎ (10, shown as 가, 나 …) | `hangul:c:<jamo>` |
   | `aspiratedTense` | ㅋ ㅌ ㅍ ㅊ ㄲ ㄸ ㅃ ㅆ ㅉ (9) | `hangul:c:<jamo>` |
   | `complexVowels` | ㅐ ㅔ ㅒ ㅖ ㅘ ㅙ ㅚ ㅝ ㅞ ㅟ ㅢ (11) | `hangul:v:<jamo>` |
   | `syllables` | 14 basic initials × 10 basic vowels (140) | `hangul:s:<syllable>` |
   | `batchim` | syllables with a **single** final from the 7 representative sounds (ㄱ ㄴ ㄷ ㄹ ㅁ ㅂ ㅇ) on common bases (~150, curated list in code) | `hangul:s:<syllable>` |

2. `Romanizer` (core): RR for **isolated syllables only**, with initial/medial/final tables, finals as representative sounds (k, n, t, l, m, p, ng), and initial ㅇ silent. Words are never auto-romanized (liaison rules); real words come from the decks.
3. Prompt: a large syllable. Answer: the romanization plus a 🔊 (TTS speaks the syllable). Introduction gating: `introductionRank` = stage order, then table order, so learners are not shown all 140 syllables on day one.
   - **Variety:** add a `realWords` stage, which picks 1–3-syllable words from all Korean decks (the pool grows with Core 2–5). The answer is the deck's own romanization (no auto-romanizing). Key: `hangul:w:<entryId>`.
4. Input modes: `touch`, `typed` (`.romanization` matcher: exact after lowercasing/trimming; ㄹ accepts `r` or `l`; ㅓ accepts `eo` only).
5. Stats section: a grid of syllables coloured by error EWMA.
6. Reference examples for the tester: 가 ga, 꿈 kkum, 밥 bap, 산 san, 의 ui, 쥐 jwi, 왜 wae, 첫 cheot, 엉 eong. Syllables with double finals (닭) are excluded from the generated stages.

**Accept:** stage filters produce the listed counts; TTS plays every syllable.

### M4-3 — Listening mode
1. `VocabDirection` gains `.listen = "listen"`. **The raw value is part of ItemKeys: never change it.** Keys `ko.core.0001#listen` keep separate stats, because hearing is a different skill.
2. `VocabOptions.DirectionOption` gains `.listening`, and `.allThree` = ko→en + en→ko + listen. Persisted enum: additive case.
3. Prompt: a large 🔊 waveform icon, with no text. The view calls `speak(hangul, onFinish:)` and calls `vm.promptDidAppear()` **in `onFinish`**, so the timer starts when the audio ends. Replay doesn't reset the timer. Backgrounding uses the existing interrupt path.
4. Answer: Hangul, romanization, meanings (same as ko→en).
5. Without a Korean voice: the Setup option is disabled with the existing install hint. A session already running with listening cards skips them, because the deck filters them out when `hasKoreanVoice == false` (pass `voiceAvailable` via `DeckUIContext.sanitize`).
6. Typed mode (after M4-4): type the meaning (`.english` matcher).

**Accept:** the timer starts at the end of speech; listen stats are separate from ko→en in the weakest-words list (labelled 🔊).

### M4-4 — Typed answers and fuzzy matching
**Files:** new `Korean/AnswerMatcher.swift` (core), `DeckUI/VocabUI.swift`, a new `App/Sources/Components/TypedAnswerField.swift`, `SessionView.swift`.

1. `AnswerMatcher.match(input:, expected: [String], kind:) -> Verdict` (`.exact`, `.close`, `.wrong`):
   - **Hangul:** NFC-normalise; strip spaces and punctuation; also accept the input with a trailing `요`/`다` removed for verbs (e.g. 가요 for 가다 counts as `.close`). Decompose to jamo and compute Levenshtein distance. Distance 0 → exact; distance ≤ 1 jamo when length ≥ 2 syllables → close.
   - **English:** lowercase; strip leading `to `, `a `, `an `, `the `; strip parentheticals in the expected glosses (`"bag (for carrying)"` → `"bag"`); match against **any** gloss. Exact → exact. Levenshtein ≤ 1 for length ≥ 5, or ≤ 2 for length ≥ 9 → close.
   - **Romanization:** see M4-2.
2. UI: in the `typed` prompt, a text field below the prompt that autofocuses with autocorrection and auto-capitalisation off. Return submits. The keyboard stays up between cards (no flicker): the field persists across `presentationID` changes and is cleared on each new card. For Hangul input with no Korean keyboard installed, show a hint: "Add the Korean keyboard in Settings → General → Keyboard".
3. Reveal: the verdict banner, `yours` vs `expected` with differing jamo/characters highlighted, override buttons, and Next.
4. Supported on vocab decks (all directions), Hangul reading, and conjugation. Particles use `choice` instead.
5. Reference examples for the tester: 학교/핵교 → close, 먹다/먹어요 → close, "to eat"/"eat" → exact, "recieve"/"receive" → close, 사과/사람 → wrong.

**Accept:**
- typing sessions don't change the time EWMA (check one item's stats before and after)
- the error EWMA does update
- overrides change the stored grade
- the hardware keyboard Return submits
- the existing pedal mapping (→/PgDn = OK) is disabled while the text field has focus

### M4-5 — Particles deck (generated)
**Deck:** `ko.particles` · kind `.koreanParticles` · "Particles" · "은/는, 이/가, 을/를 …". **New options case** `.particles(ParticleOptions)`: `particles: Set<Particle>` (default all), `nounSource` (`.allKorean` **default**, for variety: every noun in Core 1–5, AION, K-media and user decks; or `.coreOnly`), with a `PersistedFormatCheck` fixture.

1. `Particle` pairs and rules (core, `Korean/Particles.swift`):

   | Particle | After batchim | After vowel | Note |
   |---|---|---|---|
   | topic | 은 | 는 | |
   | subject | 이 | 가 | |
   | object | 을 | 를 | |
   | and/with | 과 | 와 | |
   | direction/means | 으로 | 로 | **ㄹ-batchim takes 로** |
   | copula | 이에요 | 예요 | |

   Batchim = the final-consonant index of the last syllable ≠ 0.
2. Cards: one per (particle, ending class: `batchim`, `vowel`, plus `rieul` for direction). **Key:** `particle:<particle>:<class>` (13 cards).
3. `present(options:rng:)` picks a random noun of that ending class from the noun source (pos `noun` only; **pronouns are excluded** because of 내가/제가/네가). This mirrors how Intervals picks a root (M2-4).
4. Input mode `choice` (default and only): the prompt shows "책 + (topic)" and two buttons, "책은" and "책는". Tapping one evaluates immediately via `answerEvaluated`. The reveal shows the rule ("ends in a consonant → 은") and the noun's meaning.
5. Reference examples for the tester: 책→책은, 학교→학교는, 물→물로, 집→집으로, 친구→친구예요, 사과→사과를, 선생님→선생님이.

**Accept:** every class is reachable; a ㄹ-final noun appears for the direction particle; over 50 prompts, the same noun rarely repeats (the large noun pool).

### M4-6 — Verb conjugation deck (generated)
**Deck:** `ko.conjugation` · kind `.koreanConjugation` · "Conjugation" · "가다 → 가요". **New options case** `.conjugation(ConjugationOptions)`: `forms: Set<ConjForm>` (default: **all seven**, for variety; the user can narrow it), `source` (`.allCore` **default**: every verb/adjective in Core 1–5, ~250 entries; or `.core1`), `newPerSession` (default 5), with a `PersistedFormatCheck` fixture.

1. `ConjForm`: `presentPolite` (-아요/어요), `pastPolite` (-았어요/었어요), `futurePolite` (-(으)ㄹ 거예요), `presentCasual` (-아/어), `presentFormal` (-ㅂ니다/습니다), `negativePolite` (안 + present polite), `wantTo` (-고 싶어요). Raw values are part of keys.
2. `Conjugator` (core, `Korean/Conjugator.swift`) applies, in order:
   - stem extraction (drop 다)
   - the irregular class from `conj`: **ha** (하 → 해), **b** (ㅂ → 우; 돕다/곱다 → 와), **d** (ㄷ → ㄹ before a vowel), **s** (ㅅ drops before a vowel), **reu** (르 → ㄹ라/ㄹ러), **eu** (ㅡ drops), **l** (ㄹ drops before ㄴ/ㅂ/ㅅ; e.g. 살다 → 삽니다), **h** (ㅎ-irregular adjectives: 그렇다 → 그래요), **copula** (이다)
   - vowel harmony (ㅏ/ㅗ → 아, otherwise 어)
   - contraction (가+아 → 가, 오+아 → 와, 마시+어 → 마셔, 되+어 → 돼, 주+어 → 줘, 서+어 → 서, 내+어 → 내)
   - the ending, with batchim-sensitive (으)
3. Cards: one per (entry, form). **Key:** `conj:<entryId>:<form>`. Introduction gating uses the entry `rank` and `newPerSession` (`Deck.newPerSession(options:)` from M2-0a).
4. Prompt: "가다 · past polite". Answer: "갔어요" plus a one-line rule ("ㅏ stem → 았어요, 가+았 → 갔") and 🔊. Input modes: `touch`, `typed` (`.hangul` matcher, **exact required**: "close" counts as wrong here, because spelling is the skill).
5. **Content step:** add `conj` to every Core 1 verb/adjective (72 entries). Core 2–5 (M4-1) include it from the start. Known irregulars include 모르다/빠르다 (reu), 듣다/걷다 (d), 돕다/쉽다/어렵다 (b), 쓰다/크다/나쁘다 (eu), 알다/살다/만들다/놀다/열다/길다 (l), and every -하다 verb (ha). Verify each against a dictionary; record the URL in the verification table.
6. **Reference table for the tester:** deliver `docs/conjugation-reference.md`, with ~80 forms verified against a dictionary or reference conjugator. It covers every class × every form, plus the 마시다, 되다, 주다 and 오다 contractions. It is content, not test code.

**Accept:** 10 random cards per form match the reference table.

### M4-7 — Grammar patterns & short sentences deck (content)
**Deck file:** `ko_patterns.json`, deck id `ko.patterns`, entries `ko.patterns.NNNN`, `pos: "pattern"`.

1. **~80 patterns** (beginner → lower-intermediate), ranked by usefulness, each with **3 examples**, so sentence practice has ~240 sentences. For example: -고 싶다, -(으)ㄹ 수 있다/없다, -아/어야 하다, -지 마세요, -(으)면, -고 있다, -아/어 주세요, -(으)러 가다, -기 전에, -(으)ㄴ 후에, -지만, -아/어서, -(으)니까, -(으)ㄹ 거예요, -고 (and), -네요, -죠.
2. Each entry: `hangul` = the pattern (`-고 싶다`), `meanings` = 1–2 English functions ("want to …"), `notes` = attachment rule, and `examples` = 2–3 original short sentences (≤ 40 Hangul syllables, polite style).
3. Card directions as for vocab. The ko→en prompt shows the pattern; the reveal shows the meaning, rule and examples, each with 🔊. **Sentence practice** = the `en→ko` direction with typed mode on the first example: the prompt shows the English sentence, and the user types Korean. The matcher allows "close"; override is available.
4. Validator: `pattern` entries must start with `-` or contain `~`, and need ≥ 2 examples.

**Accept:** the validator shows 0 errors; the owner spot-checks 10 entries.

### M4-8 — Custom decks (create and edit in-app; no import)
**Files:** new `App/Sources/Persistence/UserDeckStore.swift` (actor), new `App/Sources/Features/MyDecks/*`, `Decks/DeckCatalog.swift`, `Korean/DeckValidator.swift`, the export path, `SettingsView.swift`/`HomeView.swift`.

1. **Storage:** `Application Support/UserDecks/<deckId>.json`, in the same `VocabDeckFile` format plus an optional `nextEntryNumber`. No SwiftData change.
   - Deck ids: `user.<8 hex>`. Entry ids: `user.<8 hex>.NNNN`.
   - **Numbers are never reused**: `nextEntryNumber` only increases, even after a delete.
2. **Validator mode** `.user`: `romanization` is optional (it may be empty); `rank` is auto-assigned on save; `conj` and examples are optional; ids follow the user-deck format. `VocabEntry` decoding of `romanization` becomes `decodeIfPresent ?? ""`; the bundled validator still requires it.
3. **UI:** Practice → "My decks" section → "+ New deck".
   - Deck editor: title and subtitle.
   - Entry list: add, edit or delete an entry, with fields for hangul, meanings (comma-separated), pos picker (default noun), optional romanization, optional example, optional tags.
   - Deleting a deck asks for confirmation and also calls `store.reset(deck:)`.
4. **No import** (owner decision 2026-11-16). There is no file importer, no CSV and no per-deck share.
5. **Backup only:** the full data export (Settings) includes the user decks as data. `ExportSnapshot` uses an optional `userDecks` key. If M5-K4 has already bumped the schema to 2, no further bump; otherwise bump to 2.
6. `reloadCatalog()` after every change.

**Accept:**
- create, edit and practise a custom deck
- delete an entry and add another: the new id is not a reused number
- the full export contains the user decks

### M4-9 — AION 2 screenshot → cards
**Files:** new `App/Sources/Features/MyDecks/ScreenshotImportView.swift`, new `App/Sources/Services/KoreanTextExtractor.swift`.

1. Entry point: the "My AION words" deck (auto-created as a user deck with id `user.aion0001`, title "My AION words") → "Add from screenshot" (`PhotosPicker`, images only).
2. OCR: Vision `VNRecognizeTextRequest`, `.accurate`, `recognitionLanguages = ["ko-KR", "en-US"]`, `usesLanguageCorrection = true`. It runs off the main thread. **The screenshot is never stored**; only the extracted words are kept.
3. Extraction: take Hangul runs from each line; strip one trailing particle from {은 는 이 가 을 를 에 에서 의 도 만 로 으로 과 와 한테 께}, only when the remainder is ≥ 2 syllables; deduplicate. Drop tokens already present (hangul match) in **any** catalog deck, and show them as "already known (n)".
4. A review list with checkboxes; each selected word needs a meaning typed by the user (there is no offline dictionary; *ASSUMPTION*). Romanization is optional. Save appends to the deck with new ids.
5. Privacy: the photo-library permission is limited to the picker (no `NSPhotoLibraryUsageDescription` needed with `PhotosPicker`); there is no network.

**Accept:** a real AION 2 screenshot yields a plausible word list; particles are stripped correctly for 10 sample tokens; known words are filtered; saved words become practisable cards.

### M4-10 — Integration, docs, QA
1. Home → Korean section order: Hangul Reading, Core 1–3, Particles, Conjugation, Patterns, K-media (if M5 has landed), AION 2, then **My decks**.
2. `BuiltInDecks` rows for every new bundled or generated deck.
3. PLAN.md:
   - §6.1: the new key schemes
   - §8: schema additions, Romanizer, particles, conjugator
   - §9: answer modes
   - §11: typed/choice/listening UX
   - §15: M4 link
   - §17: tracker and log
4. README: QA checklist additions (Korean keyboard, listening timer, OCR, custom deck editing).

---

## 5. Tracker

| Segment | Status | Notes |
|---|---|---|
| M4-0 Infrastructure | ☑ | schema v2; choice/typed reveal via ok→grade (see PLAN §17) |
| M4-1 Core 2–5 content (~800) | ☑ (content) | Core 2 (218), Core 3 (229), Core 4 (217), Core 5 (225) = 889; not yet dictionary-checked (`docs/core-verification.md`) |
| M4-2 Hangul reading | ☑ (code) | includes `realWords` stage |
| M4-3 Listening mode | ☑ | timer starts at end of TTS |
| M4-4 Typed answers + fuzzy | ☑ | vocab, Hangul reading and conjugation all support `typed` |
| M4-5 Particles | ☑ (code) | noun pool = all Korean decks |
| M4-6 Conjugation | ☑ (code) | Core 1 `conj` tagged; reference table not dictionary-verified |
| M4-7 Patterns content (~80) | ☑ (content) | 87 patterns × 3 examples; owner spot-check of 10 pending |
| M4-8 Custom decks (no import) | ☑ (code) | own Home section "My decks" |
| M4-9 AION screenshot → cards | ☑ (code) | needs a real-screenshot check on device |
| M4-10 Integration & QA | ☑ | Korean display order, PLAN §6.1/8.3b/9.2/11.5d/15, README QA checklist |

## 6. Key and format rules introduced by M4

| Deck | ItemKey scheme |
|---|---|
| Core 2/3, Patterns, user decks | `<entryId>#ko-en` / `#en-ko` / `#listen` (existing scheme + new `listen` direction) |
| Hangul reading | `hangul:v:ㅏ`, `hangul:c:ㄱ`, `hangul:s:밥` |
| Particles | `particle:topic:batchim`, `particle:direction:rieul` |
| Conjugation | `conj:ko.core.0005:pastPolite` |

New persisted fields and cases (tolerant, each with a `PersistedFormatCheck` fixture): `SessionConfig.inputMode` (if not already added by M2-7), `DeckOptions.hangulReading`, `.particles`, `.conjugation`, `VocabOptions.DirectionOption.listening`/`.allThree`. Vocab schema: `conj`, `examples`, pos `pattern`. Export: `userDecks` (backup only).

## 7. Decisions and open questions
- **ASSUMPTION:** typed answers don't update the time EWMA, because typing speed isn't recall speed. The error EWMA still updates.
- **ASSUMPTION:** OCR words need a user-typed meaning, since there is no offline dictionary. A later idea is to suggest a meaning when the word exists in any bundled deck (already covered by "known" filtering).
- **ASSUMPTION:** conjugation "close" counts as wrong; vocab "close" counts as correct with override.
- **DECIDED (owner, 2026-11-16):** a large, varied content pool (Core 2–5, ~80 patterns, all conjugation forms on by default, particle nouns from every Korean deck).
- **DECIDED (owner, 2026-11-16):** no import of any kind.
- **DECIDED (owner, 2026-11-16):** testing is handled by the tester agent; plans contain no test work, only reference examples.
