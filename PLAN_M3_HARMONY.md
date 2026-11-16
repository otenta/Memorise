# Memorise — M3: Harmony & shapes

- **Date:** 2026-11-16
- **Owner of this file:** planner. Implementor agents execute segments in order and tick the tracker (§5). PLAN.md §16 and `CLAUDE.md` apply, including the frozen persisted-coding rule (G1: new `DeckOptions` cases are fine, renaming is not) and "never change or reuse an `ItemKey`".
- **Prerequisites:** M2-0a/0b/0c (deck hooks, `DeckUI` registry, tunings), M2-1 (`Interval`, `NoteSpelling.transposed`, `Pitch`), and M2-5 (`NotePlayer`) for the playback buttons. If M2-5 isn't there yet, playback is skipped, not blocked.
- **Testing:** out of scope; the tester agent owns it. Segments give acceptance criteria and **reference examples** only.
- **Owner direction:** large, varied pools. Defaults are wide (all keys, all qualities), so sessions don't repeat quickly.
- **Tuning:** M3 decks are **standard tuning only**: the shape data and the box/3NPS conventions are standard-tuning concepts. Their options carry no tuning field. If tunings are added later, keys use the M2 `@<tuning>` prefix rule.

---

## 1. Scope

| # | Deck / capability | Kind | What the user does |
|---|---|---|---|
| 0 | Shared UI: fret window, degree labels, vertical chord diagrams, Home groups, strum/sequence playback | infra | — |
| 1 | Theory core: chords, scales/modes, keys, diatonic harmony, Roman numerals, circle of fifths, progressions | core | — |
| 2 | Chord shape library (open, barre, CAGED, power, 7ths, sus) + voicing generator + load-time validator | data + core | — |
| 3 | **Play the Chord**: "Play B♭m7 (A-shape barre)" | `music.chords.play` | play/finger it |
| 3 | **Name the Chord**: diagram shown → name it | `music.chords.name` | name it |
| 4 | **Triads on string sets**: "C major, 1st inversion, strings 3-2-1" | `music.triads` | play it |
| 5 | **Arpeggios**: "A minor 7 arpeggio from string 6" | `music.arpeggios` | play it |
| 6 | **Scales & modes**: "A minor pentatonic, box 1" / "D Dorian, 3NPS position 2" | `music.scales` | play it |
| 7 | **Key signatures**: "How many sharps in E major?" ⇄ "Which major key has 3 flats?" | `music.theory.keysig` | answer |
| 8 | **Diatonic chords**: "iii in G major?" ⇄ "Bm is which degree in G?" | `music.theory.diatonic` | answer |
| 9 | **Progressions**: "Play ii–V–I in G" | `music.progressions` | play it |
| 10 | **Circle of fifths**: fifth above, fourth above, relative minor/major | `music.theory.circle` | answer |

All decks use the existing `touch` answer mode: self-grade, with the timer from prompt to OK. **No microphone answers in M3**: chord recognition is polyphonic and out of scope.

## 2. Order and dependencies

```
M3-0 ─┐
M3-1 ─┼─► M3-2 ─► M3-3 (play/name chord) ─► M3-9 (progressions)
      ├─► M3-4 (triads)   M3-5 (arpeggios)   M3-6 (scales)
      └─► M3-7 (key sigs)  M3-8 (diatonic)   M3-10 (circle)   ─► M3-11 (integration)
```

M3-0 and M3-1 can run in parallel. After them, the "theory" decks (7, 8, 10) and the generated fretboard decks (4, 5, 6) are independent of each other and of the shape library.

---

## 3. Shared design decisions

### 3.1 Keys (tonalities)
Only the **15 standard major key signatures** are used: C G D A E B F♯ C♯ / F B♭ E♭ A♭ D♭ G♭ C♭, with their **15 relative minors**. This keeps spelling free of double accidentals. Enharmonic pairs (F♯/G♭, C♯/D♭, B/C♭) are separate keys with separate cards, because their spellings differ.

