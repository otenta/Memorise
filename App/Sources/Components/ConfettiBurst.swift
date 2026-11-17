import SwiftUI

/// One-shot confetti burst from the top centre. Hidden entirely when Reduce Motion is on.
struct ConfettiBurst: View {
    var colors: [Color] = [Theme.coral, Theme.pink, Theme.violet, Theme.indigo, Theme.mint, Theme.amber]
    var count = 70
    var duration: Double = 2.8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var pieces: [Piece] = []

    private struct Piece {
        let angle: Double      // launch direction (radians)
        let speed: Double      // points per second
        let spin: Double       // radians per second
        let size: CGSize
        let color: Color
        let delay: Double
        let isCircle: Bool
    }

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            TimelineView(.animation(paused: start.map { Date.now.timeIntervalSince($0) > duration } ?? true)) { ctx in
                Canvas { gc, size in
                    guard let start else { return }
                    let t = ctx.date.timeIntervalSince(start)
                    let origin = CGPoint(x: size.width / 2, y: size.height * 0.18)
                    for p in pieces {
                        let lt = t - p.delay
                        guard lt > 0 else { continue }
                        let x = origin.x + cos(p.angle) * p.speed * lt
                        let y = origin.y + sin(p.angle) * p.speed * lt + 420 * lt * lt // gravity
                        let fade = max(0, 1 - lt / (duration - p.delay))
                        guard fade > 0 else { continue }
                        var g = gc
                        g.opacity = fade
                        g.translateBy(x: x, y: y)
                        g.rotate(by: .radians(p.spin * lt))
                        // Flutter: squash width over time.
                        g.scaleBy(x: abs(cos(p.spin * lt * 0.7)) * 0.8 + 0.2, y: 1)
                        let rect = CGRect(x: -p.size.width / 2, y: -p.size.height / 2, width: p.size.width, height: p.size.height)
                        g.fill(p.isCircle ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5), with: .color(p.color))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .ignoresSafeArea()
            .onAppear(perform: fire)
        }
    }

    private func fire() {
        var rng = SystemRandomNumberGenerator()
        pieces = (0..<count).map { _ in
            Piece(
                angle: Double.random(in: (-.pi * 0.95)...(-.pi * 0.05), using: &rng),
                speed: Double.random(in: 260...620, using: &rng),
                spin: Double.random(in: -9...9, using: &rng),
                size: CGSize(width: Double.random(in: 6...11, using: &rng), height: Double.random(in: 9...16, using: &rng)),
                color: colors.randomElement(using: &rng) ?? .pink,
                delay: Double.random(in: 0...0.25, using: &rng),
                isCircle: Int.random(in: 0..<5, using: &rng) == 0
            )
        }
        start = .now
    }
}

#Preview {
    ConfettiBurst()
}
