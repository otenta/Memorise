import MemoriseCore
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

/// Horizontal fretboard diagram drawn with `Canvas` (redesigned in R7-F4).
///
/// Roomy by construction: strings sit `stringSpacing` apart, the height follows the string count,
/// and no fret is narrower than `minFretWidth`. The board fills its container's width; when the
/// window has too many frets for that, it scrolls horizontally (centred on the marks) instead of
/// shrinking. Fret numbers sit in a band under the board. Supports left-handed mirroring and
/// either string order.
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

    /// Window `0…maxFret` (the whole neck up to `maxFret`).
    init(stringCount: Int = 6, maxFret: Int = 12, marks: [FretMark] = [], highlightedStrings: Set<Int> = [],
         leftHanded: Bool = false, highEOnTop: Bool = true) {
        self.init(stringCount: stringCount, fretWindow: 0...max(maxFret, 1), marks: marks, highlightedStrings: highlightedStrings,
                  leftHanded: leftHanded, highEOnTop: highEOnTop)
    }

    // MARK: Size rules (PLAN_R7 F4 §3)

    /// Distance between neighbouring strings.
    static let stringSpacing: CGFloat = 30
    /// The narrowest fret is never below this (a comfortable touch target).
    static let minFretWidth: CGFloat = 44
    static let topPad: CGFloat = 16
    static let labelBand: CGFloat = 24

    /// Board height for a string count: `(strings − 1) × spacing + margins`.
    static func height(stringCount: Int) -> CGFloat {
        CGFloat(max(stringCount - 1, 1)) * stringSpacing + topPad + labelBand + 6
    }

    /// The narrowest width at which every fret in `window` is still `minFretWidth` wide.
    static func minimumWidth(window: ClosedRange<Int>) -> CGFloat {
        let geo = Geometry(window: window, width: 1000)
        let boardW = geo.boardW
        let narrowest = (geo.firstVisible...geo.maxF).map { geo.fretX($0) - geo.fretX($0 - 1) }.min() ?? boardW
        return ceil(geo.openArea + geo.rightPad + boardW * minFretWidth / max(narrowest, 1))
    }

    @Environment(\.colorScheme) private var colorScheme

    private static let singleInlays: Set<Int> = [3, 5, 7, 9, 15, 17, 19, 21]
    private static let doubleInlays: Set<Int> = [12, 24]
    private static let numberedFrets: Set<Int> = [3, 5, 7, 9, 12, 15, 17, 19, 21, 24]

    var body: some View {
        let minW = Self.minimumWidth(window: fretWindow)
        let h = Self.height(stringCount: stringCount)
        ViewThatFits(in: .horizontal) {
            canvas.frame(minWidth: minW, maxWidth: .infinity).frame(height: h)
            scrollingBoard(width: minW, height: h)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var canvas: some View {
        Canvas { ctx, size in draw(in: &ctx, size: size) }
    }

    /// Too many frets for the width: scroll at full size, starting centred on the marks.
    private func scrollingBoard(width: CGFloat, height: CGFloat) -> some View {
        let focusX: CGFloat = {
            let geo = Geometry(window: fretWindow, width: width)
            let xs = marks.filter { fretWindow.contains($0.fret) || ($0.fret == 0 && geo.startsAtNut) }.map { geo.noteX($0.fret) }
            let x = xs.isEmpty ? 0 : (xs.min()! + xs.max()!) / 2
            return leftHanded ? width - x : x
        }()
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                canvas
                    .frame(width: width, height: height)
                    .overlay(alignment: .topLeading) {
                        Color.clear.frame(width: 1, height: 1).offset(x: focusX).id("focus")
                    }
            }
            .onAppear { proxy.scrollTo("focus", anchor: .center) }
        }
        .frame(height: height)
        .mask {
            // Soft edges hint that the neck continues.
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                                   .init(color: .black, location: 0.96), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
    }

    private var accessibilityText: String {
        guard !marks.isEmpty else { return "Fretboard" }
        return "Fretboard: " + marks.map { "string \($0.string), \($0.fret == 0 ? "open" : "fret \($0.fret)")" }
            .joined(separator: "; ")
    }

    // MARK: Geometry

    /// Horizontal geometry shared by drawing, sizing and scroll focus.
    struct Geometry {
        let window: ClosedRange<Int>
        let width: CGFloat

        var startsAtNut: Bool { window.lowerBound == 0 }
        var maxF: Int { max(window.upperBound, window.lowerBound + 1) }
        var openArea: CGFloat { startsAtNut ? 34 : 14 }
        var rightPad: CGFloat { 8 }
        var nutX: CGFloat { openArea }
        var boardW: CGFloat { max(1, width - openArea - rightPad) }
        /// Left edge: the nut (window from 0) or the fret wire below the first visible fret.
        var firstLine: Int { startsAtNut ? 0 : window.lowerBound - 1 }
        var firstVisible: Int { max(1, window.lowerBound) }

        /// Half-strength logarithmic spacing: still reads as a guitar neck, but high frets
        /// don't get so narrow that a whole-neck board has to be enormous.
        private func g(_ n: Int) -> Double { 1 - pow(2, -Double(n) / 24) }

        func fretX(_ n: Int) -> CGFloat {
            let norm = g(maxF) - g(firstLine)
            return nutX + boardW * CGFloat((g(n) - g(firstLine)) / norm)
        }

        func noteX(_ f: Int) -> CGFloat { f == 0 ? nutX - openArea / 2 : (fretX(f - 1) + fretX(f)) / 2 }
    }

    // MARK: Drawing

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let geo = Geometry(window: fretWindow, width: size.width)
        let spacing = Self.stringSpacing
        let boardTop = Self.topPad
        let boardBottom = boardTop + CGFloat(max(stringCount - 1, 1)) * spacing
        let nutX = geo.nutX
        let maxF = geo.maxF
        let firstVisible = geo.firstVisible
        func fretX(_ n: Int) -> CGFloat { geo.fretX(n) }
        func noteX(_ f: Int) -> CGFloat { geo.noteX(f) }
        func mx(_ x: CGFloat) -> CGFloat { leftHanded ? size.width - x : x }
        func stringY(_ s: Int) -> CGFloat {
            let row = highEOnTop ? s - 1 : stringCount - s
            return boardTop + CGFloat(row) * spacing
        }

        let dark = colorScheme == .dark
        let line = dark ? Color.white.opacity(0.5) : Color.black.opacity(0.45)
        let inlay = dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10)
        let midY = (boardTop + boardBottom) / 2
        let dotR: CGFloat = 5

        // Board: a soft rosewood-tinted slab with a top sheen.
        let left = min(mx(nutX), mx(fretX(maxF)))
        let boardRect = CGRect(x: left, y: boardTop - 8, width: geo.boardW, height: boardBottom - boardTop + 16)
        let slab = Path(roundedRect: boardRect, cornerRadius: 8)
        let wood = dark
            ? [Color(red: 0.30, green: 0.22, blue: 0.20), Color(red: 0.20, green: 0.15, blue: 0.14)]
            : [Color(red: 0.93, green: 0.88, blue: 0.84), Color(red: 0.86, green: 0.80, blue: 0.76)]
        ctx.fill(slab, with: .linearGradient(Gradient(colors: wood),
                                              startPoint: CGPoint(x: 0, y: boardRect.minY), endPoint: CGPoint(x: 0, y: boardRect.maxY)))
        ctx.stroke(slab, with: .color(line.opacity(0.35)), lineWidth: 0.75)

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
            frets.move(to: CGPoint(x: x, y: boardTop - 8))
            frets.addLine(to: CGPoint(x: x, y: boardBottom + 8))
        }
        ctx.stroke(frets, with: .color(line), lineWidth: 1.5)
        var nut = Path()
        nut.move(to: CGPoint(x: mx(nutX), y: boardTop - 8))
        nut.addLine(to: CGPoint(x: mx(nutX), y: boardBottom + 8))
        let nutColor = dark ? Color.white.opacity(0.8) : Color.black.opacity(0.7)
        ctx.stroke(nut, with: .color(geo.startsAtNut ? nutColor : line), lineWidth: geo.startsAtNut ? 5 : 1.5)

        // Strings (low strings thicker); highlighted strings glow.
        for s in 1...stringCount {
            let y = stringY(s)
            var p = Path()
            p.move(to: CGPoint(x: mx(nutX - geo.openArea * 0.3), y: y))
            p.addLine(to: CGPoint(x: mx(fretX(maxF)), y: y))
            let width = 1 + CGFloat(s - 1) * 0.4
            if highlightedStrings.contains(s) {
                ctx.stroke(p, with: .color(Color.accentColor.opacity(0.25)), lineWidth: width + 7)
                ctx.stroke(p, with: .color(.accentColor), lineWidth: width + 1.2)
            } else {
                ctx.stroke(p, with: .color(line), lineWidth: width)
            }
        }

        // Fret numbers, under the board.
        var numbered = Self.numberedFrets.filter { $0 >= firstVisible && $0 <= maxF }
        if !geo.startsAtNut { numbered.insert(firstVisible) }
        for f in numbered.sorted() {
            ctx.draw(
                Text("\(f)").font(.system(.caption, design: .rounded, weight: .bold).monospacedDigit()).foregroundStyle(.secondary),
                at: CGPoint(x: mx(noteX(f)), y: boardBottom + 8 + Self.labelBand / 2 + 1)
            )
        }

        // Marks.
        let r: CGFloat = 13
        let visible = geo.startsAtNut ? 0...maxF : firstVisible...maxF
        for m in marks where (1...stringCount).contains(m.string) && visible.contains(m.fret) {
            let c = CGPoint(x: mx(noteX(m.fret)), y: stringY(m.string))
            let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            let fill: Color = switch m.style {
            case .answer: .accentColor
            case .secondary: .orange
            case .muted: .gray
            }
            if m.fret == 0 {
                ctx.fill(Path(ellipseIn: rect), with: .color(fill.opacity(0.12)))
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)), with: .color(fill), lineWidth: 2.5)
            } else {
                var shadowed = ctx
                shadowed.addFilter(.shadow(color: fill.opacity(0.45), radius: 4, y: 2))
                shadowed.fill(Path(ellipseIn: rect), with: .color(fill))
            }
            if m.emphasised {
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3.5, dy: -3.5)), with: .color(fill), lineWidth: 2)
            }
            if let badge = m.badge {
                ctx.draw(
                    Text(badge).font(.system(size: 10, weight: .heavy).monospacedDigit()).foregroundStyle(.secondary),
                    at: CGPoint(x: c.x + r * 0.95, y: c.y - r * 0.95)
                )
            }
            if let label = m.label {
                ctx.draw(
                    Text(label).font(.system(size: label.count > 2 ? 10 : 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(m.fret == 0 ? fill : .white),
                    at: c
                )
            }
        }
    }
}