### 3.2 Root choice and identity
For fretboard decks with a movable shape, the **root is part of the key**, e.g. `chord:Eshape.m7:Bb`, because finding the right fret is part of the skill and the owner wants large pools. The fret position comes from the root (lowest valid fret, then +12 if a setting allows "anywhere on the neck").

### 3.3 Diagram conventions
- **Chords** use a new **vertical chord box** (`ChordDiagramView`), as guitarists expect: 6 strings vertical, a 5-fret window, `x`/`o` above the nut, finger numbers in the dots, a barre bar, and a base-fret label ("5fr").
- **Scales, arpeggios and triads** use the existing horizontal `FretboardView` with the new fret window. The root is `.answer` and the other tones are `.secondary`.
- A Settings → Music option **"Dot labels: Notes / Degrees"** (R, ♭3, 5, ♭7 …) applies to all M3 fretboard answers.

### 3.4 Home grouping
The Music section would list ~14 decks, so add `Deck.group: String` (core, display only, default `""`) and show sub-headers:

| Group | Decks |
|---|---|
| Fretboard | Notes, Name the Note, Find All, Intervals |
| Ear | Interval Ear |
| Chords & shapes | Play the Chord, Name the Chord, Triads, Arpeggios, Progressions |
| Scales | Scales & Modes |
| Theory | Key Signatures, Diatonic Chords, Circle of Fifths |

---

## 4. Segments

### M3-0 — Shared UI and playback infrastructure
**Files:** `App/Sources/Components/FretboardView.swift`, new `App/Sources/Components/ChordDiagramView.swift`, new `App/Sources/Components/CircleOfFifthsView.swift` (used by M3-10), new `App/Sources/Components/StaffView.swift` (used by M3-7), `Domain/Deck.swift` (`group`), `Features/Home/HomeView.swift`, `Support/AppSettings.swift`, `Features/Settings/SettingsView.swift`, `Services/NotePlayer.swift`.

1. `FretboardView`: replace `maxFret` with `fretWindow: ClosedRange<Int>` (keep a `maxFret` convenience init). When the window doesn't start at 0, draw no nut, label the first fret number, and keep logarithmic spacing relative to the window. Marks outside the window are ignored.
2. `FretMark.label` already exists. Add the app setting `dotLabels` (`.notes` default, `.degrees`) and a helper `DegreeLabel.text(interval:)` (R, ♭2, 2, ♭3, 3, 4, ♭5, 5, ♯5, 6, ♭7, 7).
3. `ChordDiagramView(voicing:, showFingers:)`:
   - vertical, a 5-fret window chosen from the voicing
   - `x`/`o` row, finger numbers, barre bar across the barred strings
   - base-fret label when the window doesn't start at fret 1
   - left-handed mirroring, matching the existing setting
   - accessibility label: "B flat minor 7, barre at fret 1, strings 5 to 1"
4. `StaffView(keySignature:)`: a treble staff drawn on a `Canvas`, the clef as the Unicode glyph `𝄞` (fall back to the text "Treble" if the glyph is missing), and sharps/flats in standard staff positions. Positions table: sharps F5 C5 G5 D5 A4 E5 B4; flats B4 E5 A4 D5 G4 C5 F4.
5. `CircleOfFifthsView(highlight:, secondary:)`: a 12-segment ring, majors outside and relative minors inside, with highlight/secondary styles. Used in M3-10 and optionally in M3-7/M3-8 answers.
6. `Deck.group` with a default of `""`, plus the Home sub-headers from §3.4. Empty groups are hidden.
7. `NotePlayer` helpers: `strum(midis:, spacing: 0.03)`, low→high; `sequence(midis:, spacing: 0.25)` for scales and arpeggios; `progression(chords: [[midi]], beat: 0.9)`. All share the existing synth voice pool; raise polyphony to 6 for strums.

**Accept:** all existing fretboard answers look unchanged (window 0…maxFret); `#Preview`s exist for the chord diagram (open C, F barre, Bm7 at 2fr), the staff (0, 4♯, 6♭) and the circle; Home shows the group headers.

### M3-1 — Theory core
**Files:** new `Music/Chord.swift`, `Music/Scale.swift`, `Music/Key.swift`, `Music/Progression.swift` (core, Foundation only).

