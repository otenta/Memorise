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
            poolCount = config.map { env.cardCount(for: deck, options: $0.options) } ?? 0
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
            Section {
                SetupBanner(deck: deck, poolCount: poolCount)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
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

        }
        .scrollContentBackground(.hidden)
        .auroraBackground(colors: deck.subject.colors, intensity: 0.45)
        .tint(deck.subject.accent)
    }
}

/// Gradient header: deck title, subtitle and a live "cards available" counter.
private struct SetupBanner: View {
    let deck: any Deck
    let poolCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(deck.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(poolCount)")
                        .font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(value: Double(poolCount)))
                    Text(poolCount == 1 ? "card available" : "cards available")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .foregroundStyle(.white)
                .animation(Theme.spring, value: poolCount)
                if poolCount == 0 {
                    Label("Change the options to include some cards", systemImage: "exclamationmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Theme.rose.opacity(0.7), in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            shape.fill(deck.subject.gradient)
                .overlay(alignment: .trailing) {
                    deck.subject.glyph
                        .font(.system(size: 96))
                        .foregroundStyle(.white.opacity(0.16))
                        .rotationEffect(.degrees(-12))
                        .offset(x: 14)
                }
                .overlay { shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)) }
                .clipShape(shape)
                .shadow(color: deck.subject.accent.opacity(0.35), radius: 14, y: 8)
        }
        .animation(Theme.spring, value: poolCount == 0)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cardsAvailable")
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
