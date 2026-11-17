import MemoriseCore
import SwiftUI

/// "A minor pentatonic · box 1" / "D Dorian · 3NPS position 2" — `music.scales`.
struct ScalesUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.scale else { return AnyView(EmptyView()) }
        return AnyView(VStack(spacing: 12) {
            PromptCaption(text: "PLAY THE SCALE")
            HeroText(text: p.scale.name, size: 46)
            Text(p.positionText)
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(.secondary.opacity(0.12), in: Capsule())
        }
        .accessibilityElement(children: .combine))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.scale else { return AnyView(EmptyView()) }
        let s = ctx.settings
        return AnyView(VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(p.scale.notesText).font(.headline.monospaced())
                PlayNotesButton(notes: playableNotes(card), label: "Play scale")
            }
            s.board(window: p.notes.fretWindow, marks: s.marks(p.notes))
            Text(p.scale.type.degreeLabels.joined(separator: " "))
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
        })
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.scale else { return card.key.raw }
        return "\(p.scale.name) · \(p.positionText)"
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(ScaleOptionsSection(options: options.scaleOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(CardStatsList(deck: deck, stats: stats) { label($0, settings: AppSettings.statsLabels) })
    }

    /// Ascending, then descending.
    func playableNotes(_ card: Card) -> [NoteEvent] {
        guard let p = card.scale else { return [] }
        let up = p.notes.map(\.midi)
        let seq = up + up.dropLast().reversed()
        return seq.enumerated().map { ($1, Double($0) * 0.18) }
    }
}

struct ScaleOptionsSection: View {
    @Binding var options: ScaleOptions

    var body: some View {
        Section {
            OptionChips(all: ScaleType.allCases, selection: $options.types, label: \.title, minWidth: 120, identifier: "scaleTypeChip")
        } header: {
            Text("Scales")
        } footer: {
            Text("New cards start with pentatonic boxes, then major/minor, then the modes.")
        }
        Section("Positions") {
            OptionChips(all: ScaleSystem.allCases, selection: $options.systems, label: { $0 == .box ? "Boxes (pentatonic, blues)" : "3NPS (7-note scales)" },
                        minWidth: 150, identifier: "scaleSystemChip")
            FretLimitPicker(maxFret: $options.maxFret)
        }
        Section("Tonics") {
            RootChips(roots: $options.tonics)
        }
    }
}

#Preview {
    Form { ScaleOptionsSection(options: .constant(ScaleOptions())) }
}