1. **`ChordQuality`**: raw values are part of keys, never change them.

   | raw | symbol | intervals from root |
   |---|---|---|
   | `maj` | (none) | 3 5 |
   | `min` | m | ♭3 5 |
   | `dim` | ° | ♭3 ♭5 |
   | `aug` | + | 3 ♯5 |
   | `sus2` | sus2 | 2 5 |
   | `sus4` | sus4 | 4 5 |
   | `pow5` | 5 | 5 |
   | `dom7` | 7 | 3 5 ♭7 |
   | `maj7` | maj7 | 3 5 7 |
   | `min7` | m7 | ♭3 5 ♭7 |
   | `m7b5` | m7♭5 | ♭3 ♭5 ♭7 |
   | `dim7` | °7 | ♭3 ♭5 𝄫7 (spelled as a diminished 7th; e.g. C°7 = C E♭ G♭ B𝄫, displayed as written) |
   | `six` | 6 | 3 5 6 |
   | `min6` | m6 | ♭3 5 6 |
   | `add9` | add9 | 3 5 9 |

   `Chord { root: NoteSpelling, quality }` gives `tones: [NoteSpelling]` (correctly lettered, one letter per chord degree), `symbol` ("B♭m7"), and `pitchClasses`. Double flats are allowed **only** for `dim7`'s 7th; everything else must be single-accidental with the §3.1 roots, otherwise the chord is skipped.
2. **`ScaleType`**: `major`, `naturalMinor`, `harmonicMinor`, `melodicMinor`, `majorPentatonic`, `minorPentatonic`, `blues`, and the modes `ionian`, `dorian`, `phrygian`, `lydian`, `mixolydian`, `aeolian`, `locrian`. Each has its interval pattern and `degreeLabels`. `Scale(tonic:, type:)` gives notes spelled one letter per degree for heptatonic scales; pentatonic and blues use the parent scale's spellings, with blues adding ♭5.
3. **`Key`** (`tonic: NoteSpelling`, `mode: .major/.minor`), restricted to §3.1:
   - `signature: KeySignature` (count, sharps or flats, ordered list)
   - `relative`
   - `diatonicTriads` / `diatonicSevenths` with Roman numerals (I ii iii IV V vi vii° / i ii° III iv v VI VII). For minor keys, a harmonic-minor V/V7 option.
4. **Circle of fifths:** `CircleOfFifths.order` (C G D A E B F♯/G♭ D♭ A♭ E♭ B♭ F), plus `fifthAbove`, `fourthAbove`, `relativeMinor` and `relativeMajor`, keeping the §3.1 spellings.
5. **`Progression`**: id (raw value in keys), display name, Roman numerals, mode:

   | id | Numerals |
   |---|---|
   | `I-IV-V` | I IV V |
   | `ii-V-I` | ii7 V7 Imaj7 |
   | `I-V-vi-IV` | I V vi IV |
   | `vi-IV-I-V` | vi IV I V |
   | `I-vi-IV-V` | I vi IV V |
   | `I-IV-vi-V` | I IV vi V |
   | `blues12` | I7 I7 I7 I7 IV7 IV7 I7 I7 V7 IV7 I7 V7 |
   | `ii-V-i` | ii°7(m7♭5) V7 i (minor) |
   | `i-iv-v` | i iv v (minor) |
   | `i-VI-III-VII` | i VI III VII (minor) |
   | `i-VII-VI-V` | i VII VI V (Andalusian, harmonic V) |

   `realize(in key:) -> [Chord]`.

**Reference examples for the tester:**
- C maj = C E G; B♭7 = B♭ D F A♭; F♯m7♭5 = F♯ A C E; C°7 = C E♭ G♭ B𝄫
- D dorian = D E F G A B C; E♭ major = E♭ F G A♭ B♭ C D
- A minor pentatonic = A C D E G; A blues = A C D E♭ E G
- G major: 1♯ (F♯); C♭ major: 7♭; F♯ major: 6♯; C♯ minor: 4♯
- iii in G = Bm; V7 in E♭ = B♭7; ii–V–I in G = Am7 D7 Gmaj7
- relative minor of E♭ = Cm; fifth above B = F♯; fourth above F = B♭

