import MemoriseCore
import SwiftUI
import UIKit

/// A treble staff with a key signature, drawn on a `Canvas`.
struct StaffView: View {
    let signature: KeySignature

    @Environment(\.colorScheme) private var colorScheme

    /// Staff steps above the bottom line (E4 = 0, F4 = 1 … F5 = 8, G5 = 9).
    static let sharpSteps = [8, 5, 9, 6, 3, 7, 4]   // F5 C5 G5 D5 A4 E5 B4
    static let flatSteps = [4, 7, 3, 6, 2, 5, 1]    // B4 E5 A4 D5 G4 C5 F4

    /// The treble-clef glyph needs a font that has it (Apple Symbols on iOS).
    static let hasClefGlyph: Bool = UIFont(name: "AppleSymbols", size: 12) != nil

    var body: some View {
        Canvas { ctx, size in draw(in: &ctx, size: size) }
            .aspectRatio(2.6, contentMode: .fit)
            .frame(minHeight: 90)
            .accessibilityElement()
            .accessibilityLabel("Treble staff, \(signature.longText)")
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let gap = size.height / 8
        let bottomLine = size.height / 2 + gap * 2
        let line = colorScheme == .dark ? Color.white.opacity(0.75) : Color.black.opacity(0.75)
        let ink = colorScheme == .dark ? Color.white : Color.black

        var lines = Path()
        for k in 0..<5 {
            let y = bottomLine - CGFloat(k) * gap
            lines.move(to: CGPoint(x: 8, y: y))
            lines.addLine(to: CGPoint(x: size.width - 8, y: y))
        }
        ctx.stroke(lines, with: .color(line), lineWidth: 1.2)

        // Clef (G line = step 2).
        let clefX: CGFloat = 8 + gap * 1.6
        if Self.hasClefGlyph {
            ctx.draw(Text("𝄞").font(.custom("AppleSymbols", size: gap * 6.4)).foregroundStyle(ink),
                     at: CGPoint(x: clefX, y: bottomLine - gap * 1.55))
        } else {
            ctx.draw(Text("Treble").font(.caption.weight(.bold)).foregroundStyle(ink), at: CGPoint(x: clefX, y: bottomLine - gap * 2))
        }

        let steps = signature.kind == .flats ? Self.flatSteps : Self.sharpSteps
        let glyph = signature.kind == .flats ? "♭" : "♯"
        let startX = clefX + gap * 2.4
        for i in 0..<signature.count {
            let y = bottomLine - CGFloat(steps[i]) * gap / 2
            let x = startX + CGFloat(i) * gap * 1.25
            ctx.draw(Text(glyph).font(.system(size: gap * 2.4, weight: .medium)).foregroundStyle(ink),
                     at: CGPoint(x: x, y: signature.kind == .flats ? y - gap * 0.35 : y))
        }
    }
}

#Preview("C major (none)") { StaffView(signature: KeySignature(fifths: 0)).padding() }
#Preview("E major (4♯)") { StaffView(signature: KeySignature(fifths: 4)).padding() }
#Preview("G♭ major (6♭)") { StaffView(signature: KeySignature(fifths: -6)).padding().preferredColorScheme(.dark) }
