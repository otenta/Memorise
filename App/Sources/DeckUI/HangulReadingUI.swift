import MemoriseCore
import SwiftUI

/// "How do you read 가?" — `ko.hangul` (PLAN_M4 M4-2).
struct HangulReadingUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.hangulReading else { return AnyView(EmptyView()) }
        return AnyView(HangulReadingPromptView(prompt: p))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.hangulReading else { return AnyView(EmptyView()) }
        return AnyView(HangulReadingAnswerView(prompt: p))
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.hangulReading else { return card.key.raw }
        return "\(p.text) → \(p.romanization)"
    }

    func supportedInputModes(deck: any Deck) -> [InputMode] { [.touch, .typed] }

    /// Type the romanization (ㄹ accepts r or l; matching is exact otherwise).
    func typedAnswer(for card: Card) -> TypedAnswerSpec? {
        guard let p = card.hangulReading, !p.romanization.isEmpty else { return nil }
        return TypedAnswerSpec(expected: [p.romanization], kind: .romanization)
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        let words = (deck as? HangulReadingDeck)?.realWords.count ?? 0
        return AnyView(HangulReadingOptionsSection(options: options.hangulReadingOptions, realWordCount: words))
    }

    /// Drops `realWords` when no Korean deck has short words; never leaves the stage set empty.
    func sanitize(_ options: DeckOptions, deck: any Deck) -> DeckOptions {
        guard case var .hangulReading(o) = options, let deck = deck as? HangulReadingDeck else { return options }
        if deck.realWords.isEmpty { o.stages.remove(.realWords) }
        if o.stages.isEmpty { o.stages = HangulReadingOptions().stages }
        return .hangulReading(o)
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        guard let deck = deck as? HangulReadingDeck else { return nil }
        return AnyView(Group {
            HangulStatsGrid(deck: deck, stats: stats)
            CardStatsList(deck: deck, stats: stats) { label($0, settings: AppSettings.statsLabels) }
        })
    }

    /// Speaks the syllable (or asks once for a Korean voice).
    func onReveal(_ card: Card, ctx: DeckUIContext) {
        guard let p = card.hangulReading else { return }
        let env = ctx.env
        guard env.speech.hasKoreanVoice else {
            if !env.settings.koreanVoiceHintShown {
                env.settings.koreanVoiceHintShown = true
                ctx.requestVoiceHint()
            }
            return
        }
        if env.settings.autoPlayPronunciation {
            env.speech.speak(p.text, rate: env.settings.speechRate)
        }
    }
}

// MARK: - Views

struct HangulReadingPromptView: View {
    let prompt: HangulReadingPrompt

    var body: some View {
        VStack(spacing: 12) {
            PromptCaption(text: prompt.stage == .realWords ? "READ THE WORD" : "HOW DO YOU READ IT?")
            Text(prompt.text)
                .font(.system(size: prompt.text.count > 1 ? 96 : 140, weight: .bold))
                .foregroundStyle(Subject.korean.gradient)
                .shadow(color: Theme.pink.opacity(0.3), radius: 12, y: 6)
                .lineLimit(1).minimumScaleFactor(0.4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How do you read \(prompt.text)?")
    }
}

struct HangulReadingAnswerView: View {
    let prompt: HangulReadingPrompt

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(prompt.text).font(.system(size: 56, weight: .bold))
                    .foregroundStyle(Subject.korean.gradient)
                    .lineLimit(1).minimumScaleFactor(0.5)
                SpeakButton(text: prompt.text)
            }
            Text(prompt.romanization)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .accessibilityIdentifier("hangulRomanization")
            if let note {
                Text(note).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let entry = prompt.entry {
                Text(entry.meaningText).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            }
            Text(prompt.stage.title).font(.caption.weight(.heavy)).tracking(2).foregroundStyle(.tertiary)
        }
    }

    /// What the letter is, plus the rules learners trip over.
    private var note: String? {
        switch prompt.stage {
        case .basicConsonants where prompt.jamo == "ㅇ":
            return "ㅇ is silent at the start of a syllable"
        case .basicConsonants, .aspiratedTense:
            return prompt.jamo.map { "\($0) + ㅏ" }
        case .basicVowels, .complexVowels:
            return prompt.jamo.map { "ㅇ (silent) + \($0)" }
        case .batchim:
            return "Final consonants sound as k, n, t, l, m, p or ng"
        case .syllables, .realWords:
            return nil
        }
    }
}

