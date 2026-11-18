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
| Min iOS | **iOS 18.0** | SwiftData + `@Observable`; Translation framework (M6 Lyrics); raised from 17.0 on 2026-11-18 |
| Persistence | **SwiftData** (app layer only) | Built-in, zero deps |
| Charts | **Swift Charts** | Built-in |
| TTS | **AVFoundation `AVSpeechSynthesizer`** | Offline Korean voice |
| Project generation | **XcodeGen** (`project.yml`) | Agents never hand-edit `.pbxproj`; merge-friendly |
| Logic package | **Local Swift Package `MemoriseCore`** | Pure Swift, **no Apple-UI imports**, buildable and testable on **Linux** with `swift test` |
| Third-party deps | **None** | Keep it simple (M6 uses Apple frameworks + `URLSession` only) |
| Network | **Lyrics tab only** (M6) | Everything else stays offline |
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
- **Tuning prefix rule (M2):** fretboard decks keep their bare key scheme for standard tuning forever (`fret:s6:A`); other tunings prefix the scheme with `@<TuningID>` (`fret@dropD:s6:A`). M2 schemes: Name the Note `fretname:s6:f5`, Find All `findall:A`, Intervals `int:M3:s6`, Interval Ear `ear:M3:asc` (no tuning). `TuningID`, `Interval` and `EarMode` raw values are part of keys — never change them.
- **M3 schemes (standard tuning only):** Play the Chord `chord:<shapeId>` (open) / `chord:<shapeId>:<root>` (movable), Name the Chord `chordname:…`, Triads `triad:<quality>:<inversion>:<set>:<root>`, Arpeggios `arp:<quality>:s<rootString>:<root>`, Scales `scale:<type>:<system>:p<n>:<tonic>`, Key Signatures `keysig:<tonic>:<mode>:<direction>`, Diatonic `diatonic:<tonic>:<mode>:<size>:<degree>:<direction>`, Progressions `prog:<progressionId>:<tonic>`, Circle `cof:<question>:<tonic>`. Roots/tonics use ASCII spellings (`Bb`, `F#`, `Cb`). **Shape ids in `Resources/Shapes/chord_shapes.json` are frozen**, as are the raw values of `ChordQuality`, `ScaleType`, `ScaleSystem`, `TriadInversion`, `StringSet`, `Progression`, `KeyMode`, `KeySigDirection`, `DiatonicSize`, `DiatonicDirection` and `CircleQuestion`.
- **M4 schemes (Korean):** vocab decks (Core 1–N, Patterns, AION, user decks) keep `<entryId>#<direction>` and add the `listen` direction (`ko.core.0001#listen`, separate stats). Hangul Reading `hangul:v:ㅏ` / `hangul:c:ㄱ` / `hangul:s:밥` / `hangul:w:<entryId>`, Particles `particle:<particle>:<batchim|vowel|rieul>`, Conjugation `conj:<entryId>:<form>`. User deck ids are `user.<8 hex>` (plus the fixed `user.aion0001`), and entry ids are `<deckId>.NNNN`, never reused (`nextEntryNumber` only increases). The raw values of `VocabDirection`, `Particle`, `ConjForm`, `HangulReadingOptions.Stage` and `InputMode` are frozen.
- Fretboard: `"fret:s6:A"` (string number + pitch-class canonical sharp name, e.g. `"fret:s3:C#"`).
- Korean: `"<entryId>#<direction>"`, e.g. `"ko.core.0042#ko-en"`, `"ko.core.0042#en-ko"`. Each direction has its own stats.
- If deck content is removed, orphaned stats are simply ignored (never crash).
- **M6 lyrics cache:** `Application Support/LyricsCache/<spotifyID>.json`, one file per track (`LyricsCacheFile`: schema version, track, available/not-available result, glosses, fetch time). It holds fetched lyrics and machine glosses, so it is **never part of the data export** (copyright), is excluded from device backups, and can be rebuilt by reopening songs. Settings → Lyrics → Clear lyrics cache deletes it. Spotify's refresh token lives in the Keychain, not in a file. Details: [PLAN_M6_LYRICS.md](PLAN_M6_LYRICS.md) §4.7.

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

### 7.1b M2 theory additions
- `TuningID` presets: standard (E2 A2 D3 G3 B3 E4), dropD, halfDown (E♭ standard), dadgad, openG. String names derive from the open pitch: lowest "low X", highest "high X", others "X". `FretboardOptions.tuning` defaults to `.standard` (M1 data decodes as standard).
- `Interval` m2…P8 with `semitones`, `letterSteps` (TT spelled as A4), `shortName`, `longName`. `NoteSpelling.transposed(by:)` returns `nil` when a double accidental would be needed (callers re-roll).
- `Pitch` (MIDI): `octave` (MIDI 60 = C4), `frequency` (A4 = 440 Hz, 12-TET), `nearest(toFrequency:)`. `Fretboard.positions(of:strings:tuning:fretRange:)`, `Fretboard.midi(string:fret:tuning:)`.
- DEBUG `TheoryCheck.run()` asserts at launch next to `PersistedFormatCheck`.

### 7.1c M3 theory additions
- `Accidental` gained `doubleFlat`/`doubleSharp` (raw values 3/4, appended). `NoteSpelling.adding(letters:semitones:allowDouble:)`, `.ascii`, `init?(ascii:)`, `.enharmonic`.
- `Degree` (letter steps + semitones + label), `DegreeLabel.text(interval:)`, `ChordQuality` (15 qualities, PLAN_M3 §M3-1 table), `Chord` (one letter per degree; only `dim7`'s 7th may be a double flat; `Chord.spelled` tries the `RootNames` spelling, then its enharmonic).
- `ScaleType` (14 types) and `Scale` (single accidentals only, enharmonic fallback). `Key` limited to the 15 major signatures + 15 relative minors: `signature`, `relative`, `diatonicTriads/Sevenths(harmonicV:)`, `RomanNumeral`. `CircleOfFifths` (C G D A E B F♯ D♭ A♭ E♭ B♭ F). `Progression` (11 ids) with `realize(in:)`.
- `ChordShape` / `Voicing` / `ChordShapeLibrary.shared` (67 bundled shapes) and `ShapeValidator` (load-time, all configurations; failing shapes are dropped and reported in `DeckLoadReport.validationWarnings`).

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
- `example` optional; if present, both `ko` and `en` non-empty, short (≤ 40 Hangul chars), polite `-요` style preferred. **Custom (user) decks (M6 L8b):** `en` may be blank and `ko` may have up to 80 Hangul (a saved lyric line); pattern entries still need `en`.

**Schema v2** (`VocabDeckFile.currentSchemaVersion = 2`; files with version 1…2 are accepted, and v1 files stay valid). All v2 fields are optional:
- M4 (see §8.3b, PLAN_M4 §3.2): `conj`, `examples`, pos `pattern`.
- M5 (see [PLAN_M5_KOREAN_MEDIA.md](PLAN_M5_KOREAN_MEDIA.md) §3): `register` (casual/polite/formal), `dialogue` (2–4 original lines, speakers A/B/C, ≤ 40 Hangul each, containing the phrase), `sources` (0–3 `MediaRef`s: kind song/drama/show/film, title, by, year 1990…now, locator, context ≤ 200 chars, citation = `https` URL or `"owner"`). A `url` key on a source is a validator error (names only, no links). A source with an unknown `kind` is dropped and reported; the entry is kept.
- In v2 files, `expression` headwords may also contain `? ! , . …` (진짜?, 잠깐만!).

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

### 8.3b M4 additions (Korean beyond words)

Full spec: [PLAN_M4_KOREAN.md](PLAN_M4_KOREAN.md).

- **Schema v2** (`VocabDeckFile.currentSchemaVersion` = 2; v1 files are still accepted). The additions are all optional and tolerant:
  - `conj` (`ConjugationClass`: `regular`, `ha`, `b`, `d`, `s`, `reu`, `eu`, `l`, `h`, `copula`; an unknown value decodes as `regular`) is required on every bundled verb/adjective.
  - `examples` holds up to 3 `{ko, en}` pairs.
  - `pos` gains `pattern`; `pattern` entries must start with `-` or contain `~` and have ≥ 2 examples.
  - The validator has a `.user` mode for user decks: romanization and `conj` are optional, an empty deck is allowed, and ids use the user format.
- **Romanizer** (`Korean/HangulReading.swift`): RR for **isolated syllables only**, using initial/medial/final tables. Finals take their representative sound (k n t l m p ng) and initial ㅇ is silent. Words are never auto-romanized; real-word cards use the deck's own romanization.
- **Generated decks:**
  - **Hangul Reading** (`ko.hangul`) has stages basic vowels, basic consonants, aspirated/tense, complex vowels, syllables (140), batchim (154 curated) and real words. Gating follows stage order (`newPerSession` 8).
  - **Particles** (`ko.particles`, `Korean/Particles.swift`) has 13 cards. They cover topic 은/는, subject 이/가, object 을/를, and 과/와, direction 으로/로 (an ㄹ-final takes 로) and copula 이에요/예요. Each card picks a random noun of the right ending class from every Korean deck (pronouns excluded). These cards are `choice` only.
  - **Conjugation** (`ko.conjugation`, `Korean/Conjugator.swift`) has 7 forms: present/past/future polite, present casual, present formal, negative polite and want-to. It works from the stem and the `conj` irregular class, then applies vowel harmony, contraction (가+아 → 가, 오+아 → 와, 마시+어 → 마셔, 되+어 → 돼, 주+어 → 줘) and the ending with batchim-sensitive (으). Every ㄹ-final stem drops ㄹ.
- **Custom decks** (`user.*`) are stored in `Application Support/UserDecks/<id>.json` in the `VocabDeckFile` format plus `nextEntryNumber`. There is no import; the full export includes them as `userDecks` (export schema 2).
- **Screenshot words** (`Korean/ScreenshotWords.swift`) take the Hangul runs from each OCR line and strip one trailing particle (the longest match decides) only when ≥ 2 syllables remain. They are deduplicated and split into new and already-known (known = in any catalog deck).

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

**Answer modes (M2/M4):** `SessionConfig.inputMode: InputMode` decodes tolerantly; a missing value means `.touch`. Each `DeckUI` declares `supportedInputModes`, and Setup shows "Answer by" only when there is more than one.

| `InputMode` | How the user answers | Grading | Updates the time EWMA? |
|---|---|---|---|
| `touch` (default) | Reveal → self-grade | self | yes |
| `microphone` | play the note | auto, correct only (`answerEvaluated(correct:at:countsTime:)`) | yes, measured to the note onset; **no** for a timeout reveal or an onset before the prompt (R6-3) |
| `choice` | tap one of 2–4 options | auto: `ok()` at the tap, verdict graded on Next | **no** (R4-4); the error EWMA still updates |
| `typed` | type, then Return | auto (`AnswerMatcher`: exact / close / wrong) + override | **no**; the error EWMA still updates |

`StatsUpdater.apply(updateTime:)` leaves `ewmaResponseMs`/`bestResponseMs` alone when false. The `Attempt` still stores the raw `responseMs`, so there is no schema change.

**Time is decided per answer, not per session (R4-4).** The view model passes `ok(countsTime:)` (or `answerEvaluated(…, countsTime:)`) for each card:
- a touch reveal counts, including a card that falls back to touch inside a typed, choice or mic session;
- a typed or choice reveal never counts (`InputMode.countsTime` is true only for `touch` and `microphone`);
- a mic answer counts; a mic-timeout reveal doesn't, because its time is just the timeout;
- an answer whose onset is before the prompt appeared is graded but untimed (R6-3).

**"Close" (typed answers, `AnswerMatcher`):**
- *Hangul predicates* (verbs, adjectives): a real **affirmative** conjugation of the expected word (`Conjugator.allAcceptedForms`, `ConjForm.affirmative`, main spelling or alternate, with or without 요) is close. Negative forms (몰라요 for 알다, 없어요 for 있다, 안 가요 for 가다) are wrong (R5-1). A bare stem or another word with the same first syllable (가방 for 가다) is wrong (R4-2).
- *Other Hangul*: the same word or phrase with the polite 요 added or dropped is close (미안해요 for 미안해; R6-2, PLAN_R6_FIXES T3). Otherwise, for 1–2 syllables only a batchim slip is close (의사/의자 is wrong); for 3+ syllables, jamo distance ≤ 1.
- *English*: only dropped or extra letters (one at ≥ 5 letters, two at ≥ 9); substitutions and transpositions are wrong. Parentheticals in a gloss are ignored.
- Vocab "close" counts as correct (with override); conjugation "close" counts as wrong (`exactRequired`).

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
(No undo: `undoLastGrade` was dropped from the spec by owner decision D2, 2026-11-17. The "I was right / I was wrong" overrides on typed and choice reveals cover mis-grades before Next.)
quit(): any → finished(summary of what was done)   (session status = .abandoned if 0 graded? else .completed; API only since R7-F2)
discard(): any → finished(.abandoned) + one .discardSession effect: no record, no attempts, stats restored to their values at start (R7-F2)
"End session" button = discard() before the length is reached (R7-F2, owner D2: timeouts and killed apps keep the old behaviour)
grade lockout: grade(correct:) is ignored (no effects, no state change) until gradeLockoutMs (250 ms, SchedulerConstants) after the reveal; pause time does not count
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
- **Rounds** _(R7-F1, replaces the former "already shown ×0.2" factor; `alreadyShownFactor` is kept but unused)_: a non-retry card is shown again only after every other *allowed* card has been shown once in the current round. The scheduler picks in tiers: (1) cards not shown this round and not resting; (2) if none, cards shown this round that aren't resting — this starts a new round; (3) only then resting cards (tiny pools); (4) the uniform fallback (§10.6). Each tier applies the cooldown, relaxed once to `K-1`.
- **Correct cards rest**: a card answered correctly (non-retry) sits out the rest of its round and `correctRestRounds` (1) further rounds. A deck's `siblingKeys(of:)` (vocab: the entry's other directions) are marked shown and resting together with the card, so one entry appears once per round.
- Retries are injected by the engine's retry queue, not by the scheduler, but the scheduler's cooldown still applies (if a retry would violate cooldown, the engine delays it by one card).

