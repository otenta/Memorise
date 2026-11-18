import MemoriseCore
import SwiftUI

// MARK: - Tokens

/// Visual design tokens: subject gradients, radii, springs.
enum Theme {
    static let cornerRadius: CGFloat = 24
    static let smallRadius: CGFloat = 16

    /// Snappy, slightly bouncy default spring.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.72)
    static let softSpring = Animation.spring(response: 0.55, dampingFraction: 0.85)

    static let indigo = Color(red: 0.36, green: 0.36, blue: 0.95)
    static let violet = Color(red: 0.66, green: 0.33, blue: 0.97)
    static let coral = Color(red: 1.00, green: 0.42, blue: 0.42)
    static let pink = Color(red: 0.96, green: 0.36, blue: 0.68)
    static let mint = Color(red: 0.20, green: 0.82, blue: 0.60)
    static let teal = Color(red: 0.10, green: 0.68, blue: 0.78)
    static let amber = Color(red: 1.00, green: 0.66, blue: 0.20)
    static let rose = Color(red: 1.00, green: 0.33, blue: 0.40)

    static let correctGradient = LinearGradient(colors: [mint, teal], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let wrongGradient = LinearGradient(colors: [rose, amber], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Subject {
    /// Two-stop brand colours for the subject.
    var colors: [Color] {
        switch self {
        case .music: [Theme.indigo, Theme.violet]
        case .korean: [Theme.coral, Theme.pink]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var accent: Color { colors[0] }

    /// Large decorative glyph for cards.
    @ViewBuilder var glyph: some View {
        switch self {
        case .music: Image(systemName: "guitars.fill")
        case .korean: Text("한").fontWeight(.heavy)
        }
    }
}

// MARK: - Aurora background

/// Slowly drifting soft colour field behind content.
/// Static (frame `t = 0`) when Reduce Motion is on or `animated` is false (sessions, R3-2).
/// Holds its current frame (no jump on resume) while `running` is false — scrolling, a covering
/// session — or while the scene isn't active, so it never redraws when nobody benefits.
/// Every aurora frame forces the glass materials above it to re-blur their backdrop, so pausing
/// during scrolls keeps scroll frames inside the 8 ms ProMotion budget.
///
/// Performance: the field is pure blur, so it is drawn off the main thread into a bitmap
/// `downscale`× smaller (at 1× scale) and stretched to fill. Bilinear upscaling of a blurred
/// field is visually identical, but the per-frame blur touches ~140× fewer pixels than a
/// full-resolution 3× canvas, which keeps scrolling and springs at full ProMotion rate.
struct AuroraBackground: View {
    var colors: [Color] = Subject.music.colors
    var intensity: Double = 1
    /// `false` freezes the field on its rest frame (used in sessions to keep the GPU free for the prompt and mic).
    var animated: Bool = true
    /// `false` pauses on the current frame; resuming continues smoothly from it.
    var running: Bool = true

    @State private var pausedAt: Date?
    /// Total time spent paused, subtracted from the clock so the drift never jumps.
    @State private var pausedTotal: TimeInterval = 0

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let downscale: CGFloat = 4

    private var isStatic: Bool { reduceMotion || !animated }
    private var isHeld: Bool { !running || scenePhase != .active }

    var body: some View {
        GeometryReader { geo in
            let k = Self.downscale
            TimelineView(.animation(minimumInterval: 1 / 30, paused: isStatic || isHeld)) { ctx in
                let t = isStatic ? 0 : (pausedAt ?? ctx.date).timeIntervalSinceReferenceDate - pausedTotal
                Canvas(rendersAsynchronously: true) { gc, size in
                    draw(in: &gc, size: size, t: t)
                }
                .frame(width: max(1, geo.size.width / k), height: max(1, geo.size.height / k))
                .environment(\.displayScale, 1)
                .scaleEffect(k, anchor: .topLeading)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isHeld, initial: true) { _, held in
            if held {
                if pausedAt == nil { pausedAt = .now }
            } else if let start = pausedAt {
                pausedTotal += Date.now.timeIntervalSince(start)
                pausedAt = nil
            }
        }
    }

    private func draw(in gc: inout GraphicsContext, size: CGSize, t: Double) {
        let base = scheme == .dark ? 0.32 : 0.22
        let blobs: [(Color, Double, Double, Double)] = [
            (colors[0], 0.20, 0.15, 0.13),
            (colors[1 % colors.count], 0.85, 0.30, 0.09),
            (colors[0].opacity(0.8), 0.50, 0.90, 0.07),
        ]
        gc.addFilter(.blur(radius: min(size.width, size.height) * 0.18))
        for (i, (c, bx, by, speed)) in blobs.enumerated() {
            let phase = t * speed + Double(i) * 2.1
            let x = size.width * (bx + 0.12 * sin(phase))
            let y = size.height * (by + 0.08 * cos(phase * 1.3))
            let r = max(size.width, size.height) * (0.42 + 0.05 * sin(phase * 0.7))
            gc.fill(
                Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                with: .color(c.opacity(base * intensity))
            )
        }
    }
}

extension View {
    /// Puts an `AuroraBackground` behind a scrolling screen and pauses its drift while the
    /// screen's scroll view moves (iOS 18+), so scrolling gets the whole ProMotion frame budget.
    func auroraBackground(colors: [Color] = Subject.music.colors, intensity: Double = 1,
                          animated: Bool = true, running: Bool = true) -> some View {
        modifier(ScrollAwareAurora(colors: colors, intensity: intensity, animated: animated, running: running))
    }
}

private struct ScrollAwareAurora: ViewModifier {
    let colors: [Color]
    let intensity: Double
    let animated: Bool
    let running: Bool
    @State private var scrolling = false

    func body(content: Content) -> some View {
        tracked(content)
            .background {
                AuroraBackground(colors: colors, intensity: intensity, animated: animated, running: running && !scrolling)
            }
    }

    @ViewBuilder private func tracked(_ content: Content) -> some View {
        content.onScrollPhaseChange { _, phase in
            if scrolling != phase.isScrolling { scrolling = phase.isScrolling }
        }
    }
}

// MARK: - Glass card

struct GlassCard: ViewModifier {
    var radius: CGFloat = Theme.cornerRadius
    var tint: Color?

    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(.regularMaterial)
                    .overlay { if let tint { shape.fill(tint.opacity(0.08)) } }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(scheme == .dark ? 0.22 : 0.7), .white.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: (tint ?? .black).opacity(scheme == .dark ? 0.25 : 0.12), radius: 18, y: 8)
    }
}

extension View {
    func glassCard(radius: CGFloat = Theme.cornerRadius, tint: Color? = nil) -> some View {
        modifier(GlassCard(radius: radius, tint: tint))
    }

    /// Fades + lifts the view in on first appearance, staggered by `index`.
    func appearAnimation(index: Int = 0) -> some View {
        modifier(AppearAnimation(delay: Double(index) * 0.06))
    }
}

private struct AppearAnimation: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97)
            .onAppear {
                guard !shown else { return }
                withAnimation(Theme.softSpring.delay(delay)) { shown = true }
            }
    }
}

// MARK: - Button styles

/// Springy press feedback for any tappable surface.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(Theme.spring, value: configuration.isPressed)
    }
}

