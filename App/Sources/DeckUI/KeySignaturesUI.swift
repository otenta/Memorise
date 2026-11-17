import MemoriseCore
import SwiftUI

/// "E major: how many sharps or flats?" ⇄ staff → "Which major key?" — `music.theory.keysig`.
struct KeySignaturesUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.keySignature else { return AnyView(EmptyView()) }
        switch p.direction {
        case .keyToSig:
            return AnyView(VStack(spacing: 12) {
                PromptCaption(text: "KEY SIGNATURE")
                HeroText(text: p.key.name, size: 56)
                Text("How many sharps or flats?").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine))
        case .sigToKey:
            return AnyView(VStack(spacing: 14) {
                PromptCaption(text: "WHICH KEY?")
                StaffView(signature: p.key.signature).frame(maxWidth: 340)
                (Text("Which ") + Text(p.key.mode.title).bold() + Text(" key?")).font(.title2)
            })
        }
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.keySignature else { return AnyView(EmptyView()) }
        let sig = p.key.signature
        let accidentals = sig.accidentals.map(\.displayName).joined(separator: " ")
        return AnyView(VStack(spacing: 12) {
            switch p.direction {
            case .keyToSig:
                HeroText(text: sig.shortText, size: 64)
                StaffView(signature: sig).frame(maxWidth: 340)
                if !accidentals.isEmpty { Text(accidentals).font(.title3.weight(.semibold).monospaced()) }
            case .sigToKey:
                HeroText(text: p.key.name, size: 52)
                Text("\(sig.longText)" + (accidentals.isEmpty ? "" : " · \(accidentals)"))
                    .font(.headline)
            }
            Text("Relative: \(p.key.relative.name)").font(.subheadline).foregroundStyle(.secondary)
        })
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.keySignature else { return card.key.raw }
        return p.direction == .keyToSig ? "\(p.key.name) → \(p.key.signature.shortText)" : "\(p.key.signature.shortText) → \(p.key.mode.title)"
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(KeySigOptionsSection(options: options.keySigOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(CardStatsList(deck: deck, stats: stats) { label($0, settings: AppSettings.statsLabels) })
    }
}

struct KeySigOptionsSection: View {
    @Binding var options: KeySigOptions

    var body: some View {
        Section("Keys") {
            OptionChips(all: KeyMode.allCases, selection: $options.modes, label: { $0.title.capitalized }, minWidth: 100, identifier: "modeChip")
        }
        Section("Questions") {
            OptionChips(all: KeySigDirection.allCases, selection: $options.directions, label: \.title, minWidth: 140, identifier: "directionChip")
        }
    }
}

#Preview {
    Form { KeySigOptionsSection(options: .constant(KeySigOptions())) }
}
