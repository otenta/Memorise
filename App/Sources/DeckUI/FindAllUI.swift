import MemoriseCore
import SwiftUI

/// "Find every A" — `music.fretboard.findall`.
struct FindAllUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.findAll else { return AnyView(EmptyView()) }
        return AnyView(FindAllPromptView(prompt: p, settings: ctx.settings))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.findAll else { return AnyView(EmptyView()) }
        return AnyView(FindAllAnswerView(prompt: p, settings: ctx.settings, notes: playableNotes(card)))
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.findAll else { return card.key.raw }
        return "All \(NoteFormatter.format(p.spelling, settings: settings.musicDisplay))" + tuningSuffix(p.tuning)
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(FretboardOptionsSection(options: options.fretboardOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(FretboardTunedStats(deck: deck, title: "Notes") { tuning, _ in
            ItemStatsList(
                title: "Slowest first",
                items: PitchClass.allCases.map { pc in
                    .init(key: FindAllDeck.itemKey(pc, tuning: tuning.id),
                          label: NoteSpelling.preferred(for: pc, preferFlat: false).displayName)
                },
                stats: stats
            )
        })
    }

    /// Every position low → high as an arpeggio.
    func playableNotes(_ card: Card) -> [NoteEvent] {
        guard let p = card.findAll else { return [] }
        let tuning = Tuning.preset(p.tuning)
        let pitches = Set(p.positions.map { Fretboard.midi(string: $0.string, fret: $0.fret, tuning: tuning) }).sorted()
        return pitches.enumerated().map { ($1, Double($0) * 0.35) }
    }
}

struct FindAllPromptView: View {
    let prompt: FindAllPrompt
    let settings: AppSettings

    var body: some View {
        VStack(spacing: 12) {
            Text("FIND EVERY").font(.caption.weight(.heavy)).tracking(3).foregroundStyle(.secondary)
            Text(NoteFormatter.format(prompt.spelling, settings: settings.musicDisplay))
                .font(.system(size: 88, weight: .heavy, design: .rounded))
                .foregroundStyle(Subject.music.gradient)
                .shadow(color: Theme.violet.opacity(0.3), radius: 12, y: 6)
                .lineLimit(1).minimumScaleFactor(0.4)
            Text("strings \(FretboardText.strings(prompt.strings)) · \(FretboardText.frets(prompt.fretRange))")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            if prompt.tuning != .standard { TuningBadge(tuning: prompt.tuning) }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FindAllAnswerView: View {
    let prompt: FindAllPrompt
    let settings: AppSettings
    let notes: [NoteEvent]

    var body: some View {
        let tuning = Tuning.preset(prompt.tuning)
        let marks = prompt.positions.map { pos in
            FretMark(string: pos.string, fret: pos.fret,
                     label: Pitch(midi: Fretboard.midi(string: pos.string, fret: pos.fret, tuning: tuning)).name(spelling: prompt.spelling))
        }
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Text(NoteFormatter.format(prompt.spelling, settings: settings.musicDisplay))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Subject.music.gradient)
                PlayNotesButton(notes: notes, label: "Play all positions")
            }
            settings.board(maxFret: prompt.fretRange.upperBound, tuning: tuning, marks: marks, highlight: Set(prompt.strings))
            Text("\(prompt.positions.count) position\(prompt.positions.count == 1 ? "" : "s")")
                .font(.title3.weight(.semibold).monospacedDigit())
        }
    }
}
