import MemoriseCore
import SwiftUI

/// "Which note?" — `music.fretboard.names`.
struct FretboardNamesUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.fretboardPosition else { return AnyView(EmptyView()) }
        let maxFret = ctx.options.fretboard?.fretRange.upperBound ?? 12
        return AnyView(NamePromptView(prompt: p, maxFret: maxFret, settings: ctx.settings))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.fretboardPosition else { return AnyView(EmptyView()) }
        let maxFret = ctx.options.fretboard?.fretRange.upperBound ?? 12
        return AnyView(NameAnswerView(prompt: p, maxFret: maxFret, settings: ctx.settings, notes: playableNotes(card)))
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.fretboardPosition else { return card.key.raw }
        return "s\(p.position.string) f\(p.position.fret) → \(NoteFormatter.format(p.spelling, settings: settings.musicDisplay))" + tuningSuffix(p.tuning)
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(FretboardOptionsSection(options: options.fretboardOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(NamesStats(deck: deck, stats: stats))
    }

    func playableNotes(_ card: Card) -> [NoteEvent] {
        guard let p = card.fretboardPosition else { return [] }
        return [(p.midi, 0)]
    }
}

private struct NamesStats: View {
    let deck: any Deck
    let stats: [ItemKey: ItemStats]
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let frets = env.initialConfig(for: deck).options.fretboard?.fretRange ?? 0...12
        FretboardTunedStats(deck: deck, title: "Position heatmap") { tuning, settings in
            HeatmapGrid.positions(stats: stats, tuning: tuning, frets: frets, highEOnTop: settings.highEOnTop)
        }
    }
}

struct NamePromptView: View {
    let prompt: FretboardPositionPrompt
    let maxFret: Int
    let settings: AppSettings

    var body: some View {
        let tuning = Tuning.preset(prompt.tuning)
        VStack(spacing: 16) {
            Text("WHICH NOTE?").font(.caption.weight(.heavy)).tracking(3).foregroundStyle(.secondary)
            settings.board(
                maxFret: max(maxFret, prompt.position.fret), tuning: tuning,
                marks: [FretMark(string: prompt.position.string, fret: prompt.position.fret)],
                highlight: [prompt.position.string]
            )
            if prompt.tuning != .standard { TuningBadge(tuning: prompt.tuning) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Which note is on string \(prompt.position.string), \(prompt.position.fret == 0 ? "open" : "fret \(prompt.position.fret)")?")
    }
}

struct NameAnswerView: View {
    let prompt: FretboardPositionPrompt
    let maxFret: Int
    let settings: AppSettings
    let notes: [NoteEvent]

    var body: some View {
        let tuning = Tuning.preset(prompt.tuning)
        let pos = prompt.position
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Text(NoteFormatter.format(prompt.spelling, settings: settings.musicDisplay))
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(Subject.music.gradient)
                    .lineLimit(1).minimumScaleFactor(0.5)
                PlayNotesButton(notes: notes)
            }
            settings.board(
                maxFret: max(maxFret, pos.fret), tuning: tuning,
                marks: [FretMark(string: pos.string, fret: pos.fret, label: prompt.spelling.displayName)],
                highlight: [pos.string]
            )
            Text("String \(pos.string) (\(tuning.stringName(pos.string))), \(pos.fret == 0 ? "open" : "fret \(pos.fret)")")
                .font(.title3.weight(.semibold).monospacedDigit())
        }
    }
}

#Preview("Name the note") {
    let p = FretboardPositionPrompt(position: FretPosition(string: 5, fret: 3), pitchClass: PitchClass(0), spelling: NoteSpelling(.c), tuning: .standard)
    return VStack(spacing: 30) {
        NamePromptView(prompt: p, maxFret: 12, settings: AppSettings())
        NameAnswerView(prompt: p, maxFret: 12, settings: AppSettings(), notes: [(48, 0)])
    }
    .padding()
    .environment(AppEnvironment.preview())
}
