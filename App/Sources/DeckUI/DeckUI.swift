import MemoriseCore
import SwiftUI

/// Everything a deck UI provider may need while rendering a card.
@MainActor
struct DeckUIContext {
    let env: AppEnvironment
    let deck: any Deck
    let options: DeckOptions
    /// Changes every time a card is (re-)presented.
    var presentationID = 0
    /// For providers that manage prompt timing themselves (e.g. ear training).
    var promptDidAppear: @MainActor () -> Void = {}
    /// Shown once when Korean TTS is unavailable.
    var requestVoiceHint: @MainActor () -> Void = {}
    /// Pauses the session timer (same path as ✕), e.g. while the "My snippet" sheet is open (M5 K4).
    var pauseSession: @MainActor () -> Void = {}
    /// Resumes after `pauseSession`.
    var resumeSession: @MainActor () -> Void = {}

    var settings: AppSettings { env.settings }
}

/// A note to play: MIDI number and start offset in seconds.
typealias NoteEvent = (midi: Int, delay: Double)

/// One tappable option in `choice` mode.
struct AnswerChoice: Hashable, Identifiable {
    var id: String { label }
    let label: String
    let isCorrect: Bool
}

/// Per-deck-kind UI. Adding a deck kind = one provider file + one registry line.
@MainActor
protocol DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView
    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView
    /// One-line label for summary / history rows.
    func label(_ card: Card, settings: AppSettings) -> String
    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView
    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView?
    /// Cleans stale saved options (e.g. tags the deck no longer has).
    func sanitize(_ options: DeckOptions, deck: any Deck) -> DeckOptions
    /// Called right after the answer is revealed.
    func onReveal(_ card: Card, ctx: DeckUIContext)
    /// When true, the prompt view calls `ctx.promptDidAppear()` itself.
    func managesPromptTiming(_ card: Card) -> Bool
    /// Whether "Answer by playing (microphone)" is offered.
    var supportsMicAnswer: Bool { get }
    /// Answer modes offered in Setup (the first is the default). Setup shows "Answer by" when > 1.
    func supportedInputModes(deck: any Deck) -> [InputMode]
    /// Expected answers for `typed` mode (`nil` = this card can't be typed; it falls back to touch).
    func typedAnswer(for card: Card) -> TypedAnswerSpec?
    /// Options for `choice` mode, computed once per presentation (`nil` = no choices; falls back to touch).
    func choices(for card: Card, options: DeckOptions, using rng: inout SplitMix64) -> [AnswerChoice]?
    /// Whether a stable detected pitch answers the card correctly.
    func micAccepts(_ card: Card, midi: Int) -> Bool
    /// Notes for the 🔊 button / "play note on reveal".
    func playableNotes(_ card: Card) -> [NoteEvent]
}

extension DeckUI {
    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? { nil }
    func sanitize(_ options: DeckOptions, deck: any Deck) -> DeckOptions { options }
    func managesPromptTiming(_ card: Card) -> Bool { false }
    var supportsMicAnswer: Bool { false }
    func supportedInputModes(deck: any Deck) -> [InputMode] { supportsMicAnswer ? [.touch, .microphone] : [.touch] }
    func typedAnswer(for card: Card) -> TypedAnswerSpec? { nil }
    func choices(for card: Card, options: DeckOptions, using rng: inout SplitMix64) -> [AnswerChoice]? { nil }
    func micAccepts(_ card: Card, midi: Int) -> Bool { false }
    func playableNotes(_ card: Card) -> [NoteEvent] { [] }

    /// Default: plays the card's notes when "Play note on reveal" is on.
    func onReveal(_ card: Card, ctx: DeckUIContext) {
        guard ctx.settings.playNoteOnReveal else { return }
        let notes = playableNotes(card)
        if !notes.isEmpty { ctx.env.notePlayer.play(notes) }
    }
}

/// Maps deck kinds to providers.
@MainActor
struct DeckUIRegistry {
    private let providers: [DeckKind: any DeckUI]

    init(_ providers: [DeckKind: any DeckUI]) { self.providers = providers }

    static let builtIn = DeckUIRegistry([
        .fretboardNotes: FretboardNotesUI(),
        .vocab: VocabUI(),
        .fretboardNames: FretboardNamesUI(),
        .fretboardFindAll: FindAllUI(),
        .fretboardIntervals: IntervalsUI(),
        .earIntervals: EarIntervalsUI(),
        .chordsPlay: ChordsUI(naming: false),
        .chordsName: ChordsUI(naming: true),
        .triads: TriadsUI(),
        .arpeggios: ArpeggiosUI(),
        .scales: ScalesUI(),
        .keySignatures: KeySignaturesUI(),
        .diatonic: DiatonicUI(),
        .progressions: ProgressionsUI(),
        .circleOfFifths: CircleOfFifthsUI(),
        .hangulReading: HangulReadingUI(),
        .koreanParticles: ParticlesUI(),
        .koreanConjugation: ConjugationUI(),
    ])

    func ui(for deck: any Deck) -> any DeckUI {
        if let p = providers[deck.kind] { return p }
        assertionFailure("No DeckUI for kind \(deck.kind.rawValue)")
        return PlainTextUI()
    }
}

/// Fallback provider: shows the item key.
struct PlainTextUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView { AnyView(Text(card.key.raw).font(.title)) }
    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView { AnyView(Text(card.key.raw).font(.title2)) }
    func label(_ card: Card, settings: AppSettings) -> String { card.key.raw }
    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView { AnyView(EmptyView()) }
    func onReveal(_ card: Card, ctx: DeckUIContext) {}
}

// MARK: - Shared dispatch views

/// Prompt side of any card.
struct CardPromptView: View {
    let card: Card
    let ctx: DeckUIContext

    var body: some View { ctx.env.deckUI(for: ctx.deck).prompt(card, ctx: ctx) }
}

/// Answer side of any card.
struct CardAnswerView: View {
    let card: Card
    let ctx: DeckUIContext

    var body: some View { ctx.env.deckUI(for: ctx.deck).answer(card, ctx: ctx) }
}

/// 🔊 button that plays notes with the plucked-string synth.
struct PlayNotesButton: View {
    let notes: [NoteEvent]
    var label = "Play note"
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button {
            env.notePlayer.play(notes)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Subject.music.gradient, in: Circle())
                .shadow(color: Theme.violet.opacity(0.35), radius: 6, y: 3)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityLabel(label)
        .accessibilityIdentifier("playNoteButton")
    }
}