### M3-2 — Chord shape library, voicing generator, validator
**Files:** new `Resources/Shapes/chord_shapes.json` (core bundle), new `Music/ChordShape.swift`, new `Music/ShapeValidator.swift`, `Decks/DeckCatalog.swift` (load and report).

1. **Data format** (`schemaVersion: 1`):
   ```json
   { "id": "Eshape.m7", "family": "barre", "cagedShape": "E", "quality": "min7",
     "rootString": 6, "movable": true,
     "frets":   [0, 2, 0, 0, 0, 0],      // string 6 → 1, relative to the root fret; null = muted
     "fingers": [1, 3, 1, 1, 1, 1],
     "barre":   { "fret": 0, "fromString": 6, "toString": 1 } }
   ```
   - Open shapes have `movable: false`, absolute frets and a fixed root (`"root": "C"`).
   - Ids are part of keys: **never change or reuse them**.
2. **Content: ≥ 60 shapes**, for variety:
   - **Open:** C A G E D, Am Em Dm, A7 B7 C7 D7 E7 G7, Amaj7 Cmaj7 Dmaj7 Fmaj7 Gmaj7, Am7 Dm7 Em7, Asus2 Asus4 Dsus2 Dsus4 Esus4, Cadd9, small F, A6, E5 A5 D5.
   - **Barre E-shape (root on 6):** maj, min, 7, maj7, m7, m7♭5, sus4, 6.
   - **Barre A-shape (root on 5):** maj, min, 7, maj7, m7, m7♭5, sus2, sus4, 6, m6.
   - **CAGED major:** C, A, G, E, D shapes as movable forms. **CAGED minor:** Cm, Am, Gm, Em, Dm shapes.
   - **Power chords** 5 (roots on 6 and 5); **dim7** (root on 6 and 5) and **aug** movable.
3. **Voicing generator:** `ChordShape.voicing(root: NoteSpelling, tuning: .standard, maxFret:) -> Voicing?`. For a movable shape, it finds the root fret on `rootString` (lowest ≥ 1 for a barre, ≥ 0 if the shape allows an open root) and adds the relative frets. It returns `nil` if any fret exceeds `maxFret`. A `Voicing` holds per-string frets, fingers, barre, the sounding MIDI notes and per-string degree labels.
4. **`ShapeValidator`** runs at load in every configuration, like `DeckValidator`, reporting into `DeckLoadReport.validationWarnings`. It checks that:
   - the sounded pitch classes ⊆ chord tones, and include the root and the 3rd (except `sus*`/`pow5`) and the 7th for seventh qualities
   - the lowest sounded note is the root, for shapes whose family isn't an inversion
   - fingers exist for fretted notes; ids are unique
   - the span is ≤ 4 frets
   A failing shape is **dropped** and reported.
5. **Content sourcing:** the shapes are standard guitar knowledge. The author cross-checks each against a reputable chord reference and lists the URL per shape in the PR's verification table.

**Reference examples for the tester:** A-shape min7 with root B♭ → x-1-3-1-2-1; E-shape maj with root G → 3-5-5-4-3-3; open C → x-3-2-0-1-0; C-shape CAGED with root D → x-5-4-2-3-2.

### M3-3 — "Play the Chord" and "Name the Chord" decks
**New options case** `.chords(ChordOptions)`, shared by both decks:

| Field | Default |
|---|---|
| `families: Set<ShapeFamily>` | all (`open`, `barre`, `caged`, `power`, `other`) |
| `qualities: Set<ChordQuality>` | all |
| `roots: Set<RootName>` | all 12 (spelled per §3.1; sharp/flat roots use the more common spelling: B♭, E♭, A♭, D♭, F♯) |
| `maxFret` | 12 |

