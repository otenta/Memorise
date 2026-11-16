# Memorise — M2: Music fundamentals+

- **Date:** 2026-11-16
- **Owner of this file:** planner. Implementor agents execute segments in order and tick the tracker (§4). PLAN.md §16 and `CLAUDE.md` apply. That includes the frozen persisted coding rule from G1: new `DeckOptions` cases are fine; renaming cases or changing payloads is not.
- **Prerequisites:** M1.1 G1–G5 implemented (done), G6 device checks recommended. M2 and M5 are independent and can run in either order.
- **Testing:** out of scope for this plan; the tester agent owns it (owner decision 2026-11-16). Segments give acceptance criteria and reference examples only.

---

## 1. Scope

| # | Feature | New deck / capability | Roadmap source |
|---|---|---|---|
| 0 | **Deck extensibility (F10)**: protocol hooks, UI registry, tuning plumbing, alternate tunings | refactor; no new deck | F10 / P2-8 |
| 1 | **Name the note**: a fretboard position is shown, name the note | `music.fretboard.names` | "Reverse cards" |
| 2 | **Find all**: play every A on the neck | `music.fretboard.findall` | "Find all" |
| 3 | **Intervals on the fretboard**: play a major 3rd above this note | `music.fretboard.intervals` | "Intervals" |
| 4 | **Note playback**: hear the target note (plucked-string synth) | capability, used by all music decks | "Audio playback" |
| 5 | **Interval ear training**: hear two notes, name the interval | `music.ear.intervals` | "for ear training" |
| 6 | **Microphone answer**: play the note; the app hears it and answers automatically with precise timing | capability on Notes + Intervals | "Mic pitch detection" |

## 2. Order and dependencies

```
M2-0a ─► M2-0b ─► M2-0c ─► M2-1 ─┬─► M2-2 ─┐
 (core)   (UI reg)  (tuning)  (theory)├─► M2-3 ─┤
                                     └─► M2-4 ─┼─► M2-8 (integration & QA)
                    M2-0b ─► M2-5 (audio) ─► M2-6 (ear) ─┤
                    M2-5 + M2-4 ─► M2-7 (mic) ───────────┘
```

M2-0a → M2-0c are strictly sequential and change no behaviour. After M2-1, the three fretboard decks (M2-2/3/4) can be built in parallel. M2-5 can start right after M2-0b.

---

## 3. Segments

### M2-0a — Core deck hooks (F10 part 1, no behaviour change)
**Goal:** the engine and decks stop reaching into specific option types.

**Files:** `Domain/Deck.swift`, `Session/SessionEngine.swift`, `Decks/FretboardNotesDeck.swift`, `Decks/VocabDeck.swift`, `Domain/Card.swift`, `Domain/SessionConfig.swift`, new `Decks/BuiltInDecks.swift`.

1. Add `public struct DeckKind: Hashable, Sendable, RawRepresentable { let rawValue: String }` with statics `.fretboardNotes`, `.vocab`. M2 adds more. Add `var kind: DeckKind { get }` to `Deck`.
2. Change the `Deck` protocol:
   - `present(_ card: Card, options: DeckOptions, using rng: inout SplitMix64) -> Card` **replaces** `present(_:using:)`. The default implementation returns `card`.
   - `newPerSession(options: DeckOptions) -> Int?` (default `nil` = no gating limit). `VocabDeck` returns `o.newPerSession`.
   - `SessionEngine.init` uses `deck.newPerSession(options:) ?? .max` instead of `config.options.vocab?.newPerSession`, and `presentNext` calls `deck.present(picked, options: config.options, using: &rng)`.
3. `FretboardNotesDeck.present` decides from `options.fretboard?.accidentalSpelling == .mixed`. **Remove** `FretboardNotePrompt.randomizeSpelling` (the F2 stop-gap). Cards are not persisted, so removing it is safe.
4. New `BuiltInDecks` (core): `static func defaultOptions(for id: DeckID) -> DeckOptions`, one table keyed by deck id, with a `"ko."` prefix → vocab default. `DeckOptions.fallback(for:)` forwards to it. This is the **single** closed table left in core; every M2 deck adds one row.
5. `DeckOptions` gets `var kindMatches: (DeckOptions) -> Bool`, implemented as `sameCase(as:)`. `AppEnvironment.normalized(for:)` uses it, which removes its two-case switch.