// MARK: - Zoomed answer board

/// Fret windows that frame a set of focus frets (R7-F4).
enum FretWindows {
    /// Padding each side of the focus frets.
    static let pad = 2
    static let minSpan = 5
    static let maxSpan = 6
    /// Lower bounds at or below this snap to the nut, so open-string answers keep it.
    static let nutSnap = 2

    /// One window around `frets`: lowest − 2 … highest + 2, at least 5 frets, clamped to the neck.
    static func window(around frets: [Int], neckMax: Int, padAbove: Int = pad) -> ClosedRange<Int> {
        guard let lo = frets.min(), let hi = frets.max() else { return 0...min(neckMax, 5) }
        var lower = max(0, lo - pad)
        var upper = min(neckMax, max(hi + padAbove, lower + minSpan - 1))
        if upper - lower + 1 < minSpan { lower = max(0, upper - minSpan + 1) }
        if lower <= nutSnap {
            lower = 0
            // The nut adds open-string room, so trim the top padding to keep 0…5 inside a phone card.
            if padAbove == pad { upper = min(neckMax, max(hi + 1, minSpan - 1)) }
        }
        if upper <= lower { upper = min(neckMax, lower + minSpan) }
        // Wide clusters drop to one fret of padding, so 6 frets (≥ 44 pt each) fit a phone card.
        if padAbove == pad, upper - lower + 1 > maxSpan {
            if lower > 0, lower < lo { lower += 1 }
            if upper - lower + 1 > maxSpan, upper > hi { upper -= 1 }
        }
        return lower...upper
    }

