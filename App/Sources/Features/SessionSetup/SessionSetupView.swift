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
                BigButton(title: "Start", systemImage: "play.fill", colors: deck.subject.colors) {
                    guard let config else { return }
                    env.configStore.save(config)
                    onStart(config)
                }
                .disabled(poolCount == 0)
                .padding(.horizontal)
                .padding(.vertical, 10)
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
    @Environment(AppEnvironment.self) private var env

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

            let ui = env.deckUI(for: deck)
            ui.setupSection($config.options, deck: deck)

            let modes = ui.supportedInputModes(deck: deck)
            if modes.count > 1 {
                AnswerBySection(config: $config, modes: modes)
            }

            Section {
                LabeledContent("Cards available") {
                    Text("\(poolCount)")
                        .font(.system(.body, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(poolCount == 0 ? AnyShapeStyle(.red) : AnyShapeStyle(deck.subject.gradient))
                        .contentTransition(.numericText())
                        .animation(Theme.spring, value: poolCount)
                }
            }
        }
    }
}

/// "Answer by" picker; requests mic permission when the microphone is chosen.
private struct AnswerBySection: View {
    @Binding var config: SessionConfig
    let modes: [InputMode]
    @State private var denied = MicAnswerController.permission == .denied

    var body: some View {
        Section {
            Picker("Answer by", selection: Binding(
                get: { config.inputMode },
                set: { mode in
                    guard mode == .microphone else { config.inputMode = mode; return }
                    Task {
                        let granted = await MicAnswerController.requestPermission()
                        denied = !granted
                        config.inputMode = granted ? .microphone : .touch
                    }
                }
            )) {
                ForEach(modes, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("answerByPicker")
            if config.inputMode == .microphone {
                Picker("Reveal after", selection: $config.micTimeoutSeconds) {
                    ForEach(SessionConfig.micTimeoutPresets, id: \.self) { Text("\($0) s").tag($0) }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Answer by")
        } footer: {
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        switch config.inputMode {
        case .microphone where denied:
            Text("Microphone access is off. Enable it in Settings → Privacy & Security → Microphone → Memorise.")
                .foregroundStyle(.red)
        case .microphone:
            Text("Play the note on your guitar: a correct note is graded automatically from the moment you play it. If nothing is heard, the answer is revealed for you to grade.")
        case .typed:
            Text("Type the answer and press Return. Small typos count as close; you can always override the verdict. Typing time doesn't affect your speed stats.")
        case .choice:
            Text("Tap the right option; it's graded straight away.")
        case .touch:
            Text("Think of the answer, reveal it, then grade yourself.")
        }
    }
}

extension InputMode {
    var systemImage: String {
        switch self {
        case .touch: "hand.tap.fill"
        case .microphone: "mic.fill"
        case .choice: "square.grid.2x2.fill"
        case .typed: "keyboard.fill"
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

#Preview("Fretboard") {
    SessionSetupView(deck: FretboardNotesDeck()) { _ in }
        .environment(AppEnvironment.preview())
}

#Preview("Vocab") {
    let env = AppEnvironment.preview()
    return SessionSetupView(deck: env.catalog.decks.last!) { _ in }
        .environment(env)
}
