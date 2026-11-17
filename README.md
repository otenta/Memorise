# Memorise

Personal, offline iOS flashcard app for **guitar fretboard notes, harmony and theory** and **Korean** (vocabulary, Hangul reading, particles, conjugation, your own decks), with timed
responses and an adaptive scheduler that shows your slowest / most-missed cards more often.

See [PLAN.md](PLAN.md) for the full design.

## Layout
- `Packages/MemoriseCore` — all domain logic (Foundation only): decks, music theory, scheduler, session engine, stats, persistence protocol, bundled Korean deck JSON.
- `App/` — SwiftUI app: SwiftData store, screens, fretboard renderer, TTS, haptics.
- `project.yml` — XcodeGen spec (the `.xcodeproj` is generated, not committed).

## Build & run on your iPhone
1. Install Xcode and XcodeGen: `brew install xcodegen`.
2. `xcodegen generate && open Memorise.xcodeproj`.
3. Set your bundle id / Team in `project.yml` (or *Signing & Capabilities*).
4. Enable Developer Mode on the phone, select it, Run.
   - Free Apple ID: the app expires after 7 days; re-run from Xcode to refresh (data is kept).
   - Paid program: 1-year provisioning + TestFlight.

Core only: `cd Packages/MemoriseCore && swift build`.

## Hardware keyboard / page-turner pedal
- Prompt: Space, Return, →, ↓, Page Down = OK · Esc = pause
- Reveal: →, Page Down, Return = Correct · ←, Page Up, Backspace = Wrong

## Microphone
Mic answers (Fretboard Notes, Intervals) need microphone permission; the app asks the first time you enable "Answer by playing". If denied, sessions fall back to touch. Change it in *Settings → Privacy & Security → Microphone → Memorise*.

## Manual QA checklist
- [ ] Response time feels accurate (prompt → OK)
- [ ] Background the app mid-card → card re-shown with a fresh timer after resume
- [ ] Pedal / keyboard keys work in prompt and reveal
- [ ] Korean TTS plays (install a Korean voice if prompted)
- [ ] Export shares JSON + CSV; reset clears stats after confirmation
- [ ] Dark mode, landscape, largest Dynamic Type on prompt screens
- [ ] M2 tunings: a Drop D session shows "6 · D" chips and "low D"; E on string 6 → frets 2 and 14; its stats only appear under the Drop D heatmap; M1 history still reads as Standard
- [ ] M2 synth: string 6 fret 5 plays A2 = 110 Hz (check with a tuner); no clicks; background music keeps playing; plays with the silent switch on
- [ ] M2 ear: the on-screen timer starts at the second note; Replay doesn't reset it; descending and harmonic sound right
- [ ] M2 mic: 20 Notes cards played → ≥ 18 auto-graded; wrong notes never auto-grade; time within 100 ms of a stopwatch; no false triggers in 2 min of silence; denying permission falls back to touch
- [ ] M3 Home: music decks show Fretboard / Ear / Chords & shapes / Scales / Theory sub-headers
- [ ] M3 chord diagrams: open C = x-3-2-0-1-0, F barre has a barre bar, Bm7 shows "2fr"; left-handed mirrors the box; 20 random cards match their symbol
- [ ] M3 playback: chord 🔊 strums low → high; scales/arpeggios go up and back down; ii–V–I plays 3 strums on the beat; blues plays 12 bars (or 4 with the option)
- [ ] M3 fretboard windows: A minor pentatonic box 1 shows frets 5–8 with no nut; Dot labels = Degrees shows R/♭3/5
- [ ] M3 theory: E major → 4♯ on the staff (F♯ C♯ G♯ D♯); iii in G = Bm; fifth above F♯ shows D♭ (= C♯)
- [ ] M4 Home: Korean shows Hangul Reading, Core 1…, Particles, Conjugation, AION 2; "My decks" follows with "+ New deck" and "AION 2 words from a screenshot"
- [ ] M4 typed (Korean keyboard): with no Korean keyboard enabled, an en→ko card shows the "Add the Korean keyboard" hint; once it's added, the keyboard stays up between cards; Return submits; 학교/핵교 → Close, 사과/사람 → Wrong; "I was right" changes the stored grade; one item's median time is unchanged after a typed session; pedal keys don't reveal while typing
- [ ] M4 choice: Particles shows 책은 / 책는; 물 + direction → 물로; an exact answer auto-advances after 0.8 s (toggle off in Settings → Session)
- [ ] M4 listening timer: the on-screen timer starts when the speech ends, and Replay doesn't reset it; with no Korean voice, the Listening option is disabled; listen items show 🔊 in Weakest words
- [ ] M4 Patterns: `-(으)ㄹ 수 있다` reveal shows 3 examples, each with 🔊; en→ko typed shows the English sentence and accepts the Korean one; auto-play speaks the first example, not the symbols
- [ ] M4 Hangul Reading / Conjugation: 꿈 → kkum, 의 → ui; 가다 · past polite → 갔어요, 듣다 → 들어요, 살다 · formal → 삽니다
- [ ] M4 custom deck editing: create a deck, add 3 words (one with no romanization), practise it; delete a word and add another, and the new id isn't a reused number; delete the deck → it disappears and its stats reset; the full export contains `userDecks`
- [ ] M4 OCR: a real Korean AION 2 screenshot gives a plausible word list; particles are stripped (몬스터를 → 몬스터, but 집으로 stays whole); known words are counted under "Already known"; words saved with typed meanings become cards in "My AION words"; there is no photo-library permission prompt (picker only)
