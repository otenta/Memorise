import MemoriseCore
import SwiftUI

/// Vertical chord box: 6 strings, a 5-fret window, x/o above the nut, finger numbers, barre bar
/// and a base-fret label ("5fr"). Mirrors for left-handed players.
struct ChordDiagramView: View {
    let voicing: Voicing
    var showFingers = true
    var leftHanded = false
    /// Smaller text and strokes for progression rows.
    var compact = false

    static let rows = 5

    @Environment(\.colorScheme) private var colorScheme

    /// First fret row shown (1 = nut drawn).
    var baseFret: Int {
        voicing.highestFret <= Self.rows ? 1 : voicing.lowestFret
    }

    var body: some View {
        Canvas { ctx, size in draw(in: &ctx, size: size) }
            .aspectRatio(0.82, contentMode: .fit)
            .frame(minWidth: compact ? 80 : 150)
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
    }

    var accessibilityText: String {
        var parts = [voicing.chord.spokenSymbol]
        if let b = voicing.barre { parts.append("barre at fret \(b.fret)") }
        let s = voicing.soundedStrings
        if let lo = s.first, let hi = s.last { parts.append("strings \(lo) to \(hi)") }
        parts.append(voicing.tab)
        return parts.joined(separator: ", ")
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let top: CGFloat = compact ? 16 : 26
        let left: CGFloat = compact ? 16 : 28
        let right: CGFloat = compact ? 6 : 10
        let bottom: CGFloat = 6
        let gridW = size.width - left - right
        let gridH = size.height - top - bottom
        let colW = gridW / 5
        let rowH = gridH / CGFloat(Self.rows)
        let line = colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)
        let accent = Color.accentColor

        // String index 0 = string 6 (left when right-handed).
        func x(_ i: Int) -> CGFloat { left + CGFloat(leftHanded ? 5 - i : i) * colW }
        func rowY(_ fret: Int) -> CGFloat { top + (CGFloat(fret - baseFret) + 0.5) * rowH }

        // Grid.
        var grid = Path()
        for i in 0..<6 {
            grid.move(to: CGPoint(x: x(i), y: top))
            grid.addLine(to: CGPoint(x: x(i), y: top + gridH))
        }
        for r in 0...Self.rows {
            let y = top + CGFloat(r) * rowH
            grid.move(to: CGPoint(x: left, y: y))
            grid.addLine(to: CGPoint(x: left + gridW, y: y))
        }
        ctx.stroke(grid, with: .color(line), lineWidth: compact ? 1 : 1.3)
        if baseFret == 1 {
            var nut = Path()
            nut.move(to: CGPoint(x: left - 1, y: top))
            nut.addLine(to: CGPoint(x: left + gridW + 1, y: top))
            ctx.stroke(nut, with: .color(line), lineWidth: compact ? 3 : 5)
        } else {
            ctx.draw(
                Text("\(baseFret)fr").font(.system(size: compact ? 9 : 13, weight: .semibold, design: .rounded)).foregroundStyle(.secondary),
                at: CGPoint(x: leftHanded ? size.width - left / 2 + 2 : left / 2 - 2, y: rowY(baseFret))
            )
        }

        let r = min(colW, rowH) * 0.36
        // Barre.
        if let b = voicing.barre, b.fret >= baseFret {
            let i1 = 6 - b.fromString, i2 = 6 - b.toString
            let xa = min(x(i1), x(i2)), xb = max(x(i1), x(i2))
            let y = rowY(b.fret)
            let rect = CGRect(x: xa - r, y: y - r, width: xb - xa + 2 * r, height: 2 * r)
            ctx.fill(Path(roundedRect: rect, cornerRadius: r), with: .color(accent))
        }

        // Markers and dots.
        for i in 0..<6 {
            let markY = top - (compact ? 8 : 12)
            let markFont = Font.system(size: compact ? 10 : 15, weight: .bold, design: .rounded)
            guard let fret = voicing.frets[i] else {
                ctx.draw(Text("×").font(markFont).foregroundStyle(.secondary), at: CGPoint(x: x(i), y: markY))
                continue
            }
            if fret == 0 {
                let o = CGRect(x: x(i) - r * 0.6, y: markY - r * 0.6, width: r * 1.2, height: r * 1.2)
                ctx.stroke(Path(ellipseIn: o), with: .color(line), lineWidth: 1.5)
                continue
            }
            let c = CGPoint(x: x(i), y: rowY(fret))
            let isRoot = voicing.degreeLabels[i] == "R"
            let inBarre = voicing.barre.map { $0.fret == fret && (min($0.fromString, $0.toString)...max($0.fromString, $0.toString)).contains(6 - i) } ?? false
            if !inBarre || isRoot {
                let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect), with: .color(isRoot ? Theme.pink : accent))
            }
            if showFingers, let finger = voicing.fingers[i] {
                ctx.draw(Text("\(finger)").font(.system(size: r * 1.1, weight: .heavy, design: .rounded)).foregroundStyle(.white), at: c)
            }
        }
    }
}

extension Chord {
    /// "B flat minor seventh" — used for VoiceOver.
    var spokenSymbol: String { longName }
}

#Preview("Open C") {
    let v = ChordShapeLibrary.shared.shape(id: "open.C")!.voicing(root: NoteSpelling(.c), maxFret: 12)!
    return ChordDiagramView(voicing: v).frame(width: 200).padding()
}

#Preview("F barre") {
    let v = ChordShapeLibrary.shared.shape(id: "Eshape.maj")!.voicing(root: NoteSpelling(.f), maxFret: 12)!
    return ChordDiagramView(voicing: v).frame(width: 200).padding()
}

#Preview("Bm7 at 2fr, left-handed") {
    let v = ChordShapeLibrary.shared.shape(id: "Ashape.m7")!.voicing(root: NoteSpelling(.b), maxFret: 12)!
    return ChordDiagramView(voicing: v, leftHanded: true).frame(width: 200).padding()
}
