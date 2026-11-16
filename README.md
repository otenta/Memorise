# Memorise

Personal, offline iOS flashcard app for **guitar fretboard notes** and **Korean vocabulary**, with timed
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

## Manual QA checklist
- [ ] Response time feels accurate (prompt → OK)
- [ ] Background the app mid-card → card re-shown with a fresh timer after resume
- [ ] Pedal / keyboard keys work in prompt and reveal
- [ ] Korean TTS plays (install a Korean voice if prompted)
- [ ] Export shares JSON + CSV; reset clears stats after confirmation
- [ ] Dark mode, landscape, largest Dynamic Type on prompt screens