### 10.4 Anti-pattern penalty

`w *= deck.patternPenalty(candidate, recent: history.suffix(3))`.
- Fretboard: rules in §7.2.
- Vocab: same entry in the other direction as previous card → ×0.1; same tag as both of the previous 2 cards → ×0.7.

### 10.5 Introduction gating

**Coverage-first sessions (R8-S1)** — decks with `usesCoverageSessions` (vocab, conjugation, Hangul reading); `SessionComposer`:
- An **entry** is all pool cards sharing one `introductionRank`. Card state: `new` (never attempted), `wrong` (`ItemStats.lastAnswerWasWrong`: `lastWrongAt == lastSeenAt`), else `correct`. Entry state: `wrong` (any wrong card), `fresh` (all new), `partial` (new + correct), `covered` (all correct).
- Queue order: ≤ `floor(targetEntries × reviewShare)` (0.3) *due* wrong entries (shuffled); `fresh` in rank order; `partial`; remaining due wrong; not-yet-due wrong (soonest first); `covered` (least recently seen first). One card per entry per session (fresh: random direction; partial: its new cards; covered: oldest card).
- A wrong card is **due** once `sessionsSinceMiss >= gap - 1`, where sessions are the deck's *completed* sessions starting after the miss and `gap = wrongGapSessions.lowerBound + fnv1a("<itemKey>|<lastWrongAt>") % width` (2…4; stable per miss, no stored state). `newPerSession` is ignored for these decks.
- A session never repeats an answered-correct word until the whole deck is covered. *Coverage* (Home ring) = pool cards whose last counted answer was correct ÷ pool cards (`DeckCoverage`).

**Unranked / music decks and other ranked decks (original rules):**

To avoid throwing 200 unseen words at the user:
- Unseen cards are introduced in `introductionRank` order (frequency rank).
- Only the **next `newPerSession`** unseen cards (by rank) are eligible in a session; others have `w = 0`.
- If the eligible seen pool is too small to fill the session, the engine may exceed `newPerSession` to fill (log nothing special).
- **Fill target (R7-F1):** whole ranks are added in order until seen + eligible *entries* (ranks, not cards) reach `min(entries in pool, max(minEligiblePool, targetDistinct))`. `targetDistinct` = `n` for `.cards(n)`, `m × cardsPerMinuteEstimate` (8) for `.minutes(m)`. So a session never has to repeat a word to fill its length.
- Fretboard deck returns `nil` rank → no gating (all 42/72 cards are eligible from day one).

### 10.6 Selection

_(R8-S1)_ With the composer, `Scheduler.allowed` (the keys of the first `targetEntries` composed entries) replaces the `eligibleNew`/seen test. When a round's allowed cards are used up and the session isn't over, the engine adds the next composed entry (`extendAllowed`, "top-up") instead of starting a new round; rounds repeat cards only when the queue is empty.

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

### 11.5b M2 layouts and microphone UX
- **Name the Note:** prompt = board with one unlabelled dot + highlighted string, "Which note?"; answer = note name, labelled dot, "String n (name), fret f", 🔊.
- **Find All:** prompt = "Find every A" + "strings 6–1 · frets 0–12"; answer = every position labelled with octave ("A2"), count, 🔊 arpeggio low→high.
- **Intervals:** prompt = "Play a major 3rd above C" + board with the root dot; answer = target name, root (orange) + targets (primary accent, others grey) in the playable window, "major 3rd = 4 semitones", 🔊 root→target.
- **Interval Ear:** prompt plays the two notes and starts the timer when the second note sounds; Replay never resets it. Answer = long name, semitones, both note names, 🔊.
- **Microphone (Notes, Intervals):** Setup toggle "Answer by playing" + "Reveal after 5/10/20 s". Prompt shows a "Listening…" chip with a level meter; a stable wrong note shows "Heard G♯" and keeps listening; a stable correct note grades correct immediately with the response time measured to the note onset. Timeout reveals for manual grading, and that card's time is not counted. Detector analysis runs only while listening; audio from before the prompt is ignored (R5-3, R6-3). Mic sessions show 🎤 in history and the summary.
- Settings → Music: "Play note on reveal" (default off), "Note volume".

### 11.5c M3 components and layouts
- `FretboardView(fretWindow:)`: a window not starting at 0 draws no nut and labels its first fret; spacing stays logarithmic within the window. `FretMark` gained `badge` (small order number) and `emphasised` (ring, e.g. triad bass).
- `ChordDiagramView`: vertical box, 5-fret window (nut when the voicing fits frets 1–5, else "Nfr"), ×/○ row, finger numbers, barre bar, roots in pink, left-handed mirroring, VoiceOver "B flat minor seventh, barre at fret 1, strings 5 to 1, x-1-3-1-2-1".
- `StaffView(signature:)`: treble staff with 𝄞 (Apple Symbols; "Treble" text fallback) and sharps/flats at standard positions.
- `CircleOfFifthsView(highlight:secondary:)`: majors outside, relative minors inside.
- Home: music decks get sub-headers from `Deck.group` (Fretboard, Ear, Chords & shapes, Scales, Theory); empty groups are hidden.
- Settings → Music: "Dot labels: Notes / Degrees" (scales, arpeggios, triads) and "Show chord shape hint".
- `NotePlayer`: 6 voices, `strum` / `sequence` / `progression`; voices are assigned when a note starts (render-thread pending queue), so long sequences don't steal their own notes.

### 11.5d M4 Korean UX
- **Typed:** a `TypedAnswerField` sits below the prompt. It autofocuses with autocorrect and auto-capitalisation off, and Return submits. The field persists across cards, so the keyboard stays up, and it is cleared on each new card. "Don't know" reveals the card as wrong. Pedal/arrow keys are disabled while the field has focus. A Hangul answer with no Korean keyboard enabled shows "Add the Korean keyboard in Settings → General → Keyboard". The reveal shows a verdict banner (✓ Correct / ≈ Close: check spelling / ✗), *yours* vs *expected* with the differences highlighted, "I was right" / "I was wrong" overrides, and **Next**.
- **Choice:** 2–4 large option buttons (Particles: "책은" / "책는"; Name the Chord: 4 options). A tap reveals the verdict and rule; Next grades it. The tap time is stored on the attempt but does not feed the time EWMA (R4-4).
- **Auto-advance:** after 0.8 s on an exact typed/choice answer. This is the Settings → Session toggle "Auto-advance typed/choice answers" (default on).
- **Listening:** the prompt is a large 🔊 with no text. The timer starts when TTS finishes, and Replay doesn't reset it. Without a Korean voice, the Setup option is disabled and existing listening cards are filtered out. The weakest-words list labels listen items 🔊.
- **Home:** the Korean section is ordered Hangul Reading, Core 1…N, Particles, Conjugation, Patterns, other bundled decks, AION 2. A separate **My decks** section follows, with "+ New deck" and "AION 2 words from a screenshot".
- **My decks:** the deck editor has a title, subtitle, word list with swipe-delete, an add/edit word sheet (hangul, meanings, pos, optional romanization/example/tags) and a delete-deck confirmation (this also resets stats). The "My AION words" editor has "Add from screenshot".
- **Screenshot import:** `PhotosPicker` (images only), then Vision OCR (ko-KR + en-US, `.accurate`), then a review list with checkboxes. Each selected word needs a typed meaning; romanization is optional. The list also shows "Already known (n)". The screenshot is never stored.
- **Stats:** Hangul Reading shows a syllable grid per stage, coloured by error EWMA.

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

