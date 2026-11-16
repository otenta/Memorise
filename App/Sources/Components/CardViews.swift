import MemoriseCore
import SwiftUI

// MARK: - Dispatch

/// Prompt side of any card.
struct CardPromptView: View {
    let card: Card
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        switch card.content {
        case let .fretboardNote(p): FretboardPromptView(prompt: p, settings: env.settings)
        case let .vocab(p): VocabPromptView(prompt: p)
        }
    }
}

/// Answer side of any card.
struct CardAnswerView: View {
    let card: Card
    let maxFret: Int
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        switch card.content {
        case let .fretboardNote(p): FretboardAnswerView(prompt: p, maxFret: maxFret, settings: env.settings)
        case let .vocab(p): VocabAnswerView(prompt: p)
        }
    }
}

// MARK: - Fretboard

struct FretboardPromptView: View {
    let prompt: FretboardNotePrompt
    let settings: AppSettings
    private static let deck = FretboardNotesDeck()

    var body: some View {
        let display = settings.musicDisplay
        VStack(spacing: 12) {
            Text("Play").font(.title3).foregroundStyle(.secondary)
            Text(Self.deck.noteText(prompt, settings: display))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.4)
            Text("on \(Self.deck.stringText(prompt, settings: display))")
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.deck.promptText(prompt, settings: display))
    }
}

struct FretboardAnswerView: View {
    let prompt: FretboardNotePrompt
    let maxFret: Int
    let settings: AppSettings

    var body: some View {
        let name = prompt.spelling.displayName
        VStack(spacing: 16) {
            Text(NoteFormatter.format(prompt.spelling, settings: settings.musicDisplay))
                .font(.largeTitle.weight(.bold))
            FretboardView(
                maxFret: maxFret,
                marks: prompt.answerFrets.map { FretMark(string: prompt.stringNumber, fret: $0, label: name) },
                highlightedStrings: [prompt.stringNumber],
                leftHanded: settings.leftHanded,
                highEOnTop: settings.highEOnTop
            )
            Text(FretboardNotesDeck.answerText(frets: prompt.answerFrets))
                .font(.title3.weight(.semibold).monospacedDigit())
        }
    }
}

// MARK: - Vocab

struct VocabPromptView: View {
    let prompt: VocabPrompt

    var body: some View {
        let e = prompt.entry
        VStack(spacing: 12) {
            switch prompt.direction {
            case .koToEn:
                Text(e.hangul)
                    .font(.system(size: 64, weight: .semibold))
                    .lineLimit(2).minimumScaleFactor(0.4)
                    .multilineTextAlignment(.center)
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

struct VocabAnswerView: View {
    let prompt: VocabPrompt
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let e = prompt.entry
        let settings = env.settings
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Text(e.hangul).font(.system(size: 48, weight: .semibold))
                    .lineLimit(2).minimumScaleFactor(0.5)
                speakButton(e.hangul, label: "Play pronunciation")
            }
            if settings.showRomanization {
                Text(e.romanization).font(.title3).foregroundStyle(.secondary)
            }
            Text(e.meaningText).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(e.pos).font(.subheadline).foregroundStyle(.secondary)
            if let ex = e.example {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text(ex.ko).font(.body)
                        speakButton(ex.ko, label: "Play example")
                    }
                    Text(ex.en).font(.callout).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
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
            Image(systemName: "speaker.wave.2.fill").font(.title3).frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityIdentifier("speakButton")
    }
}

// MARK: - Previews

private let previewEntry = VocabEntry(
    id: "ko.core.0001", hangul: "사랑", romanization: "sarang", meanings: ["love"], pos: "noun", rank: 1,
    example: .init(ko: "사랑해요.", en: "I love you.")
)

#Preview("Fretboard prompt") {
    let p = FretboardNotePrompt(stringNumber: 6, pitchClass: PitchClass(9), spelling: NoteSpelling(.a), answerFrets: [5])
    return FretboardPromptView(prompt: p, settings: AppSettings()).padding()
}

#Preview("Fretboard answer") {
    let p = FretboardNotePrompt(stringNumber: 6, pitchClass: PitchClass(9), spelling: NoteSpelling(.a), answerFrets: [5, 17])
    return FretboardAnswerView(prompt: p, maxFret: 22, settings: AppSettings()).padding()
}

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
