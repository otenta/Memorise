import MemoriseCore
import SwiftUI

/// The bubble above a tapped word: meaning, speaker and Add to deck (PLAN_M6 §4.8, L7).
struct WordBubble: View {
    let token: LyricToken
    let state: GlossState
    let line: LineGloss
    let onSpeak: () -> Void
    let onAdd: () -> Void

    private var text: String {
        switch token {
        case let .word(t, _): t
        case let .phrase(t, _, _): t
        case let .plain(t): t
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(text).font(.title3.weight(.bold)).lineLimit(2).minimumScaleFactor(0.7)
                if case let .deck(entry, _, _) = state, entry.hangul != text {
                    Text("→ \(entry.hangul)").font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            meaning
            lineSection
            HStack(spacing: 10) {
                Button(action: onSpeak) {
                    Image(systemName: "speaker.wave.2.fill")
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel("Pronounce")
                .accessibilityIdentifier("lyrics.bubble.speak")

                Button(action: onAdd) {
                    Label("Add to deck", systemImage: "plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Subject.korean.gradient, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("lyrics.bubble.add")
            }
        }
        .padding(16)
        // A fixed width, then the full wrapped height, so the popover measures the real size (PLAN_R11 P-9).
        .frame(width: 300, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeOut(duration: 0.15), value: state)
        .animation(.easeOut(duration: 0.15), value: line)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lyrics.bubble")
    }

    @ViewBuilder private var meaning: some View {
        switch state {
        case let .deck(entry, deckTitle, _):
            VStack(alignment: .leading, spacing: 2) {
                wrapping(Text(entry.meaningText).font(.body))
                wrapping(Text("In: \(deckTitle)").font(.caption).foregroundStyle(.secondary))
            }
        case let .auto(gloss):
            VStack(alignment: .leading, spacing: 2) {
                wrapping(Text(gloss).font(.body))
                Text("Auto-translated").font(.caption).foregroundStyle(.secondary)
            }
        case .pending:
            // Same shape as the result, so the bubble doesn't jump when the meaning arrives.
            VStack(alignment: .leading, spacing: 2) {
                Text("Translating this word").font(.body)
                Text("Auto-translated").font(.caption)
            }
            .redacted(reason: .placeholder)
            .accessibilityLabel("Translating")
        case .needsLanguagePack:
            wrapping(Text("Meaning unavailable. Download Korean in Settings → Apps → Translate.")
                .font(.footnote).foregroundStyle(.secondary))
        case .noWordMeaning:
            wrapping(Text("No single-word meaning: see the line below.").font(.footnote).foregroundStyle(.secondary))
        }
    }

    private func wrapping(_ text: some View) -> some View {
        text.fixedSize(horizontal: false, vertical: true)
    }

    /// What the whole line means (P-4), so a weak word translation still gives the sense.
    @ViewBuilder private var lineSection: some View {
        if line != .unavailable {
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("Line").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                switch line {
                case let .genius(text):
                    lineText(text, caption: "Translation: Genius")
                case let .auto(text):
                    lineText(text, caption: "Auto-translated")
                case .pending:
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Translating this line, one moment while the meaning arrives").font(.body)
                        Text("Auto-translated").font(.caption)
                    }
                    .redacted(reason: .placeholder)
                    .accessibilityLabel("Translating line")
                case .needsLanguagePack:
                    wrapping(Text("Meaning unavailable. Download Korean in Settings → Apps → Translate.")
                        .font(.footnote).foregroundStyle(.secondary))
                case .unavailable:
                    EmptyView()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("lyrics.bubble.line")
        }
    }

    private func lineText(_ text: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
private struct BubblePreviews: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                WordBubble(
                    token: .word(text: "사랑해", range: 0..<3),
                    state: .deck(
                        VocabEntry(id: "ko.core.0001", hangul: "사랑하다", romanization: "saranghada",
                                   meanings: ["to love", "to be deeply fond of someone", "to cherish and care for"],
                                   pos: "verb", rank: 1),
                        deckTitle: "Love and feelings, level 2", matchedForm: "사랑해"),
                    line: .genius("I love you more than I can say, and I will keep loving you through every season that passes"),
                    onSpeak: {}, onAdd: {})
                WordBubble(token: .word(text: "보고", range: 0..<2), state: .pending, line: .pending, onSpeak: {}, onAdd: {})
                WordBubble(
                    token: .word(text: "몰라", range: 0..<2), state: .noWordMeaning,
                    line: .auto("I don't know, I don't know, I really don't know why"), onSpeak: {}, onAdd: {})
                WordBubble(token: .word(text: "몰라", range: 0..<2), state: .needsLanguagePack, line: .needsLanguagePack, onSpeak: {}, onAdd: {})
            }
            .glassCard()
            .padding()
        }
    }
}

#Preview("Bubbles") { BubblePreviews() }

#Preview("Bubbles · Dynamic Type XL") { BubblePreviews().dynamicTypeSize(.xxxLarge) }
#endif
