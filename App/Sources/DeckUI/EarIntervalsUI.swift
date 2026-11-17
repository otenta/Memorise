import MemoriseCore
import SwiftUI

/// "Hear it, name it" — `music.ear.intervals`. The prompt plays the notes and starts the
/// response timer when the second note starts.
struct EarIntervalsUI: DeckUI {
    static let gap = 0.6

    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.earInterval else { return AnyView(EmptyView()) }
        return AnyView(EarPromptView(prompt: p, presentationID: ctx.presentationID, promptDidAppear: ctx.promptDidAppear))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.earInterval else { return AnyView(EmptyView()) }
        return AnyView(EarAnswerView(prompt: p, notes: playableNotes(card)))
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.earInterval else { return card.key.raw }
        return "\(p.interval.shortName) \(Self.arrow(p.mode))"
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(EarOptionsSection(options: options.earIntervalOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(ItemStatsList(
            title: "Weakest first",
            items: Interval.allCases.flatMap { i in
                EarMode.allCases.map { m in
                    ItemStatsList.Item(key: EarIntervalsDeck.itemKey(i, mode: m), label: "\(i.longName) \(Self.arrow(m))")
                }
            }.filter { stats[$0.key] != nil },
            stats: stats
        ))
    }

    func managesPromptTiming(_ card: Card) -> Bool { true }

    func playableNotes(_ card: Card) -> [NoteEvent] {
        card.earInterval?.sequence(gap: Self.gap).map { ($0.midi, $0.delay) } ?? []
    }

    /// The prompt itself plays the notes; don't replay them automatically on reveal.
    func onReveal(_ card: Card, ctx: DeckUIContext) {}

    static func arrow(_ m: EarMode) -> String {
        switch m {
        case .ascending: "↑"
        case .descending: "↓"
        case .harmonic: "≡"
        }
    }
}

struct EarPromptView: View {
    let prompt: EarIntervalPrompt
    let presentationID: Int
    let promptDidAppear: @MainActor () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 18) {
            Text("NAME THE INTERVAL").font(.caption.weight(.heavy)).tracking(3).foregroundStyle(.secondary)
            Image(systemName: "ear.fill")
                .font(.system(size: 80, weight: .bold))
                .foregroundStyle(Subject.music.gradient)
                .symbolEffect(.bounce, value: pulse)
            Text(prompt.mode.title).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            Button {
                play()
            } label: {
                Label("Replay", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("replayButton")
        }
        // Plays once per presentation; the timer starts when the second note starts.
        .task(id: presentationID) {
            play()
            try? await Task.sleep(for: .seconds(prompt.secondNoteDelay(gap: EarIntervalsUI.gap)))
            guard !Task.isCancelled else { return }
            promptDidAppear()
        }
    }

    /// Replaying never resets the timer (`promptDidAppear` is idempotent).
    private func play() {
        env.notePlayer.play(prompt.sequence(gap: EarIntervalsUI.gap).map { ($0.midi, $0.delay) })
        pulse.toggle()
    }
}

struct EarAnswerView: View {
    let prompt: EarIntervalPrompt
    let notes: [NoteEvent]

    var body: some View {
        let low = Pitch(midi: prompt.rootMidi)
        let high = Pitch(midi: prompt.upperMidi)
        let lowSpelling = NoteSpelling.preferred(for: low.pitchClass, preferFlat: false)
        let highSpelling = lowSpelling.transposed(by: prompt.interval) ?? .preferred(for: high.pitchClass, preferFlat: false)
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(prompt.interval.longName.capitalized)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Subject.music.gradient)
                    .lineLimit(1).minimumScaleFactor(0.5)
                PlayNotesButton(notes: notes, label: "Replay interval")
            }
            Text("\(prompt.interval.semitones) semitone\(prompt.interval.semitones == 1 ? "" : "s")")
                .font(.title3.weight(.semibold))
            Text("\(low.name(spelling: lowSpelling)) – \(high.name(spelling: highSpelling)) · \(prompt.mode.title.lowercased())")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

struct EarOptionsSection: View {
    @Binding var options: EarIntervalOptions

    var body: some View {
        Section("Intervals") {
            IntervalChips(intervals: $options.intervals)
        }
        Section {
            Picker("Mode", selection: $options.mode) {
                ForEach(EarMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Playback")
        } footer: {
            Text("The timer starts when the second note sounds. Replay as often as you like.")
        }
    }
}
