import SwiftUI

/// A marked position on the fretboard. Generic so chords/scales can reuse it later.
struct FretMark: Hashable, Sendable {
    enum Style: Hashable, Sendable {
        /// Primary answer (accent filled).
        case answer
        /// Secondary emphasis (e.g. chord tones, root alternatives).
        case secondary
        /// De-emphasised context.
        case muted
    }

    /// 1 = high E … 6 = low E.
    let string: Int
    /// 0 = open string.
    let fret: Int
    var label: String?
    var style: Style = .answer
    /// Small secondary label above the dot (e.g. fingering order).
    var badge: String?
    /// Thicker outline (e.g. the bass note of a triad).
    var emphasised = false
}

/// Horizontal fretboard diagram drawn with `Canvas`.
///
/// Logarithmic fret spacing, inlays, optional left-handed mirroring and string-order flip.
struct FretboardView: View {
    var stringCount = 6
    /// Visible frets. A window starting above 0 draws no nut and labels its first fret.
    var fretWindow: ClosedRange<Int> = 0...12
    var marks: [FretMark] = []
    var highlightedStrings: Set<Int> = []
    var leftHanded = false
    /// `true` = string 1 (high E) at the top, as in tab.
    var highEOnTop = true

    init(stringCount: Int = 6, fretWindow: ClosedRange<Int>, marks: [FretMark] = [], highlightedStrings: Set<Int> = [],
         leftHanded: Bool = false, highEOnTop: Bool = true) {
        self.stringCount = stringCount
        self.fretWindow = fretWindow.lowerBound < 0 ? 0...max(fretWindow.upperBound, 1) : fretWindow
        self.marks = marks
        self.highlightedStrings = highlightedStrings
        self.leftHanded = leftHanded
        self.highEOnTop = highEOnTop
    }

    /// Window `0…maxFret` (the M1/M2 look).
    init(stringCount: Int = 6, maxFret: Int = 12, marks: [FretMark] = [], highlightedStrings: Set<Int> = [],
         leftHanded: Bool = false, highEOnTop: Bool = true) {
        self.init(stringCount: stringCount, fretWindow: 0...max(maxFret, 1), marks: marks, highlightedStrings: highlightedStrings,
                  leftHanded: leftHanded, highEOnTop: highEOnTop)
    }

    private var maxFret: Int { max(fretWindow.upperBound, fretWindow.lowerBound + 1) }
    private var startsAtNut: Bool { fretWindow.lowerBound == 0 }

    @Environment(\.colorScheme) private var colorScheme

    private static let singleInlays: Set<Int> = [3, 5, 7, 9, 15, 17, 19, 21]
    private static let doubleInlays: Set<Int> = [12, 24]
    private static let numberedFrets: Set<Int> = [3, 5, 7, 9, 12, 15, 17, 19, 21, 24]

    var body: some View {
        Canvas { ctx, size in draw(in: &ctx, size: size) }
            .frame(minHeight: 150)
            .aspectRatio(3.2, contentMode: .fit)
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard !marks.isEmpty else { return "Fretboard" }
        return "Fretboard: " + marks.map { "string \($0.string), \($0.fret == 0 ? "open" : "fret \($0.fret)")" }
            .joined(separator: "; ")
    }

    // MARK: Drawing

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let openArea: CGFloat = startsAtNut ? 30 : 14
        let rightPad: CGFloat = 8
        let topPad: CGFloat = 14
        let labelBand: CGFloat = 18
        let nutX = openArea
        let boardW = max(1, size.width - openArea - rightPad)
        let boardTop = topPad
        let boardBottom = size.height - labelBand
        let spacing = (boardBottom - boardTop) / CGFloat(max(stringCount - 1, 1))
        let maxF = maxFret
        // Left edge: the nut (window from 0) or the fret wire below the first visible fret.
        let firstLine = startsAtNut ? 0 : fretWindow.lowerBound - 1
        let firstVisible = max(1, fretWindow.lowerBound)
        func g(_ n: Int) -> Double { 1 - pow(2, -Double(n) / 12) }
        let norm = g(maxF) - g(firstLine)

        func fretX(_ n: Int) -> CGFloat { nutX + boardW * CGFloat((g(n) - g(firstLine)) / norm) }
        func mx(_ x: CGFloat) -> CGFloat { leftHanded ? size.width - x : x }
        func stringY(_ s: Int) -> CGFloat {
            let row = highEOnTop ? s - 1 : stringCount - s
            return boardTop + CGFloat(row) * spacing
        }
        func noteX(_ f: Int) -> CGFloat { f == 0 ? nutX - openArea / 2 : (fretX(f - 1) + fretX(f)) / 2 }