**Accept:** a DEBUG build behaves identically: Sharps/Flats/Mixed spelling, vocab gating, `PersistedFormatCheck` passes. `grep -rn "options.vocab\|options.fretboard" Packages/MemoriseCore/Sources/MemoriseCore/Session` is empty.

### M2-0b — App deck-UI registry (F10 part 2, no behaviour change)
**Goal:** adding a deck kind means adding **one** UI provider file plus one registry line. No downcasts or content switches remain in shared views.

**Files:** new `App/Sources/DeckUI/DeckUI.swift`, `DeckUI/FretboardNotesUI.swift`, `DeckUI/VocabUI.swift`, and edits to `CardViews.swift`, `Formatters.swift` (`CardLabel`), `SessionSetupView.swift`, `StatsView.swift`, `SessionViewModel.swift`, `AppEnvironment.swift`.

1. Protocol:
   ```swift
   @MainActor protocol DeckUI {
       func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView
       func answer(_ card: Card, ctx: DeckUIContext) -> AnyView
       func label(_ card: Card, settings: AppSettings) -> String
       func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView
       func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView?
       func sanitize(_ options: DeckOptions, deck: any Deck) -> DeckOptions   // default: identity
       func onReveal(_ card: Card, ctx: DeckUIContext)                         // default: no-op (vocab: TTS)
   }
   ```
   - `DeckUIContext` carries `settings`, `config` (for max fret, tuning, autoplay), `deck`, and the services (`speech`, later `notePlayer`).
   - `AnyView` is acceptable here because there are few views per card and none sit on a hot path.
2. `DeckUIRegistry` maps `[DeckKind: any DeckUI]` and lives on `AppEnvironment` as `env.deckUI(for: deck)`. An unknown kind triggers `assertionFailure` and falls back to a plain-text provider.
3. Move the existing code into the providers, unchanged:
   - **Fretboard:** `FretboardPromptView`/`AnswerView`, `FretboardOptionsSection`, `FretboardHeatmap`.
   - **Vocab:** the vocab views, `VocabOptionsSection`, `WeakestWordsSection`, the tag sanitising from `initialConfig`, and the auto-play TTS from `SessionViewModel.autoPlayIfNeeded`.
4. Shared views call the registry:
   - `CardPromptView` / `CardAnswerView` take `deck` + `card`
   - `CardLabel.text` → `ui.label`
   - `SessionSetupView`'s options switch → `ui.setupSection`
   - `StatsView`'s `is`/`as?` chain → `ui.statsSection`
   - `SessionViewModel.maxFret` moves into the fretboard provider's context use
5. Code review gate: after this segment, `grep -rn "as? VocabDeck\|is FretboardNotesDeck\|case let .fretboardNote\|case let .vocab" App/Sources` should only hit files under `App/Sources/DeckUI/`.

**Accept:** every screen looks and behaves the same: Setup for both kinds, Session, Summary labels, Stats heatmap and weakest words, vocab auto-play. All existing `#Preview`s still render.

### M2-0c — Tuning plumbing and alternate tunings (F10 part 3)
**Goal:** the real `Tuning` flows to every view, and the user can choose from a few common tunings without mixing stats between tunings.

**Files:** `Music/Fretboard.swift`, `Decks/FretboardNotesDeck.swift`, `Components/FretboardView.swift`, `Features/Stats/FretboardHeatmap.swift`, `DeckUI/FretboardNotesUI.swift`, `Domain/PersistedFormatCheck.swift`, PLAN §7.

1. `Tuning` gets a stable `id: TuningID` (a `String` raw-value enum). Presets (MIDI, string 6 → 1):

   | `TuningID` | Name | Open strings |
   |---|---|---|
   | `standard` | Standard | E2 A2 D3 G3 B3 E4 (40 45 50 55 59 64) |
   | `dropD` | Drop D | D2 A2 D3 G3 B3 E4 (38 45 50 55 59 64) |
   | `halfDown` | E♭ standard | E♭2 A♭2 D♭3 G♭3 B♭3 E♭4 (39 44 49 54 58 63) |
   | `dadgad` | DADGAD | D2 A2 D3 G3 A3 D4 (38 45 50 55 57 62) |
   | `openG` | Open G | D2 G2 D3 G3 B3 D4 (38 43 50 55 59 62) |

   `Tuning.stringName(_:)` derives names from the open pitch, e.g. "low D".
