import MemoriseCore
import SwiftUI

/// 12-segment circle of fifths: majors outside, relative minors inside.
struct CircleOfFifthsView: View {
    struct Spot: Hashable {
        let index: Int
        var minor = false
    }

    var highlight: Spot?
    var secondary: Spot?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { ctx, size in draw(in: &ctx, size: size) }
            .aspectRatio(1, contentMode: .fit)
            .frame(minWidth: 160, maxWidth: 320)
            .accessibilityElement()
            .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        func name(_ s: Spot) -> String {
            (s.minor ? CircleOfFifths.minors[s.index].spokenName + " minor" : CircleOfFifths.order[s.index].spokenName + " major")
        }
        var parts = ["Circle of fifths"]
        if let highlight { parts.append("highlighted \(name(highlight))") }
        if let secondary { parts.append("answer \(name(secondary))") }
        return parts.joined(separator: ", ")
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let R = min(size.width, size.height) / 2 - 2
        let outerIn = R * 0.64, innerIn = R * 0.34
        let base = colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
        let stroke = colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.18)

        func segment(_ i: Int, _ r0: CGFloat, _ r1: CGFloat) -> Path {
            let a0 = Angle.degrees(Double(i) * 30 - 105), a1 = Angle.degrees(Double(i) * 30 - 75)
            var p = Path()
            p.addArc(center: c, radius: r1, startAngle: a0, endAngle: a1, clockwise: false)
            p.addArc(center: c, radius: r0, startAngle: a1, endAngle: a0, clockwise: true)
            p.closeSubpath()
            return p
        }
        func point(_ i: Int, _ r: CGFloat) -> CGPoint {
            let a = (Double(i) * 30 - 90) * .pi / 180
            return CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
        }

        for i in 0..<12 {
            for minor in [false, true] {
                let spot = Spot(index: i, minor: minor)
                let path = minor ? segment(i, innerIn, outerIn) : segment(i, outerIn, R)
                let fill: GraphicsContext.Shading = spot == highlight ? .color(Theme.pink)
                    : spot == secondary ? .color(.accentColor) : .color(base)
                ctx.fill(path, with: fill)
                ctx.stroke(path, with: .color(stroke), lineWidth: 1)
                let filled = spot == highlight || spot == secondary
                let text = minor ? CircleOfFifths.minors[i].displayName + "m" : CircleOfFifths.order[i].displayName
                let font: Font = minor ? .system(size: R * 0.1, weight: .semibold, design: .rounded)
                    : .system(size: R * 0.14, weight: .bold, design: .rounded)
                ctx.draw(Text(text).font(font).foregroundStyle(filled ? Color.white : Color.primary),
                         at: point(i, minor ? (innerIn + outerIn) / 2 : (outerIn + R) / 2))
            }
        }
    }
}

#Preview("D → A") {
    CircleOfFifthsView(highlight: .init(index: 2), secondary: .init(index: 3)).padding()
}

#Preview("Relative minor of E♭, dark") {
    CircleOfFifthsView(highlight: .init(index: 9), secondary: .init(index: 9, minor: true)).padding().preferredColorScheme(.dark)
}