1. **Play the Chord** (`music.chords.play`, kind `.chordsPlay`, group "Chords & shapes"):
   - Cards: open shapes → one card each (`chord:<shapeId>`); movable shapes → one card per root that has a valid voicing (`chord:<shapeId>:<root>`). The pool is ~400 cards with defaults.
   - Prompt: the big chord symbol ("B♭m7"), a shape hint ("A-shape barre"), and the setting "Show shape hint" (default on).
   - Answer: the `ChordDiagramView`, tones with degrees ("B♭ D♭ F A♭ · R ♭3 5 ♭7"), and a 🔊 strum.
   - Pattern penalty: same shape as previous ×0.35; same root as previous ×0.5.
2. **Name the Chord** (`music.chords.name`, kind `.chordsName`):
   - Same card set; keys `chordname:…`.
   - Prompt: the diagram only. Answer: the symbol plus the long name ("B flat minor seventh") and the tones.
   - The input mode `choice` becomes available once M4-0 lands: 4 options (the correct chord, the same root with a different quality, the same quality with a different root, and one random). Until then, `touch` only.
3. Stats sections: a grid of quality × root coloured by error EWMA; open chords listed separately.

**Accept:** every card's diagram matches its symbol (spot-check 20 against the reference); no voicing exceeds `maxFret`; the strum sounds the shown notes low→high.

### M3-4 — Triads on string sets (generated)
**Deck:** `music.triads`, kind `.triads`. **New options case** `.triads(TriadOptions)`:
- `qualities` (default maj, min, dim, aug)
- `inversions` (default root, first, second)
- `stringSets` (default all four adjacent sets: 1-2-3, 2-3-4, 3-4-5, 4-5-6)
- `roots` (all 12)
- `maxFret` (15)

1. Generator (core): for (root, quality, inversion, set), assign the inversion's bottom→top tones to the set's strings low→high in close position. Choose the lowest fret position where every note is ≥ 0 and ≤ `maxFret` **and** the span is ≤ 4. Skip the combination if none exists. This works for any tuning; M3 uses standard.
2. **Key:** `triad:<quality>:<inversion>:<set>:<root>`. That is up to 4 × 3 × 4 × 12 = 576 cards: a large pool, as requested.
3. Prompt: "**C major**, 1st inversion, strings **3-2-1**". Answer: the board in a fret window around the shape, with dots labelled by degree (R/3/5) and the bass note emphasised, plus "E G C" and a 🔊 strum.
4. Pattern penalty: same string set ×0.5; same inversion ×0.6; same root ×0.5.

**Reference example:** C major 1st inversion on 3-2-1 → frets 9-8-8 (E G C); G major root position on 4-3-2 → 5-4-3.

### M3-5 — Arpeggios (generated)
**Deck:** `music.arpeggios`, kind `.arpeggios`. **New options case** `.arpeggios(ArpeggioOptions)`:
- `qualities` (default maj, min, dom7, maj7, min7, m7b5)
- `rootStrings` (6, 5)
- `roots` (all 12)
- `span` (`.oneOctave`, `.twoOctaves`; default two)
- `maxFret` (15)

1. Generator: from the root on `rootString` at the lowest valid fret (≥ 1, or 0 for an open root), collect chord tones ascending within a box of the root fret −1…+4, moving to higher strings, until the span is reached. Use the existing `Fretboard.positions` and chord pitch classes.
2. **Key:** `arp:<quality>:s<rootString>:<root>` (~144 cards).
3. Prompt: "**A m7** arpeggio · root on string 6 · 2 octaves". Answer: the windowed board with every arpeggio note (degree labels), fingering-order numbers as small secondary labels, and a 🔊 ascending sequence.

### M3-6 — Scales & modes (generated positions)
**Deck:** `music.scales`, kind `.scales`, group "Scales". **New options case** `.scales(ScaleOptions)`:
- `types` (default: major, naturalMinor, majorPentatonic, minorPentatonic, blues, and all 7 modes)
- `systems` (`.box` for pentatonic/blues: 5 positions; `.threeNPS` for heptatonic: 7 positions)
- `tonics` (all 12 per §3.1 spelling)
- `maxFret` (17)