2. `FretboardOptions` gains `tuning: TuningID = .standard`, decoded tolerantly (an unknown value falls back to `.standard`; add it to `recoveredFields` only if the key is present but unreadable).
3. **ItemKey namespace:** standard tuning keeps today's keys **unchanged forever** (`fret:s6:A`). Non-standard tunings prefix the deck's key scheme with the tuning, e.g. `fret@dropD:s6:A`. This rule applies to every M2 fretboard deck. Write it into PLAN §6.1 next to the "never change keys" rule.
4. Decks are no longer constructed with a fixed tuning. `cards(options:)` reads `Tuning.preset(o.tuning)`. `FretboardNotesDeck.init()` takes no tuning; keep a deprecated `init(tuning:)` only if something still needs it.
5. Views:
   - `FretboardView` takes `stringCount` from the tuning (it already has the parameter)
   - `FretboardHeatmap` takes `tuning` and uses `tuning.stringNumbers`; remove `1...6`
   - the static `FretboardNotesDeck()` in `CardViews` goes away, because the provider uses `ctx.deck`
   - `SessionSetupView`'s string chips come from the tuning, showing names like "6 · D"
6. Setup: add a **Tuning** picker (menu style) at the top of the fretboard options section. The heatmap and stats show the tuning currently selected in the Stats deck picker: add a small tuning menu in the stats section, defaulting to the last-used tuning.
7. `PersistedFormatCheck`: keep the **legacy** M1 JSON fixtures, which have no `tuning` key. Assert that they decode to `.standard` with empty `recoveredFields`. Add a new fixture with `tuning: "dropD"` for the byte-identical re-encode check. Legacy fixtures are now checked by decode only, since re-encoding adds the new key.

**Accept:**
- With Standard, keys, stats and heatmap are identical to before.
- A Drop D session shows "6 · low D", and its answers are correct: E on string 6 → frets 2 and 14.
- Its stats appear only under the Drop D heatmap.
- History sessions from M1 still show "Standard".

### M2-1 — Theory additions (core)
**Files:** new `Music/Interval.swift`, `Music/Pitch.swift`, `Music/Fretboard.swift`, PLAN §7.1.

1. `Interval`: `m2 M2 m3 M3 P4 TT P5 m6 M6 m7 M7 P8`, with `semitones`, `letterSteps` (m2/M2 → 1, m3/M3 → 2, P4 → 3, TT → 3 (spelled as A4), P5 → 4, m6/M6 → 5, m7/M7 → 6, P8 → 7), `shortName` ("M3"), and `longName` ("major 3rd"). Raw values are part of ItemKeys: **never change them**.
2. `NoteSpelling.transposed(by: Interval) -> NoteSpelling?`:
   - target letter = letter + `letterSteps`
   - accidental = whatever makes the pitch class correct
   - returns `nil` if that would need a double sharp or double flat (callers re-roll)
   - Examples: C + M3 = E; E + M3 = G♯; B♭ + P4 = E♭; F + TT = B; A♯ + M3 → nil.
3. `Pitch` (MIDI note): `midi: Int`, `pitchClass`, `octave` (scientific: MIDI 60 = C4), `frequency` (A4 = 440 Hz, 12-TET), `nearest(toFrequency:) -> (Pitch, cents)`.
4. `Fretboard.positions(of pitchClass:, strings:, tuning:, fretRange:) -> [(string, fret)]`, and `Fretboard.midi(string:, fret:, tuning:)`.

**Accept:** the transposition examples above hold, every interval from each of the 7 naturals gives the correct pitch class, and `frequency(69) == 440`. These are reference examples for the tester.

### M2-2 — "Name the note" deck (reverse cards)
**Deck:** `music.fretboard.names` · kind `.fretboardNames` · title "Name the Note" · subtitle "See a fret, say the note". Options: reuses `.fretboard(FretboardOptions)`.

1. Cards are every (string ∈ strings, fret ∈ fretRange) whose pitch class is in `noteSet` (naturals → only natural positions). **Key:** `fretname:s<string>:f<fret>`, with the tuning prefix rule. Expected sizes: 6 strings × 0…12 → 78 positions (all) or 46 (naturals).
2. Prompt: a `FretboardView` showing the single dot (no label) and the string highlighted, plus the caption "Which note?". Answer: the note name (letter/solfège per settings, spelled by `accidentalSpelling`, Mixed randomised in `present`) plus "string n, fret f".
3. Pattern penalty: same string as previous ×0.35; same fret as previous ×0.5; same pitch class as previous ×0.35.
4. Stats section: a per-position heatmap (string × fret grid). Reuse `FretboardHeatmap`'s cell rendering, keyed by position.

