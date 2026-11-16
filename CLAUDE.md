# Memorise — agent conventions

Read `PLAN.md` first (§16 summarised here).
- All domain logic lives in `Packages/MemoriseCore`, which imports only Foundation.
- Inject randomness (`SplitMix64`) and clocks (`MonotonicClock`); no `Date()`/`.random()` in core logic paths except via injected defaults.
- Persisted `Codable` types use hand-written tolerant `init(from:)`; every new property needs a default; never rename coding keys or enum raw values.
- `DeckOptions` and `SessionLength` have a frozen, hand-written wire format. New cases are fine; renaming cases or changing payload types needs a legacy decode path plus an update to `PersistedFormatCheck`.
- Never change or reuse an `ItemKey` or Korean entry `id`. Deck JSON in `Resources/Decks` is the source of truth.
- Scheduling constants live in `SchedulerConstants`; update PLAN §9.4/§10 if tuned.
- SwiftUI: `@Observable` view models, `NavigationStack`, a `#Preview` per view, accessibility identifiers on interactive controls.
- Never hand-edit the `.xcodeproj`; edit `project.yml` and run `xcodegen generate`.
- Record plan deviations in PLAN.md §17 Decision log.
