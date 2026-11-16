import MemoriseCore
import SwiftUI

/// Session Setup sheet (§11.2): length, focus, retry, deck-specific options.
struct SessionSetupView: View {
    let deck: any Deck
    let onStart: (SessionConfig) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var config: SessionConfig?
    @State private var poolCount = 0

    var body: some View {
        NavigationStack {
            Group {
                if let binding = Binding($config) {
                    SetupForm(deck: deck, config: binding, poolCount: poolCount)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(deck.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                BigButton(title: "Start", systemImage: "play.fill") {
                    guard let config else { return }
                    env.configStore.save(config)
                    onStart(config)
                }
                .disabled(poolCount == 0)
                .padding()
                .background(.bar)
                .accessibilityIdentifier("startButton")
            }
        }
        .onAppear { if config == nil { config = env.initialConfig(for: deck) } }
        .task(id: config?.options) {
            poolCount = config.map { deck.cards(options: $0.options).count } ?? 0
        }
        .presentationDetents([.large])
    }
}

private struct SetupForm: View {
    let deck: any Deck
    @Binding var config: SessionConfig
    let poolCount: Int

    var body: some View {
        Form {
            LengthSection(length: $config.length)

            Section {
                Picker("Focus on weak cards", selection: $config.focus) {
                    Text("Off").tag(FocusLevel.off)
                    Text("Normal").tag(FocusLevel.normal)
                    Text("Strong").tag(FocusLevel.strong)
                }
                .pickerStyle(.segmented)
                Toggle("Retry wrong cards", isOn: $config.retryWrongCards)
            } header: {
                Text("Focus on weak cards")
            } footer: {
                Text("Slow and missed cards show up more often. Off = uniform random.")
            }

            switch config.options {
            case let .fretboard(o):
                FretboardOptionsSection(options: Binding(
                    get: { o },
                    set: { config.options = .fretboard($0) }
                ))
            case let .vocab(o):
                VocabOptionsSection(
                    options: Binding(get: { o }, set: { config.options = .vocab($0) }),
                    allTags: (deck as? VocabDeck)?.allTags ?? []
                )
            }

            Section {
                LabeledContent("Cards available", value: "\(poolCount)")
            }
        }
    }
}

private struct LengthSection: View {
    @Binding var length: SessionLength

    private enum Mode: Hashable { case cards, timed }

    var body: some View {
        let mode: Mode = if case .minutes = length { .timed } else { .cards }
        Section("Length") {
            Picker("Mode", selection: Binding(
                get: { mode },
                set: { length = $0 == .cards ? .cards(20) : .minutes(5) }
            )) {
                Text("Cards").tag(Mode.cards)
                Text("Timed").tag(Mode.timed)
            }
            .pickerStyle(.segmented)

            switch length {
            case let .cards(n):
                Picker("Cards", selection: Binding(get: { n }, set: { length = .cards($0) })) {
                    ForEach(SessionLength.cardPresets, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            case let .minutes(m):
                Picker("Minutes", selection: Binding(get: { m }, set: { length = .minutes($0) })) {
                    ForEach(SessionLength.minutePresets, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

private struct FretboardOptionsSection: View {
    @Binding var options: FretboardOptions

    var body: some View {
        Section("Strings") {
            HStack(spacing: 8) {
                ForEach([6, 5, 4, 3, 2, 1], id: \.self) { s in
                    let on = options.strings.contains(s)
                    Button {
                        if on { if options.strings.count > 1 { options.strings.remove(s) } } else { options.strings.insert(s) }
                    } label: {
                        Text("\(s)")
                            .font(.headline.monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(on ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("String \(s)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        Section("Notes") {
            Picker("Notes", selection: $options.noteSet) {
                Text("Naturals").tag(FretboardOptions.NoteSet.naturals)
                Text("All notes").tag(FretboardOptions.NoteSet.all)
            }
            .pickerStyle(.segmented)
            if options.noteSet == .all {
                Picker("Accidentals", selection: $options.accidentalSpelling) {
                    Text("Sharps").tag(FretboardOptions.AccidentalSpelling.sharps)
                    Text("Flats").tag(FretboardOptions.AccidentalSpelling.flats)
                    Text("Mixed").tag(FretboardOptions.AccidentalSpelling.mixed)
                }
                .pickerStyle(.segmented)
            }
            Picker("Max fret", selection: Binding(
                get: { options.fretRange.upperBound },
                set: { options.fretRange = options.fretRange.lowerBound...$0 }
            )) {
                ForEach(FretboardOptions.maxFretPresets, id: \.self) { Text("\($0)").tag($0) }
            }
        }
    }
}

private struct VocabOptionsSection: View {
    @Binding var options: VocabOptions
    let allTags: [String]

    var body: some View {
        Section("Words") {
            Picker("Direction", selection: $options.direction) {
                Text("Korean → English").tag(VocabOptions.DirectionOption.koToEn)
                Text("English → Korean").tag(VocabOptions.DirectionOption.enToKo)
                Text("Both").tag(VocabOptions.DirectionOption.both)
            }
            Stepper("New words per session: \(options.newPerSession)", value: $options.newPerSession, in: 0...30)
            Toggle("Auto-play pronunciation", isOn: $options.autoPlayAudio)
        }
        if !allTags.isEmpty {
            Section {
                ForEach(allTags, id: \.self) { tag in
                    Toggle(tag.capitalized, isOn: Binding(
                        get: { options.tags.contains(tag) },
                        set: { if $0 { options.tags.insert(tag) } else { options.tags.remove(tag) } }
                    ))
                }
            } header: {
                Text("Topics")
            } footer: {
                Text(options.tags.isEmpty ? "No topic selected: all words are included." : "Only words with a selected topic are included.")
            }
        }
    }
}

#Preview("Fretboard") {
    SessionSetupView(deck: FretboardNotesDeck()) { _ in }
        .environment(AppEnvironment.preview())
}

#Preview("Vocab") {
    let env = AppEnvironment.preview()
    return SessionSetupView(deck: env.catalog.decks.last!) { _ in }
        .environment(env)
}
