import MemoriseCore
import SwiftUI

/// Korean vocabulary decks.
struct VocabUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.vocab else { return AnyView(EmptyView()) }
        if p.direction == .listen { return AnyView(ListeningPromptView(prompt: p, ctx: ctx)) }
        return AnyView(VocabPromptView(prompt: p))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.vocab else { return AnyView(EmptyView()) }
        return AnyView(VocabAnswerView(prompt: p))
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.vocab else { return card.key.raw }
        switch p.direction {
        case .koToEn: return "\(p.entry.hangul) → \(p.entry.meaningText)"
        case .enToKo: return "\(p.entry.meaningText) → \(p.entry.hangul)"
        case .listen: return "🔊 \(p.entry.hangul) → \(p.entry.meaningText)"
        }
    }

    func supportedInputModes(deck: any Deck) -> [InputMode] { [.touch, .typed] }

    /// ko→en / listen: type the meaning. en→ko: type the Hangul.
    func typedAnswer(for card: Card) -> TypedAnswerSpec? {
        guard let p = card.vocab else { return nil }
        let e = p.entry
        switch p.direction {
        case .koToEn, .listen:
            return TypedAnswerSpec(expected: e.meanings, kind: .english)
        case .enToKo:
            // Patterns: sentence practice — the prompt is the first example's English.
            if e.partOfSpeech == .pattern, let ex = e.allExamples.first {
                return TypedAnswerSpec(expected: [ex.ko], kind: .hangul)
            }
            return TypedAnswerSpec(expected: [e.hangul], kind: .hangul, isPredicate: e.partOfSpeech?.isPredicate ?? false)
        }
    }

    /// Listening prompts start the timer when the audio ends.
    func managesPromptTiming(_ card: Card) -> Bool { card.vocab?.direction == .listen }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(VocabOptionsSection(options: options.vocabOptions, allTags: (deck as? VocabDeck)?.allTags ?? []))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        guard let vocab = deck as? VocabDeck else { return nil }
        return AnyView(WeakestWordsSection(deck: vocab, stats: stats))
    }

    /// Drops tag filters the deck no longer has.
    func sanitize(_ options: DeckOptions, deck: any Deck) -> DeckOptions {
        guard case let .vocab(o) = options, let vocab = deck as? VocabDeck else { return options }
        return .vocab(o.sanitized(allTags: vocab.allTags))
    }

    /// Auto-plays the pronunciation (or asks once for a Korean voice).
    func onReveal(_ card: Card, ctx: DeckUIContext) {
        guard let vocab = card.vocab else { return }
        let env = ctx.env
        guard env.speech.hasKoreanVoice else {
            if !env.settings.koreanVoiceHintShown {
                env.settings.koreanVoiceHintShown = true
                ctx.requestVoiceHint()
            }
            return
        }
        // Listening: the user has just heard it; don't replay over the reveal.
        if vocab.direction != .listen, env.settings.autoPlayPronunciation, ctx.options.vocab?.autoPlayAudio ?? true {
            env.speech.speak(vocab.entry.spokenText, rate: env.settings.speechRate)
        }
    }
}

// MARK: - Views

struct VocabPromptView: View {
    let prompt: VocabPrompt