### 11.8 Lyrics tab (M6)

Full spec: [PLAN_M6_LYRICS.md](PLAN_M6_LYRICS.md) §4 and §5 (L6–L8). Tab `music.note.list`, tag 3, shown second.
- **Picker:** setup text when no Spotify client ID is configured; a Connect Spotify card when signed out; when connected, a Now playing card, a search field and Recent / Playlists / Liked lists. Tapping a song starts it in Spotify and opens the reader.
- **Reader:** two pages, Korean and English (swipe left). Tap a word or phrase for a bubble (meaning, 🔊, ＋ Add to deck). A track without Korean lyrics shows "Lyrics not available for this track"; a missing translation shows "English translation not available". Footer names the sources, no links.
- **Add to deck:** saves the word to a new or existing custom deck with a "Heard in" song reference.
- **Settings:** Lyrics section with Clear lyrics cache and Disconnect Spotify.

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
- `MonotonicClock`, `ManualClock` (tests), `SessionEngine` state machine, retry queue, pause/interrupt/resume, quit, `SessionSummary` builder. (`undoLastGrade` dropped, D2.)
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

**M2 — Music fundamentals+**: planned in [PLAN_M2_MUSIC.md](PLAN_M2_MUSIC.md) (M2-0a…M2-8, starting with F10 deck extensibility and alternate tunings).
- Reverse cards: fretboard position shown → name the note.
- "Find all": play every A on the neck (answer shows all positions; one timing).
- Intervals on the fretboard (play a major 3rd above this note).
- **Audio playback** of the target note (AVAudioEngine plucked-string synth / sampler) for ear training.
- **Microphone pitch detection** (AVAudioEngine + YIN or autocorrelation) to auto-detect the played note → OK and correctness become automatic; precise reaction time. Requires `NSMicrophoneUsageDescription`.

**M3 — Harmony & shapes**: planned in [PLAN_M3_HARMONY.md](PLAN_M3_HARMONY.md) (M3-0…M3-11; requires M2-0a/0b/0c, M2-1, and M2-5 for playback).
- Chords (open, barre, CAGED shapes), triads on string sets (1-2-3, 2-3-4, …) and inversions, arpeggios, scales and modes (positions/boxes, 3NPS), key signatures, diatonic chords in a key, progressions ("play ii–V–I in G", Roman numerals), circle of fifths. `FretboardView`'s `FretMark` API is reused for answers.

M3 status: code implemented 2026-11-17 (see §17 decision log and the PLAN_M3_HARMONY.md tracker).

**M4 — Korean beyond words**: planned in [PLAN_M4_KOREAN.md](PLAN_M4_KOREAN.md) (M4-0…M4-10; requires M2-0a/0b).
- Korean Core 2/3 decks (next frequency bands), Hangul reading deck, particles (은/는, 이/가, 을/를…), verb conjugation drills (present/past/future, polite/casual), short sentences and patterns, listening cards (TTS plays, you recall meaning), optional typed answers with the Korean keyboard and fuzzy check.
- **AION 2 screenshot → cards**: import a screenshot, on-device OCR with the Vision framework (supports Korean), pick unknown words, add them to a custom "My AION words" deck.
- User-created custom decks (no import, owner decision 2026-11-16).

M4 status: implemented 2026-11-17 for M4-0, M4-2…M4-10 (see §8.3b, §9.2, §11.5d, the §17 decision log and the PLAN_M4_KOREAN.md tracker). M4-1 content is in: Core 2–5 are added, and Core 5 was extended to 450 entries (M4-1b, see §17; PLAN_R6_FIXES T2). Dictionary verification is still open (`docs/core-verification.md`, R4-6/R6-4).

**M5 — Korean phrases from K-pop & K-dramas** (can be scheduled before M2; must start after G1)
- New `ko.media` deck of everyday phrases heard in popular songs and dramas, using vocab deck schema v2 (additive: `register`, `dialogue`, `sources`).
- On reveal, a "snippet" panel shows an original mini-dialogue, verified "Heard in" references (title, artist/network, year, where, our own description; names only, no links), and the user's own on-device, text-only "My snippet".
- No lyrics, script transcripts or clips are bundled (copyright), and every media reference is verified with a citation. Full plan: [PLAN_M5_KOREAN_MEDIA.md](PLAN_M5_KOREAN_MEDIA.md).