**Accept:** all 46 natural positions appear over a long session; answer names match the theory check; a left-handed or flipped board still places the dot correctly.

### M2-3 — "Find all" deck
**Deck:** `music.fretboard.findall` · kind `.fretboardFindAll` · "Find All" · "Every A on the neck". Options: `.fretboard(FretboardOptions)`. Strings and range limit where you must find them.

1. One card per pitch class in `noteSet` (7 or 12). **Key:** `findall:<canonicalSharpName>` (+ tuning prefix). The string set does not change the key. *ASSUMPTION:* finding every A is one skill regardless of which strings are included.
2. Prompt: "Find every **A**" plus "strings 6–1 · frets 0–12". Timing runs as usual from prompt to OK; the user plays or points to them all, then taps OK.
3. Answer: the board with **all** positions marked, the octave shown in the dot labels ("A2", "A3"…), and a count ("10 positions").
4. Pattern penalty: same pitch class back-to-back is already prevented by cooldown; a fifth-related previous note ×0.7 (optional; skip if it complicates).
5. **Timing note:** response times are naturally much longer here (5–20 s). The response clamp max of 30 s covers it. The summary colour thresholds are relative to the item's own EWMA, so no special-casing is needed.

**Accept:** with naturals and 0…12, there are 7 cards and each answer shows the correct number of positions (e.g. E on 6 strings × 0–12 = 12 positions, including both open E strings).

### M2-4 — "Intervals" deck
**Deck:** `music.fretboard.intervals` · kind `.fretboardIntervals` · "Intervals" · "Play a 3rd above this note". **New options case** `.intervals(IntervalOptions)` (new case, frozen-coding rule respected; add a `PersistedFormatCheck` fixture):

| Field | Default |
|---|---|
| `intervals: Set<Interval>` | {m3, M3, P4, P5, P8} |
| `strings: Set<Int>` | all (root strings) |
| `fretRange` | 0…12 (root frets) |
| `tuning: TuningID` | `.standard` |
| `accidentalSpelling` | `.sharps` |

1. Cards: one per (interval, root string). **Key:** `int:<interval.raw>:s<string>` (+ tuning prefix).
2. `present(options:rng:)` picks a **random root fret** in range on that string, so the root pitch varies every time. Spell the root (Mixed → random). Compute the target spelling via `transposed`; if that returns `nil`, re-roll (max 10 tries, then use a natural root). The root choice is therefore part of presentation and not part of identity, consistent with the stable-key rule.
3. Prompt: board with the root dot labelled ("C"), plus the text "Play a **major 3rd** above **C**".
4. Answer: the target note name (e.g. "E"), with every target position marked within a playable window: same string, or the next 1–2 higher strings, within root fret −4…+5. The nearest/typical shape is highlighted (`.answer`) and the others are `.secondary`. Caption: "major 3rd = 4 semitones".
5. Pattern penalty: same interval as previous ×0.35; same root string ×0.6.

**Accept:** over 50 prompts with Mixed spelling, no double accidental appears; each answer's marked positions sound the interval (verify on guitar for 10 random cards).

### M2-5 — Note playback (plucked-string synth)
**Goal:** hear the exact pitch of the answer (string + fret → MIDI). Fully offline, no samples.

**Files:** new `App/Sources/Services/NotePlayer.swift`, new `App/Sources/Services/AudioSessionCoordinator.swift`, `SpeechService.swift`, `AppSettings.swift`, `SettingsView.swift`, fretboard providers.

1. **Synth:** Karplus–Strong on an `AVAudioSourceNode` (mono, 48 kHz).
   - excitation: noise burst lowpassed by a 2-tap average
   - decay factor 0.996
   - 1.6 s max with a 30 ms release
   - peak −6 dBFS
   - polyphony 4 (for intervals or a harmonic ear mode)
   - Precompute nothing; the per-sample loop is cheap.
   - `play(midi:at delay: TimeInterval = 0)` and `play(sequence:[(midi, delay)])`.
