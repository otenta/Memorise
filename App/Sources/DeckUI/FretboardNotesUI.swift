import MemoriseCore
import SwiftUI

/// "Play {note} on string {n}" — `music.fretboard.notes`.
struct FretboardNotesUI: DeckUI {
    private static let deck = FretboardNotesDeck()

    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.fretboardNote else { return AnyView(EmptyView()) }
        return AnyView(FretboardNotePromptView(prompt: p, settings: ctx.settings))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.fretboardNote else { return AnyView(EmptyView()) }
        let maxFret = ctx.options.fretboard?.fretRange.upperBound ?? 12
        return AnyView(FretboardNoteAnswerView(prompt: p, maxFret: maxFret, settings: ctx.settings, notes: playableNotes(card)))
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.fretboardNote else { return card.key.raw }
        return "\(NoteFormatter.format(p.spelling, settings: settings.musicDisplay)) · string \(p.stringNumber)" + tuningSuffix(p.tuning)
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(FretboardOptionsSection(options: options.fretboardOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(FretboardTunedStats(deck: deck, title: "Fretboard heatmap") { tuning, settings in
            HeatmapGrid.notes(stats: stats, tuning: tuning, highEOnTop: settings.highEOnTop)
        })
    }

    var supportsMicAnswer: Bool { true }

    /// Correct pitch class anywhere in the guitar's range (R7-F3). The string can't be told from
    /// the pitch, and YIN octave errors on low strings used to reject correctly played notes.
    func micAccepts(_ card: Card, midi: Int) -> Bool {
        guard let p = card.fretboardNote else { return false }
        return PitchClass(midi) == p.pitchClass && micRange(.preset(p.tuning)).contains(midi)
    }

    /// The lowest answer fret.
    func playableNotes(_ card: Card) -> [NoteEvent] {
        guard let p = card.fretboardNote, let f = p.answerFrets.first else { return [] }
        return [(Fretboard.midi(string: p.stringNumber, fret: f, tuning: .preset(p.tuning)), 0)]
    }
}

/// Pitches a guitar in `tuning` can produce: the lowest open string to string 1 at fret 24.
func micRange(_ tuning: Tuning) -> ClosedRange<Int> {
    (tuning.openMidi.min() ?? 40)...(tuning.openMidi(string: 1) + 24)
}

/// " · Drop D" for non-standard tunings.
func tuningSuffix(_ t: TuningID) -> String { t == .standard ? "" : " · \(Tuning.preset(t).name)" }

extension Binding where Value == DeckOptions {
    /// Typed binding to the fretboard payload (setters keep the case).
    var fretboardOptions: Binding<FretboardOptions> {
        Binding<FretboardOptions>(
            get: { wrappedValue.fretboard ?? FretboardOptions() },
            set: { wrappedValue = .fretboard($0) }
        )
    }

    var intervalOptions: Binding<IntervalOptions> {
        Binding<IntervalOptions>(
            get: { wrappedValue.intervals ?? IntervalOptions() },
            set: { wrappedValue = .intervals($0) }
        )
    }

    var earIntervalOptions: Binding<EarIntervalOptions> {
        Binding<EarIntervalOptions>(
            get: { wrappedValue.earIntervals ?? EarIntervalOptions() },
            set: { wrappedValue = .earIntervals($0) }
        )
    }

    var vocabOptions: Binding<VocabOptions> {
        Binding<VocabOptions>(
            get: { wrappedValue.vocab ?? VocabOptions() },
            set: { wrappedValue = .vocab($0) }
        )
    }
}

/// Stats wrapper defaulting to the deck's last-used tuning.
struct FretboardTunedStats<Content: View>: View {
    let deck: any Deck
    let title: String
    @ViewBuilder let content: (Tuning, AppSettings) -> Content
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        TunedStatsSection(title: title, initialTuning: env.initialConfig(for: deck).options.tuning ?? .standard) { tuning in
            content(tuning, env.settings)
        }
    }
}

// MARK: - Views

struct FretboardNotePromptView: View {
    let prompt: FretboardNotePrompt
    let settings: AppSettings
    private static let deck = FretboardNotesDeck()

    var body: some View {
        let display = settings.musicDisplay
        VStack(spacing: 12) {
            Text("PLAY").font(.caption.weight(.heavy)).tracking(3).foregroundStyle(.secondary)
            Text(Self.deck.noteText(prompt, settings: display))
                .font(.system(size: 88, weight: .heavy, design: .rounded))
                .foregroundStyle(Subject.music.gradient)
                .shadow(color: Theme.violet.opacity(0.3), radius: 12, y: 6)
                .lineLimit(1).minimumScaleFactor(0.4)
            Text("on \(Self.deck.stringText(prompt, settings: display))")
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
            if prompt.tuning != .standard {
                TuningBadge(tuning: prompt.tuning)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.deck.promptText(prompt, settings: display))
    }
}

struct FretboardNoteAnswerView: View {
    let prompt: FretboardNotePrompt
    let maxFret: Int
    let settings: AppSettings
    let notes: [NoteEvent]

    var body: some View {
        let name = prompt.spelling.displayName
        let tuning = Tuning.preset(prompt.tuning)
        FretboardAnswerLayout {
            Text(NoteFormatter.format(prompt.spelling, settings: settings.musicDisplay))
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(Subject.music.gradient)
                .shadow(color: Theme.violet.opacity(0.25), radius: 8, y: 4)
            PlayNotesButton(notes: notes)
        } board: {
            settings.answerBoard(
                neckMax: max(maxFret, prompt.answerFrets.max() ?? 0), tuning: tuning, focus: prompt.answerFrets,
                marks: prompt.answerFrets.map { FretMark(string: prompt.stringNumber, fret: $0, label: name) },
                highlight: [prompt.stringNumber],
                caption: FretboardNotesDeck.answerText(frets: prompt.answerFrets)
            )
        }
    }
}

/// Small "Drop D" capsule.
struct TuningBadge: View {
    let tuning: TuningID

    var body: some View {
        Label(Tuning.preset(tuning).name, systemImage: "tuningfork")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.primary.opacity(0.06), in: Capsule())
    }
}

#Preview("Fretboard prompt") {
    let p = FretboardNotePrompt(stringNumber: 6, pitchClass: PitchClass(9), spelling: NoteSpelling(.a), answerFrets: [5])
    return FretboardNotePromptView(prompt: p, settings: AppSettings()).padding()
}

#Preview("Fretboard answer, landscape", traits: .landscapeLeft) {
    let p = FretboardNotePrompt(stringNumber: 6, pitchClass: PitchClass(9), spelling: NoteSpelling(.a), answerFrets: [5, 17])
    return FretboardNoteAnswerView(prompt: p, maxFret: 22, settings: AppSettings(), notes: [(45, 0)])
        .padding()
        .environment(AppEnvironment.preview())
}

#Preview("Fretboard answer") {
    let p = FretboardNotePrompt(stringNumber: 6, pitchClass: PitchClass(9), spelling: NoteSpelling(.a), answerFrets: [5, 17])
    return FretboardNoteAnswerView(prompt: p, maxFret: 22, settings: AppSettings(), notes: [(45, 0)])
        .padding()
        .environment(AppEnvironment.preview())
}