    var body: some View {
        let e = prompt.entry
        VStack(spacing: 12) {
            switch prompt.direction {
            case .koToEn, .listen:
                Text(e.hangul)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(Subject.korean.gradient)
                    .shadow(color: Theme.pink.opacity(0.3), radius: 12, y: 6)
                    .lineLimit(2).minimumScaleFactor(0.4)
                    .multilineTextAlignment(.center)
            case .enToKo where e.partOfSpeech == .pattern && !e.allExamples.isEmpty:
                // Sentence practice: say the first example in Korean.
                PromptCaption(text: "SAY IT IN KOREAN · \(e.hangul)")
                Text(e.allExamples[0].en)
                    .font(.system(size: 32, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
            case .enToKo:
                Text(e.meaningText)
                    .font(.system(size: 40, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                Text(e.pos).font(.title3).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Listening prompt: speaks the word, no text. The timer starts when the audio ends.
struct ListeningPromptView: View {
    let prompt: VocabPrompt
    let ctx: DeckUIContext
    @State private var playing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 18) {
            PromptCaption(text: "LISTEN · WHAT DOES IT MEAN?")
            Button(action: replay) {
                Image(systemName: "waveform")
                    .font(.system(size: 76, weight: .bold))
                    .foregroundStyle(Subject.korean.gradient)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: playing && !reduceMotion)
                    .frame(width: 160, height: 160)
                    .background(.thinMaterial, in: Circle())
                    .shadow(color: Theme.pink.opacity(0.3), radius: 12, y: 6)
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .accessibilityLabel("Play again")
            .accessibilityIdentifier("listenReplayButton")
            Text("Tap to hear it again").font(.footnote).foregroundStyle(.secondary)
        }
        .task(id: ctx.presentationID) {
            playing = true
            let done = ctx.promptDidAppear
            ctx.env.speech.speak(prompt.entry.spokenText, rate: ctx.settings.speechRate) {
                playing = false
                done()
            }
        }
    }

    /// Replay doesn't reset the timer.
    private func replay() {
        playing = true
        ctx.env.speech.speak(prompt.entry.spokenText, rate: ctx.settings.speechRate) { playing = false }
    }
}

struct VocabAnswerView: View {
    let prompt: VocabPrompt
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let e = prompt.entry
        let settings = env.settings
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(e.hangul).font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Subject.korean.gradient)
                    .lineLimit(2).minimumScaleFactor(0.5)
                // Patterns: each example has its own 🔊; the headword itself isn't speakable.
                if e.partOfSpeech != .pattern { speakButton(e.hangul, label: "Play pronunciation") }
            }
            if settings.showRomanization, !e.romanization.isEmpty {
                Text(e.romanization).font(.title3).foregroundStyle(.secondary)
            }
            Text(e.meaningText).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(e.pos).font(.subheadline).foregroundStyle(.secondary)
            ForEach(e.allExamples, id: \.self) { ex in
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text(ex.ko).font(.body)
                        speakButton(ex.ko, label: "Play example")
                    }
                    Text(ex.en).font(.callout).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if let notes = e.notes {
                Text(notes).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private func speakButton(_ text: String, label: String) -> some View {
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

struct VocabOptionsSection: View {
    @Binding var options: VocabOptions
    let allTags: [String]
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let voice = env.speech.hasKoreanVoice
        Section {
            Picker("Direction", selection: $options.direction) {
                Text("Korean → English").tag(VocabOptions.DirectionOption.koToEn)
                Text("English → Korean").tag(VocabOptions.DirectionOption.enToKo)
                Text("Both").tag(VocabOptions.DirectionOption.both)
                if voice {
                    Text("Listening 🔊").tag(VocabOptions.DirectionOption.listening)
                    Text("All three").tag(VocabOptions.DirectionOption.allThree)
                }
            }
            .accessibilityIdentifier("vocabDirectionPicker")
            Stepper("New words per session: \(options.newPerSession)", value: $options.newPerSession, in: 0...30)
            Toggle("Auto-play pronunciation", isOn: $options.autoPlayAudio)
        } header: {
            Text("Words")
        } footer: {
            if !voice {
                Text("Listening cards need a Korean voice: Settings → Accessibility → Spoken Content → Voices → Korean.")
            } else if options.direction.includesListening {
                Text("Listening cards play the word; the timer starts when it finishes.")
            }
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

private let previewEntry = VocabEntry(
    id: "ko.core.0001", hangul: "사랑", romanization: "sarang", meanings: ["love"], pos: "noun", rank: 1,
    example: .init(ko: "사랑해요.", en: "I love you.")
)

#Preview("Vocab ko→en") {
    VStack(spacing: 40) {
        VocabPromptView(prompt: VocabPrompt(entry: previewEntry, direction: .koToEn))
        VocabAnswerView(prompt: VocabPrompt(entry: previewEntry, direction: .koToEn))
    }
    .padding()
    .environment(AppEnvironment.preview())
}

#Preview("Vocab en→ko, dark") {
    VocabPromptView(prompt: VocabPrompt(entry: previewEntry, direction: .enToKo))
        .padding()
        .preferredColorScheme(.dark)
}

extension VocabEntry {
    /// What TTS reads for the headword: patterns (`-(으)ㄹ 수 있다`) read their first example sentence instead.
    var spokenText: String {
        partOfSpeech == .pattern ? (allExamples.first?.ko ?? hangul) : hangul
    }
}