2. **Audio session:** one `AudioSessionCoordinator` (MainActor) owns the category:
   - `.playback` + `.mixWithOthers` for TTS and synth (today's behaviour, D3)
   - `.playAndRecord` + `.measurement` + `.defaultToSpeaker` only while the mic is active (M2-7)
   - `SpeechService` uses the coordinator instead of setting the category itself
   - deactivate on session end (existing P4-a)
3. **UI:** a 🔊 button on music answers. Fretboard Notes plays the lowest answer fret; Name the Note plays that position; Find All plays the positions low→high as an arpeggio; Intervals plays root then target. Settings → Music: **"Play note on reveal"** (default off) and **"Note volume"**.
4. Engine timing is unaffected, because playback starts on reveal, after the response time has been recorded.

**Accept (device):**
- the pitch matches a tuned guitar (check with a tuner app: A2 = 110 Hz on string 6, fret 5)
- no clicks at note start or end
- background music keeps playing
- the silent switch behaves as D3 (plays through)

### M2-6 — Interval ear-training deck
**Deck:** `music.ear.intervals` · kind `.earIntervals` · "Interval Ear" · "Hear it, name it". **New options case** `.earIntervals(EarIntervalOptions)`: `intervals` (default {m3, M3, P4, P5, P8}), `mode` (`.ascending` default, `.descending`, `.harmonic`), `rootRange` (MIDI 48…67, i.e. C3…G4).

1. Cards: one per (interval, mode). **Key:** `ear:<interval.raw>:<mode.raw>`.
2. `present`: a random root in `rootRange` (stored in a new `EarIntervalPrompt { interval, mode, rootMidi }`, added as a `CardContent` case).
3. **Prompt flow:** the prompt view plays the two notes (0.6 s apart; harmonic = together) and calls `vm.promptDidAppear()` **when the second note starts**, so the response timer measures recognition and not playback. A "Replay" button replays without resetting the timer. If the app is backgrounded mid-playback, the existing interrupt path re-shows the card with a fresh timer.
4. Answer: the interval long name, semitone count, and both note names; plus 🔊 to replay.
5. Mic is never used; audio-off devices still work, since the user can turn the volume up.
6. Pattern penalty: same interval as previous ×0.35.

**Accept:** the timer starts at the second note (check the on-screen timer setting); Replay doesn't reset it; descending and harmonic modes sound correct.

### M2-7 — Microphone answer (pitch detection)
**Goal:** on Fretboard Notes and Intervals, the user can **play** the answer. The app detects a stable correct pitch, records the response time precisely from the note onset, and grades the card correct automatically.

**Files:** new `App/Sources/Services/PitchDetector.swift` (YIN), new `App/Sources/Services/MicAnswerController.swift`, `Session/SessionEngine.swift` (core), `Domain/SessionConfig.swift` (core), `project.yml`, the Setup provider sections, `SessionView.swift`.

1. **Permission:** `NSMicrophoneUsageDescription` in `project.yml` → info: "Memorise listens to your guitar to check the note you play." Request it on the first session that uses mic mode. If permission is denied, show an inline note in Setup and fall back to touch.
2. **Config:** `SessionConfig` gains `inputMode: InputMode = .touch` (`.touch`, `.microphone`), decoded tolerantly. Add a `PersistedFormatCheck` fixture; legacy fixtures decode to `.touch`. The Setup toggle "Answer by playing (microphone)" is shown only for decks whose UI provider reports `supportsMicAnswer` (Notes, Intervals).
3. **Detector (YIN):**
   - input tap, 2048-sample frames, 512 hop, at the hardware rate
   - threshold 0.12, parabolic interpolation
   - RMS gate −45 dBFS
   - range 70–1 400 Hz
   - output `(midi, cents, confidence, onsetHostTime)`
   - Runs off the main thread; publishes on MainActor at most every hop.
   - **Stable** = same MIDI note within ±40 cents for 3 consecutive frames. The onset is the host time of the first frame of that run.
4. **Matching:**
   - Fretboard Notes: stable pitch class == target **and** MIDI within the target string's playable range (`openMidi … openMidi + maxFret`).
   - Intervals: target pitch class within one octave above the root.
   - A mismatch shows a transient "Heard G♯" chip and keeps listening. Wrong notes never auto-grade.
5. **Engine API (core):** `answerDetected(at onset: Duration) -> [SessionEffect]`. It is valid only in `.prompting`. It does `ok` at `onset`; `responseMs` is measured from `promptShownAt` to `onset`, clamped ≥ 0. It then grades correct immediately with `gradeMs = 0`, bypassing the lockout, which is meant for human double-taps.
   - Clock mapping: the controller converts `onsetHostTime` to the engine clock as `clock.now() - (nowHostTime - onsetHostTime)`. Use `AVAudioTime.seconds(forHostTime:)` on both values. Document that the clocks are both monotonic and that the mapping error is < 1 ms while the device is awake.
6. **Timeout:** after `micTimeout` (Setup: 10 s default; options 5/10/20 s), the card reveals for **manual** grading, because the user may have played correctly while the mic missed it. Tapping OK at any time works as today.
7. **Session UX:**
   - a small live level meter and a "Listening…" chip on the prompt
   - the detector pauses during reveal and during TTS/synth playback, to avoid hearing itself
   - the audio session switches to `.playAndRecord` for the session and is restored on exit
8. **Persistence:** no `Attempt` schema change. Mic sessions are identified by `config.inputMode`, so the summary and history can label them "🎤".

**Accept (device, guitar in standard tuning):**
- 20 Notes cards answered by playing: ≥ 18 auto-graded correctly
- a wrong note never auto-grades
- the response time differs from a stopwatch by < 100 ms
- quiet-room false triggers: 0 in 2 minutes of silence
- denying permission falls back cleanly

### M2-8 — Integration, docs, QA
1. Home: the Music section lists, in order, Fretboard Notes, Name the Note, Find All, Intervals, Interval Ear.
2. `BuiltInDecks` has one row per new deck; `DeckCatalog.builtIn()` includes them.
3. PLAN.md:
   - §6.1: the tuning key-prefix rule and the new key schemes
   - §7: tunings, intervals, `Pitch`
   - §11: the new prompt/answer layouts and mic UX
   - §15: M2 marked planned, with a link here
   - §17: tracker and decision-log entries
4. README: the manual QA checklist gains the M2-0c, M2-5, M2-6 and M2-7 device checks, and the microphone permission note.

---

## 4. Tracker

| Segment | Status | Notes |
|---|---|---|
| M2-0a Core deck hooks (F10.1) | ☐ | no behaviour change |
| M2-0b Deck-UI registry (F10.2) | ☐ | no behaviour change |
| M2-0c Tuning plumbing + presets (F10.3) | ☐ | key prefix rule |
| M2-1 Theory: intervals, spelling, Pitch | ☐ | |
| M2-2 Name the Note deck | ☐ | |
| M2-3 Find All deck | ☐ | |
| M2-4 Intervals deck | ☐ | new options case |
| M2-5 Note playback (synth) | ☐ | |
| M2-6 Interval Ear deck | ☐ | new options case + content case |
| M2-7 Microphone answer | ☐ | `NSMicrophoneUsageDescription` |
| M2-8 Integration & QA | ☐ | |

## 5. Key and format rules introduced by M2 (summary)

| Deck | ItemKey scheme (standard tuning) | Non-standard tuning |
|---|---|---|
| Fretboard Notes | `fret:s6:A` (unchanged) | `fret@dropD:s6:A` |
| Name the Note | `fretname:s6:f5` | `fretname@dropD:s6:f5` |
| Find All | `findall:A` | `findall@dropD:A` |
| Intervals | `int:M3:s6` | `int@dropD:M3:s6` |
| Interval Ear | `ear:M3:asc` | n/a |

New persisted fields and cases: `FretboardOptions.tuning`, `DeckOptions.intervals`, `DeckOptions.earIntervals`, `SessionConfig.inputMode`. Each has tolerant decoding and a `PersistedFormatCheck` fixture, per G1.

## 6. Decisions and open questions
- **ASSUMPTION:** mic mode auto-grades **only correct** answers; timeouts fall back to self-grading. This is honest, because pitch detection can miss a correctly played note.
- **ASSUMPTION:** synthesised plucked tones (no samples) are good enough for M2; a sampler is a later upgrade.
- **ASSUMPTION:** the five tuning presets are enough; custom tunings come later.
- **DECIDED (owner, 2026-11-16):** testing is handled by the tester agent; this plan contains no test work.
- **OPEN (owner):** should mic mode also exist for **Find All**? It would need tracking a sequence of distinct octaves; it is left out of M2.