1. Generators (core):
   - **Pentatonic/blues boxes:** position *n* starts on the *n*-th scale degree on string 6, with 2 notes per string (blues adds the ♭5 where it falls inside the box).
   - **3NPS:** position *n* starts on degree *n* on string 6, with 3 consecutive scale notes per string ascending.
   - Both shift +12 if the start fret < 0, and skip the position if any note exceeds `maxFret`.
2. **Key:** `scale:<type>:<system>:p<position>:<tonic>`. That is roughly (7 heptatonic types × 7 positions + 3 × 5) × 12 ≈ 750 cards: a large pool. Introduction gating ranks pentatonic first, then major/minor, then modes, through `introductionRank`, so day one isn't 750 random cards.
3. Prompt: "**A minor pentatonic** · box 1" / "**D dorian** · 3NPS position 2". Answer: the windowed board with all notes, the roots as `.answer`, degree labels per setting, the scale notes as text, and a 🔊 ascending/descending sequence.
4. Pattern penalty: same type ×0.4; same tonic ×0.5; same position ×0.6.

**Reference examples:** A minor pentatonic box 1 → frets 5-8 on every string (5/8, 5/7, 5/7, 5/7, 5/8, 5/8, strings 6 → 1); G major 3NPS position 1 → string 6 frets 3-5-7.

### M3-7 — Key signatures deck
**Deck:** `music.theory.keysig`, kind `.keySignatures`, group "Theory". **New options case** `.keySignatures(KeySigOptions)`: `modes` (major, minor; default both), `directions` (`keyToSig`, `sigToKey`; default both).

1. Cards: 15 keys × 2 modes × 2 directions = 60. **Key:** `keysig:<tonic>:<mode>:<direction>`.
2. `keyToSig` prompt: "**E major**: how many sharps or flats?" → answer: the `StaffView` with 4♯ plus "F♯ C♯ G♯ D♯".
3. `sigToKey` prompt: the `StaffView` showing the signature, with "Which **major** key?" (or minor) → answer: "E major" (relative: C♯ minor).
4. Pattern penalty: the same signature count back-to-back ×0.5.

### M3-8 — Diatonic chords & Roman numerals
**Deck:** `music.theory.diatonic`, kind `.diatonic`. **New options case** `.diatonic(DiatonicOptions)`:
- `modes` (major default; minor optional, with harmonic V)
- `chordSize` (`.triads` default, `.sevenths`, `.both`)
- `directions` (`degreeToChord`, `chordToDegree`; default both)
- `keys` (all 15 majors and/or their relative minors)

1. **Key:** `diatonic:<tonic>:<mode>:<size>:<degree>:<direction>`. With defaults: 15 × 7 × 2 = 210 cards; with sevenths and minor: ~840.
2. Prompts: "**iii** in **G major**?" → "**Bm** (B D F♯)", and "**Bm** in **G major** is…?" → "**iii**". The answer also shows the whole key's chord row, with the asked degree highlighted.
3. Pattern penalty: same key ×0.5; same degree ×0.5.