    /// Groups `frets` into clusters that each fit one comfortable window (≤ 7 frets wide),
    /// returning one window per cluster.
    static func windows(around frets: [Int], neckMax: Int) -> [ClosedRange<Int>] {
        let sorted = Array(Set(frets)).sorted()
        var clusters: [[Int]] = []
        for f in sorted {
            if let first = clusters.last?.first, f - first <= 3 + (first <= nutSnap + pad ? 2 : 0) {
                clusters[clusters.count - 1].append(f)
            } else {
                clusters.append([f])
            }
        }
        return clusters.map { window(around: $0, neckMax: neckMax) }
    }
}

/// The answer-side board: zoomed windows around `focus`, a pager when the windows don't fit side
/// by side, and an optional "Whole neck" toggle that shows 0…`neckMax` scrolled to the answer.
struct FretboardAnswerBoard: View {
    let stringCount: Int
    let neckMax: Int
    let focus: [Int]
    let marks: [FretMark]
    var highlight: Set<Int> = []
    var leftHanded = false
    var highEOnTop = true
    /// Caption under the board ("Fret 5 (also 17)").
    var caption: String?
    var showsWholeNeckToggle = true

    @AppStorage("fretboard.wholeNeck") private var wholeNeck = false
    @State private var page: Int? = 0

