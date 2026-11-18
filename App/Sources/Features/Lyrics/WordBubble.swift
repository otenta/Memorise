import MemoriseCore
import SwiftUI

/// The bubble above a tapped word: meaning, speaker and Add to deck (PLAN_M6 §4.8, L7).
struct WordBubble: View {
    let token: LyricToken
    let state: GlossState
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
                Text(text).font(.title3.weight(.bold))
                if case let .deck(entry, _, _) = state, entry.hangul != text {
                    Text("→ \(entry.hangul)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            meaning
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
        .frame(minWidth: 220, maxWidth: 300, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lyrics.bubble")
    }

    @ViewBuilder private var meaning: some View {
        switch state {
        case let .deck(entry, deckTitle, _):
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.meaningText).font(.body)
                Text("In: \(deckTitle)").font(.caption).foregroundStyle(.secondary)
            }
        case let .auto(gloss):
            VStack(alignment: .leading, spacing: 2) {
                Text(gloss).font(.body)
                Text("Auto-translated").font(.caption).foregroundStyle(.secondary)
            }
        case .pending:
            HStack(spacing: 8) {
                ProgressView()
                Text("Translating…").font(.subheadline).foregroundStyle(.secondary)
            }
        case .needsLanguagePack:
            Text("Meaning unavailable. Download Korean in Settings → Apps → Translate.")
                .font(.footnote).foregroundStyle(.secondary)
        case .noWordMeaning:
            Text("No single-word meaning.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

#Preview("Bubble") {
    VStack(spacing: 20) {
        WordBubble(token: .word(text: "보고", range: 0..<2), state: .pending, onSpeak: {}, onAdd: {})
        WordBubble(token: .word(text: "너를", range: 0..<2), state: .auto("you"), onSpeak: {}, onAdd: {})
        WordBubble(token: .word(text: "몰라", range: 0..<2), state: .needsLanguagePack, onSpeak: {}, onAdd: {})
    }
    .glassCard()
    .padding()
}
