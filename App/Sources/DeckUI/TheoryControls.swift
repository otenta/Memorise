import MemoriseCore
import SwiftUI

/// Multi-select chips for any option set (keeps at least `minimum` selected).
struct OptionChips<T: Hashable>: View {
    let all: [T]
    @Binding var selection: Set<T>
    let label: (T) -> String
    var minimum = 1
    var minWidth: CGFloat = 56
    var identifier = "optionChip"

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minWidth), spacing: 6)], spacing: 6) {
            ForEach(all, id: \.self) { item in
                let on = selection.contains(item)
                Button {
                    withAnimation(Theme.spring) {
                        if on { if selection.count > minimum { selection.remove(item) } } else { selection.insert(item) }
                    }
                } label: {
                    Text(label(item))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            Capsule().fill(on ? AnyShapeStyle(Subject.music.gradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                        }
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel(label(item))
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("\(identifier).\(label(item))")
            }
        }
        .padding(.vertical, 4)
    }
}

/// The 12 roots, spelled per `RootNames`.
struct RootChips: View {
    @Binding var roots: Set<PitchClass>
    var body: some View {
        OptionChips(all: PitchClass.allCases, selection: $roots, label: { RootNames.spelling($0).displayName }, minWidth: 44, identifier: "rootChip")
    }
}

/// The 15 major keys (ASCII tonics).
struct MajorKeyChips: View {
    @Binding var keys: Set<String>
    var body: some View {
        OptionChips(all: Key.majors.map(\.tonic.ascii), selection: $keys,
                    label: { NoteSpelling(ascii: $0)?.displayName ?? $0 }, minWidth: 44, identifier: "keyChip")
    }
}

/// Plain integer picker for a max fret.
struct FretLimitPicker: View {
    @Binding var maxFret: Int
    var title = "Max fret"
    var values = [5, 7, 9, 12, 15, 17, 19, 22, 24]

    var body: some View {
        Picker(title, selection: $maxFret) {
            ForEach(Array(Set(values + [maxFret])).sorted(), id: \.self) { Text("\($0)").tag($0) }
        }
        .accessibilityIdentifier("maxFretPicker")
    }
}

/// Big gradient headline used by M3 prompts.
struct HeroText: View {
    let text: String
    var size: CGFloat = 64

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(Subject.music.gradient)
            .lineLimit(1).minimumScaleFactor(0.35)
            .contentTransition(.numericText())
    }
}

/// Small uppercase caption above a prompt ("PLAY", "NAME IT").
struct PromptCaption: View {
    let text: String
    var body: some View {
        Text(text).font(.caption.weight(.heavy)).tracking(3).foregroundStyle(.secondary)
    }
}

/// "Weakest first" list built from the deck's current cards.
struct CardStatsList: View {
    let deck: any Deck
    let stats: [ItemKey: ItemStats]
    var title = "Weakest first"
    var filter: (Card) -> Bool = { _ in true }
    let label: (Card) -> String
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let cards = deck.cards(options: env.initialConfig(for: deck).options)
        ItemStatsList(
            title: title,
            items: cards.filter { stats[$0.key] != nil && filter($0) }.map { ItemStatsList.Item(key: $0.key, label: label($0)) },
            stats: stats
        )
    }
}

/// Spoken-free fallback pitches for a chord with no diagram (root near C3).
func chordMidis(_ chord: Chord, base: Int = 48) -> [Int] {
    let root = base + chord.root.pitchClass.value
    return chord.quality.degrees.map { root + $0.semitones }
}

extension Binding where Value == DeckOptions {
    var chordOptions: Binding<ChordOptions> {
        Binding<ChordOptions>(get: { wrappedValue.chords ?? ChordOptions() }, set: { wrappedValue = .chords($0) })
    }

    var triadOptions: Binding<TriadOptions> {
        Binding<TriadOptions>(get: { wrappedValue.triads ?? TriadOptions() }, set: { wrappedValue = .triads($0) })
    }

    var arpeggioOptions: Binding<ArpeggioOptions> {
        Binding<ArpeggioOptions>(get: { wrappedValue.arpeggios ?? ArpeggioOptions() }, set: { wrappedValue = .arpeggios($0) })
    }

    var scaleOptions: Binding<ScaleOptions> {
        Binding<ScaleOptions>(get: { wrappedValue.scales ?? ScaleOptions() }, set: { wrappedValue = .scales($0) })
    }

    var keySigOptions: Binding<KeySigOptions> {
        Binding<KeySigOptions>(get: { wrappedValue.keySignatures ?? KeySigOptions() }, set: { wrappedValue = .keySignatures($0) })
    }

    var diatonicOptions: Binding<DiatonicOptions> {
        Binding<DiatonicOptions>(get: { wrappedValue.diatonic ?? DiatonicOptions() }, set: { wrappedValue = .diatonic($0) })
    }

    var progressionOptions: Binding<ProgressionOptions> {
        Binding<ProgressionOptions>(get: { wrappedValue.progressions ?? ProgressionOptions() }, set: { wrappedValue = .progressions($0) })
    }

    var circleOptions: Binding<CircleOptions> {
        Binding<CircleOptions>(get: { wrappedValue.circle ?? CircleOptions() }, set: { wrappedValue = .circle($0) })
    }
}

#Preview("Chips") {
    @Previewable @State var roots: Set<PitchClass> = RootNames.all
    @Previewable @State var keys: Set<String> = DiatonicOptions.allKeys
    Form {
        Section("Roots") { RootChips(roots: $roots) }
        Section("Keys") { MajorKeyChips(keys: $keys) }
    }
}