    private var windows: [ClosedRange<Int>] {
        let w = FretWindows.windows(around: focus, neckMax: neckMax)
        return w.isEmpty ? [0...min(neckMax, 5)] : w
    }

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if wholeNeck {
                    board(0...max(neckMax, focus.max() ?? 0))
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    zoomed.transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .animation(Theme.softSpring, value: wholeNeck)
            footer
        }
    }

    @ViewBuilder private var zoomed: some View {
        let windows = windows
        if windows.count == 1 {
            board(windows[0])
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(windows.enumerated()), id: \.offset) { _, w in
                        board(w).frame(minWidth: FretboardView.minimumWidth(window: w))
                    }
                }
                pager(windows)
            }
        }
    }

    /// One window per page, with paging dots.
    private func pager(_ windows: [ClosedRange<Int>]) -> some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(windows.enumerated()), id: \.offset) { i, w in
                        board(w)
                            .containerRelativeFrame(.horizontal)
                            .id(i)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            .frame(height: FretboardView.height(stringCount: stringCount))
            HStack(spacing: 6) {
                ForEach(windows.indices, id: \.self) { i in
                    let on = (page ?? 0) == i
                    Capsule()
                        .fill(on ? AnyShapeStyle(Subject.music.gradient) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                        .frame(width: on ? 18 : 7, height: 7)
                        .onTapGesture { withAnimation(Theme.spring) { page = i } }
                }
            }
            .animation(Theme.spring, value: page)
            .accessibilityElement()
            .accessibilityLabel("Position \((page ?? 0) + 1) of \(windows.count)")
            .accessibilityAdjustableAction { dir in
                withAnimation(Theme.spring) {
                    switch dir {
                    case .increment: page = min(windows.count - 1, (page ?? 0) + 1)
                    case .decrement: page = max(0, (page ?? 0) - 1)
                    @unknown default: break
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let caption {
                Text(caption)
                    .font(.system(.headline, design: .rounded, weight: .semibold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            if showsWholeNeckToggle {
                Button {
                    withAnimation(Theme.softSpring) { wholeNeck.toggle() }
                } label: {
                    Label(wholeNeck ? "Zoom in" : "Whole neck",
                          systemImage: wholeNeck ? "plus.magnifyingglass" : "arrow.left.and.right")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.primary.opacity(0.07), in: Capsule())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityIdentifier("fretboardWholeNeckToggle")
            }
        }
    }

    private func board(_ window: ClosedRange<Int>) -> FretboardView {
        FretboardView(stringCount: stringCount, fretWindow: window, marks: marks, highlightedStrings: highlight,
                      leftHanded: leftHanded, highEOnTop: highEOnTop)
    }
}

/// Answer-card layout for fretboard decks: header (note + ▶) above the board in portrait,
/// to its left in landscape, so the board always gets the full width it can.
struct FretboardAnswerLayout<Header: View, Board: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let board: Board
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        if verticalSizeClass == .compact {
            HStack(alignment: .center, spacing: 16) {
                VStack(spacing: 10) { header }
                    .fixedSize()
                board.frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 14) {
                HStack(spacing: 12) { header }
                board
            }
        }
    }
}

// MARK: - Previews

#Preview("Answer A on string 6 (5 & 17)") {
    FretboardAnswerBoard(stringCount: 6, neckMax: 22, focus: [5, 17],
                         marks: [FretMark(string: 6, fret: 5, label: "A"), FretMark(string: 6, fret: 17, label: "A")],
                         highlight: [6], caption: "Fret 5 (also 17)")
        .padding(24)
        .glassCard()
        .padding()
}

#Preview("Single answer, fret 5") {
    FretboardAnswerBoard(stringCount: 6, neckMax: 12, focus: [5],
                         marks: [FretMark(string: 6, fret: 5, label: "A")], highlight: [6], caption: "Fret 5")
        .padding(24)
        .glassCard()
        .padding()
}

#Preview("Open string keeps the nut") {
    FretboardAnswerBoard(stringCount: 6, neckMax: 12, focus: [0, 12],
                         marks: [FretMark(string: 1, fret: 0, label: "E"), FretMark(string: 1, fret: 12, label: "E")],
                         highlight: [1], caption: "Open string (also 12)")
        .padding(24)
        .glassCard()
        .padding()
}

#Preview("Window 4…9 (scale box)") {
    FretboardView(fretWindow: 4...9, marks: [
        FretMark(string: 6, fret: 5, label: "R"), FretMark(string: 6, fret: 8, label: "♭3", style: .secondary, badge: "2"),
        FretMark(string: 1, fret: 5, label: "R", emphasised: true),
    ])
    .padding()
}

#Preview("Whole neck scrolls, left-handed, dark") {
    FretboardView(maxFret: 22, marks: [FretMark(string: 1, fret: 0, label: "E"), FretMark(string: 1, fret: 12, label: "E")],
                  highlightedStrings: [1], leftHanded: true)
        .padding()
        .preferredColorScheme(.dark)
}