/// 🔊 button that speaks Korean text.
struct SpeakButton: View {
    let text: String
    var label = "Play pronunciation"
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button {
            env.speech.speak(text, rate: env.settings.speechRate)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Subject.korean.gradient, in: Circle())
                .shadow(color: Theme.pink.opacity(0.35), radius: 6, y: 3)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(PressableStyle(scale: 0.88))
        .accessibilityLabel(label)
        .accessibilityIdentifier("speakButton")
    }
}

struct HangulReadingOptionsSection: View {
    @Binding var options: HangulReadingOptions
    let realWordCount: Int

    private var stages: [HangulReadingOptions.Stage] {
        HangulReadingOptions.Stage.allCases.filter { $0 != .realWords || realWordCount > 0 }
    }

    var body: some View {
        Section {
            ForEach(stages, id: \.self) { stage in
                Toggle(isOn: Binding(
                    get: { options.stages.contains(stage) },
                    set: { on in
                        if on { options.stages.insert(stage) } else if options.stages.count > 1 { options.stages.remove(stage) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.title)
                        Text(stage == .realWords ? "\(realWordCount) short words from your Korean decks" : stage.subtitle)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("hangulStage.\(stage.rawValue)")
            }
            Stepper("New per session: \(options.newPerSession)", value: $options.newPerSession, in: 1...30)
                .accessibilityIdentifier("hangulNewPerSessionStepper")
        } header: {
            Text("Stages")
        } footer: {
            Text("New cards are introduced in stage order, a few per session.")
        }
    }
}

/// Every letter and syllable of the enabled stages, coloured by error rate.
struct HangulStatsGrid: View {
    let deck: HangulReadingDeck
    let stats: [ItemKey: ItemStats]
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let enabled = env.initialConfig(for: deck).options.hangulReading?.stages ?? []
        // Enabled stages, plus any stage practised before.
        let shown = HangulReadingOptions.Stage.allCases.filter { stage in
            stage != .realWords && (enabled.contains(stage) || deck.prompts(for: stage).contains { stats[HangulReadingDeck.itemKey($0)] != nil })
        }
        ForEach(shown, id: \.self) { stage in
            Section(stage.title) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 38), spacing: 4)], spacing: 4) {
                    ForEach(deck.prompts(for: stage), id: \.self) { p in
                        cell(p)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func cell(_ p: HangulReadingPrompt) -> some View {
        let s = stats[HangulReadingDeck.itemKey(p)]
        let seen = (s?.attempts ?? 0) > 0
        let fill: Color = seen ? Color(hue: 0.33 * (1 - min(max(s!.ewmaError, 0), 1)), saturation: 0.7, brightness: 0.85) : Color.gray.opacity(0.15)
        return Text(p.text)
            .font(.system(size: 18, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 38)
            .foregroundStyle(seen ? Color.white : Color.secondary)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(seen ? "\(p.text), \(Fmt.percent(s?.accuracy)) correct" : "\(p.text), not practised")
    }
}

extension Binding where Value == DeckOptions {
    var hangulReadingOptions: Binding<HangulReadingOptions> {
        Binding<HangulReadingOptions>(get: { wrappedValue.hangulReading ?? HangulReadingOptions() }, set: { wrappedValue = .hangulReading($0) })
    }
}

#Preview("Hangul reading") {
    let deck = HangulReadingDeck()
    let p = deck.prompts(for: .batchim)[3]
    VStack(spacing: 40) {
        HangulReadingPromptView(prompt: p)
        HangulReadingAnswerView(prompt: p)
    }
    .padding()
    .environment(AppEnvironment.preview())
}

#Preview("Stats grid, dark") {
    let deck = HangulReadingDeck()
    let stats: [ItemKey: ItemStats] = Dictionary(uniqueKeysWithValues: deck.prompts(for: .basicVowels).enumerated().map { i, p in
        let key = HangulReadingDeck.itemKey(p)
        return (key, ItemStats(itemKey: key, deckID: deck.id, attempts: 4, correctCount: 4 - i % 4, ewmaError: Double(i % 4) / 4))
    })
    List { HangulStatsGrid(deck: deck, stats: stats) }
        .environment(AppEnvironment.preview())
        .preferredColorScheme(.dark)
}
