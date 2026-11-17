import MemoriseCore
import SwiftUI

/// "책 + (topic)" → 책은 / 책는 — `ko.particles` (PLAN_M4 M4-5).
struct ParticlesUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.particle else { return AnyView(EmptyView()) }
        return AnyView(ParticlePromptView(prompt: p))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.particle else { return AnyView(EmptyView()) }
        return AnyView(ParticleAnswerView(prompt: p))
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.particle else { return card.key.raw }
        return "\(p.particle.pair) · \(p.rule)"
    }

    /// Choice only: two buttons, the right and the wrong form.
    func supportedInputModes(deck: any Deck) -> [InputMode] { [.choice] }

    func choices(for card: Card, options: DeckOptions, using rng: inout SplitMix64) -> [AnswerChoice]? {
        guard let p = card.particle else { return nil }
        let pair = [AnswerChoice(label: p.correct, isCorrect: true), AnswerChoice(label: p.wrong, isCorrect: false)]
        return Bool.random(using: &rng) ? pair : pair.reversed()
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(ParticleOptionsSection(options: options.particleOptions))
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(CardStatsList(deck: deck, stats: stats) { label($0, settings: AppSettings.statsLabels) })
    }

    /// Speaks the correct form.
    func onReveal(_ card: Card, ctx: DeckUIContext) {
        guard let p = card.particle, ctx.env.speech.hasKoreanVoice, ctx.settings.autoPlayPronunciation else { return }
        ctx.env.speech.speak(p.correct, rate: ctx.settings.speechRate)
    }
}

// MARK: - Views

struct ParticlePromptView: View {
    let prompt: ParticlePrompt

    var body: some View {
        VStack(spacing: 14) {
            PromptCaption(text: "ADD THE PARTICLE")
            HStack(spacing: 10) {
                KoreanHeadline(text: prompt.noun.hangul, role: .prompt)
                Text("+").font(.system(size: 40, weight: .bold)).foregroundStyle(.secondary)
            }
            Text(prompt.particle.title)
                .font(.title2.weight(.bold))
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(.secondary.opacity(0.12), in: Capsule())
            Text(prompt.noun.meaningText).font(.callout).foregroundStyle(.secondary)
                .lineLimit(2).multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prompt.noun.hangul) plus the \(prompt.particle.title) particle")
    }
}

struct ParticleAnswerView: View {
    let prompt: ParticlePrompt

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                KoreanHeadline(
                    text: prompt.noun.hangul, role: .answer, style: AnyShapeStyle(.primary),
                    tail: prompt.particle.form(after: prompt.ending)
                )
                .layoutPriority(1)
                SpeakButton(text: prompt.correct)
            }
            Text(prompt.rule).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            Text("\(prompt.noun.hangul) = \(prompt.noun.meaningText)")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("\(prompt.particle.title.uppercased()) · \(prompt.particle.pair)")
                .font(.caption.weight(.heavy)).tracking(2).foregroundStyle(.tertiary)
        }
        .accessibilityIdentifier("particleAnswer")
    }
}

struct ParticleOptionsSection: View {
    @Binding var options: ParticleOptions

    var body: some View {
        Section {
            ForEach(Particle.allCases, id: \.self) { particle in
                Toggle(isOn: Binding(
                    get: { options.particles.contains(particle) },
                    set: { on in
                        if on { options.particles.insert(particle) } else if options.particles.count > 1 { options.particles.remove(particle) }
                    }
                )) {
                    HStack {
                        Text(particle.pair).font(.headline)
                        Text(particle.title).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("particleToggle.\(particle.rawValue)")
            }
        } header: {
            Text("Particles")
        }
        Section {
            Picker("Nouns from", selection: $options.nounSource) {
                ForEach(ParticleOptions.NounSource.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("particleNounSourcePicker")
        } footer: {
            Text("Each card picks a random noun with the right ending, so you see a new word most times.")
        }
    }
}

extension Binding where Value == DeckOptions {
    var particleOptions: Binding<ParticleOptions> {
        Binding<ParticleOptions>(get: { wrappedValue.particles ?? ParticleOptions() }, set: { wrappedValue = .particles($0) })
    }
}

private let previewNoun = VocabEntry(id: "ko.core.0100", hangul: "책", romanization: "chaek", meanings: ["book"], pos: "noun", rank: 100)

#Preview("Particles") {
    let p = ParticlePrompt(particle: .topic, ending: .batchim, noun: previewNoun)
    VStack(spacing: 40) {
        ParticlePromptView(prompt: p)
        ParticleAnswerView(prompt: p)
    }
    .padding()
    .environment(AppEnvironment.preview())
}

#Preview("Particles, dark") {
    ParticlePromptView(prompt: ParticlePrompt(particle: .direction, ending: .rieul, noun: VocabEntry(id: "ko.core.0101", hangul: "물", romanization: "mul", meanings: ["water"], pos: "noun", rank: 101)))
        .padding()
        .preferredColorScheme(.dark)
}
