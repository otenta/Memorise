import MemoriseCore
import SwiftUI

/// "가다 · past polite" → 갔어요 — `ko.conjugation` (PLAN_M4 M4-6).
struct ConjugationUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.conjugation else { return AnyView(EmptyView()) }
        return AnyView(ConjugationPromptView(prompt: p))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.conjugation else { return AnyView(EmptyView()) }
        return AnyView(ConjugationAnswerView(prompt: p))
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.conjugation else { return card.key.raw }
        return "\(p.entry.hangul) · \(p.form.title) → \(p.answer)"
    }

    func supportedInputModes(deck: any Deck) -> [InputMode] { [.touch, .typed] }

    /// Spelling is the skill: "close" counts as wrong.
    func typedAnswer(for card: Card) -> TypedAnswerSpec? {
        guard let p = card.conjugation else { return nil }
        return TypedAnswerSpec(expected: [p.answer], kind: .hangul, exactRequired: true)
    }

    /// Never leaves the form set empty.
    func sanitize(_ options: DeckOptions, deck: any Deck) -> DeckOptions {
        guard case var .conjugation(o) = options else { return options }
        if o.forms.isEmpty { o.forms = ConjugationOptions().forms }
        return .conjugation(o)
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(ConjugationOptionsSection(options: options.conjugationOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(CardStatsList(deck: deck, stats: stats) { label($0, settings: AppSettings.statsLabels) })
    }

    /// Speaks the conjugated form.
    func onReveal(_ card: Card, ctx: DeckUIContext) {
        guard let p = card.conjugation else { return }
        let env = ctx.env
        guard env.speech.hasKoreanVoice else {
            if !env.settings.koreanVoiceHintShown {
                env.settings.koreanVoiceHintShown = true
                ctx.requestVoiceHint()
            }
            return
        }
        guard ctx.settings.autoPlayPronunciation else { return }
        env.speech.speak(p.answer, rate: ctx.settings.speechRate)
    }
}

// MARK: - Views

struct ConjugationPromptView: View {
    let prompt: ConjugationPrompt

    var body: some View {
        VStack(spacing: 14) {
            PromptCaption(text: "CONJUGATE")
            Text(prompt.entry.hangul)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(Subject.korean.gradient)
                .shadow(color: Theme.pink.opacity(0.3), radius: 12, y: 6)
                .lineLimit(1).minimumScaleFactor(0.4)
            Text(prompt.form.title)
                .font(.title2.weight(.bold))
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(.secondary.opacity(0.12), in: Capsule())
            Text(prompt.form.ending).font(.callout.weight(.semibold)).foregroundStyle(.tertiary)
            Text(prompt.entry.meaningText).font(.callout).foregroundStyle(.secondary)
                .lineLimit(2).multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prompt.entry.hangul), \(prompt.form.title)")
    }
}

struct ConjugationAnswerView: View {
    let prompt: ConjugationPrompt

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(prompt.answer)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Theme.pink)
                    .lineLimit(1).minimumScaleFactor(0.4)
                SpeakButton(text: prompt.answer)
            }
            Text(prompt.rule).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text("\(prompt.entry.hangul) = \(prompt.entry.meaningText)")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("\(prompt.form.title.uppercased()) · \(prompt.form.ending)")
                .font(.caption.weight(.heavy)).tracking(2).foregroundStyle(.tertiary)
        }
        .accessibilityIdentifier("conjugationAnswer")
    }
}

struct ConjugationOptionsSection: View {
    @Binding var options: ConjugationOptions

    var body: some View {
        Section {
            ForEach(ConjForm.allCases, id: \.self) { form in
                Toggle(isOn: Binding(
                    get: { options.forms.contains(form) },
                    set: { on in
                        if on { options.forms.insert(form) } else if options.forms.count > 1 { options.forms.remove(form) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(form.title.capitalized).font(.headline)
                        Text(form.ending).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("conjFormToggle.\(form.rawValue)")
            }
        } header: {
            Text("Forms")
        }
        Section {
            Picker("Verbs from", selection: $options.source) {
                ForEach(ConjugationOptions.Source.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("conjSourcePicker")
            Stepper("New per session: \(options.newPerSession)", value: $options.newPerSession, in: 1...30)
                .accessibilityIdentifier("conjNewPerSessionStepper")
        } footer: {
            Text("New words come in by frequency. Typed answers must be spelled exactly.")
        }
    }
}

extension Binding where Value == DeckOptions {
    var conjugationOptions: Binding<ConjugationOptions> {
        Binding<ConjugationOptions>(get: { wrappedValue.conjugation ?? ConjugationOptions() }, set: { wrappedValue = .conjugation($0) })
    }
}

private let previewVerb = VocabEntry(id: "ko.core.0033", hangul: "가다", romanization: "gada", meanings: ["to go"], pos: "verb", rank: 33, conj: "regular")

#Preview("Conjugation") {
    let c = Conjugator.conjugate(previewVerb, .pastPolite)!
    let p = ConjugationPrompt(entry: previewVerb, form: .pastPolite, answer: c.text, rule: c.rule, rank: 0)
    VStack(spacing: 40) {
        ConjugationPromptView(prompt: p)
        ConjugationAnswerView(prompt: p)
    }
    .padding()
    .environment(AppEnvironment.preview())
}

#Preview("Conjugation, dark") {
    let verb = VocabEntry(id: "ko.core.0043", hangul: "듣다", romanization: "deutda", meanings: ["to listen"], pos: "verb", rank: 43, conj: "d")
    let c = Conjugator.conjugate(verb, .presentPolite)!
    ConjugationAnswerView(prompt: ConjugationPrompt(entry: verb, form: .presentPolite, answer: c.text, rule: c.rule, rank: 0))
        .padding()
        .environment(AppEnvironment.preview())
        .preferredColorScheme(.dark)
}