        let line = colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55)
        let inlay = colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
        let midY = (boardTop + boardBottom) / 2
        let dotR = min(spacing * 0.22, 6)

        // Board background.
        let boardRect = CGRect(x: min(mx(nutX), mx(fretX(maxF))), y: boardTop - 4, width: boardW, height: boardBottom - boardTop + 8)
        ctx.fill(Path(roundedRect: boardRect, cornerRadius: 4), with: .color(inlay.opacity(0.35)))

        // Inlays.
        for f in firstVisible...maxF {
            let x = mx(noteX(f))
            if Self.singleInlays.contains(f) {
                ctx.fill(Path(ellipseIn: CGRect(x: x - dotR, y: midY - dotR, width: dotR * 2, height: dotR * 2)), with: .color(inlay))
            } else if Self.doubleInlays.contains(f) {
                for y in [boardTop + spacing * 1.5, boardBottom - spacing * 1.5] {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(inlay))
                }
            }
        }

        // Frets + nut.
        var frets = Path()
        for f in firstVisible...maxF {
            let x = mx(fretX(f))
            frets.move(to: CGPoint(x: x, y: boardTop))
            frets.addLine(to: CGPoint(x: x, y: boardBottom))
        }
        ctx.stroke(frets, with: .color(line), lineWidth: 1)
        var nut = Path()
        nut.move(to: CGPoint(x: mx(nutX), y: boardTop - 2))
        nut.addLine(to: CGPoint(x: mx(nutX), y: boardBottom + 2))
        ctx.stroke(nut, with: .color(line), lineWidth: startsAtNut ? 4 : 1)

        // Strings (low strings thicker).
        for s in 1...stringCount {
            let y = stringY(s)
            var p = Path()
            p.move(to: CGPoint(x: mx(nutX - openArea * 0.2), y: y))
            p.addLine(to: CGPoint(x: mx(fretX(maxF)), y: y))
            let highlighted = highlightedStrings.contains(s)
            ctx.stroke(
                p,
                with: .color(highlighted ? .accentColor : line),
                lineWidth: 0.8 + CGFloat(s - 1) * 0.35 + (highlighted ? 1.6 : 0)
            )
        }

        // Fret numbers.
        var numbered = Self.numberedFrets.filter { $0 >= firstVisible && $0 <= maxF }
        if !startsAtNut { numbered.insert(firstVisible) }
        for f in numbered.sorted() {
            ctx.draw(
                Text("\(f)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary),
                at: CGPoint(x: mx(noteX(f)), y: boardBottom + labelBand / 2 + 2)
            )
        }

        // Marks.
        let r = min(spacing * 0.45, 14)
        let visible = startsAtNut ? 0...maxF : firstVisible...maxF
        for m in marks where (1...stringCount).contains(m.string) && visible.contains(m.fret) {
            let c = CGPoint(x: mx(noteX(m.fret)), y: stringY(m.string))
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            let fill: Color = switch m.style {
            case .answer: .accentColor
            case .secondary: .orange
            case .muted: .gray
            }
            if m.fret == 0 {
                ctx.stroke(Path(ellipseIn: rect), with: .color(fill), lineWidth: 2.5)
            } else {
                ctx.fill(Path(ellipseIn: rect), with: .color(fill))
            }
            if m.emphasised {
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(fill), lineWidth: 2)
            }
            if let badge = m.badge {
                ctx.draw(
                    Text(badge).font(.system(size: max(8, r * 0.6), weight: .heavy).monospacedDigit()).foregroundStyle(.secondary),
                    at: CGPoint(x: c.x + r * 0.95, y: c.y - r * 0.95)
                )
            }
            if let label = m.label {
                ctx.draw(
                    Text(label).font(.system(size: r * 0.85, weight: .bold)).foregroundStyle(m.fret == 0 ? fill : .white),
                    at: c
                )
            }
        }
    }
}

#Preview("Answer A on string 6") {
    FretboardView(maxFret: 24, marks: [FretMark(string: 6, fret: 5, label: "A"), FretMark(string: 6, fret: 17, label: "A")], highlightedStrings: [6])
        .padding()
}

#Preview("Window 4…9 (scale box)") {
    FretboardView(fretWindow: 4...9, marks: [
        FretMark(string: 6, fret: 5, label: "R"), FretMark(string: 6, fret: 8, label: "♭3", style: .secondary, badge: "2"),
        FretMark(string: 1, fret: 5, label: "R", emphasised: true),
    ])
    .padding()
}

#Preview("Left-handed, dark") {
    FretboardView(marks: [FretMark(string: 1, fret: 0, label: "E"), FretMark(string: 1, fret: 12, label: "E")], highlightedStrings: [1], leftHanded: true)
        .padding()
        .preferredColorScheme(.dark)
}
