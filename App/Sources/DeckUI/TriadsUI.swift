import MemoriseCore
import SwiftUI

/// "C major, 1st inversion, strings 3-2-1" — `music.triads`.
struct TriadsUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.triad else { return AnyView(EmptyView()) }
        return AnyView(VStack(spacing: 12) {
            PromptCaption(text: "PLAY THE TRIAD")
            HeroText(text: "\(p.chord.root.displayName) \(p.chord.quality.longName)", size: 52)
            Text(p.inversion.title).font(.title2.weight(.semibold))
            (Text("strings ") + Text(p.stringSet.title).bold())
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.triad else { return AnyView(EmptyView()) }
        let s = ctx.settings
        return AnyView(VStack(spacing: 14) {
            HStack(spacing: 12) {
                HeroText(text: p.notes.map(\.spelling.displayName).joined(separator: " "), size: 40)
                PlayNotesButton(notes: playableNotes(card), label: "Strum triad")
            }
            s.board(window: p.notes.fretWindow, marks: s.marks(p.notes, emphasiseFirst: true), highlight: Set(p.stringSet.strings))
            Text("frets " + p.notes.map { "\($0.position.fret)" }.joined(separator: "-") + "  ·  bass: \(p.notes.first?.degree ?? "")")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        })
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.triad else { return card.key.raw }
        return "\(p.chord.symbol) · \(p.inversion.title) · \(p.stringSet.title)"
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(TriadOptionsSection(options: options.triadOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(CardStatsList(deck: deck, stats: stats) { label($0, settings: AppSettings.statsLabels) })
    }

    func playableNotes(_ card: Card) -> [NoteEvent] {
        card.triad.map { NotePlayer.strumEvents($0.notes.map(\.midi), spacing: 0.05) } ?? []
    }
}

struct TriadOptionsSection: View {
    @Binding var options: TriadOptions

    var body: some View {
        Section("Triads") {
            OptionChips(all: ChordQuality.triadQualities, selection: $options.qualities, label: { $0.longName }, minWidth: 90, identifier: "qualityChip")
            OptionChips(all: TriadInversion.allCases, selection: $options.inversions, label: \.title, minWidth: 100, identifier: "inversionChip")
        }
        Section("String sets") {
            OptionChips(all: StringSet.allCases, selection: $options.stringSets, label: \.title, identifier: "stringSetChip")
        }
        Section("Roots") {
            RootChips(roots: $options.roots)
            FretLimitPicker(maxFret: $options.maxFret)
        }
    }
}

extension AppSettings {
    /// Settings instance for stats labels, which are formatting-independent.
    static let statsLabels = AppSettings(defaults: UserDefaults(suiteName: "memorise.statsLabels") ?? .standard)
}

#Preview {
    Form { TriadOptionsSection(options: .constant(TriadOptions())) }
}
