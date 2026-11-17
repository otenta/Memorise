import MemoriseCore
import SwiftUI

/// Big Hangul headline that sizes itself to its length and never splits a word (R7-F6).
///
/// SwiftUI wraps Hangul at any syllable, so a plain `Text` can cut 보고 싶어 into 보고 싶 / 어.
/// Here each space-separated word is its own one-line `Text`, and `WordFlowLayout` flows the
/// words onto centred lines. A word too wide for the line shrinks instead of wrapping; past
/// three lines, every word shrinks uniformly until the headline fits in three.
struct KoreanHeadline: View {
    enum Role { case prompt, answer }

    let text: String
    var role: Role = .prompt
    var style: AnyShapeStyle = AnyShapeStyle(Subject.korean.gradient)
    /// Soft pink glow under prompt headlines; answers sit on a busier card and skip it.
    var glow: Bool? = nil
    /// Text appended to the last word in `tailStyle` (the particle in Particles answers).
    var tail: String? = nil
    var tailStyle: Color = Theme.pink

    /// Dynamic Type multiplier (×100 for precision).
    @ScaledMetric(relativeTo: .largeTitle) private var typeScale: CGFloat = 100

    static let maxLines = 3

    /// Base point size for the headline, from the plan's length table.
    static func baseSize(for text: String, role: Role) -> CGFloat {
        let n = text.filter { !$0.isWhitespace }.count
        switch (role, n) {
        case (.prompt, ...3): return 60
        case (.prompt, 4...6): return 50
        case (.prompt, 7...10): return 40
        case (.prompt, _): return 32
        case (.answer, ...3): return 46
        case (.answer, 4...6): return 40
        case (.answer, 7...10): return 32
        case (.answer, _): return 28
        }
    }

    private var size: CGFloat {
        let base = Self.baseSize(for: text + (tail ?? ""), role: role)
        // Grows with Dynamic Type, capped so accessibility sizes can't swamp the card.
        return base * min(typeScale / 100, 1.8)
    }

    private var words: [String] {
        var w = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if w.isEmpty { w = [text] }
        return w
    }

    var body: some View {
        let words = words
        WordFlowLayout(spacing: size * 0.26, lineSpacing: size * 0.08, maxLines: Self.maxLines) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                wordText(word, isLast: i == words.count - 1)
                    .font(.system(size: size, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(style)
        .shadow(color: (glow ?? (role == .prompt)) ? Theme.pink.opacity(0.3) : .clear, radius: 12, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text + (tail ?? ""))
        .accessibilityAddTraits(.isStaticText)
    }

    private func wordText(_ word: String, isLast: Bool) -> Text {
        guard isLast, let tail else { return Text(word) }
        return Text("\(word)\(Text(tail).foregroundStyle(tailStyle))")
    }
}

/// Flows subviews (words) onto centred lines. A word wider than the line is proposed the line
/// width, so a `minimumScaleFactor` text shrinks rather than wraps. If the words need more than
/// `maxLines`, all of them are proposed a uniformly smaller width until they fit.
struct WordFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    var maxLines: Int

    struct Placement {
        var lines: [[Int]]
        var sizes: [CGSize]
        var scale: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let p = place(width: proposal.width, subviews: subviews)
        let width = p.lines.map { lineWidth($0, p) }.max() ?? 0
        return CGSize(width: min(width, proposal.width ?? .infinity), height: height(p))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = place(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for line in p.lines {
            let lh = line.map { p.sizes[$0].height }.max() ?? 0
            var x = bounds.midX - lineWidth(line, p) / 2
            for i in line {
                let s = p.sizes[i]
                subviews[i].place(
                    at: CGPoint(x: x, y: y + (lh - s.height) / 2),
                    proposal: ProposedViewSize(s)
                )
                x += s.width + spacing * p.scale
            }
            y += lh + lineSpacing
        }
    }

    // MARK: Helpers

    private func lineWidth(_ line: [Int], _ p: Placement) -> CGFloat {
        line.reduce(0) { $0 + p.sizes[$1].width } + spacing * p.scale * CGFloat(max(0, line.count - 1))
    }

    private func height(_ p: Placement) -> CGFloat {
        p.lines.reduce(0) { $0 + ($1.map { p.sizes[$0].height }.max() ?? 0) }
            + lineSpacing * CGFloat(max(0, p.lines.count - 1))
    }

    /// Tries full size first, then steps down until the words fit in `maxLines`.
    private func place(width: CGFloat?, subviews: Subviews) -> Placement {
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        guard let width, width.isFinite, width > 0 else {
            return Placement(lines: [Array(subviews.indices)], sizes: ideal, scale: 1)
        }
        var scale: CGFloat = 1
        while true {
            let p = flow(width: width, ideal: ideal, scale: scale, subviews: subviews)
            if p.lines.count <= maxLines || scale <= 0.4 { return p }
            scale -= 0.05
        }
    }

    private func flow(width: CGFloat, ideal: [CGSize], scale: CGFloat, subviews: Subviews) -> Placement {
        // Each word's width at this scale, capped at the line; the text shrinks to the proposal.
        let sizes: [CGSize] = subviews.indices.map { i in
            let target = min(ideal[i].width * scale, width)
            if target >= ideal[i].width - 0.5 { return ideal[i] }
            let s = subviews[i].sizeThatFits(ProposedViewSize(width: target, height: nil))
            return CGSize(width: min(s.width, target), height: s.height)
        }
        var lines: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for i in sizes.indices {
            let add = (current.isEmpty ? 0 : spacing * scale) + sizes[i].width
            if !current.isEmpty && used + add > width + 0.5 {
                lines.append(current)
                current = [i]
                used = sizes[i].width
            } else {
                current.append(i)
                used += add
            }
        }
        if !current.isEmpty { lines.append(current) }
        return Placement(lines: lines, sizes: sizes, scale: scale)
    }
}

#Preview("Korean headlines") {
    let samples = [
        "사랑해", "보고 싶어", "괜찮아요", "어떡해", "공부하다", "기억이 안 나요", "처음 뵙겠습니다",
        // Longest headword per Korean deck.
        "안녕히 가세요", "수고하셨습니다", "오랜만이에요", "맛있게 드세요",
        "새해 복 많이 받으세요", "재사용 대기시간", "이게 최선입니까?", "-(으)ㄴ/는 줄 알았다",
    ]
    ScrollView {
        VStack(spacing: 28) {
            ForEach(samples, id: \.self) { s in
                VStack(spacing: 8) {
                    KoreanHeadline(text: s, role: .prompt)
                    KoreanHeadline(text: s, role: .answer, style: AnyShapeStyle(Theme.pink))
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .glassCard(tint: Theme.pink)
            }
            KoreanHeadline(text: "학교", role: .answer, style: AnyShapeStyle(.primary), tail: "에서")
        }
        .padding(.horizontal, 36)
    }
    .background(AuroraBackground(colors: Subject.korean.colors))
}
