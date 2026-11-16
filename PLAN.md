# Memorise — Implementation Plan

> A personal iOS flashcard app for learning **guitar fretboard / music theory** and **Korean**, with timed responses and an adaptive scheduler that shows you the cards you are slowest on more often.
>
> This document is the single source of truth for implementing agents. It is split into **segments** (§12) that can be implemented one at a time, each with clear scope, files, and acceptance criteria. Read §1–§11 once before starting any segment.

---

## Table of contents

1. [Product vision](#1-product-vision)
2. [Milestone 1 scope](#2-milestone-1-scope)
3. [Core user flow](#3-core-user-flow)
4. [Tech stack and constraints](#4-tech-stack-and-constraints)
5. [Repository layout](#5-repository-layout)
6. [Domain model](#6-domain-model)
7. [Music module (fretboard notes)](#7-music-module-fretboard-notes)
8. [Korean module (vocabulary)](#8-korean-module-vocabulary)
9. [Timing, session engine and statistics](#9-timing-session-engine-and-statistics)
10. [Adaptive scheduler](#10-adaptive-scheduler)
11. [UI / UX specification](#11-ui--ux-specification)
12. [Implementation segments](#12-implementation-segments)
13. [Testing strategy](#13-testing-strategy)
14. [Building, CI and installing on your iPhone](#14-building-ci-and-installing-on-your-iphone)
15. [Future roadmap (post-M1)](#15-future-roadmap-post-m1)
16. [Conventions for implementing agents](#16-conventions-for-implementing-agents)
17. [Progress tracker](#17-progress-tracker)

---

## 1. Product vision

A **very simple**, single-user, offline iOS app. One loop, reused for every subject:

1. A **prompt** card appears (e.g. *"Play **A (La)** on the **6th string**"* or *"**사랑**"*).
2. The user performs/recalls it (plays the note on the guitar, says the word's meaning).
3. The user taps **OK** → the app records the **response time** (prompt shown → OK tapped) and **reveals the answer** (fretboard diagram with the fret highlighted / the translation).
4. The user self-grades **✓ Correct** or **✗ Wrong**.
5. Next card — random, but **not in an obvious pattern** (no immediate repeats, no runs on the same string, etc.).
6. At the end, a **summary** of times and accuracy.
7. Over sessions, cards that were **slow or wrong** are shown **more often**.

The same engine must later support chords, arpeggios, scales, triads, progressions, Korean sentences, grammar, listening, etc. **Extensibility of card types is a first-class requirement**, even though M1 ships only two.

Non-goals (for now): accounts, servers, social features, monetisation, App Store release, Android.

---

## 2. Milestone 1 scope

M1 = "fully functional iOS app that shows notes and basic Korean words".

**In scope**

| Area | Included in M1 |
|---|---|
| Decks | **Fretboard Notes** (generated), **Korean Core 1** (~200 most common words), **Korean — AION 2** (~80 in-game words) |
| Session | Configurable length, timed prompt, reveal, self-grade, wrong-card retry, pause/quit |
| Scheduler | Adaptive weighted-random selection with anti-pattern rules (§10) |
| Summary | Per-session stats + per-card list + chart |
| Stats | Per-deck history, trend chart, fretboard heatmap, weakest-items list |
| Korean extras | Text-to-speech pronunciation (on-device `AVSpeechSynthesizer`, `ko-KR`) |
| Settings | Note naming, accidentals, fret range, handedness, TTS, focus intensity, export data, reset stats |
| Input | Big tap targets, "tap anywhere" mode, **hardware keyboard / Bluetooth page-turner pedal** support |
| Persistence | Local, on-device (SwiftData) |
| Quality | Unit tests for all logic, CI building the iOS app |

**Out of scope for M1** (see §15): microphone pitch detection, audio note playback, chords/scales/etc., Korean sentences, custom user decks, iCloud sync, widgets, notifications.

---

## 3. Core user flow

```
Home (deck list)
  └─ tap deck ─► Session Setup sheet (length, options) ─► Start
                    └─► Session screen
                          ┌──────────────────────────────────────────┐
                          │ PROMPT  (timer running, hidden by default)│
                          │   [            OK            ]            │
                          └──────────────────────────────────────────┘
                                         │ tap OK (time recorded)
                          ┌──────────────────────────────────────────┐
                          │ REVEAL  (fretboard / translation + TTS)   │
                          │   [ ✗ Wrong ]        [ ✓ Correct ]         │
                          └──────────────────────────────────────────┘
                                         │ grade (persisted immediately)
                                 next card … until session length reached
                    └─► Summary screen ─► Done (back to Home)
Home ─► Stats tab (per deck history, heatmap, weakest items)
Home ─► Settings tab
```

---

## 4. Tech stack and constraints

| Concern | Decision | Rationale |
|---|---|---|
| Language | **Swift 6** (strict concurrency on) | Current standard |
| UI | **SwiftUI** | Simple, declarative, previews |
| Min iOS | **iOS 17.0** | Needed for SwiftData + `@Observable` |
| Persistence | **SwiftData** (app layer only) | Built-in, zero deps |
| Charts | **Swift Charts** | Built-in |
| TTS | **AVFoundation `AVSpeechSynthesizer`** | Offline Korean voice |
| Project generation | **XcodeGen** (`project.yml`) | Agents never hand-edit `.pbxproj`; merge-friendly |
| Logic package | **Local Swift Package `MemoriseCore`** | Pure Swift, **no Apple-UI imports**, buildable and testable on **Linux** with `swift test` |
| Third-party deps | **None** in M1 | Keep it simple |
| Devices | iPhone first (portrait + landscape). iPad works but is not optimised. | Personal use |

### The critical architectural rule

All domain logic (music theory, deck generation, deck loading, scheduling, stats maths, session state machine, summaries) lives in **`MemoriseCore`**, which:

- imports only `Foundation` (no SwiftUI, SwiftData, AVFoundation, UIKit, Charts);
- has deterministic, injectable **randomness** (`RandomNumberGenerator`) and **clock** (§9.1);
- defines persistence as a **protocol** (`StatsStore`) with an **in-memory implementation** for tests.

The **App target** is a thin layer: SwiftUI views, view models (`@Observable`), the SwiftData implementation of `StatsStore`, TTS, haptics.

This lets implementing agents running on Linux (no Xcode) build and test almost everything with `swift test`; the iOS build is verified by CI on a macOS runner (§14).

---

## 5. Repository layout

```
Memorise/
├── PLAN.md                         ← this file
├── README.md                       ← short: what it is, how to build, link to PLAN.md
├── CLAUDE.md                       ← agent conventions (created in S0, summarises §16)
├── project.yml                     ← XcodeGen spec (app + test targets)
├── .gitignore                      ← Xcode, SwiftPM, .DS_Store, *.xcodeproj (generated)
├── .github/workflows/
│   ├── core-tests.yml              ← Linux: swift test on MemoriseCore
│   └── ios-build.yml               ← macOS: xcodegen + xcodebuild build & test
├── Packages/
│   └── MemoriseCore/
│       ├── Package.swift
│       ├── Sources/MemoriseCore/
│       │   ├── Domain/             ← Card, CardContent, Deck, ItemKey, Attempt, SessionRecord, ItemStats, DeckOptions
│       │   ├── Music/              ← PitchClass, NoteName, Spelling, Solfege, Tuning, Fretboard
│       │   ├── Decks/              ← FretboardNotesDeck, VocabDeck, DeckCatalog
│       │   ├── Korean/             ← VocabEntry, VocabDeckFile (JSON schema), Hangul helpers
│       │   ├── Scheduling/         ← Scheduler, WeightCalculator, PatternRules, IntroductionPolicy, SeededRNG
│       │   ├── Session/            ← SessionEngine (state machine), MonotonicClock, SessionConfig
│       │   ├── Stats/              ← StatsUpdater, Summary, Statistics helpers (median, p90…)
│       │   ├── Persistence/        ← StatsStore protocol, InMemoryStatsStore, Export (JSON/CSV)
│       │   └── Resources/Decks/    ← ko_core_1.json, ko_aion2.json (bundled via Bundle.module)
│       └── Tests/MemoriseCoreTests/
└── App/
    ├── Sources/
    │   ├── MemoriseApp.swift
    │   ├── AppEnvironment.swift    ← wires store, catalog, settings, TTS
    │   ├── Persistence/            ← SwiftData @Model types + SwiftDataStatsStore
    │   ├── Features/
    │   │   ├── Home/
    │   │   ├── SessionSetup/
    │   │   ├── Session/
    │   │   ├── Summary/
    │   │   ├── Stats/
    │   │   └── Settings/
    │   ├── Components/             ← FretboardView, VocabCardView, BigButton, StatTile…
    │   ├── Services/               ← SpeechService (TTS), Haptics, KeyboardInput
    │   └── Support/                ← Formatters, Color tokens, Preview data
    ├── Resources/
    │   ├── Assets.xcassets         ← AppIcon, AccentColor
    │   └── Info.plist (generated by XcodeGen settings where possible)
    ├── Tests/                      ← AppTests (SwiftData store tests, view-model tests)
    └── UITests/                    ← one smoke test: start a session, answer, see summary
```

Deck JSON files live **inside the core package** so Linux tests can validate them.

---

## 6. Domain model

All types below are in `MemoriseCore`, `Sendable`, and `Codable` where noted.

### 6.1 Identifiers — stability is sacred

```swift
public struct DeckID: Hashable, Codable, Sendable { public let raw: String }   // e.g. "music.fretboard.notes", "ko.core.1", "ko.aion2"
public struct ItemKey: Hashable, Codable, Sendable { public let raw: String }  // unique across ALL decks
```

- `ItemKey` is the key for statistics. **Never reuse or rename an ItemKey** once shipped; stats are joined on it.
- Fretboard: `"fret:s6:A"` (string number + pitch-class canonical sharp name, e.g. `"fret:s3:C#"`).
- Korean: `"<entryId>#<direction>"`, e.g. `"ko.core.0042#ko-en"`, `"ko.core.0042#en-ko"`. Each direction has its own stats.
- If deck content is removed, orphaned stats are simply ignored (never crash).

### 6.2 Cards

```swift
public struct Card: Identifiable, Hashable, Sendable {
    public var id: ItemKey { key }
    public let key: ItemKey
    public let deckID: DeckID
    public let content: CardContent
}

/// Extensible: add a case per new card type (chords, scales, sentences…).
public enum CardContent: Hashable, Sendable {
    case fretboardNote(FretboardNotePrompt)     // M1
    case vocab(VocabPrompt)                     // M1
    // future: .fretPositionToNote, .interval, .chordShape, .scale, .triad, .progression, .sentence, .listening …
}

public struct FretboardNotePrompt: Hashable, Sendable {
    public let stringNumber: Int          // 1 = high E … 6 = low E (standard guitar numbering)
    public let pitchClass: PitchClass
    public let spelling: NoteSpelling     // how to display it (A, C♯, D♭…) chosen at generation time
    public let answerFrets: [Int]         // all frets in the configured range that produce this pitch class
}

public struct VocabPrompt: Hashable, Sendable {
    public let entry: VocabEntry
    public let direction: VocabDirection  // .koToEn or .enToKo
}
```

Rendering is the App's job: the App switches on `CardContent` and picks a prompt view and an answer view. Adding a new card type = new case + new deck generator/loader + two views. Nothing else in the engine changes.

### 6.3 Decks

```swift
public protocol Deck: Sendable {
    var id: DeckID { get }
    var title: String { get }
    var subject: Subject { get }                 // .music, .korean
    /// All cards available under the given options (options are deck-specific, see below).
    func cards(options: DeckOptions) -> [Card]
    /// Deck-specific anti-pattern penalty in (0, 1]; 1 = no penalty. See §10.4.
    func patternPenalty(candidate: Card, recent: [Card]) -> Double
    /// Optional introduction ordering for unseen cards (e.g. Korean frequency rank). nil = no gating.
    func introductionRank(of card: Card) -> Int?
}

public enum Subject: String, Codable, Sendable { case music, korean }

public enum DeckOptions: Hashable, Codable, Sendable {
    case fretboard(FretboardOptions)
    case vocab(VocabOptions)
}
```

`DeckCatalog` returns all built-in decks: `FretboardNotesDeck`, `VocabDeck(file: ko_core_1.json)`, `VocabDeck(file: ko_aion2.json)`.

### 6.4 Records & stats

```swift
public struct SessionRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let deckID: DeckID
    public let startedAt: Date
    public var endedAt: Date?
    public var status: SessionStatus            // .inProgress, .completed, .abandoned
    public let config: SessionConfig            // snapshot (length, options, focus) for history
}

public struct Attempt: Identifiable, Codable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let itemKey: ItemKey
    public let deckID: DeckID
    public let index: Int                       // position in session (0-based)
    public let shownAt: Date                    // wall clock, for history only
    public let responseMs: Int                  // prompt fully shown → OK tapped (MONOTONIC clock)
    public let gradeMs: Int                     // OK tapped → grade tapped
    public let correct: Bool
    public let isRetry: Bool                    // re-shown after a wrong answer in the same session
    public let wasInterrupted: Bool             // app went to background / paused while prompt visible
}

public struct ItemStats: Codable, Sendable, Equatable {
    public let itemKey: ItemKey
    public let deckID: DeckID
    public var attempts: Int                    // counted attempts (excludes retries & interrupted)
    public var correctCount: Int
    public var ewmaResponseMs: Double?          // over CORRECT counted attempts only
    public var ewmaError: Double                // 0…1, EWMA of (wrong ? 1 : 0)
    public var bestResponseMs: Int?
    public var lastSeenAt: Date?
    public var lastWrongAt: Date?
}
```

---

## 7. Music module (fretboard notes)

### 7.1 Theory primitives

- `PitchClass`: 0…11, `C = 0`, `C♯/D♭ = 1`, … `B = 11`. Arithmetic modulo 12.
- `NoteLetter`: C D E F G A B. `Accidental`: natural, sharp, flat.
- `NoteSpelling { letter, accidental }` → `pitchClass`. Display uses the Unicode symbols **♯ ♭** (not `#`/`b`) in UI; ItemKeys use ASCII canonical sharps (`C#`).
- **Solfège (fixed-do)**: C Do, D Re, E Mi, F Fa, G Sol, A La, B **Si** (setting allows **Ti**). Accidentals carry over: `Do♯`, `Si♭`.
- `NoteNaming` setting: `.letter` → "A", `.solfege` → "La", `.both` → **"A (La)"** (default, matches the user's example).
- `Tuning`: list of open-string pitches from string 6 → 1. M1 ships **Standard: E2 A2 D3 G3 B3 E4**. Pitches stored as MIDI numbers (E2 = 40, A2 = 45, D3 = 50, G3 = 55, B3 = 59, E4 = 64) so future features (octaves, audio) work. The Tuning type must allow other tunings later (Drop D, etc.).
- `Fretboard.frets(for pitchClass:, onString:, tuning:, fretRange:) -> [Int]`: all frets f in range where `(openMidi + f) % 12 == pitchClass`.
  - Example: A on string 6, range 0…12 → `[5]`; range 0…22 → `[5, 17]`. E on string 6, 0…12 → `[0, 12]`.

### 7.2 Fretboard Notes deck

`FretboardOptions` (with defaults):

| Option | Type | Default | Notes |
|---|---|---|---|
| `strings` | Set<Int> | {1,2,3,4,5,6} | User can drill e.g. only 5 & 6 |
| `noteSet` | enum | `.naturals` | `.naturals` (7 per string), `.all` (12 per string) |
| `accidentalSpelling` | enum | `.sharps` | `.sharps`, `.flats`, `.mixed` (random per card, deterministic given RNG) |
| `fretRange` | ClosedRange<Int> | 0…12 | max fret 12/15/17/19/22/24; affects which frets are *shown* in the answer (with max ≥ 11 every pitch class exists on every string) |

Cards = every (string ∈ strings) × (pitchClass ∈ noteSet) that has **at least one** answer fret in range. Naturals → 42 cards; all → 72 cards.

**Prompt text**: `Play {note} on string {n} ({open-string name})`, e.g. *"Play **A (La)** on **string 6** (low E)"*. A setting `showStringHint` (default true) toggles the "(low E)" hint. String names: 6 "low E", 5 "A", 4 "D", 3 "G", 2 "B", 1 "high E".

**Answer view**: horizontal fretboard diagram (see §11.5) with the target string highlighted and **every** matching fret in range marked, plus the text "Fret 5 (also 17)".

**Pattern penalty** (§10.4): same string as previous card ×0.35; same pitch class as previous ×0.35; same string as 2-back ×0.7. Penalties multiply.

---

## 8. Korean module (vocabulary)

### 8.1 Card directions

- **ko→en (recognition)**: prompt shows **Hangul** large (no romanization); user recalls the meaning (out loud or mentally) → OK → reveal shows romanization, meaning(s), part of speech, example sentence, 🔊 button.
- **en→ko (production)**: prompt shows the **English meaning(s)** + part of speech; user says/writes the Korean → OK → reveal Hangul + romanization + 🔊.
- `VocabOptions.direction`: `.koToEn` (default), `.enToKo`, `.both` (both directions are separate items in the pool; pattern rule prevents the two directions of the same entry being shown back-to-back).
- `VocabOptions.newPerSession`: Int, default **10** (see §10.5).
- `VocabOptions.autoPlayAudio`: Bool, default **true** for reveal on ko→en, and on reveal for en→ko.
- `VocabOptions.tags`: optional tag filter (e.g. only "combat" words from the AION deck). M1: support in core; UI may expose as a simple multi-select.

Grading is always **self-graded**; synonyms/close answers are the user's call.

### 8.2 Deck file JSON schema (v1)

File: `Packages/MemoriseCore/Sources/MemoriseCore/Resources/Decks/<file>.json`

```json
{
  "schemaVersion": 1,
  "deckId": "ko.core.1",
  "title": "Korean Core 1",
  "subtitle": "200 most common words",
  "subject": "korean",
  "entries": [
    {
      "id": "ko.core.0001",
      "hangul": "나",
      "romanization": "na",
      "meanings": ["I", "me"],
      "pos": "pronoun",
      "rank": 1,
      "tags": ["pronoun"],
      "hanja": null,
      "example": { "ko": "나는 학생이에요.", "en": "I am a student." },
      "notes": "Casual. Polite/humble form: 저."
    }
  ]
}
```

Rules (enforced by a validator + unit test that runs over every bundled file):

- `id` unique across **all** files; format `<deckId-prefix>.<4-digit number>`; never reused.
- `hangul` non-empty, contains only Hangul syllables (U+AC00–U+D7A3), spaces, and `~`/`-` punctuation.
- `romanization`: **Revised Romanization of Korean**, lowercase, non-empty.
- `meanings`: 1–4 short English glosses, most common first.
- `pos` ∈ {noun, pronoun, verb, adjective, adverb, particle, determiner, numeral, interjection, expression, counter, suffix}.
- Verbs/adjectives are listed in **dictionary form** (`-다`), e.g. 가다, 먹다, 좋다.
- `rank`: 1…N, unique within the file, defines introduction order (§10.5).
- `example` optional; if present, both `ko` and `en` non-empty, short (≤ 40 Hangul chars), polite `-요` style preferred.

### 8.3 Bundled content for M1

**`ko_core_1.json` — Korean Core 1 (~200 entries)**
Content source/criteria for the authoring agent:
- Take the highest-frequency everyday vocabulary (reference: National Institute of Korean Language 한국어 학습용 어휘 목록, Level A / TOPIK I core vocabulary). Do not copy any copyrighted list verbatim; author entries yourself.
- Composition guide: pronouns & people (~15), core verbs (~40: 하다, 있다, 없다, 되다, 가다, 오다, 보다, 먹다, 마시다, 알다, 모르다, 주다, 받다, 말하다, 듣다, 읽다, 쓰다, 사다, 만들다, 좋아하다, 싫어하다, 살다, 자다, 일하다, 공부하다, 기다리다, 만나다, 앉다, 서다, 열다, 닫다, 시작하다, 끝나다, 찾다, 놀다, 배우다, 가르치다, 생각하다, 싸우다, 이기다 …), core adjectives (~25: 좋다, 나쁘다, 크다, 작다, 많다, 적다, 길다, 짧다, 빠르다, 느리다, 쉽다, 어렵다, 맛있다, 재미있다, 강하다, 약하다, 높다, 낮다, 새롭다, 같다, 다르다 …), time words (~15: 오늘, 내일, 어제, 지금, 나중에, 아침, 밤, 시간, 주, 년 …), numbers (Sino: 일 이 삼 … 십, 백, 천, 만; Native: 하나 둘 셋 … 열), question words (누구, 뭐/무엇, 언제, 어디, 왜, 어떻게, 얼마, 몇), common nouns (~40: 사람, 친구, 집, 물, 밥, 돈, 일, 말, 이름, 문, 길, 나라, 눈, 손, 머리, 마음, 세상 …), adverbs & connectors (~20: 아주, 정말, 너무, 다시, 같이, 먼저, 그리고, 그런데, 그래서, 하지만, 안, 못, 잘, 빨리, 천천히 …), essential expressions (~10: 네, 아니요, 감사합니다, 미안합니다, 안녕하세요, 괜찮아요, 잠깐만요 …).

**`ko_aion2.json` — Korean · AION 2 (~80 entries)**
Game UI / gameplay vocabulary, tagged by area. Seed list below (authoring agent fills romanization, examples, ranks; **the user should verify against the actual Korean AION 2 client** and the deck is designed to grow). Tag values in brackets.

| Hangul | Meaning | Tag |
|---|---|---|
| 퀘스트 | quest | ui |
| 임무 | mission, task | ui |
| 수락 | accept | ui |
| 거절 | decline | ui |
| 확인 | confirm, OK | ui |
| 취소 | cancel | ui |
| 완료 | complete | ui |
| 보상 | reward | ui |
| 획득 | acquire, obtain | ui |
| 설정 | settings | ui |
| 가방 / 인벤토리 | bag / inventory | ui |
| 지도 | map | ui |
| 우편 | mail | ui |
| 상점 | shop | ui |
| 구매 | purchase | ui |
| 판매 | sell | ui |
| 거래소 | trading post, broker | economy |
| 키나 | Kinah (currency) | economy |
| 장비 | equipment, gear | items |
| 무기 | weapon | items |
| 방어구 | armor | items |
| 장신구 | accessory | items |
| 물약 | potion | items |
| 소모품 | consumable | items |
| 재료 | material | items |
| 강화 | enhancement, upgrade | items |
| 제작 | crafting | items |
| 채집 | gathering | items |
| 등급 | grade, tier | items |
| 일반 / 고급 / 희귀 / 영웅 / 전설 / 신화 | common / superior / rare / heroic / legendary / mythic (one entry each) | items |
| 레벨 | level | character |
| 경험치 | experience (EXP) | character |
| 생명력 | HP | character |
| 정신력 | MP | character |
| 스킬 | skill | combat |
| 공격 | attack | combat |
| 방어 | defense | combat |
| 공격력 | attack power | combat |
| 방어력 | defense power | combat |
| 치명타 | critical hit | combat |
| 명중 | accuracy | combat |
| 회피 | evasion | combat |
| 막기 | block | combat |
| 저항 | resistance | combat |
| 피해 | damage | combat |
| 회복 | recovery, healing | combat |
| 재사용 대기시간 | cooldown | combat |
| 사망 | death | combat |
| 부활 | resurrection | combat |
| 몬스터 | monster | world |
| 보스 | boss | world |
| 던전 | dungeon | world |
| 필드 | field, open world | world |
| 마을 | village, town | world |
| 이동 | move, travel | world |
| 순간이동 | teleport | world |
| 비행 | flight | world |
| 날개 | wings | world |
| 천족 | Elyos | lore |
| 마족 | Asmodians | lore |
| 데바 | Daeva | lore |
| 어비스 | Abyss | lore |
| 파티 | party | social |
| 레기온 | legion (guild) | social |
| 친구 | friend | social |
| 귓속말 | whisper | social |
| 채팅 | chat | social |
| 검성 | Gladiator | class |
| 수호성 | Templar | class |
| 살성 | Assassin | class |
| 궁성 | Ranger | class |
| 마도성 | Sorcerer | class |
| 정령성 | Spiritmaster | class |
| 치유성 | Cleric | class |
| 호법성 | Chanter | class |

Ranks: order by usefulness when starting the game (ui → character → combat → items → world → social → class → lore).

### 8.4 Text-to-speech

`SpeechService` (App layer): `AVSpeechSynthesizer`, voice `AVSpeechSynthesisVoice(language: "ko-KR")`, rate ~0.45. Speaks `hangul` (and the example sentence via a second button). If no Korean voice is installed, show a one-time hint pointing to *Settings → Accessibility → Spoken Content → Voices → Korean*. Audio session category `.playback` with `.mixWithOthers` so it doesn't kill music the user might have playing.

---

## 9. Timing, session engine and statistics

### 9.1 Timing rules

- Response time = **monotonic** time between "prompt became visible" and "OK tapped". Use `ContinuousClock` (never `Date` for durations).
- Core defines `public protocol MonotonicClock: Sendable { func now() -> Duration }` (elapsed since an arbitrary origin). App uses a `ContinuousClock`-backed implementation; tests use a `ManualClock` that the test advances.
- "Prompt became visible": the App calls `engine.promptDidAppear()` from the prompt view's `onAppear` **after** any transition animation completes (use a transition duration ≤ 150 ms and call after it, or disable animation for the prompt). The engine starts the timer there, not when the card was selected.
- **Interruptions**: if the app leaves the foreground (`scenePhase != .active`) or the user pauses while a prompt is visible, the attempt is marked `wasInterrupted = true`. On resume, the **same card is re-shown with a fresh timer**; the interrupted attempt is stored for completeness but excluded from all stats and summaries.
- **Clamping** for stats (not for storage): response times are clamped to **[150 ms, 30 000 ms]** before entering EWMA/summary maths. Raw value is always stored.
- Timer display on the prompt is **hidden by default** (setting `showTimer`), to avoid pressure.
- `gradeMs` (OK → grade) is logged but not used by the scheduler in M1.

### 9.2 Session configuration

```swift
public struct SessionConfig: Codable, Hashable, Sendable {
    public var deckID: DeckID
    public var options: DeckOptions
    public var length: SessionLength          // .cards(Int) default 20; presets 10/20/30/50; or .minutes(Int) presets 3/5/10
    public var focus: FocusLevel              // .off (uniform), .normal (default), .strong — see §10
    public var retryWrongCards: Bool          // default true
}
```

Timed sessions end when the timer expires **after** the current card is graded.

### 9.3 Session engine (state machine)

`SessionEngine` is a pure, `@MainActor`-free value/class in core driven by the App's view model.

```
         start()
idle ───────────────► prompting(card)  ── promptDidAppear() → timer starts
                         │ ok()                      ▲
                         ▼                           │ next card
                      revealed(card, responseMs)     │
                         │ grade(correct:)           │
                         ▼                           │
                      graded ── more cards? ── yes ──┘
                         │ no
                         ▼
                      finished(summary)

pause()/interrupt(): prompting → paused → resume() → prompting(same card, new timer)
quit(): any → finished(summary of what was done)   (session status = .abandoned if 0 graded? else .completed)
grade lockout: grade(correct:) is ignored (no effects, no state change) until gradeLockoutMs (250 ms, SchedulerConstants) after the reveal; pause time does not count
undoLastGrade(): allowed only from the state right after a grade and before the next ok(); flips correctness, re-applies stats (stretch goal, nice to have)
```

Engine responsibilities:
1. Ask the **Scheduler** for the next card (passing history of this session).
2. Manage the **retry queue**: when a card is graded wrong and `retryWrongCards` is on, schedule it to re-appear after **3–5** further cards (random), or **earlier** when the scheduler has nothing else to offer (starved pool, see §10.6), and **at most once per card per session**. Retry attempts have `isRetry = true`. Retries do **not** count toward session length and are **excluded** from ItemStats updates (they're primed, so not informative) but are shown in the summary separately.
3. After each grade: build `Attempt`, call `StatsUpdater` to compute the new `ItemStats`, and persist **both immediately** through `StatsStore` (crash-safe).
4. On finish, compute `SessionSummary`.

On app launch, every `SessionRecord` with status `.inProgress` is closed before any read or write. If it has ≥ 1 counted attempt, it becomes `.completed`, with `endedAt` derived from its last attempt. Otherwise it becomes `.abandoned`. Attempts already saved are kept and remain valid. _(Revised 2026-11-16, F6.)_

### 9.4 Stats update (per counted attempt)

Constants (in one `SchedulerConstants` struct so they can be tuned):

| Constant | Value |
|---|---|
| `alphaTime` | 0.3 |
| `alphaError` | 0.3 |
| `minResponseMs` / `maxResponseMs` (clamp) | 150 / 30 000 |

```
t = clamp(responseMs)
attempts += 1
if correct:
    correctCount += 1
    ewmaResponseMs = (ewmaResponseMs == nil) ? t : alphaTime*t + (1-alphaTime)*ewmaResponseMs
    bestResponseMs = min(bestResponseMs ?? t, t)
    ewmaError = (1-alphaError)*ewmaError
else:
    ewmaError = alphaError*1 + (1-alphaError)*ewmaError
    lastWrongAt = now
    // a wrong answer's time does NOT update ewmaResponseMs (a fast wrong answer must not look "fast")
lastSeenAt = now
```

### 9.5 Session summary

`SessionSummary` (core) contains:
- counts: cards graded (excluding retries & interrupted), correct, wrong, accuracy %;
- timing over **correct, counted** attempts: mean, **median**, p90, fastest (card + ms), slowest (card + ms), total session duration;
- comparison: median vs. previous completed session of the same deck (Δ ms and %), accuracy vs. previous;
- per-attempt rows: card, responseMs, correct, isRetry, and the item's **historical EWMA before this session** so the UI can show ▲ slower / ▼ faster per card;
- `slowest5` and `wrong` lists ("these will appear more often").

Statistics helpers (median, percentile with linear interpolation, mean) are in `Stats/Statistics.swift` with tests.

---

## 10. Adaptive scheduler

Goal: random-feeling sequence, **biased towards slow and wrong cards**, never patterned. Must be deterministic given an injected RNG (tests use a seeded `SplitMix64`).

### 10.1 Inputs

- `pool: [Card]` — `deck.cards(options:)`.
- `stats: [ItemKey: ItemStats]` for the deck.
- `history: [Card]` — cards already shown this session (in order, including retries).
- `focus: FocusLevel`, `now: Date`, `rng`.

### 10.2 Base weight per card

For a card with stats (`attempts > 0`):

```
ref      = median of ewmaResponseMs over all cards in the pool that have one (fallback 4000 ms if none)
ratio    = clamp((ewmaResponseMs ?? ref) / ref, 0.33, 4.0)
slow     = ratio ^ gamma          gamma: focus .off = 0, .normal = 1.5, .strong = 2.5
err      = 1 + k_err * ewmaError  k_err: .off = 0, .normal = 3, .strong = 5
unc      = 1 + 1 / attempts        (few observations → a bit more likely, to learn the true time)
stale    = 1 + min(daysSince(lastSeenAt), 14) / 14     (1…2; not-seen-for-a-while → more likely)
w        = slow * err * unc * stale
```

For a card **without** stats (unseen): `w = W_NEW = 1.5` (subject to §10.5 gating).

Floor: `w = max(w, 0.05)` so every eligible card can still appear.

### 10.3 In-session adjustments

- **Cooldown**: a card that is among the last `K` shown is ineligible (`w = 0`), `K = min(3, pool.count - 1)`.
- **Already shown this session** (and not a pending retry): `w *= 0.2` — approximates sampling without replacement while still allowing repeats in long sessions/small pools.
- Retries are injected by the engine's retry queue, not by the scheduler, but the scheduler's cooldown still applies (if a retry would violate cooldown, the engine delays it by one card).

### 10.4 Anti-pattern penalty

`w *= deck.patternPenalty(candidate, recent: history.suffix(3))`.
- Fretboard: rules in §7.2.
- Vocab: same entry in the other direction as previous card → ×0.1; same tag as both of the previous 2 cards → ×0.7.

### 10.5 Introduction gating (vocab decks)

To avoid throwing 200 unseen words at the user:
- Unseen cards are introduced in `introductionRank` order (frequency rank).
- Only the **next `newPerSession`** unseen cards (by rank) are eligible in a session; others have `w = 0`.
- If the eligible seen pool is too small to fill the session, the engine may exceed `newPerSession` to fill (log nothing special).
- Fretboard deck returns `nil` rank → no gating (all 42/72 cards are eligible from day one).

### 10.6 Selection

Weighted random choice over eligible cards (`Σw > 0`). If all weights are 0 (tiny pool + cooldown), relax cooldown to `K-1` and retry. If still 0:
1. The engine first flushes the earliest pending retry that is not the immediately previous card.
2. Otherwise, the scheduler picks uniformly from the **allowed set**: cards not excluded (no pending retries) and either seen or in `eligibleNew`. It excludes the immediately previous card when it can.
3. If the allowed set is empty, the scheduler returns `nil`. The engine then flushes any remaining retry, or ends the session.

The fallback never picks a pending-retry card or a gated unseen card. _(Revised 2026-11-16 after CODE_REVIEW P2-1; see PLAN_M1_FIXES.md F3.)_

### 10.7 Required tests (non-exhaustive)

- Same seed → same sequence.
- No card repeats within `K` positions; no same-string back-to-back above expected rate over 10 000 draws.
- A card with `ewmaResponseMs` 3× the median is drawn significantly more often (e.g. ≥ 2× the frequency of a median card over 10 000 draws at `.normal`).
- `.off` focus ≈ uniform (chi-square-ish tolerance) apart from cooldown.
- Wrong-heavy card (`ewmaError` 0.8) drawn more often than a correct one with equal time.
- Vocab gating: with 200 unseen and `newPerSession = 10`, a 20-card session introduces exactly the 10 lowest-rank entries (plus fill rule when nothing is seen).

---

## 11. UI / UX specification

General: SwiftUI, system fonts, Dark Mode supported, Dynamic Type supported for text (fretboard scales with width), large tap targets (≥ 60 pt for OK/grade), haptics on OK (light) and grade (success/error). `UIApplication.shared.isIdleTimerDisabled = true` during a session (restore after). Portrait and landscape.

Root: `TabView` with **Practice**, **Stats**, **Settings**.

### 11.1 Practice (Home)

- Sections **Music** and **Korean**, each a list of deck rows.
- Deck row: title, subtitle, small stats line: "42 cards · 87% · median 2.4 s · last: 2 days ago" (or "New").
- Tap → Session Setup sheet.

### 11.2 Session Setup (sheet)

- Length: segmented presets (10 / 20 / 30 / 50 cards) + "Timed" (3 / 5 / 10 min).
- Focus on weak cards: Off / Normal / Strong.
- Retry wrong cards: toggle.
- Deck-specific:
  - Fretboard: string chips (6 5 4 3 2 1, multi-select), Naturals / All notes, Sharps / Flats / Mixed, max fret.
  - Vocab: Direction (Korean → English / English → Korean / Both), New words per session (stepper 0–30), tag filter (optional).
- Last-used config per deck is remembered (in `@AppStorage`/UserDefaults as JSON).
- **Start** button.

### 11.3 Session screen

- Top bar: progress (`7 / 20` + thin progress bar, or remaining time), pause button, close (✕ → confirm "End session?" → summary of what was done).
- **Prompt state**: the prompt centred, very large (fretboard: note name huge, string line below; vocab: Hangul ~64 pt). Bottom half: huge **OK** button. Setting `tapAnywhereForOK` (default **on**) makes the entire screen act as OK (except top bar).
- **Reveal state**: answer view (fretboard diagram / vocab details with 🔊), response time shown small ("2.3 s", colored green/yellow/red vs. item's EWMA), and two large buttons **✗ Wrong** (left, red) and **✓ Correct** (right, green). Swipe left/right on the card as alternate gesture.
- **Hardware keyboard / Bluetooth page-turner pedal** (great for hands-on-guitar): via `.onKeyPress` / `.keyboardShortcut`:
  - Prompt: Space, Return, → , ↓, Page Down = **OK**.
  - Reveal: → / Page Down / Return = **Correct**; ← / Page Up / Backspace = **Wrong**.
  - Esc = pause.
  (Most page-turner pedals send arrow or Page Up/Down keys.)
- Paused overlay: "Paused — tap to resume" (the card will be re-shown with a fresh timer).
- Transitions: quick (≤150 ms) cross-fade; respect Reduce Motion.

### 11.4 Summary screen

- Header tiles: Cards, Accuracy, Median time, Total time; each with Δ vs. last session (▲/▼).
- Chart (Swift Charts): bar per card in order shown, height = response time, color = correct/wrong; horizontal rule at the median.
- "Slowest" list (top 5) and "Missed" list with a caption "These will show up more often".
- Full list (collapsible): card label, time, ✓/✗, ▲/▼ vs. history, retries marked.
- **Done** returns to Home. Also accessible later from Stats history.

### 11.5 Fretboard component (`FretboardView`)

- Drawn with SwiftUI `Canvas` (or `Path`s); horizontal; nut on the left (mirrored when **left-handed** setting is on).
- 6 strings, string 1 (high E) at **top** (as seen when looking down at the guitar while playing; setting `stringOrder` to flip, default high-E-on-top = tab orientation).
- Frets 0…maxFret with correct-ish **logarithmic spacing** (fret position ∝ 1 − 2^(−n/12)), normalised to the available width; inlay dots at 3, 5, 7, 9, 15, 17, 19, 21 and double at 12/24; fret numbers under 3/5/7/9/12.
- Highlights: target string drawn thicker/accent color; answer fret(s) as filled circles labeled with the note name; open-string answer (fret 0) drawn left of the nut.
- Reusable later for chords/scales: API takes a list of `FretMark { string, fret, label, style }` — design it generically now.

### 11.6 Stats tab

- Deck picker at top.
- Trend chart: median response time per completed session (line) + accuracy (secondary, or toggle).
- Session history list → tap opens that session's Summary.
- **Fretboard deck**: heatmap grid, rows = strings 6…1 (or 1…6 per setting), columns = 12 pitch classes, cell color = item `ewmaResponseMs` (green fast → red slow, grey unseen), small × marker if `ewmaError > 0.3`. Tap cell → popover with stats.
- **Vocab decks**: "Weakest words" list sorted by scheduler weight (descending) and a "Learned / Seen / New" count.

### 11.7 Settings tab

- Music: Note naming (Letter / Solfège / Both), "Si" vs "Ti", Left-handed, String order, Default max fret, Show string hint.
- Korean: Auto-play pronunciation, Speech rate, Show romanization on reveal (default on).
- Session: Tap anywhere for OK, Show timer during prompt, Haptics.
- Data: **Export** (JSON of all sessions + attempts + item stats, and CSV of attempts) via `ShareLink`; **Reset stats** per deck or all (confirmation dialog).
- About: version, link to repo (text only).

App settings are stored with `@AppStorage`; a `Settings` struct in core mirrors the values that core logic needs (e.g. naming, solfège variant) so formatting functions are testable.

---

## 12. Implementation segments

Each segment = one focused agent task. Order and dependencies:

```
S0 ─► S1 ─┬─► S2 ─► S3 ─┐
          ├─► S4 ───────┤
          └─► S5 ───────┴─► S6 ─► S7 ─► S8 ─► S9 ─► S10 ─► S11 ─► S12 ─► S13
```
S2, S4, S5 can run in parallel after S1. S9's `FretboardView` can start once S2 is done.

Every segment's **Definition of Done**: code compiles; `swift test` passes in `Packages/MemoriseCore` (on Linux if a toolchain is available, otherwise CI); CI iOS build green for segments touching `App/`; no new compiler warnings; public types documented with `///`; §17 tracker updated in this file; committed with a message `S<n>: <summary>`.

---

### S0 — Project scaffolding & CI
**Goal:** empty but buildable app + package + CI.
- Create layout of §5 (empty folders with `.gitkeep` where needed).
- `Packages/MemoriseCore/Package.swift`: swift-tools-version 6.0, platforms `.iOS(.v17)`, `.macOS(.v14)`; library `MemoriseCore`; test target; `resources: [.process("Resources")]`. Placeholder `Memorise.version` and one trivial test.
- `project.yml` (XcodeGen): app target `Memorise` (iOS 17, iPhone+iPad, bundle id `com.example.memorise` — leave a clear `# TODO: set your bundle id` comment and a `DEVELOPMENT_TEAM` setting left empty), depends on the local package; unit test target `MemoriseTests`; UI test target `MemoriseUITests`; `SWIFT_VERSION 6.0`, strict concurrency complete; Info.plist keys: display name "Memorise", supported orientations portrait + landscape, `UILaunchScreen` empty dict.
- `App/Sources/MemoriseApp.swift`: TabView with 3 placeholder tabs.
- `.gitignore`: `*.xcodeproj` (generated), `xcuserdata`, `.build`, `DerivedData`, `.DS_Store`, `.swiftpm`.
- `.github/workflows/core-tests.yml`: ubuntu-latest, install Swift 6 (e.g. `swift-actions/setup-swift` or `swift:6.0` container), `swift test` in the package.
- `.github/workflows/ios-build.yml`: macos-latest, `brew install xcodegen`, `xcodegen generate`, `xcodebuild -scheme Memorise -destination 'platform=iOS Simulator,name=<latest available iPhone>' build test` (`CODE_SIGNING_ALLOWED=NO`). Pick the simulator dynamically (`xcrun simctl list devices available`) so the workflow doesn't break when runner images change.
- `README.md` (short) and `CLAUDE.md` (agent conventions from §16).
**Accept:** both workflows green on push; `xcodegen generate && open Memorise.xcodeproj` runs on the user's Mac.

### S1 — Core domain types
**Goal:** §6 types in `Domain/`.
- `DeckID`, `ItemKey`, `Subject`, `Card`, `CardContent` (with M1 cases; associated prompt structs may be stubbed with the fields of §6.2 and filled by S2/S4), `Deck` protocol, `DeckOptions`, `SessionConfig`, `SessionLength`, `FocusLevel`, `SessionRecord`, `SessionStatus`, `Attempt`, `ItemStats` (with `static func empty(key:deck:)`).
- Codable round-trip tests for every Codable type.
**Accept:** tests green; types `Sendable`.

### S2 — Music theory primitives
**Goal:** §7.1 in `Music/`.
- `PitchClass`, `NoteLetter`, `Accidental`, `NoteSpelling` (+ preferred sharp/flat spelling for a pitch class), `Solfege` (Si/Ti), `NoteNaming` formatter (`"A (La)"`), `Tuning.standard` with MIDI numbers, string names, `Fretboard.frets(...)`.
**Accept:** tests: every string/pitch-class combo in standard tuning for range 0…12 and 0…24 (table-driven, spot-check A/s6 → [5,17] in 0…24, E/s1 → [0,12], C/s5 → [3,15], F♯/s4 → [4,16]); formatting tests for all naming modes and accidentals.

### S3 — Fretboard Notes deck
**Goal:** §7.2 `FretboardNotesDeck` conforming to `Deck`.
- Card generation from `FretboardOptions`, stable ItemKeys (`fret:s6:A`, `fret:s3:C#` — spelling choice must not change the key), prompt text builder (pure function taking naming settings), `patternPenalty`.
**Accept:** naturals = 42 cards, all = 72; strings filter works; key stability test (same pitch class spelled ♯ or ♭ → same key); penalty values as specified.

### S4 — Korean content & loader
**Goal:** §8.2–8.3.
- `VocabEntry`, `VocabDirection`, `VocabDeckFile` (Codable schema v1), `VocabDeck` conforming to `Deck` (cards per direction option, tag filter, `introductionRank`, `patternPenalty`), `DeckCatalog` loading from `Bundle.module`.
- `DeckValidator` implementing all rules of §8.2 returning a list of human-readable errors.
- **Author `ko_core_1.json` (~200 entries) and `ko_aion2.json` (~80 entries)** per §8.3. Accuracy matters: correct Hangul spelling, standard Revised Romanization, natural English glosses, polite-style examples.
**Accept:** validator test passes on all bundled files (0 errors); unique IDs across files; entry counts within ±10% of targets; `.both` produces 2 cards per entry with distinct keys.

### S5 — Scheduler & stats maths
**Goal:** §9.4 and §10.
- `SplitMix64: RandomNumberGenerator` (seedable), `SchedulerConstants`, `StatsUpdater`, `WeightCalculator`, `Scheduler.nextCard(...)`, `IntroductionPolicy`, `Statistics` (mean/median/percentile).
- Deck-agnostic: uses the `Deck` protocol (create a tiny `TestDeck` in tests).
**Accept:** all §10.7 tests + StatsUpdater tests (wrong answers don't change time EWMA; clamping; EWMA arithmetic).

### S6 — Session engine & summary
**Goal:** §9.1–9.3, §9.5.
- `MonotonicClock`, `ManualClock` (tests), `SessionEngine` state machine, retry queue, pause/interrupt/resume, quit, `SessionSummary` builder, optional `undoLastGrade`.
- Engine talks to `StatsStore` (protocol from S7 — define the protocol here if S7 is not yet done, see S7) and the Scheduler.
**Accept:** tests drive full sessions with `ManualClock` + seeded RNG + `InMemoryStatsStore`: correct responseMs; interrupted attempts excluded; retries appear 3–5 cards later (or earlier when the pool is starved, §10.6), once, not counted toward length; timed session ends after current card; summary numbers verified by hand-computed fixture.

### S7 — Persistence
**Goal:** storage behind a protocol.
- Core: `protocol StatsStore: Sendable` (async methods: `stats(for deck:) -> [ItemKey: ItemStats]`, `save(_ stats:)`, `save(_ attempt:)`, `upsert(_ session:)`, `sessions(for deck:)`, `attempts(for session:)`, `markInProgressSessionsAbandoned()`, `reset(deck:)`, `resetAll()`, `exportSnapshot() -> ExportSnapshot`). `InMemoryStatsStore` (actor). `Exporter` → JSON (`ExportSnapshot` Codable) and CSV (attempts).
- App: SwiftData `@Model` classes `SDSession`, `SDAttempt`, `SDItemStats` (unique `itemKey`), mapping to/from core structs; `SwiftDataStatsStore` using a `@ModelActor`. Schema versioned (`VersionedSchema` V1) so future migrations are possible.
**Accept:** core tests for in-memory store + exporter (CSV header/escaping); app tests (on CI) for SwiftData store CRUD with an in-memory `ModelConfiguration`.

### S8 — App shell, Home, Session Setup
**Goal:** §11.1–11.2.
- `AppEnvironment` (catalog, store, settings, speech) injected via `.environment`.
- Home deck list with stats line; Session Setup sheet with all options; remembered last config per deck.
- Abandon stale in-progress sessions at launch.
**Accept:** previews for both screens with sample data; launching shows 3 decks; Start navigates to a placeholder session screen with the config.

### S9 — Session screen & card renderers
**Goal:** §11.3, §11.5, §8.4.
- `SessionViewModel` (`@Observable`, wraps `SessionEngine`), Session screen states, `FretboardView` (generic `FretMark` API), fretboard prompt/answer views, vocab prompt/answer views, `SpeechService`, haptics, keep-awake, scenePhase interruption handling, keyboard/pedal input, tap-anywhere mode, swipe-to-grade.
**Accept:** full session playable on simulator for all 3 decks; previews for each card view in light/dark; UI smoke test (S13) can drive it via accessibility identifiers (`okButton`, `correctButton`, `wrongButton`).

### S10 — Summary screen
**Goal:** §11.4 with Swift Charts.
**Accept:** shows correct numbers for a seeded session (compare to core summary); reachable from session end and from history.

### S11 — Stats tab
**Goal:** §11.6: trend chart, history list, fretboard heatmap, weakest words.
**Accept:** previews with synthetic stats; heatmap colors match spec; tapping a session opens its summary.

### S12 — Settings, export, polish
**Goal:** §11.7 + app icon (simple generated icon: a guitar-fret/Hangul motif, single 1024 px asset), accent color, accessibility labels on all controls, Dynamic Type check, Reduce Motion, empty states, landscape layout check.
**Accept:** export produces valid JSON/CSV shared via share sheet; reset works with confirmation; no layout breakage at largest Dynamic Type on prompt screens.

### S13 — QA & release-to-self
- UI smoke test: launch → Fretboard deck → length 10 → answer all (alternate correct/wrong) → summary visible → Stats shows 1 session.
- Manual QA checklist (add to README): timing accuracy, background/foreground mid-card, pedal keys, TTS, export, reset, dark mode, landscape.
- README: install-on-device steps (§14).
**Accept:** all CI green; checklist completed by the user on device.

---

## 13. Testing strategy

| Layer | How | Where it runs |
|---|---|---|
| Core logic (theory, decks, validator, scheduler, stats, engine, exporter) | XCTest or Swift Testing (`import Testing`) — pick **Swift Testing** if the Linux toolchain supports it (Swift 6 does), else XCTest | Linux (`swift test`) + CI |
| Deck content | Validator test over all bundled JSON | Linux + CI |
| SwiftData store | XCTest with in-memory `ModelContainer` | macOS CI |
| View models | XCTest with `InMemoryStatsStore`, `ManualClock`, seeded RNG | macOS CI |
| UI | 1–2 XCUITest smoke flows + SwiftUI previews for every view | macOS CI / Xcode |

Determinism: no test may depend on wall-clock time or unseeded randomness.

---

## 14. Building, CI and installing on your iPhone

**Agents (Linux cloud sessions):** cannot run Xcode. They:
1. Work mostly in `MemoriseCore` and run `swift test` locally if a Swift 6 toolchain is available (install via `swiftly` / swift.org tarball if the network allows; otherwise rely on CI).
2. Push and rely on the **`ios-build.yml`** GitHub Actions macOS workflow to verify the app compiles and app/UI tests pass. Check the workflow result before marking a segment done. (Note: macOS runner minutes on private repos are billed at a higher rate; keep the workflow lean — single simulator, cache DerivedData if useful.)

**You (on your Mac):**
1. Install Xcode (latest) and XcodeGen (`brew install xcodegen`).
2. `git clone`, `xcodegen generate`, open `Memorise.xcodeproj`.
3. Set your Team in *Signing & Capabilities* (or set `DEVELOPMENT_TEAM` and bundle id in `project.yml`).
4. Plug in the iPhone (Developer Mode on: *Settings → Privacy & Security → Developer Mode*), select it, Run.
   - **Free Apple ID**: app expires after **7 days**; re-run from Xcode to refresh. Data persists across re-installs as long as the bundle id stays the same and you don't delete the app.
   - **Paid Apple Developer Program**: 1-year provisioning and TestFlight (install from your phone without a cable).

---

## 15. Future roadmap (post-M1)

Every item below should only need: new `CardContent` case(s), a deck generator/loader, prompt/answer views, optional pattern rules. The engine, scheduler, stats, summary and history are reused as-is.

**M2 — Music fundamentals+**
- Reverse cards: fretboard position shown → name the note.
- "Find all": play every A on the neck (answer shows all positions; one timing).
- Intervals on the fretboard (play a major 3rd above this note).
- **Audio playback** of the target note (AVAudioEngine plucked-string synth / sampler) for ear training.
- **Microphone pitch detection** (AVAudioEngine + YIN or autocorrelation) to auto-detect the played note → OK and correctness become automatic; precise reaction time. Requires `NSMicrophoneUsageDescription`.

**M3 — Harmony & shapes**
- Chords (open, barre, CAGED shapes), triads on string sets (1-2-3, 2-3-4, …) and inversions, arpeggios, scales and modes (positions/boxes, 3NPS), key signatures, diatonic chords in a key, progressions ("play ii–V–I in G", Roman numerals), circle of fifths. `FretboardView`'s `FretMark` API is reused for answers.

**M4 — Korean beyond words**
- Korean Core 2/3 decks (next frequency bands), Hangul reading deck, particles (은/는, 이/가, 을/를…), verb conjugation drills (present/past/future, polite/casual), short sentences and patterns, listening cards (TTS plays, you recall meaning), optional typed answers with the Korean keyboard and fuzzy check.
- **AION 2 screenshot → cards**: import a screenshot, on-device OCR with the Vision framework (supports Korean), pick unknown words, add them to a custom "My AION words" deck.
- User-created custom decks & JSON import.

**M5 — Korean phrases from K-pop & K-dramas** (can be scheduled before M2; must start after G1)
- New `ko.media` deck of everyday phrases heard in popular songs and dramas, using vocab deck schema v2 (additive: `register`, `dialogue`, `sources`).
- On reveal, a "snippet" panel shows an original mini-dialogue, verified "Heard in" references (title, artist/network, year, where, our own description; names only, no links), and the user's own on-device, text-only "My snippet".
- No lyrics, script transcripts or clips are bundled (copyright), and every media reference is verified with a citation. Full plan: [PLAN_M5_KOREAN_MEDIA.md](PLAN_M5_KOREAN_MEDIA.md).

**Later / quality of life**
- iCloud sync (SwiftData + CloudKit), home-screen widget with daily streak, practice reminders, spaced-repetition hybrid (combine response-time weighting with interval scheduling for Korean), Apple Watch remote OK button, Shortcuts/Siri "start fretboard session".

---

## 16. Conventions for implementing agents

- Read this plan; work on **one segment at a time**; keep diffs focused on that segment.
- `MemoriseCore` must not import SwiftUI/SwiftData/UIKit/AVFoundation/Charts.
- No third-party dependencies without updating this plan first.
- Inject randomness and clocks; no `Date()`/`.random()` calls in core logic paths except via injected providers.
- Never change or reuse an existing `ItemKey` or Korean entry `id`.
- Constants for scheduling live in `SchedulerConstants`; if you tune them, update §9.4/§10 here.
- SwiftUI: `@Observable` view models, `NavigationStack`, no `ObservableObject` in new code; every view has a `#Preview`.
- Accessibility identifiers on interactive controls used by UI tests.
- Commit message format: `S<n>: <short summary>`; update §17 in the same commit.
- Persisted `Codable` types use hand-written tolerant `init(from:)`; every new property needs a default; never rename coding keys or enum raw values.
- `DeckOptions` and `SessionLength` have a frozen, hand-written wire format. New cases are fine; renaming cases or changing payload types needs a legacy decode path plus an update to `PersistedFormatCheck`.
- If the plan is ambiguous or wrong, make the smallest sensible decision, implement it, and record it in **§17 Decision log**.

---

## 17. Progress tracker

| Segment | Status | Notes |
|---|---|---|
| S0 Scaffolding & CI | ☑ | Build-only CI (no tests, per owner) |
| S1 Domain types | ☑ |  |
| S2 Music theory | ☑ |  |
| S3 Fretboard deck | ☑ |  |
| S4 Korean content & loader | ☑ | Core 1 = 205, AION 2 = 81 entries |
| S5 Scheduler & stats | ☑ |  |
| S6 Session engine & summary | ☑ | undoLastGrade not implemented (stretch) |
| S7 Persistence | ☑ |  |
| S8 Shell, Home, Setup | ☑ |  |
| S9 Session screen | ☑ |  |
| S10 Summary screen | ☑ |  |
| S11 Stats tab | ☑ |  |
| S12 Settings & polish | ☑ |  |
| S13 QA | ☑ | UI smoke test skipped (no tests, per owner); manual checklist in README |

**M1.1 review fixes:** tracked in [PLAN_M1_FIXES.md](PLAN_M1_FIXES.md): §4 for Round 1 (F0–F10) and §8 for Round 2 (G1–G6).

### Decision log
_(Agents append dated entries here: decision, reason, segment.)_

- 2026-11-16 · All · Owner asked for implementation only: no unit/UI test targets; CI builds core (Linux) and app (macOS) without tests.
- 2026-11-16 · S6/S7 · `SessionEngine` is synchronous and returns `SessionEffect`s; `SessionRecorder` applies them to the `StatsStore` strictly in order on a background task (avoids non-Sendable engine crossing actors; still persisted per grade).
- 2026-11-16 · S1 · `Deck` gained `subtitle`, `defaultOptions` and `present(_:using:)` (random ♯/♭ choice for `.mixed` spelling at presentation time; key unchanged). `patternPenalty` takes `ArraySlice<Card>`.
- 2026-11-16 · S5 · `.off` focus = weight 1 for every eligible card (truly uniform). Pending retries are excluded from scheduler picks (engine injects them). Fill rule: gating relaxes until ≥ 6 eligible cards (`minEligiblePool`). `newPerSession` counts entries (ranks), both directions of an entry share a rank.
- 2026-11-16 · S6 · Interrupted attempt stores elapsed time so far with `correct = false`; paused time is excluded from timed sessions. When the length is reached, still-pending retries are dropped. Retries flush if the scheduler has nothing left.
- 2026-11-16 · S4 · Slash entries split (가방, 인벤토리 separate). Economy tag ranked after items. Deck ids prefixes: `ko.core.NNNN`, `ko.aion2.NNNN`.
- 2026-11-16 · S7 · `StatsStore` methods are `async throws`; added `attempts(forDeck:)` for trend charts. SwiftData models are flat (no relationships), config stored as JSON `Data`.
- 2026-11-16 · S0 · Info.plist generated at `App/Info.plist` (outside resources to avoid copy-phase clash). Resources bundled with `.copy("Resources/Decks")` to keep the subdirectory.
- 2026-11-16 · S11 · "Learned" = ≥ 3 counted attempts and error EWMA < 0.2.
- 2026-11-16 · M1.1 · Fix plan F2–F9 implemented. D1 = No: no test target, so F1 and every per-segment test step were skipped; F0 skipped (no commits requested). `VocabOptions.sanitized(allTags:)` added in core for P3-2. `Fmt.delta` zero renders `= 0.00 s` / `= 0 pt`. `undoLastGrade` remains deferred.
- 2026-11-16 · Planner · Round 2 review (N1–N7) planned as G1–G6 in PLAN_M1_FIXES.md §7–§10. N7 resolved: §9.3 and S6 now say retries may come back earlier in a starved pool, and §9.3's launch sweep text now matches F6.
- 2026-11-16 · M1.1 R2 · G1–G5 code implemented. G1: wire shape captured from the M1 build before editing; `FretboardOptions.strings` and `VocabOptions.tags` are now encoded sorted (decode unchanged) so `PersistedFormatCheck` byte comparison is deterministic (Set order is per-process). `SessionConfig` equality/hash exclude `recoveredFields`. G5: timing log + DEBUG-simulator seeder added; measurements pending (owner). G6 pending (owner, on device).
- 2026-11-16 · Planner · Added milestone M5 (K-pop/K-drama phrases with a reveal snippet panel), planned as K1–K5 in PLAN_M5_KOREAN_MEDIA.md. Bundled content excludes lyrics, transcripts and clips; references must be verified with citations; personal snippets are stored on-device only.
- 2026-11-16 · Owner/Planner · M5: no external links (names only, app stays offline); no audio clips in My snippet; content priority BTS, LE SSERAFIM, TWICE, NewJeans, ILLIT and newer groups, then reality shows (Kian's Bizarre B&B, The Devil's Plan), then popular dramas. Show references may be owner-verified (`citation: "owner"`).
