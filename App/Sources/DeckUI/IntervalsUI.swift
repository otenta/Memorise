import MemoriseCore
import SwiftUI

/// "Play a major 3rd above C" — `music.fretboard.intervals`.
struct IntervalsUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.interval else { return AnyView(EmptyView()) }
        return AnyView(IntervalPromptView(prompt: p, settings: ctx.settings, maxFret: boardMax(p, ctx)))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.interval else { return AnyView(EmptyView()) }
        return AnyView(IntervalAnswerView(prompt: p, settings: ctx.settings, maxFret: boardMax(p, ctx), notes: playableNotes(card)))
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.interval else { return card.key.raw }
        return "\(p.interval.shortName) above \(NoteFormatter.format(p.rootSpelling, settings: settings.musicDisplay)) · s\(p.root.string)" + tuningSuffix(p.tuning)
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(IntervalOptionsSection(options: options.intervalOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(FretboardTunedStats(deck: deck, title: "Intervals") { tuning, _ in
            ItemStatsList(
                title: "Weakest first",
                items: Interval.allCases.flatMap { i in
                    tuning.stringNumbers.map { s in
                        ItemStatsList.Item(key: IntervalsDeck.itemKey(i, string: s, tuning: tuning.id), label: "\(i.shortName) · string \(s)")
                    }
                }.filter { stats[$0.key] != nil },
                stats: stats
            )
        })
    }

    var supportsMicAnswer: Bool { true }

    /// Target pitch class within one octave above the root.
    func micAccepts(_ card: Card, midi: Int) -> Bool {
        guard let p = card.interval else { return false }
        return PitchClass(midi) == p.targetSpelling.pitchClass && ((p.rootMidi + 1)...(p.rootMidi + 12)).contains(midi)
    }

    /// Root, then target.
    func playableNotes(_ card: Card) -> [NoteEvent] {
        guard let p = card.interval else { return [] }
        return [(p.rootMidi, 0), (p.targetMidi, 0.6)]
    }

    private func boardMax(_ p: IntervalPrompt, _ ctx: DeckUIContext) -> Int {
        let range = ctx.options.intervals?.fretRange.upperBound ?? 12
        return max(12, range, p.root.fret, p.targets.map(\.fret).max() ?? 0)
    }
}

struct IntervalPromptView: View {
    let prompt: IntervalPrompt
    let settings: AppSettings
    let maxFret: Int

    var body: some View {
        let root = NoteFormatter.format(prompt.rootSpelling, settings: settings.musicDisplay)
        VStack(spacing: 14) {
            (Text("Play a ") + Text(prompt.interval.longName).bold() + Text(" above"))
                .font(.title2)
                .multilineTextAlignment(.center)
            Text(root)
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .foregroundStyle(Subject.music.gradient)
                .lineLimit(1).minimumScaleFactor(0.4)
            settings.board(
                maxFret: maxFret, tuning: .preset(prompt.tuning),
                marks: [FretMark(string: prompt.root.string, fret: prompt.root.fret, label: prompt.rootSpelling.displayName, style: .secondary)],
                highlight: [prompt.root.string]
            )
            if prompt.tuning != .standard { TuningBadge(tuning: prompt.tuning) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Play a \(prompt.interval.longName) above \(root), from string \(prompt.root.string) fret \(prompt.root.fret)")
    }
}

struct IntervalAnswerView: View {
    let prompt: IntervalPrompt
    let settings: AppSettings
    let maxFret: Int
    let notes: [NoteEvent]

    var body: some View {
        let target = prompt.targetSpelling.displayName
        let marks = [FretMark(string: prompt.root.string, fret: prompt.root.fret, label: prompt.rootSpelling.displayName, style: .secondary)]
            + prompt.targets.map { t in
                FretMark(string: t.string, fret: t.fret, label: target, style: t == prompt.primary ? .answer : .muted)
            }
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Text(NoteFormatter.format(prompt.targetSpelling, settings: settings.musicDisplay))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Subject.music.gradient)
                PlayNotesButton(notes: notes, label: "Play interval")
            }
            settings.board(maxFret: maxFret, tuning: .preset(prompt.tuning), marks: marks,
                           highlight: Set(prompt.targets.map(\.string)))
            Text("\(prompt.interval.longName) = \(prompt.interval.semitones) semitone\(prompt.interval.semitones == 1 ? "" : "s")")
                .font(.title3.weight(.semibold))
        }
    }
}

struct IntervalOptionsSection: View {
    @Binding var options: IntervalOptions

    var body: some View {
        Section("Intervals") {
            IntervalChips(intervals: $options.intervals)
        }
        Section {
            TuningPicker(tuning: $options.tuning)
            StringChips(strings: $options.strings, tuning: .preset(options.tuning))
            MaxFretPicker(range: $options.fretRange, title: "Max root fret")
            AccidentalPicker(spelling: $options.accidentalSpelling)
        } header: {
            Text("Root note")
        } footer: {
            Text("The root is picked at random on the chosen strings, so every card has a new starting note.")
        }
    }
}
