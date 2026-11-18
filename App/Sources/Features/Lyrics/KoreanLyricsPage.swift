import MemoriseCore
import SwiftUI

/// The Hangul page: every line is a flow of tappable words and phrases (PLAN_M6 L7).
struct KoreanLyricsPage: View {
    @Environment(AppEnvironment.self) private var env
    let model: LyricsReaderViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(model.lines) { line in
                    if line.isHeader {
                        Text(line.text)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 14)
                    } else if line.tokens.isEmpty {
                        Color.clear.frame(height: 8)
                    } else {
                        LyricFlowLayout(spacing: 7, rowSpacing: 4) {
                            ForEach(Array(line.tokens.enumerated()), id: \.offset) { _, token in
                                LyricTokenView(token: token, line: line, model: model)
                            }
                        }
                    }
                }
                if let footer = model.footer {
                    Text(footer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                        .accessibilityIdentifier("lyrics.footer")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .refreshable { await model.load(force: true) }
    }
}

/// One token: plain text, or a button that opens the bubble.
private struct LyricTokenView: View {
    @Environment(AppEnvironment.self) private var env
    let token: LyricToken
    let line: ReaderLine
    let model: LyricsReaderViewModel
    @State private var shown = false

    var body: some View {
        switch token {
        case let .plain(text):
            Text(text).font(.title3).foregroundStyle(.secondary)
        case let .word(text, _):
            tappable(text, phrase: false)
        case let .phrase(text, _, _):
            tappable(text, phrase: true)
        }
    }

    private func tappable(_ text: String, phrase: Bool) -> some View {
        let known = model.isKnown(token)
        return Button {
            shown = true
        } label: {
            Text(text)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .underline(known, pattern: .dot, color: Theme.pink)
                .padding(.horizontal, phrase ? 6 : 0)
                .padding(.vertical, 2)
                .background {
                    if phrase { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.pink.opacity(0.16)) }
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityHint("Shows the meaning")
        .popover(isPresented: $shown, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            WordBubble(
                token: token, state: model.meaning(for: token),
                onSpeak: { env.speech.speak(text, rate: env.settings.speechRate) },
                onAdd: {
                    shown = false
                    model.adding = model.candidate(for: token, in: line)
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }
}
