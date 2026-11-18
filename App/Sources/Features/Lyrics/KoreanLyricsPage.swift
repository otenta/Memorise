import MemoriseCore
import SwiftUI

/// The Hangul page: every line is a flow of tappable words and phrases (PLAN_M6 L7).
struct KoreanLyricsPage: View {
    @Environment(AppEnvironment.self) private var env
    let model: LyricsReaderViewModel
    /// The token whose bubble is open. Held here so a token view keeps no state of its own.
    @State private var selected: SelectedToken?
    /// Global y of the last tap, recorded by the token's spatial gesture. `nil` for a VoiceOver activation.
    @State private var tapY: CGFloat?
    /// The page's frame in the window, measured once here (not per token).
    @State private var pageFrame: CGRect = .zero

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
                            ForEach(line.tokens) { token in
                                let mine = SelectedToken(line: line.id, token: token.id, edge: .bottom)
                                let isSelected = selected?.line == mine.line && selected?.token == mine.token
                                LyricTokenView(
                                    readerToken: token,
                                    arrowEdge: isSelected ? selected?.edge ?? .bottom : .bottom,
                                    isPresented: Binding(
                                        get: { isSelected },
                                        set: { if !$0, isSelected { selected = nil } }
                                    ),
                                    onTapAt: { tapY = $0 },
                                    onOpen: { open(mine) }
                                ) {
                                    bubble(for: token, in: line)
                                }
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pageFrame = $0 }
        .refreshable { await model.load(force: true) }
    }

    /// Opens the bubble below the word when it was tapped in the top 45 % of the page, above it otherwise (P-9).
    /// Deferred one turn so the spatial tap, which may land after the button action, has recorded its position.
    private func open(_ token: SelectedToken) {
        DispatchQueue.main.async {
            var edge = Edge.bottom
            if let tapY, pageFrame.height > 0, tapY - pageFrame.minY < 0.45 * pageFrame.height { edge = .top }
            tapY = nil
            selected = SelectedToken(line: token.line, token: token.token, edge: edge)
        }
    }

    /// Read only when the popover opens, so the token views never observe the gloss store.
    private func bubble(for token: ReaderToken, in line: ReaderLine) -> some View {
        WordBubble(
            token: token.token, state: model.meaning(for: token.token), line: model.lineMeaning(for: line),
            onSpeak: { env.speech.speak(token.text, rate: env.settings.speechRate) },
            onAdd: {
                selected = nil
                model.adding = model.candidate(for: token.token, in: line)
            }
        )
        .presentationCompactAdaptation(.popover)
    }
}

/// Which token's bubble is open: line id + token id.
private struct SelectedToken: Equatable {
    let line: Int
    let token: Int
    /// The popover's arrow edge: `.top` puts the bubble below the word.
    let edge: Edge
}

/// One token: plain text, or a button that opens the bubble. Reads nothing observable (PLAN_R10 LA3).
private struct LyricTokenView<Bubble: View>: View {
    let readerToken: ReaderToken
    let arrowEdge: Edge
    @Binding var isPresented: Bool
    let onTapAt: (CGFloat) -> Void
    let onOpen: () -> Void
    @ViewBuilder let bubble: () -> Bubble

    var body: some View {
        if readerToken.isTappable {
            tappable(isPhrase: isPhrase)
        } else {
            Text(readerToken.text).font(.title3).foregroundStyle(.secondary)
        }
    }

    private var isPhrase: Bool {
        if case .phrase = readerToken.token { return true }
        return false
    }

    private func tappable(isPhrase phrase: Bool) -> some View {
        let underline: Color = readerToken.isDeckHit ? Theme.pink : .secondary
        return Button {
            onOpen()
        } label: {
            Text(readerToken.text)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .underline(true, pattern: .dot, color: underline)
                .padding(.horizontal, phrase ? 6 : 0)
                .padding(.vertical, 2)
                .background {
                    if phrase { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.pink.opacity(0.16)) }
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { onTapAt($0.location.y) })
        .accessibilityHint("Shows the meaning")
        .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: arrowEdge, content: bubble)
    }
}