### M3-9 — Progressions deck
**Deck:** `music.progressions`, kind `.progressions`, group "Chords & shapes". **New options case** `.progressions(ProgressionOptions)`: `progressions` (all from M3-1), `keys` (all 15 majors + their minors, used per the progression's mode), `voicingStyle` (`.open` preferred where available, falling back to barre; `.barre`; `.caged` nearest-position).

1. **Key:** `prog:<progressionId>:<tonic>` (~165 cards).
2. Prompt: "Play **ii–V–I** in **G**" (the Roman numerals are shown, not the chord names).
3. Answer:
   - chord names in sequence (Am7 → D7 → Gmaj7)
   - a row of small `ChordDiagramView`s chosen by `voicingStyle`
   - a **nearest-position** rule for `.caged`: each next voicing minimises the fret distance to the previous one
   - 🔊 plays the progression (one strum per chord on the beat; blues = 12 bars at a brisk tempo, or the first 4 bars only, as a setting)
4. Pattern penalty: same progression ×0.4; same key ×0.5.

### M3-10 — Circle of fifths deck
**Deck:** `music.theory.circle`, kind `.circleOfFifths`, group "Theory". **New options case** `.circle(CircleOptions)`: `questions` (`fifthAbove`, `fourthAbove`, `relativeMinor`, `relativeMajor`; default all).

1. Cards: 12 positions × 4 questions = 48 (with §3.1 spellings, the enharmonic positions use the circle spelling shown in M3-1). **Key:** `cof:<question>:<tonic>`.
2. Prompt: "Fifth above **D**?". Answer: "**A**", plus the `CircleOfFifthsView` with D highlighted and A as secondary, and the rule ("clockwise = up a fifth").

### M3-11 — Integration and docs
1. `BuiltInDecks`: a row per new deck (defaults per segment) and the `musicDecks` list with groups.
2. `DeckUI` providers: one file per kind under `App/Sources/DeckUI/`. No shared-view switches (the M2-0b rule).
3. `PersistedFormatCheck`: a fixture per new `DeckOptions` case (the existing launch format guard).
4. PLAN.md:
   - §6.1: the M3 key schemes and "shape ids are frozen"
   - §7: the theory additions
   - §11: the chord diagram, staff, circle and Home groups
   - §15: M3 link
   - §17: tracker and decision log
5. README: the manual QA checklist adds the diagram orientation (left-handed), playback of strums, scales and progressions, and Home groups.

---

## 5. Tracker

| Segment | Status | Notes |
|---|---|---|
| M3-0 Shared UI + playback helpers | ☐ | fret window, chord box, staff, circle, Home groups |
| M3-1 Theory core | ☐ | chords, scales, keys, progressions |
| M3-2 Shape library + validator | ☐ | ≥ 60 shapes, verification table |
| M3-3 Play / Name the Chord | ☐ | ~400 cards each |
| M3-4 Triads on string sets | ☐ | up to 576 cards |
| M3-5 Arpeggios | ☐ | ~144 cards |
| M3-6 Scales & modes | ☐ | ~750 cards, gated introduction |
| M3-7 Key signatures | ☐ | 60 cards |
| M3-8 Diatonic chords | ☐ | 210–840 cards |
| M3-9 Progressions | ☐ | ~165 cards |
| M3-10 Circle of fifths | ☐ | 48 cards |
| M3-11 Integration & docs | ☐ | |

## 6. Key and format rules introduced by M3

| Deck | ItemKey scheme |
|---|---|
| Play the Chord | `chord:<shapeId>` (open) · `chord:<shapeId>:<root>` (movable) |
| Name the Chord | `chordname:<shapeId>[:<root>]` |
| Triads | `triad:<quality>:<inversion>:<set>:<root>` |
| Arpeggios | `arp:<quality>:s<rootString>:<root>` |
| Scales | `scale:<type>:<system>:p<n>:<tonic>` |
| Key signatures | `keysig:<tonic>:<mode>:<direction>` |
| Diatonic | `diatonic:<tonic>:<mode>:<size>:<degree>:<direction>` |
| Progressions | `prog:<progressionId>:<tonic>` |
| Circle | `cof:<question>:<tonic>` |

Frozen identifiers: shape ids, `ChordQuality`, `ScaleType`, `Progression` ids, question/direction raw values, and root/tonic spellings (ASCII: `Bb`, `F#`). New persisted `DeckOptions` cases: `chords`, `triads`, `arpeggios`, `scales`, `keySignatures`, `diatonic`, `progressions`, `circle`.

## 7. Decisions and open questions
- **ASSUMPTION:** M3 is standard tuning only (§0). Other tunings would need tuning-specific shape data.
- **ASSUMPTION:** the root is part of the identity for movable shapes and generated positions (§3.2), which gives the large pools the owner asked for. Stats are per root.
- **ASSUMPTION:** no microphone answers for chords or scales in M3. Polyphonic chord detection (chroma matching) is a candidate for a later milestone.
- **ASSUMPTION:** the 𝄞 glyph renders with the system fonts; there is a text fallback.
- **OPEN (owner):** are any chord families or scale types unwanted (e.g. the modes, dim7/aug), or is "all on by default" right?
