import MemoriseCore
import SwiftUI

/// "A m7 arpeggio · root on string 6 · 2 octaves" — `music.arpeggios`.
struct ArpeggiosUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.arpeggio else { return AnyView(EmptyView()) }
        return AnyView(VStack(spacing: 12) {
            PromptCaption(text: "ARPEGGIO")
            HeroText(text: p.chord.symbol, size: 80)
            Text("root on string \(p.rootString) · \(p.span.title)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.chord.longName) arpeggio, root on string \(p.rootString), \(p.span.title)"))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.arpeggio else { return AnyView(EmptyView()) }
        let s = ctx.settings
        return AnyView(VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text("\(p.chord.tonesText)  ·  \(p.chord.degreesText)")
                    .font(.headline.monospaced())
                PlayNotesButton(notes: playableNotes(card), label: "Play arpeggio")
            }
            s.board(window: p.notes.fretWindow, marks: s.marks(p.notes, badges: true), highlight: Set(p.notes.map(\.position.string)))
            Text("\(p.notes.count) notes · numbers show the playing order")
                .font(.footnote)
                .foregroundStyle(.secondary)
        })
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.arpeggio else { return card.key.raw }
        return "\(p.chord.symbol) arpeggio · s\(p.rootString)"
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(ArpeggioOptionsSection(options: options.arpeggioOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(CardStatsList(deck: deck, stats: stats) { label($0, settings: AppSettings.statsLabels) })
    }

    /// Up, then back down to the root.
    func playableNotes(_ card: Card) -> [NoteEvent] {
        guard let p = card.arpeggio else { return [] }
        let up = p.notes.map(\.midi)
        let seq = up + up.dropLast().reversed()
        return seq.enumerated().map { ($1, Double($0) * 0.22) }
    }
}

struct ArpeggioOptionsSection: View {
    @Binding var options: ArpeggioOptions
    private let qualities: [ChordQuality] = [.maj, .min, .dom7, .maj7, .min7, .m7b5, .dim7, .aug, .six, .min6]

    var body: some View {
        Section("Qualities") {
            OptionChips(all: qualities, selection: $options.qualities, label: \.chipLabel, identifier: "qualityChip")
        }
        Section("Root") {
            OptionChips(all: [6, 5], selection: $options.rootStrings, label: { "String \($0)" }, minWidth: 100, identifier: "rootStringChip")
            RootChips(roots: $options.roots)
        }
        Section("Range") {
            Picker("Span", selection: $options.span) {
                ForEach(ArpeggioSpan.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("arpeggioSpanPicker")
            FretLimitPicker(maxFret: $options.maxFret)
        }
    }
}

#Preview {
    Form { ArpeggioOptionsSection(options: .constant(ArpeggioOptions())) }
}