/// Circular glass icon button used in toolbars over aurora backgrounds.
struct CircleIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }
}

// MARK: - Progress

/// Rounded gradient progress bar with a glowing leading edge.
struct GradientProgressBar: View {
    let value: Double
    var colors: [Color] = Subject.music.colors

    var body: some View {
        GeometryReader { geo in
            let w = max(0, min(1, value)) * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(w, value > 0 ? 8 : 0))
                    .shadow(color: colors.last!.opacity(0.6), radius: 6)
            }
        }
        .frame(height: 8)
        .animation(Theme.spring, value: value)
        .accessibilityElement()
        .accessibilityValue(Fmt.percent(value))
    }
}

/// Animated ring gauge (0…1).
struct RingGauge: View {
    let value: Double
    var colors: [Color] = [Theme.mint, Theme.teal]
    var lineWidth: CGFloat = 14

    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    AngularGradient(colors: colors + [colors[0]], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: colors[0].opacity(0.45), radius: 8)
        }
        .onAppear {
            if reduceMotion { shown = value } else {
                withAnimation(.spring(response: 1.1, dampingFraction: 0.8).delay(0.15)) { shown = value }
            }
        }
        .onChange(of: value) { _, v in
            if reduceMotion { shown = v } else { withAnimation(Theme.softSpring) { shown = v } }
        }
    }
}

#Preview("Theme") {
    ZStack {
        AuroraBackground(colors: Subject.korean.colors)
        VStack(spacing: 24) {
            RingGauge(value: 0.82).frame(width: 120, height: 120)
            GradientProgressBar(value: 0.4, colors: Subject.korean.colors)
            Text("Glass").font(.title).padding(40).glassCard(tint: Theme.pink)
            CircleIconButton(systemImage: "xmark") {}
        }
        .padding()
    }
}