**M6 — K-pop Lyrics reader**: planned in [PLAN_M6_LYRICS.md](PLAN_M6_LYRICS.md) (L0…L9).
- A new Lyrics tab: connect Spotify (PKCE, Premium), pick a song, and it plays in Spotify in the background while Memorise shows its Hangul lyrics (LRCLIB, then Genius), fetched at runtime and cached on-device only.
- Tap a word or phrase for a bubble meaning (deck entry first, then Apple's on-device Translation); swipe left for the Genius English translation, or "English translation not available"; a track without Korean lyrics shows "Lyrics not available for this track".
- ＋ Add to deck saves the word to a new or existing custom deck, with the lyric line as the example and a "Heard in" song reference. Raises the app's minimum to iOS 18 and is the first network feature.

M6 status: code implemented 2026-11-18 (L0–L8, docs in L9; see §6.1, §11.8, the §17 decision log and the PLAN_M6_LYRICS.md tracker). Device checks are open.

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
| S6 Session engine & summary | ☑ | `undoLastGrade` dropped from the spec (owner D2, 2026-11-17) |
| S7 Persistence | ☑ |  |
| S8 Shell, Home, Setup | ☑ |  |
| S9 Session screen | ☑ |  |
| S10 Summary screen | ☑ |  |
| S11 Stats tab | ☑ |  |
| S12 Settings & polish | ☑ |  |
| S13 QA | ☑ | UI smoke test skipped (no tests, per owner); manual checklist in README |

**M1.1 review fixes:** tracked in [PLAN_M1_FIXES.md](PLAN_M1_FIXES.md): §4 for Round 1 (F0–F10) and §8 for Round 2 (G1–G6).

**Milestones after M1:**

| Milestone | Status | Tracker / notes |
|---|---|---|
| M2 Music | ☑ (code) | [PLAN_M2_MUSIC.md](PLAN_M2_MUSIC.md); on-device mic QA pending |
| M3 Harmony | ☑ (code) | [PLAN_M3_HARMONY.md](PLAN_M3_HARMONY.md) |
| M4 Korean | ☑ (code + content) | [PLAN_M4_KOREAN.md](PLAN_M4_KOREAN.md) §5; M4-1b extension added (R6-4); dictionary verification open |
| M5 K-pop & K-drama phrases | 🟡 | [PLAN_M5_KOREAN_MEDIA.md](PLAN_M5_KOREAN_MEDIA.md) §6. K1, K3, K4 in code; K2 content wired by PLAN_R6_FIXES T1 (pending owner spot-check D2); K5 = PLAN_R6_FIXES T7 |
| M6 K-pop Lyrics reader | ☑ (code) | [PLAN_M6_LYRICS.md](PLAN_M6_LYRICS.md) §7; L0–L9 done. On-device checks pending: Spotify/Genius credentials, dashboard redirect `memorise-spotify://callback`, README QA checklist |
| Review fixes | — | Round 5: [PLAN_R5_FIXES.md](PLAN_R5_FIXES.md) (S7 = K2 open); Round 6: [PLAN_R6_FIXES.md](PLAN_R6_FIXES.md); Round 7 (owner device test): [PLAN_R7_FIXES.md](PLAN_R7_FIXES.md); Round 8 review: [PLAN_R9_FIXES.md](PLAN_R9_FIXES.md)  |

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
- 2026-11-16 · Planner · M2 planned in PLAN_M2_MUSIC.md. F10 is split into M2-0a (core hooks; `present(options:)` replaces the F2 `randomizeSpelling` flag), M2-0b (app DeckUI registry) and M2-0c (tuning presets; standard keys unchanged, other tunings use the `@<tuning>` key prefix). New decks: Name the Note, Find All, Intervals, Interval Ear. Capabilities: Karplus–Strong playback and YIN mic answer (auto-grades correct only).
- 2026-11-16 · Planner · M4 planned in PLAN_M4_KOREAN.md: answer modes touch/microphone/choice/typed (typed doesn't update the time EWMA), engine `answerEvaluated(correct:at:countsTime:)`, Core 2/3 continuing `ko.core.` ids, generated Hangul reading/particles/conjugation decks with DEBUG fixture checks, listening direction `listen`, patterns deck, file-based user decks + JSON import, Vision OCR for AION screenshots. Shares vocab schema v2 with M5 (first to land bumps it).
- 2026-11-16 · Owner/Planner · Plans contain no test work; the tester agent owns testing (M2/M4 DEBUG self-checks are replaced by reference examples). M4: large varied pool (Core 2–5 ≈ 800 words, ~80 patterns, all conjugation forms on by default, particle nouns from all Korean decks), no import of any kind. M5 K2 target raised to ~80 phrases.
- 2026-11-16 · Planner · M3 planned in PLAN_M3_HARMONY.md: theory core (chords, scales/modes, 15 standard keys, diatonic + Roman numerals, circle, 11 progressions), ≥ 60-shape chord library with a load-time validator, decks Play/Name the Chord, Triads, Arpeggios, Scales & Modes (box + 3NPS), Key Signatures, Diatonic, Progressions, Circle of Fifths. Standard tuning only; the root is part of the key (large pools); Home groups music decks; no mic for chords.
- 2026-11-16 · M2 · M2-0a…M2-8 code implemented (PLAN_M2_MUSIC.md). Name the Note naturals at 6 strings × 0–12 = **48** positions (every standard open string is natural, so fret 0 and 12 both count), not 46 as estimated in the M2 plan. Unknown `tuning` values fall back to standard silently (nested option fields don't feed `SessionConfig.recoveredFields`). `micTimeoutSeconds` is a new tolerant `SessionConfig` field. Intervals deck: when no target fits the −4…+5 window it shows the same-string target, then any position. Synth: Karplus–Strong with a fractional-delay allpass for tuning. YIN window 1024 inside 2048-sample frames. MemoriseCoreTests (owner-added) does not compile against the G3/M2 API changes; not updated (D1 = No).
- 2026-11-17 · M3 · M3-0…M3-11 code implemented (PLAN_M3_HARMONY.md). Root/tonic option sets are persisted as `Set<PitchClass>` (ints) and spelled at generation via `RootNames` (B♭ E♭ A♭ D♭ F♯), falling back to the enharmonic when a chord/scale would need a double accidental (e.g. D♭°7 → C♯°7, D♭ Locrian → C♯ Locrian); keys use the actual spelling. Diatonic/Progression key sets are major tonics (ASCII); minor uses the relative minor. Minor diatonic cards always use the harmonic V/V7 (no option). Movable shapes are never placed with a sounded fret 0 (so e.g. E-shape E needs fret 12). Shape/triad span rule = at most 4 fret positions (max − min ≤ 3). Arpeggio box = root fret −1…+4; a span that doesn't fit is truncated. Default card counts: Play/Name the Chord 369 each, Triads 540, Arpeggios 144, Scales 936, Key Signatures 60, Diatonic 210, Progressions 157 (minor keys whose harmonic V needs 𝄪 are skipped), Circle 48. "Name the Chord" choice mode waits for M4-0. Chord stats grid colours by error EWMA averaged across shapes. Shape sources were cross-checked against standard chord charts from memory, not URLs (no verification table yet — owner/tester to spot-check).
- 2026-11-17 · M4 · M4-0, M4-3, M4-4 (vocab) code implemented, plus Name the Chord `choice` mode (4 options: answer, same root/other quality, same quality/other root, random). **Deviation:** typed *and* choice answers reveal with `ok()` and grade with the stored verdict on Next (or auto-advance after 0.8 s when exact), instead of `answerEvaluated` grading immediately; this gives a reveal showing the verdict and rule (as M4-5 asks for). `answerEvaluated(correct:at:countsTime:)` exists and backs the mic path. Time EWMA is skipped for the whole session when `inputMode == .typed` (including any card that falls back to touch). Typed mode adds "Don't know" (reveal as wrong). `VocabDeckFile.currentSchemaVersion` = 2 (v1 still accepted); `conj` required-for-predicates validation is deferred to M4-6 with the Core 1 content step. Hangul predicate "close" = input (minus trailing 요) starts with the dictionary stem. English close uses OSA distance (transpositions = 1, so "recieve" → close). Listening is hidden in Setup and stripped from saved configs when no Korean voice is installed. New setting: "Auto-advance typed/choice answers" (default on).
- 2026-11-17 · M4 · M4-2 Hangul reading (`ko.hangul`, `.hangulReading(HangulReadingOptions)`) implemented. **Additions:** `HangulReadingOptions.newPerSession` (default 8) so stage-order gating actually limits new cards (a deck returning `nil` introduces everything); batchim stage = 154 curated common syllables with any single final (not just the 7 letters ㄱㄴㄷㄹㅁㅂㅇ, so 첫/옷/밭 are covered), double finals filtered out; `syllables` stage is vowel-major (가나다…, then 거너더…); `realWords` takes 1–3-syllable, space-free, non-pattern entries from every Korean deck, deduplicated by spelling, shortest first. Batchim answers note "final consonants sound as k, n, t, l, m, p or ng". Stats: syllable grid per stage coloured by error EWMA (green → red). DEBUG `HangulReadingDeck.selfCheck()` (reference romanizations + stage counts) runs inside `PersistedFormatCheck.run()`.
- 2026-11-17 · M4 · M4-5 Particles (`ko.particles`, `.particles(ParticleOptions)`) implemented: 13 cards `particle:<particle>:<batchim|vowel|rieul>`; `present` picks a random `noun`-POS entry (syllables only, deduplicated by spelling; pronouns excluded by POS) of the card's ending class; `.coreOnly` = decks with id prefix `ko.core.` and falls back to all decks when a class would be empty. Choice mode only, so it grades through the existing choice path (reveal, then grade on Next; see the entry above) rather than `answerEvaluated` immediately. The wrong option for ㄹ + direction is 으로. Today's pool: 137 nouns (16 ending in ㄹ). DEBUG `ParticlesDeck.selfCheck()` covers the M4-5 §5 reference forms.
- 2026-11-17 · M4 · M4-6 Conjugation (`ko.conjugation`, `.conjugation(ConjugationOptions)`: `forms`, `source` `allCore|core1`, `newPerSession` 5) implemented. `Korean/Conjugator.swift` is rule-based on syllable indices; the 아/어 ("해") form is built first, so past = 해-form + ㅆ + 어요. Cards are `conj:<entryId>:<form>`; intro rank = word order (Core deck number, then rank) × 7 + form index. **Deviations:** (1) `negativePolite` uses lexical opposites: 있다 → 없어요 (맛있다/재미있다 likewise), 알다 → 몰라요, 이다 → 아니에요. 없다 and 모르다 get no negative card. Noun + 하다 *verbs* put 안 before 하다 (공부 안 해요); 좋아하다/싫어하다 and -하다 adjectives keep 안 in front. (2) `wantTo` is skipped for adjectives, 없다 and 모르다. (3) All ㄹ-final stems get ㄹ-drop and no 으 whatever their `conj`, because that is universal. Core 1: `conj` added to all 72 predicates; the file is now schemaVersion 2. The validator now requires `conj` on every predicate (relax it in M4-8 user mode). Today: 72 predicates → 473 cards. `docs/conjugation-reference.md` (178 rows, hand-written) mirrors DEBUG `ConjugationDeck.selfCheck()`; it has not been dictionary-verified yet.
- 2026-11-17 · M4 · M4-8 Custom decks implemented.
  - Core: `Korean/UserDecks.swift` has pure helpers: `newDeckID` (via injected `SplitMix64`), `adding`/`updating`/`deleting`/`renaming`, and `EntryDraft`. Ranks are re-assigned 1…N; `nextEntryNumber` only increases (DEBUG `UserDecks.selfCheck()`).
  - `DeckValidator.validate(_:mode:)` gains `.user` mode: romanization and `conj` optional, empty deck allowed, `user.<8 hex>` id and a non-empty title required. `VocabEntry.romanization` decodes missing as `""`. `VocabDeckFile` now has hand-written tolerant Codable with `nextEntryNumber`. `BuiltInDecks.defaultOptions` treats `user.` ids as vocab.
  - `ExportSnapshot.schemaVersion` = 2 with optional `userDecks`, because M5-K4 hasn't landed.
  - App: `Persistence/UserDeckStore.swift` (actor, `Application Support/UserDecks/<id>.json`, atomic writes). `AppEnvironment.loadUserDecks/saveUserDeck/deleteUserDeck` (delete also calls `store.reset(deck:)`) and `reloadCatalog()` after every change.
  - **Deviation:** user decks show in their own Home "My decks" section after the subjects, not inside Korean. Each card has an Edit button and an "Edit deck" context menu; tapping an empty deck opens the editor. "+ New deck" asks for a title in an alert, then opens the editor (`Features/MyDecks/UserDeckEditorView.swift`: title, subtitle, words list with swipe-delete, add/edit word sheet, delete deck with confirmation).
  - The reveal hides an empty romanization.
- 2026-11-17 · M4 · M4-9 AION screenshot → cards implemented.
  - Core: `Korean/ScreenshotWords.swift`. It takes Hangul runs per OCR line and strips one trailing particle, but only when ≥ 2 syllables remain. The longest matching particle decides, so 집으로 stays whole and doesn't become 집으. Results are deduplicated and split into new and known, where known = any catalog vocab hangul. DEBUG `selfCheck` covers 10 sample tokens.
  - App: `Services/KoreanTextExtractor.swift` (Vision `.accurate`, ko-KR + en-US, language correction, detached task; the image data isn't kept). `Features/MyDecks/ScreenshotImportView.swift` (`PhotosPicker` images only; review list with toggle, required meaning and optional romanization; "Already known (n)"; saved as nouns tagged `aion2`).
  - **Deviation:** `UserDecks.isUserDeckID` special-cases `user.aion0001`, which isn't 8-hex. `AppEnvironment.ensureAionDeck()` creates "My AION words" on first use.
  - Entry points: Home → My decks → "AION 2 words from a screenshot", and the AION deck's editor → "Add from screenshot". Typed meanings survive picking another screenshot.
- 2026-11-17 · M4 · M4-10 step 1: `DeckCatalog.koreanDisplayOrder` sorts Korean decks as Hangul Reading, Core 1…N, Particles, Conjugation, `ko.patterns`, other bundled decks, `ko.aion2`, then user decks (Home shows those under "My decks"). Steps 3–4 (PLAN §6.1/8/9/11/15 and the README QA checklist) are still open.
- 2026-11-17 · M4 · M4-10 done. Step 2: `BuiltInDecks.defaultOptions` already had rows for `ko.hangul`, `ko.particles` and `ko.conjugation`, and user ids fall back to vocab. Steps 3–4 added §6.1 (M4 key schemes), §8.3b (schema v2, Romanizer, generated decks, custom decks, screenshot words), §9.2 (answer modes table), §11.5d (typed/choice/listening/My decks UX), the §15 M4 status line, and the README QA checklist items (Korean keyboard, listening timer, OCR, custom-deck editing).
- 2026-11-17 · M4 · M4-7 Patterns. `ko_patterns.json` (`ko.patterns`, schema 2) has 87 patterns, ranked by usefulness. Each has 3 original polite-style example sentences (261 in total), an attachment rule in `notes`, and one theme tag from a fixed list (tense, desire, ability, request, obligation, permission, connector, reason, condition, time, plan, experience, guess, ending, change, comparison, particle, quote, negation, nominal). It is listed in `bundledVocabFiles` between Core 1 and AION 2.
  - The validator adds pattern rules: `Hangul.isValidPatternHeadword`, which must start with `-` or contain `~`, and allows compatibility jamo plus `( ) / ?` (e.g. `-(으)ㄹ 수 있다`, `-(으)ㄹ까요?`). It also requires ≥ 2 examples.
  - **Additions:** TTS for a pattern headword (auto-play and listening) reads its first example sentence (`VocabEntry.spokenText`, App), and the reveal hides the headword 🔊, because the raw pattern text isn't speakable. Each example keeps its own 🔊.
  - The deck was generated by a scratch script; the JSON is the source of truth. Owner spot-check pending.
- 2026-11-17 · M4 · M4-1 Core 2 and Core 3 added.
  - **Core 2** (`ko_core_2.json`): 218 entries, `ko.core.0206`–`0423`. 50 % are nouns across 18 themes, 30 % are verbs/adjectives, and 42 have example sentences.
  - **Core 3** (`ko_core_3.json`): 229 entries, `0424`–`0652`. 52 % are nouns across 20 themes, 31 % are verbs/adjectives, and 31 have example sentences.
  - Both use schema 2 and give every verb/adjective a `conj` class. Tags come from a fixed theme list (food, place, body, time, weather, nature, animal, people, school, work, home, clothes, transport, travel, shopping, hobby, media, feeling, colour, daily, health, communication, frequency, connector, greeting, counter, quantity, direction, society). Both are listed in `bundledVocabFiles` after Core 1.
  - The validator adds the M4-1 duplicate check: the same hangul + pos in two `ko.core.*` files is reported. It is limited to Core decks so that themed decks (AION's 친구/가방) can repeat core words.
  - **Deviation:** the verification table (`docs/core-verification.md`) links each entry to a KRDict search, but nothing has been dictionary-checked yet, because this session had no web access. Every Conjugator output was reviewed by hand.
  - **Known gap:** 춤추다 → "안 춤춰요" (natural Korean: 춤 안 춰요), because the Conjugator moves 안 only for noun + 하다 verbs.
- 2026-11-17 · M4 · M4-1 Core 4 (`ko_core_4.json`): 217 entries, `ko.core.0653`–`0869`. 52 % are nouns across 18 themes (adding society/news, work and life, school, feelings and character, health), 31 % are verbs/adjectives, and 31 have example sentences. Its rows were appended to `docs/core-verification.md`, which is still unchecked.
  - **Conjugator fix:** `negativePolite` no longer splits one-syllable roots that aren't nouns on their own (`Conjugator.boundHaRoots`: 원 변 피 망 향 통 상 구 취 위). It now gives 안 원해요 / 안 변해요 / 안 피해요 instead of "원 안 해요". Real noun roots still split (일 안 해요, 말 안 해요).
- 2026-11-17 · M4 · M4-1 Core 5 (`ko_core_5.json`): 225 entries, `ko.core.0870`–`1094`. This completes M4-1 content: Core 2–5 add 889 words, against the ~800 target. 48 % are nouns across 23 themes (adding directions/compass points, holidays, clothes and accessories, animals and weather), 34 % are verbs/adjectives (covering every irregular class: ㄷ 깨닫다/싣다, ㅅ 붓다/긋다, ㄹ 날다/졸다, 르 흐르다/누르다, 으 잠그다/뜨다, ㅂ 줍다/가렵다, ㅎ 어떻다/동그랗다), and 30 have example sentences. No hangul + pos repeats Core 1–4. Its rows were appended to `docs/core-verification.md` (889 rows, all still unchecked).
  - **Conjugator fix:** 정 added to `boundHaRoots`, so 정하다 now gives 안 정해요 instead of "정 안 해요".
  - **Known oddities (grammatical, semantically rare):** negatives of 없다-compounds (안 맛없어요, 안 재미없어요) and of 어떻다 (안 어때요); 화나다 → 안 화나요 (colloquially 화 안 나요).
- 2026-11-17 · M5 · K1 (schema v2 media fields + validator): `Register`, `DialogueLine` and `MediaRef` added to `Korean/Vocab.swift`; `VocabEntry` gains `register`, `dialogue` and `sources` with defaulted init parameters. `DeckValidator` adds the dialogue, source and citation rules and the v2 expression-punctuation headword rule. `currentYear` is injected (default: system calendar).
  - **Deviation:** the schema bump to 2 was already done by M4, so K1 adds fields only.
  - **Deviation:** a source with an unknown `kind` is reported through the validator's error list (the catalog shows it as a validation warning and still loads the deck), because the validator has no separate warning channel. A non-encoded `droppedSourceCount` on `VocabEntry` carries the count.
  - **Deviation:** `"ko_media"` sits commented out in `bundledVocabFiles` (before `ko_aion2`) until K2 adds the file.
  - K3 (reveal snippet panel) is UI work and is left for the UI engineer.
- 2026-11-17 · M5 · K4 (code part): `PersonalSnippet` and `PersonalSnippetFile` (core, lenient decoding, text trimmed and capped at 500, blank snippets dropped). `actor PersonalSnippetStore` (app) keeps `Application Support/personal_snippets.json` with atomic writes; no SwiftData change.
  - `AppEnvironment` loads snippets at launch and offers `personalSnippet(for:)`, `savePersonalSnippet` (empty text deletes), `deletePersonalSnippet` and `deleteAllPersonalSnippets`.
  - `ExportSnapshot.personalSnippets` is an optional key. The schema stays at 2, because M4-8 already bumped it.
  - `DeckUIContext.pauseSession` / `resumeSession` call the same engine pause path as ✕. Pausing while revealed shifts `revealedAt`, so grade time isn't inflated.
  - **Deviation:** the file is wrapped as `{schemaVersion, snippets}` rather than a bare map, so it can evolve. An unreadable file is renamed to `personal_snippets.unreadable-<ts>.json` and never overwritten; if renaming fails, writes are refused.
  - Left for the UI engineer: the add/edit sheet in `MediaSnippetView`, and the "Also delete my snippets?" prompt in reset-all, which calls `env.deleteAllPersonalSnippets()`.
- 2026-11-17 · M5 · K3 + K4 UI. `MediaSnippetView` (In a scene chat bubbles A/B/C, Heard in rows, My snippet card) is embedded in `VocabAnswerView` only when `dialogue`/`sources` is non-empty. `RegisterChip` appears next to the romanization (answer), under the hangul (ko→en prompt) and next to the pos (en→ko prompt). `SnippetEditorSheet` has a 500-char ring, an optional source, and Save/Delete. Settings reset-all then asks "Also delete my snippets?" (only when snippets exist).
  - **Deviation:** the sheet is hosted by `SessionView`, not by `MediaSnippetView`, because pausing swaps the reveal for the pause card and would dismiss a sheet owned by the reveal. `DeckUIContext.editSnippet` → `SessionViewModel.editSnippet` pauses and sets `snippetTarget`; on dismiss it resumes. While the sheet is open, the session keeps rendering the reveal (same view branch, so the scroll position survives) instead of the pause card. Outside sessions (previews), `MediaSnippetView` presents its own sheet.
- 2026-11-17 · UI polish. Home: "Jump back in" hero for the most recently practised deck, then each display group as a 2-column tile grid with a per-group palette (`Subject.palette`). Stats: deck chip carousel instead of a menu picker, overview tiles (accuracy, median, sessions, seen), illustrated empty trend, accuracy rings on history rows. Setup: gradient banner with a live card count (replaces the "Cards available" row), aurora background, subject tint. Summary: `ConfettiBurst` at live session end when accuracy ≥ 80 % (off with Reduce Motion).
  - DEBUG simulator-only launch arguments for UI screenshots: `-uiTab N` (start tab) and `-uiSetupDeck <id>` (open a deck's Setup sheet).
- 2026-11-17 · UI polish 2. Session: the card shows two cards stacked behind it (they stay put while the top card is swiped) and a faint subject watermark; short reveals are vertically centred. My decks editor: gradient banner with an animated word count, empty state, initial-avatar rows, aurora background and Korean tint. Word editor: live flashcard preview. Screenshot import: illustrated hero with a scan-beam animation while reading, and a gradient picker button.
  - More DEBUG simulator-only launch arguments: `-uiSession <id>`, `-uiReveal YES`, `-uiImport YES`, `-uiEditAion YES` (the last two create the AION deck if needed).

- 2026-11-17 · Code Review Round 4 fixes (code only; tests are left to the tester). R4-1 (tests/CI) and R4-6 (content verification) are not code-writer work and stay open. R3-2 (freeze the aurora) is UI work and stays open.
  - **R4-2 grading (decision):** Hangul predicates accept as *close* only a real conjugation of the expected word (`Conjugator.allAcceptedForms`, every `ConjForm` plus alternates, with or without 요). The old stem-prefix rule is gone, so 가방 for 가다 and a bare 하 are now wrong. For 1–2 syllable words, only a batchim slip (same initial and vowel in each syllable, one final differs) is close; 의사/의자 is wrong. Words of 3+ syllables keep jamo distance ≤ 1. English *close* now allows only dropped or extra letters (one at ≥ 5 letters, two at ≥ 9); substitutions and transpositions are wrong. Accepted residual risk: doubled-letter real words (desert/dessert, later/latter) still count as close. `TypedAnswerSpec` gained `conjugationClass` and `isAdjective`.
  - **R4-3:** `Conjugation.alternates` / `ConjugationPrompt.alternates`. Negative: the long negation `-지 않아요` always, plus `안 공부해요` for split noun+하다 verbs. Optional contraction (ㅗ/ㅜ/ㅣ/ㅚ/ㅐ/ㅔ stems with an initial consonant, regular or ㄹ class): 보아요, 주어요, 되어요, 마시어요, 보내어요 in the present, casual and past forms. 놓다 also accepts 놔요 and 놨어요. The conjugation drill's typed spec passes `[answer] + alternates`.
  - **R4-4 (decision):** `countsTime` is decided per answer. `SessionEngine.ok(countsTime:)` (default true) stores the flag for the reveal. Choice no longer counts time (recognition, not recall). A typed or choice reveal passes `activeMode.countsTime`, a touch fallback in a typed session counts, and a mic-timeout reveal never counts. **Deferred:** an optional `Attempt.answerMode`, because persisting it needs a SwiftData `SchemaV2` plus a migration stage.
  - **R4-5:** run-tracking and level smoothing moved to `MicFrameTracker` on the detector queue, behind a lock. Main only hears about stable notes (with a listening-generation token, so stale notes are dropped) and `levelDB` at ≤ 20 Hz with steps of more than 1 dB, only while listening.
  - **R5-3:** YIN runs only while listening (`PitchDetector.setActive`, set from `MicAnswerController.setListening`, `start` and `stop`); the ring keeps filling, so re-arming has a full frame at once.
  - **R6-3:** frames whose window starts before arming (`PitchFrame.windowStartSeconds < armedAt`) are ignored; an onset before the prompt is recorded untimed (`countsTime: false`). The saved `Attempt.responseMs` stays 0: an "untimed" flag on `Attempt` would be a persisted-schema change and is out of scope.
  - **R4-7:** `PitchFrame.hostSeconds` is now the start of the newest hop, not the start of the window. Remaining uncertainty: late by up to one hop (≈ 11 ms at 48 kHz) when the note began earlier in the window and needed more periods to detect.
  - **R4-8:** `DeckOptions` encodes from one `payload` (key, value) switch; `caseKey` derives from it, and `wireKey` is public for round-trip checks. No wire change. `Deck.kind` defaults to `DeckKind(rawValue: id.raw)`.
  - **R4-9 (decision):** `personal_snippets.json` is excluded from device backups after every atomic write, which keeps the "never leaves the device except Export" promise. Moving to a new phone needs Export. User decks make no such promise and stay in backups.
  - **R4-10:** the launch user-deck load merges by `deckId` (memory wins, and decks deleted before the load completes aren't revived); snippets merge the same way. `deleteUserDeck` resets stats before deleting the file. `micTimeoutSeconds` is snapped to the nearest preset in `initialConfig` and when arming the timeout. Screenshot import guesses the part of speech (`UserDecks.guessedPartOfSpeech`: 다 plus "to …" makes a verb, "to be …" an adjective). User -하다 predicates get `conj: "ha"`.
  - **R4-11:** `DeckValidator` (bundled) rejects 러-irregular headwords (`Conjugator.isUnmodelledReoIrregular`: 푸르다, and 이르다 meaning arrive/reach). `chord_shapes.json` has a `_note` header saying shape ids are frozen, and `ChordShapeLibrary.shape(id:)` is a dictionary lookup. `ChordChoices` returning 2–3 options is left for the UI engineer to check in the view.

- 2026-11-17 · Code Review Round 5 fixes (PLAN_R5_FIXES S1, S2, S3, S5; code only).
  - **R5-1:** typed predicate matching accepts affirmative forms only (`ConjForm.affirmative`, every case except `.negativePolite`, passed as `Conjugator.allAcceptedForms(…, forms:)`). 몰라요 for 알다, 없어요 for 있다 and 안 가요 for 가다 are now wrong. The conjugation drill is unchanged. **Decision:** there is no "the form must contain the stem" filter, because irregulars (들어요, 도와요, 몰라요, 추워요) would fail it.
  - **R5-2:** `AppEnvironment.cardCount(for:options:)` caches pool sizes per (deck, options); `reloadCatalog()` clears the cache. Home and Setup use it. `StatsStore.stats(forDecks:)` is a protocol requirement with a looping default; SwiftData does one fetch with `raws.contains(deckID)`. Home's `load()` makes one store call.
  - **R5-6:** (a) snippet deletes and delete-all made before the launch load are tombstoned, so a stale disk read doesn't revive them; a later save wins. (b) `grade(correct:haptic:)`: typed and choice answers get one haptic, at the reveal. (c) The `PhotosPicker` label title is computed outside the Sendable closure.
- 2026-11-17 · Code Review Round 5 frontend (PLAN_R5_FIXES S4, S6; UI only).
  - **R3-2 (S4):** `AuroraBackground(animated:)`. `false` pauses the `TimelineView` and draws the static `t = 0` frame, the same frame Reduce Motion uses. `SessionView` passes `animated: false`. The optional step is also done: every aurora pauses while `scenePhase != .active`. Other screens still animate.
  - **R5-5 b (S6):** `VocabUI` always embeds `MediaSnippetView`. `shouldShow(for:)` is renamed to `hasMedia(for:)`. A plain entry with no saved snippet shows only a lifted `AddSnippetButton`: no section header, identifier `addSnippetButton`, VoiceOver label "Add your own snippet for <hangul>". On reveal it plays one dash-crawl and icon bounce, which is skipped under Reduce Motion. When a snippet is saved, the button blur-morphs into the full "My snippet" section. Entry ids can't collide: bundled ids are `ko.*` with no duplicates across the 7 decks, and user ids are `user.<8hex>.NNNN`.
- 2026-11-17 · Planner · P1 (R5-4, R6-6, R3-7) spec alignment. §9.2: the `choice` row is "time EWMA: no", and time is decided per answer (touch reveal counts, including a touch fallback; typed, choice and mic-timeout reveals don't; an onset before the prompt is untimed, R6-3); added the normative definition of "close" (R4-2, R5-1, R6-2). §9.3, §12 S6 and the §17 tracker: `undoLastGrade` removed (owner D2). §11.5b/§11.5d updated for mic timing and choice timing. §15 M4 status: Core 2–5 in, Core 5 at 450. PLAN_M4 §3.1 and M4-0 step 2 now say `countsTime` is per answer. README: "OK" → "Reveal" (R3-7). Owner decision D1 (PLAN_R6_FIXES): commit the Core 5 / AION 2 extension before its verification rows exist.
- 2026-11-17 · Planner · P2 (R6-4): **M4-1b**, unplanned content recorded after the fact. Core 5 grew from 225 to 450 entries (`ko.core.1095`–`1319`, ranks 226–450; new POS mix: noun 67, verb 55, adverb 38, adjective 18, other 47) and AION 2 from 81 to 140 (`ko.aion2.0082`–`0140`, all nouns, some community slang such as 장판 and 기믹 that needs in-game confirmation). The reviewer verified the change is additive only: no existing id changed or was removed, ids are contiguous, and every predicate has `conj`. The owner chose (D1) to commit it before verification (PLAN_R6_FIXES T2). Verification rows are C1 (content agent), plus an owner spot-check of 15 entries per deck. Six phrases also exist in `ko.media` (어떡해, 안녕, 화이팅, 거짓말, 오빠, 언니). This is allowed, because the duplicate-Hangul check is limited to `ko.core.*`; they are separate items with separate stats. Process rule going forward: new content needs a plan segment **before** it is written.
- 2026-11-17 · Planner · P3 (R6-6): K5 is scheduled as PLAN_R6_FIXES T7, after T1. Step 2's direction default (`.koToEn`) is already met. Added a milestone table (M2–M5 and the review-fix plans) under the §17 tracker; this covers K5 step 4's tracker row.
- 2026-11-17 · Code Review Round 6 fixes (PLAN_R6_FIXES; code only).
  - **R6-2 (T3):** for non-predicate Hangul, ±요 is close (typed vocab). Exact-required modes (conjugation drill) still grade close as wrong.
  - **R6-2 (T4):** seven gloss collisions in `ko.media` resolved with parentheticals (`stripParentheticals` keeps ko→en grading on the plain gloss). Media-deck gloss uniqueness is a content test, not a validator rule.
- 2026-11-17 · R6-7a (PLAN_R6_FIXES T6, frontend). **Measured** with a temporary draw probe in the aurora `Canvas`, launched with `-uiSession ko.core.1` on the iPhone 17 Pro simulator. Home's aurora kept drawing at 30 frames/s for the whole session under the `.fullScreenCover`, while the session's frozen aurora drew 3 frames. **Fix:** HomeView passes `animated: launch == nil`. After the fix, Home draws 5 frames during the cover transition and then stops. Home on its own still runs at 30 fps. HomeView is the only screen that presents `SessionView`. The probe was removed.
- 2026-11-17 · ProMotion / fluidity pass (frontend, UI only).
  - **120 Hz:** added `CADisableMinimumFrameDurationOnPhone: true` to `project.yml` and regenerated `Info.plist`. Without it, iPhone caps the app's own SwiftUI animations, `TimelineView` and `Canvas` animation at 60 Hz.
  - **Aurora cost, measured** on the iPhone 17 Pro simulator, with Home idle and 10 s CPU-time deltas. The animated aurora costs about 7% of app CPU and about 33% of render-server CPU. Frozen, both drop to about 0.1–0.4%. Removing the blur filter changes nothing. So the cost is the glass materials above the aurora re-blurring their backdrop on every aurora frame, plus the 30 Hz main-thread tick. The blur itself is not the cost.
  - **Fix:** `.auroraBackground(colors:intensity:animated:running:)` replaces `.background { AuroraBackground(…) }` on every screen. On iOS 18+, it holds the aurora while the screen's scroll view is scrolling (`onScrollPhaseChange`). A held aurora keeps its frame and resumes without a jump, using a clock that excludes paused time. Probe result during a 2.4 s programmatic scroll on Home: 0 draws, then 30 fps resumes when the scroll phase is `idle` again. Home now *holds* under the session cover (`running: launch == nil`, which supersedes R6-7a's `animated:`), so it no longer snaps to the rest frame when the cover opens. `animated: false` (the rest frame) stays for sessions (R3-2).
  - **Aurora drawing:** it now renders off the main thread (`Canvas(rendersAsynchronously:)`) into a bitmap 4× smaller at 1× scale, upscaled to fill. That is about 140× fewer blurred pixels on a device GPU, and it looks the same (screenshots compared). It made no measurable difference in the simulator.
- 2026-11-17 · Planner · **PLAN_R7_FIXES** from the owner's on-device test (8 findings).
  - F1: card selection by rounds (no repeat until the pool is used up; correct cards rest one extra round; introduction tops up to the session's distinct-card target). This replaces the in-session `alreadyShownFactor`.
  - F2: "End session" discards (no record, no attempts, stats restored).
  - F3: mic "Correct / Try again" feedback, with octave-tolerant matching.
  - F4: zoomed horizontal fretboard.
  - F5: stable Home section ids.
  - F6: `KoreanHeadline` (length-tiered sizes, no mid-word breaks).
  - F7: one deck per Korean headword (hidden in code, JSON untouched) and interleaved derived-deck introduction.
  - C2: distinct glosses. The owner waived the append-only content rule for this.
  - Defaults D1–D5 are listed in PLAN_R7_FIXES §4.
- 2026-11-17 · Owner confirmed PLAN_R7_FIXES §4 defaults D1–D5 as final.
- 2026-11-17 · R7-F1 (implementor, core). Card selection by rounds: `Scheduler.select(…blocked:resting:)` returns the card plus `startsNewRound`; `nextCard` wraps it and keeps its old call shape. `SessionEngine` tracks `round`, `shownThisRound` and `restUntilRound`; a correct non-retry grade rests the card and its `Deck.siblingKeys` (new hook, default `[]`; vocab returns the other directions) until `round + 1 + correctRestRounds`, a wrong grade clears its rest. Siblings are also marked shown when a card is shown, so a two-direction session shows each entry once per round. `IntroductionPolicy.eligibleNewKeys(…targetDistinct:)` counts entries (ranks) for the fill rule. New constants `correctRestRounds = 1`, `cardsPerMinuteEstimate = 8`; `alreadyShownFactor` unused. No persisted-format change. **Deviation:** the plan's single `blocked:` parameter is split into `blocked` (shown ∪ resting) and `resting`, because the tiers need to tell the two apart. Note for the tester: the fill floor `minEligiblePool` now counts entries, so a two-direction pool admits up to twice as many cards as before.
- 2026-11-17 · R7-F2 (implementor, core + app). "End session" discards: `SessionEngine.discard()` keeps the stats passed to `init` and returns one `.discardSession(id:deck:restore:delete:)` effect (changed keys restored, keys with no row at start deleted). `StatsStore.discard(session:restore:delete:deck:)` is a protocol requirement with no default (in-memory, SwiftData in one `save()`, deferred forwards); the test double `FailingStore` got a no-op stub so the test target compiles. Ordering is guaranteed by `SessionRecorder`'s single serial queue, so the deferred store needs no extra flush. `SessionViewModel.quit()` discards unless `engine.isLengthReached` (now public), sets `discarded`, and `SessionView` dismisses the cover without a summary. Dialog: "This session won't be saved." / "Discard session" / "Keep going". `SummaryView` never celebrates an `.abandoned` summary (headline "Ended early"). **Deviation:** the effect also carries `deck` so `apply(_:)` can call the store without a lookup. The optional Home toast was not added.
- 2026-11-17 · R7-F3 (implementor, app). Mic answers confirm before moving on. `SessionViewModel` holds `micFeedback` (`.correct`, `.tryAgain(heard:)`, `.notQuite`) and a per-presentation wrong-note count. A correct note stops listening, shows "Correct", and grades after 0.9 s from the captured onset (so `responseMs` is not inflated); after any wrong note it is stored wrong (owner D1) via `answerEvaluated(correct: false, …, countsTime: false)`. A wrong note shows "Try again · heard X" for 1.2 s; with spoken feedback on, listening pauses until the utterance ends. The third wrong note reveals the answer (untimed) and grades it wrong after 1.5 s; any tap-grade on that reveal is also stored wrong. Pause cancels a pending "Correct" (the card is re-shown unanswered). `MicAnswerController.onWrongNote` replaces the chip's "Heard G♯" text; `SpeechService.speakEnglish` uses an English voice at the default rate. `AppSettings.spokenMicFeedback` (default on, `UserDefaults` with a default) with a Settings → Music toggle. `FretboardNotesUI` / `IntervalsUI.micAccepts` accept the right pitch class anywhere from the lowest open string to string 1 + 24 frets (intervals still reject the root itself). **Deviations:** the same wrong note within 2 s is ignored, so a string still ringing after the mic re-arms doesn't count as a second attempt. The reveal banner says "Not quite: here's the answer" and leaves the fret text to the reveal card, since the banner has no deck-specific answer string.
- 2026-11-17 · R7-F5 (frontend). Home sections have stable identity: `ForEach(Subject.allCases, id: \.rawValue)` → one `subjectSection` container `.id(subject.rawValue)`; groups are a `DeckGroup` struct with id `"subject.title.index"` (index suffix guards against a recurring title). Outer `LazyVStack` → `VStack` (kept eager; ~27 tiles). The fast-fling repro can't be scripted in the simulator and there is no G5 timing log in the app, so render time wasn't measured; Home renders unchanged in the simulator. `appearAnimation` already guards on `shown`, so it animates only on first appearance. Owner: please do the 10-fling check on device.
- 2026-11-17 · R7-F6 (frontend). New `KoreanHeadline(text:role:style:glow:tail:)` + `WordFlowLayout`: plan size table, `@ScaledMetric(.largeTitle)` capped at ×1.8, one `Text` per space-separated word (`lineLimit(1)`, `minimumScaleFactor(0.35)`), centred lines. **Deviation:** the "max 3 lines" rule is enforced inside the layout (uniform scale-down in 5 % steps to 0.4) instead of `ViewThatFits`, because `ViewThatFits` can't measure a flow layout's height against an unconstrained card height. Used in vocab prompt/answer, conjugation prompt/answer, particles prompt and answer (`tail:` keeps the pink particle), Hangul Reading multi-character prompt/answer. `MediaSnippetView` shows no big headword, so it is unchanged. Particles prompt row now centre-aligned (a custom Layout has no text baseline).
- 2026-11-17 · R7-F4 (frontend). `FretboardView` redesign: fixed 30 pt string spacing, height `(strings − 1) × 30 + margins`, 26 pt dots, a minimum fret width of 44 pt (`minimumWidth(window:)`), fret numbers in a band under the board, a wood-tone board, glowing highlighted strings. If a window can't fit at 44 pt per fret, the board scrolls horizontally, centred on the marks, with faded edges, instead of shrinking. **Deviation:** fret spacing is half-strength logarithmic (2^(−n/24)), so a whole-neck board isn't enormous at the 44 pt minimum. `FretWindows.window/windows` cluster the answer frets. Each window is lowest − 2 … highest + 2, at least 5 frets, and snaps to the nut at ≤ 2 (then padding above is 1). Wide clusters drop to 1-fret padding to stay ≤ 6 frets. New `FretboardAnswerBoard` shows one window, side-by-side windows when they fit, or a paging `ScrollView` with gradient dots, plus a caption and a "Whole neck" toggle (`@AppStorage("fretboard.wholeNeck")`). `FretboardAnswerLayout` puts the header left of the board in landscape. Applied to Notes, Name the Note (prompt window plus answer), Intervals (prompt: root − 2 … root + 5; answer: root and primary target) and Find All. Scales, Arpeggios and Triads keep their own windows and pick up the size rules. Heatmaps are untouched.
- 2026-11-17 · R7-F7 (implementor, core). **Part A:** `DeckCatalog.builtIn()` computes `hiddenDuplicates`: the key is NFC Hangul without trailing `?!.~` plus `pos`, and the owner order is `headwordOwnershipOrder` (Core 1 → Core 5 → Patterns → AION 2 → Media, owner D3). A later deck's duplicate goes into `VocabDeck(file:hiddenEntryIDs:)`; `entries` (and so `cards`, tags and the derived decks) excludes hidden ids. JSON, ids and `ItemKey`s are unchanged, and user decks are never hidden. Duplicates inside one deck are kept. Result: 6 entries hidden (`ko.aion2.0067` 친구, `.0011` 가방, `.0013` 지도; `ko.media.0010` 어떡해, `.0071` 화이팅, `.0028` 안녕); 0 `(headword, pos)` pairs remain in two decks. `DeckValidator.overlapWarnings` → `DeckLoadReport.overlapWarnings`, a new field that is logged in DEBUG only. It is not part of `validationWarnings`, so it isn't shown on Home and doesn't trip the DEBUG assert. It lists 15 shared spellings, grouped by Hangul so different-POS pairs show too (cross-deck and still visible: 오빠, 언니, 진짜, 거짓말, 멋지다 in `ko.media` as expressions; inside Core: 일, 팔, 안, 새), and **85** shared first glosses among visible entries (case-insensitive, parentheticals kept, so C2's "bag (backpack)" style resolves them). **Part B:** `DerivedIntroductionOrder.interleave` round-robins across source decks, and each source gets a Fisher–Yates shuffle seeded by `SplitMix64(seed: FNV-1a(derivedID|sourceID))`. The index draw is our own, so the order doesn't depend on the stdlib shuffle. Conjugation `.allCore` and Particles' noun order use it; Hangul Reading real words stay shortest-first, interleaved within each length; Conjugation `.core1` keeps Core 1 rank order. First 10 introduced words, overlap with Core 1's first 10 (before → after): Conjugation 0 → 0, but it used to start with Core 1's own top predicates (하다, 있다, 없다, 되다, 가다…) and now starts 쓰다, 운동하다, 아름답다…; Hangul Reading 1 (네) → 0; Particles 0 → 0, but it used to start 사람, 친구, 가족… (Core 1's top nouns) and now starts 밤, 휴대폰, 경찰…. Pairwise overlap between derived decks: 0. **Deviation:** Particles has no introduction gating (it picks a random noun at `present`), so the interleave only changes its noun order and each card's default noun.

- 2026-11-17 · R7-C2 (content agent). The shared first glosses F7 reported (85, among visible entries) are now **0**. 110 `meanings[0]` strings were edited across all 8 `ko_*.json` files; no `id`, `rank`, `hangul` or other meaning changed. Rule: in each group the earliest entry (F7 ownership order, then rank) keeps its gloss, and every later entry gets an R6 T4 parenthetical naming its sense or register. Examples: 미안해 "I'm sorry (casual)", 저희 "we (humble)", 봉투 "bag (envelope, paper bag)", 보스 "boss (monster)", 상점 "shop (in-game store)", -지만 "but (verb ending)". Grading doesn't change, because `stripParentheticals` drops the parenthetical. **Synonym list for the owner:** none was needed. Close pairs were separated by register or nuance instead of being listed: 색/색깔 "colour (colloquial)", 아주/매우 "very (formal)", 잠깐/잠시 "for a moment (formal)", 간단하다/단순하다 "simple (plain)". The owner can still ask for any of these to be merged. This waiver of the append-only content rule comes from the owner (#7).
- 2026-11-17 · Content batch C3 (content agent, owner request: "find korean words starting from the most common ones… K-pop and K-drama phrases… AION 2 in-game words… you can create new decks if they fit a specific category"). **New decks:** `ko_core_6.json` (Korean Core 6, 156 words, ids `ko.core.1534`–`1689`, ranks 1–156) holds the next-frequency vocabulary. Core 1–5 already cover about 1,530 words, so it focuses on body, home, food, transport, school/tech, work, nature, feelings, verbs of cooking and handling, and texture/taste adjectives. `ko_slang.json` (Korean · Slang & Internet, 53 entries, `ko.slang.0001`–`0053`, all `register: casual`) holds MZ-generation abbreviations, dating and fandom terms (최애, 입덕, 성덕, 직캠, 본방사수), food slang (치맥, 얼죽아) and internet words (갑분싸, 어쩔티비, 낄끼빠빠); each abbreviation's expansion is in `notes`. Registering them took a small code change in `DeckCatalog`: `bundledVocabFiles` gets `ko_core_6` after Core 5 and `ko_slang` after Media, and `headwordOwnershipOrder` gets `ko.core.6` after Core 5 and `ko.slang` last. Display order needs no change (Core N is sorted by number; slang takes the "other bundled" slot). **Appended:** AION 2 +40 (`ko.aion2.0193`–`0232`; Deva Pass, Cuna, Stigma/Stigma Shard, Abyss Points, tuning stones, breakthrough, Expedition, Awakening Battle, Shugo Festa, Rudra, and community words 새싹, 무료 버스, 공팟, 트라이팟, 점핑). These come from Inven AION 2 guides (boards 6493/124, 6444/2080, 6444/1329). Media +23 (`ko.media.0147`–`0169`); 9 have web-verified title sources (BTS 피 땀 눈물, 불타오르네, 작은 것들을 위한 시, 봄날; dramas 선재 업고 튀어, 눈물의 여왕, 사랑의 불시착; shows 나 혼자 산다, 대환장 기안장) and 14 are unsourced everyday drama lines. Every new headword is unique across all Korean decks; shared first glosses stay at 0. **For the tester:** `entryCountsMatchTracker` and `mediaDeckIsValidAndSlotsBeforeAion2` need the new counts (Core 6 = 156, Slang = 53, AION 2 = 232, Media = 169), and the catalog now has 2 more vocab decks plus a derived "Conjugation · Core 6".
- 2026-11-17 · R8-S1/S2 (implementor). `SessionComposer` + `DeckHistory` (core), `Scheduler.allowed` with `extendAllowed` (mutating, chosen over a per-call parameter), engine top-up queue, `SchedulerConstants.wrongGapSessions = 2...4` and `reviewShare = 0.3` (§10.5). `DeckCoverage`, `StatsStore.deckHistory(for:)`, `AppEnvironment.cardKeys`, `DeckRowInfo.coverage/coveredCount` (§9.5: coverage = pool cards whose last counted answer was correct ÷ pool cards). No persisted-format change. **Deviations:** (1) the plan says music decks have no ranks, but several (triads, scales, chords, theory, progressions) do, so the composer is opt-in through a new `Deck.usesCoverageSessions` (default false; true for vocab, conjugation, Hangul reading) and every other deck stays byte-identical; (2) `SessionEngine(history:)` is `DeckHistory? = nil` rather than `.empty`, so "no history given" (every wrong card due) is distinguishable from a real empty history; (3) `DeckRowInfo.make` takes `poolKeys:` and a stats dictionary; `StatsView` passes its stats keys.
- 2026-11-18 · Owner/Planner · M6 planned in PLAN_M6_LYRICS.md. Owner: no synced lyrics; Spotify Premium; lyrics fetched from LRCLIB/Genius at runtime (Genius page-scraped, accepted for personal use), never bundled or exported; fetched English translation only, "English translation not available" otherwise; "Lyrics not available for this track" decided by Hangul share, not genre; saved cards keep the lyric line as their example. Planner: minimum iOS raised to 18.0 for the whole app (Translation framework); first deviation from §1 offline/no-network, still no third-party dependencies; `UserDecks.EntryDraft`/`replacing` must carry `sources` (they drop them today).
- 2026-11-18 · M6-L0 (implementor). Deployment target raised to iOS 18.0 in `project.yml` (the one always-true `#available(iOS 18.0, *)` in `Theme.swift` removed; the `MemoriseCore` package keeps its own iOS 17 floor, it uses no iOS 18 API). Build config now flows through `App/Config/Base.xcconfig`, which optionally includes the gitignored `Secrets.xcconfig` (Spotify client ID, Genius access token) into Info.plist keys `SpotifyClientID` / `GeniusAccessToken`. First network feature (deviation from §1 offline): Lyrics tab only, no third-party dependencies. Redirect URI `memorise-spotify://callback` is owner-verified in the Spotify dashboard (blocker rule: if rejected, stop and re-plan to an HTTPS redirect).
- 2026-11-18 · M6-L5 (implementor). `GlossService.runBatch` uses `session.translate(batch:)` (results stream in, so bubble spinners fill one by one) instead of `translations(from:)`; `Translation` is imported `@preconcurrency` because `TranslationSession` is not `Sendable` and its methods are `@concurrent`. Words the session cannot translate are marked unavailable, so a bubble never spins forever. `AppEnvironment` owns `spotify`, `lyrics` and `glosses`; `reloadCatalog()` refreshes the gloss lookup.
- 2026-11-18 · M6-L6/L7/L8 (frontend). (1) The reader's line layout is `LyricFlowLayout` (file `WordFlowLayout.swift`): `WordFlowLayout` already exists in `KoreanHeadline.swift` (centred headline lines), so the lyrics one, which is left-aligned and wraps without scaling, got its own name. (2) The deck validator requires a card example to have both `ko` and `en` filled and `ko` ≤ 40 Hangul, so the planned "`en` empty when the lines don't align" would fail validation. `AddToDeckSheet` keeps the lyric line as the example only when the English line is filled (aligned or typed) and the Korean line is within 40 Hangul; otherwise the card is saved without an example and the sheet says why. (3) Playlist rows can be opened even when Spotify won't share their songs; the detail view then shows "Spotify only shares songs from playlists you own" (rows carry a lock caption). (4) The reader requests the Korean title (`SpotifyClient.withKoreanTitle`) when it opens a song without one; a failure leaves the title as it was.
- 2026-11-18 · Owner/Planner · M6 L-D10: the deck validator's example rules are relaxed for **custom (`.user`) decks only**. `en` may be blank and `ko` may have up to 80 Hangul (`userExampleMaxHangul`), except for `pattern` entries, which still need `en`. Bundled decks keep both lines required and the 40 limit (`bundledExampleMaxHangul`). This restores L-D8 (saved lyric words keep their line). Segment PLAN_M6_LYRICS.md L8b, after L9. No wire change.
- 2026-11-18 · M6-L8b (implementor). Owner decision L-D10: `DeckValidator` example rules are relaxed for `.user` mode only. A custom-deck example needs a non-blank `ko`, `en` may be blank, and `ko` may have up to `DeckValidator.userExampleMaxHangul` (80) syllables. Pattern entries in a user deck still need `en` on every example (the pattern prompt is the first example's English). Bundled decks keep both lines and the 40 limit (`bundledExampleMaxHangul`); dialogue lines keep 40 everywhere. No wire change. `AddToDeckSheet` now always keeps the lyric line (≤ 80 Hangul), the practice reveal hides a blank English row, and this supersedes the L6/L7/L8 note (2) above.
- 2026-11-18 · Planner · Review Round 8 planned in PLAN_R9_FIXES.md. P-1 (R7-3): a killed session counts as `.completed` only with ≥ 5 counted attempts (`minCountedForKilledSession`), otherwise `.abandoned`; this corrects PLAN_R8 S1's acceptance premise (segment SF2). P-2 (R7-5): the coverage ring is shown only for `usesCoverageSessions` decks; other decks keep the accuracy ring (UF2). Recorded deviation from PLAN_R8 S1: Particles has no `introductionRank`, so it keeps adaptive selection instead of coverage composition. R8-8 needs no new decision: the M6 owner decisions (personal use, Genius page-scrape accepted, L-D8/L-D10 keep the lyric line in user decks, which are exported) already cover it; if the app is ever shared beyond the owner, move the Genius call behind a proxy or drop the HTML path. O-1 (R7-4): owner chose option (a) on 2026-11-18: `reviewShare` scales from 0.3 to `reviewShareMax` 0.6 with `dueCount ÷ targetEntries`, and `wrongGapSessions` is documented as a minimum gap (segment SF4).
- 2026-11-18 · R9-LF1 (implementor). `TrackQuery.sameArtist` rule 2 uses a **prefix** test (shorter key ≥ 4 characters) instead of the planned containment, because containment makes `("Rain", "Brain")` match, which the LF1 acceptance list says must be false. `("V", "V (BTS)")`, `("IU", "아이유 (IU)")` and `("BTS", "BTS (방탄소년단)")` match through the whole-word rule. `GeniusParser.lyricsHit` now requires a title match (`TrackQuery.titleMatches`); `translationHit` checks the artist as whole words in the hit title. The existing `LyricsTests` call sites got the new `titles:` argument (uncommitted QA file, left unstaged).
- 2026-11-18 · R9-LF3 (implementor). Request budgets are per phase: `LyricsConstants.koreanRequestBudget = 7` and `englishRequestBudget = 3` (replacing the single 5), each unit may include one retry after a 5xx. A cached document with no English page is fresh for `missingEnglishTTLDays = 7` (measured from `fetchedAt`), then refetched; a refetch that finds no English keeps the cached English page. PLAN_M6 §4.4 reworded.
- 2026-11-18 · R9-LF4 (implementor). The plan's only wire change: `LyricsCacheFile.koreanTitleChecked` (additive, missing = `false`, `schemaVersion` stays 1). `LyricsService.lyrics(for:forceRefresh:koreanTitle:)` now returns `(outcome, track)` and calls the `ko-KR` lookup only when the track has no Korean title, the cache doesn't know it and the entry is stale or missing; a fresh cached song needs no Spotify call. `SpotifyClient.withKoreanTitle` was replaced by `koreanTitle(of:) -> KoreanTitleLookup`.
- 2026-11-18 · R9-LF5/LF6/LF7 (implementor). Picker: `refreshAll` reloads Recent and the visible list, other lists reload once when opened (`staleSources`); a failed refresh keeps the list (`listError`, not yet shown: UF1); `reset()` runs on disconnect and a `generation` counter drops in-flight loads of the old account; `open(_:play:)` pushes the reader first and plays in a background task. `SpotifyClient.nowPlaying()` now returns `SpotifyPlayback` (track + `isPlaying`). Playlists page by 50, playlist songs by 100 (`PlaylistContents.tracks(_, nextOffset:)`). Robustness: Keychain `write` updates in place (no delete first) and `SpotifyAuth.keychainWriteFailed` is exposed (UI in UF1); the refresh task is cleared by identity; a timeout reads \"Spotify didn't respond\" (`SpotifyError.timedOut`), not offline; only `NO_ACTIVE_DEVICE` (or an unexplained 404) opens the Spotify app; declining the Korean language pack stops further prompts until the reader's refresh; the lyrics cache keeps at most `LyricsConstants.cacheMaxEntries = 200` files (LRU by modification date); `AppEnvironment.preview()` uses an in-memory Keychain, an offline HTTP stub and a memory-only cache; `SpotifyRequests` refuses ids that aren't base-62; Clear lyrics cache also empties the in-memory glosses.
