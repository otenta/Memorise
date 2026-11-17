import MemoriseCore
import SwiftUI

/// "Play ii–V–I in G" — `music.progressions`.
struct ProgressionsUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.progression else { return AnyView(EmptyView()) }
        return AnyView(VStack(spacing: 12) {
            PromptCaption(text: "PLAY THE PROGRESSION")
            HeroText(text: p.progression.title, size: 52)
            (Text("in ") + Text(p.key.name).bold()).font(.title2)
            if p.progression == .blues12 {
                Text(p.progression.numeralsText).font(.footnote.monospaced()).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.progression else { return AnyView(EmptyView()) }
        return AnyView(ProgressionAnswerView(prompt: p, settings: ctx.settings, notes: playableNotes(card)))
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.progression else { return card.key.raw }
        return "\(p.progression.title) in \(p.key.name)"
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(ProgressionOptionsSection(options: options.progressionOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(CardStatsList(deck: deck, stats: stats) { label($0, settings: AppSettings.statsLabels) })
    }

    /// One strum per chord on the beat (brisker for the blues).
    func playableNotes(_ card: Card) -> [NoteEvent] {
        guard let p = card.progression else { return [] }
        let chords = zip(p.chords, p.voicings).prefix(p.playCount).map { c, v in v?.midis ?? chordMidis(c) }
        return NotePlayer.progressionEvents(Array(chords), beat: p.progression == .blues12 ? 0.6 : 0.9)
    }
}

struct ProgressionAnswerView: View {
    let prompt: ProgressionPrompt
    let settings: AppSettings
    let notes: [NoteEvent]

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(uniqueSymbols.joined(separator: " → "))
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Subject.music.gradient)
                    .lineLimit(2).minimumScaleFactor(0.5)
                PlayNotesButton(notes: notes, label: "Play progression")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(diagrams.enumerated()), id: \.offset) { _, item in
                        VStack(spacing: 4) {
                            Text(item.numeral).font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                            Text(item.chord.symbol).font(.subheadline.weight(.bold))
                            if let v = item.voicing {
                                ChordDiagramView(voicing: v, leftHanded: settings.leftHanded, compact: true).frame(width: 92)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    /// Chord names in order (the blues collapses repeats).
    private var uniqueSymbols: [String] {
        let symbols = prompt.chords.map(\.symbol)
        guard prompt.progression == .blues12 else { return symbols }
        var seen: [String] = []
        for s in symbols where !seen.contains(s) { seen.append(s) }
        return seen
    }

    /// One diagram per distinct chord.
    private var diagrams: [(numeral: String, chord: Chord, voicing: Voicing?)] {
        var seen: Set<String> = []
        var result: [(String, Chord, Voicing?)] = []
        for (i, c) in prompt.chords.enumerated() where seen.insert(c.symbol).inserted {
            result.append((prompt.progression.steps[i].numeral, c, prompt.voicings[i]))
        }
        return result
    }
}

struct ProgressionOptionsSection: View {
    @Binding var options: ProgressionOptions

    var body: some View {
        Section("Progressions") {
            OptionChips(all: Progression.allCases, selection: $options.progressions, label: \.title, minWidth: 130, identifier: "progressionChip")
        }
        Section {
            Picker("Diagrams", selection: $options.voicingStyle) {
                ForEach(VoicingStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("voicingStylePicker")
            Toggle("Blues: play first 4 bars only", isOn: $options.bluesFourBars)
                .accessibilityIdentifier("bluesFourBarsToggle")
        } header: {
            Text("Playback")
        } footer: {
            Text("Nearest (CAGED) keeps each chord close to the previous one on the neck.")
        }
        Section("Keys (minor progressions use the relative minor)") {
            MajorKeyChips(keys: $options.keys)
        }
    }
}

#Preview {
    Form { ProgressionOptionsSection(options: .constant(ProgressionOptions())) }
}
