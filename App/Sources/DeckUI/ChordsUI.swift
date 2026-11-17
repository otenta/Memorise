import MemoriseCore
import SwiftUI

/// "Play the Chord" (`music.chords.play`) and "Name the Chord" (`music.chords.name`).
struct ChordsUI: DeckUI {
    /// `true` = diagram prompt, name answer.
    let naming: Bool

    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.chord else { return AnyView(EmptyView()) }
        if naming {
            return AnyView(VStack(spacing: 14) {
                PromptCaption(text: "NAME THIS CHORD")
                ChordDiagramView(voicing: p.voicing, showFingers: false, leftHanded: ctx.settings.leftHanded)
                    .frame(maxWidth: 230)
            })
        }
        return AnyView(ChordSymbolPrompt(prompt: p, showHint: ctx.settings.showShapeHint))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.chord else { return AnyView(EmptyView()) }
        return AnyView(ChordAnswerView(prompt: p, settings: ctx.settings, showName: naming, notes: playableNotes(card)))
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.chord else { return card.key.raw }
        return "\(p.chord.symbol) · \(p.shape.hint)"
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(ChordOptionsSection(options: options.chordOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(Group {
            ChordQualityRootGrid(deck: deck, stats: stats)
            CardStatsList(deck: deck, stats: stats, title: "Open chords", filter: { $0.chord?.shape.movable == false }) { card in
                card.chord.map { "\($0.chord.symbol) · open" } ?? card.key.raw
            }
        })
    }

    func supportedInputModes(deck: any Deck) -> [InputMode] { naming ? [.touch, .choice] : [.touch] }

    /// Name the Chord: the answer, same root/other quality, same quality/other root, one random.
    func choices(for card: Card, options: DeckOptions, using rng: inout SplitMix64) -> [AnswerChoice]? {
        guard naming, let p = card.chord else { return nil }
        let answer = p.chord
        return ChordChoices.options(for: answer, qualities: options.chords?.qualities ?? [], using: &rng)
            .map { AnswerChoice(label: $0.symbol, isCorrect: $0.symbol == answer.symbol) }
    }

    /// Strum low → high.
    func playableNotes(_ card: Card) -> [NoteEvent] {
        guard let p = card.chord else { return [] }
        return NotePlayer.strumEvents(p.voicing.midis)
    }
}

struct ChordSymbolPrompt: View {
    let prompt: ChordCardPrompt
    let showHint: Bool

    var body: some View {
        VStack(spacing: 12) {
            PromptCaption(text: "PLAY")
            HeroText(text: prompt.chord.symbol, size: 84)
            if showHint {
                Text(prompt.shape.hint)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Play \(prompt.chord.longName)" + (showHint ? ", \(prompt.shape.hint)" : ""))
    }
}

struct ChordAnswerView: View {
    let prompt: ChordCardPrompt
    let settings: AppSettings
    let showName: Bool
    let notes: [NoteEvent]

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                HeroText(text: prompt.chord.symbol, size: showName ? 64 : 44)
                PlayNotesButton(notes: notes, label: "Strum chord")
            }
            if showName {
                Text(prompt.chord.longName).font(.title3.weight(.semibold))
                Text(prompt.shape.hint).font(.subheadline).foregroundStyle(.secondary)
            } else {
                ChordDiagramView(voicing: prompt.voicing, leftHanded: settings.leftHanded)
                    .frame(maxWidth: 230)
            }
            Text("\(prompt.chord.tonesText)  ·  \(prompt.chord.degreesText)")
                .font(.headline.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct ChordOptionsSection: View {
    @Binding var options: ChordOptions

    var body: some View {
        Section("Shapes") {
            OptionChips(all: ShapeFamily.allCases, selection: $options.families, label: \.title, minWidth: 80, identifier: "familyChip")
        }
        Section("Qualities") {
            OptionChips(all: ChordQuality.allCases, selection: $options.qualities, label: \.chipLabel, identifier: "qualityChip")
        }
        Section {
            RootChips(roots: $options.roots)
            FretLimitPicker(maxFret: $options.maxFret)
        } header: {
            Text("Roots")
        } footer: {
            Text("Movable shapes are asked on every chosen root, at the lowest position that fits.")
        }
    }
}

// MARK: - Stats

/// Quality × root grid coloured by error EWMA (movable shapes, averaged across shapes).
struct ChordQualityRootGrid: View {
    let deck: any Deck
    let stats: [ItemKey: ItemStats]
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let cards = deck.cards(options: env.initialConfig(for: deck).options).filter { $0.chord?.shape.movable == true }
        var errors: [ChordQuality: [Int: [Double]]] = [:]
        for c in cards {
            guard let p = c.chord, let s = stats[c.key], s.attempts > 0 else { continue }
            errors[p.chord.quality, default: [:]][p.chord.root.pitchClass.value, default: []].append(s.ewmaError)
        }
        let qualities = ChordQuality.allCases.filter { errors[$0] != nil }
        return Section("Quality × root (errors)") {
            if qualities.isEmpty {
                Text("Practise some barre or CAGED chords to fill this grid.").font(.footnote).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                        GridRow {
                            Text("")
                            ForEach(0..<12, id: \.self) { pc in
                                Text(RootNames.spelling(PitchClass(pc)).displayName).font(.caption2.weight(.bold)).frame(width: 26)
                            }
                        }
                        ForEach(qualities, id: \.self) { q in
                            GridRow {
                                Text(q.chipLabel).font(.caption.weight(.semibold)).frame(minWidth: 40, alignment: .leading)
                                ForEach(0..<12, id: \.self) { pc in
                                    let e = errors[q]?[pc].map { $0.reduce(0, +) / Double($0.count) }
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(e.map { Color(hue: 0.33 * (1 - min(1, $0)), saturation: 0.75, brightness: 0.85) } ?? Color.secondary.opacity(0.12))
                                        .frame(width: 26, height: 22)
                                        .accessibilityLabel("\(RootNames.spelling(PitchClass(pc)).displayName)\(q.symbol): " + (e.map { "\(Int(($0 * 100).rounded()))% error" } ?? "not practised"))
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

#Preview("Play prompt") {
    let shape = ChordShapeLibrary.shared.shape(id: "Ashape.m7")!
    let p = ChordCardPrompt(shape: shape, voicing: shape.voicing(root: NoteSpelling(.b, .flat), maxFret: 12)!)
    return ChordSymbolPrompt(prompt: p, showHint: true).padding()
}

#Preview("Answer") {
    let shape = ChordShapeLibrary.shared.shape(id: "Ashape.m7")!
    let p = ChordCardPrompt(shape: shape, voicing: shape.voicing(root: NoteSpelling(.b, .flat), maxFret: 12)!)
    return ChordAnswerView(prompt: p, settings: AppSettings(defaults: .init(suiteName: "preview")!), showName: false, notes: [])
        .environment(AppEnvironment.preview())
        .padding()
}
