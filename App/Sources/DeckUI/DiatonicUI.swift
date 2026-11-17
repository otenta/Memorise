import MemoriseCore
import SwiftUI

/// "iii in G major?" ⇄ "Bm in G major is…?" — `music.theory.diatonic`.
struct DiatonicUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.diatonic else { return AnyView(EmptyView()) }
        let asked = p.direction == .degreeToChord ? p.chord.numeral : p.chord.chord.symbol
        return AnyView(VStack(spacing: 12) {
            PromptCaption(text: p.direction == .degreeToChord ? "WHICH CHORD?" : "WHICH DEGREE?")
            HeroText(text: asked, size: 80)
            (Text("in ") + Text(p.key.name).bold() + Text(p.direction == .chordToDegree ? " is…?" : "?"))
                .font(.title2)
        }
        .accessibilityElement(children: .combine))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.diatonic else { return AnyView(EmptyView()) }
        let answer = p.direction == .degreeToChord ? p.chord.chord.symbol : p.chord.numeral
        return AnyView(VStack(spacing: 14) {
            HStack(spacing: 12) {
                HeroText(text: answer, size: 64)
                PlayNotesButton(notes: playableNotes(card), label: "Play chord")
            }
            Text(p.chord.chord.tonesText).font(.title3.weight(.semibold).monospaced())
            DiatonicRow(row: p.row, highlight: p.chord.degree)
            if p.key.mode == .minor && p.chord.degree == 5 {
                Text("Minor keys use the harmonic-minor V").font(.footnote).foregroundStyle(.secondary)
            }
        })
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.diatonic else { return card.key.raw }
        return "\(p.chord.numeral) in \(p.key.name) = \(p.chord.chord.symbol)"
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(DiatonicOptionsSection(options: options.diatonicOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(CardStatsList(deck: deck, stats: stats) { label($0, settings: AppSettings.statsLabels) })
    }

    func playableNotes(_ card: Card) -> [NoteEvent] {
        card.diatonic.map { NotePlayer.strumEvents(chordMidis($0.chord.chord)) } ?? []
    }
}

/// The key's chord row with one degree highlighted.
struct DiatonicRow: View {
    let row: [DiatonicChord]
    let highlight: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(row, id: \.degree) { c in
                let on = c.degree == highlight
                VStack(spacing: 2) {
                    Text(c.numeral).font(.caption.weight(.heavy))
                    Text(c.chord.symbol).font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(on ? AnyShapeStyle(Subject.music.gradient) : AnyShapeStyle(Color.secondary.opacity(0.12)))
                }
                .scaleEffect(on ? 1.06 : 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.map { "\($0.numeral) \($0.chord.symbol)" }.joined(separator: ", "))
    }
}

struct DiatonicOptionsSection: View {
    @Binding var options: DiatonicOptions

    var body: some View {
        Section {
            OptionChips(all: KeyMode.allCases, selection: $options.modes, label: { $0.title.capitalized }, minWidth: 100, identifier: "modeChip")
            Picker("Chords", selection: $options.chordSize) {
                Text("Triads").tag(DiatonicChordSize.triads)
                Text("7ths").tag(DiatonicChordSize.sevenths)
                Text("Both").tag(DiatonicChordSize.both)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("chordSizePicker")
            OptionChips(all: DiatonicDirection.allCases, selection: $options.directions, label: \.title, minWidth: 140, identifier: "directionChip")
        } header: {
            Text("Questions")
        } footer: {
            Text("Minor keys use the harmonic-minor V (e.g. E in A minor).")
        }
        Section("Keys (minor uses the relative minor)") {
            MajorKeyChips(keys: $options.keys)
        }
    }
}

#Preview {
    let g = Key.majors[1]
    return DiatonicRow(row: g.diatonicTriads(), highlight: 3).padding()
}
