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
                Text(text).font(.title3.weight(.bold))
                if case let .deck(entry, _, _) = state, entry.hangul != text {
                    Text("→ \(entry.hangul)").font(.subheadline).foregroundStyle(.secondary)
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
        .frame(minWidth: 220, maxWidth: 320, alignment: .leading)
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
            Text("No single-word meaning: see the line below.").font(.footnote).foregroundStyle(.secondary)
        }
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
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Translating line…").font(.subheadline).foregroundStyle(.secondary)
                    }
                case .needsLanguagePack:
                    Text("Meaning unavailable. Download Korean in Settings → Apps → Translate.")
                        .font(.footnote).foregroundStyle(.secondary)
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

#Preview("Bubble") {
    VStack(spacing: 20) {
        WordBubble(token: .word(text: "보고", range: 0..<2), state: .pending, line: .pending, onSpeak: {}, onAdd: {})
        WordBubble(
            token: .word(text: "너를", range: 0..<2), state: .auto("you"),
            line: .genius("I see you and I forget everything"), onSpeak: {}, onAdd: {})
        WordBubble(
            token: .word(text: "몰라", range: 0..<2), state: .noWordMeaning,
            line: .auto("I don't know, I don't know"), onSpeak: {}, onAdd: {})
        WordBubble(token: .word(text: "몰라", range: 0..<2), state: .needsLanguagePack, line: .needsLanguagePack, onSpeak: {}, onAdd: {})
    }
    .glassCard()
    .padding()
}
