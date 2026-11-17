import MemoriseCore
import SwiftUI

/// "Fifth above D?" — `music.theory.circle`.
struct CircleOfFifthsUI: DeckUI {
    func prompt(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.circle else { return AnyView(EmptyView()) }
        return AnyView(VStack(spacing: 12) {
            PromptCaption(text: "CIRCLE OF FIFTHS")
            Text(p.question.title + " of").font(.title2.weight(.semibold))
            HeroText(text: p.from.displayName + (p.fromIsMinor ? "m" : ""), size: 96)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(p.question.title) of \(p.from.spokenName)\(p.fromIsMinor ? " minor" : "")"))
    }

    func answer(_ card: Card, ctx: DeckUIContext) -> AnyView {
        guard let p = card.circle else { return AnyView(EmptyView()) }
        return AnyView(VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HeroText(text: p.answer.displayName + (p.answerIsMinor ? "m" : ""), size: 72)
                if let exact = p.exactSpelling {
                    Text("(= \(exact.displayName))").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            CircleOfFifthsView(
                highlight: .init(index: p.fromIndex, minor: p.fromIsMinor),
                secondary: .init(index: p.answerIndex, minor: p.answerIsMinor)
            )
            .frame(maxWidth: 260)
            Text(p.question.rule).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        })
    }

    func label(_ card: Card, settings: AppSettings) -> String {
        guard let p = card.circle else { return card.key.raw }
        return "\(p.question.title) of \(p.from.displayName)\(p.fromIsMinor ? "m" : "")"
    }

    func setupSection(_ options: Binding<DeckOptions>, deck: any Deck) -> AnyView {
        AnyView(Section("Questions") {
            OptionChips(all: CircleQuestion.allCases, selection: options.circleOptions.questions, label: \.title, minWidth: 140, identifier: "circleQuestionChip")
        })
    }

    func statsSection(deck: any Deck, stats: [ItemKey: ItemStats]) -> AnyView? {
        AnyView(CardStatsList(deck: deck, stats: stats) { label($0, settings: AppSettings.statsLabels) })
    }

    /// The two roots, one after the other.
    func playableNotes(_ card: Card) -> [NoteEvent] {
        guard let p = card.circle else { return [] }
        let a = 48 + p.from.pitchClass.value, b = 48 + p.answer.pitchClass.value
        return [(a, 0), (b < a ? b + 12 : b, 0.6)]
    }
}

#Preview {
    CircleOfFifthsView(highlight: .init(index: 0), secondary: .init(index: 0, minor: true)).padding()
}
