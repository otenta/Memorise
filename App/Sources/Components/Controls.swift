import MemoriseCore
import SwiftUI

/// Large, full-width action button (≥ 60 pt tall) with a gradient fill and springy press.
struct BigButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = .accentColor
    /// Overrides `tint` with a two-stop gradient.
    var colors: [Color]?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(GradientButtonStyle(colors: colors ?? [tint, tint.opacity(0.78)]))
    }
}

struct GradientButtonStyle: ButtonStyle {
    let colors: [Color]
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let fill: [Color] = isEnabled ? colors : [.gray.opacity(0.45), .gray.opacity(0.35)]
        configuration.label
            .foregroundStyle(.white)
            .background {
                shape.fill(LinearGradient(colors: fill, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .top) {
                        // Soft top sheen.
                        shape.fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
                    }
            }
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: (isEnabled ? colors[0] : .clear).opacity(configuration.isPressed ? 0.2 : 0.4),
                    radius: configuration.isPressed ? 6 : 14, y: configuration.isPressed ? 3 : 8)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(Theme.spring, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.2), value: isEnabled)
    }
}

/// Compact glass metric tile with an optional icon and delta line.
struct StatTile: View {
    let title: String
    let value: String
    var delta: String?
    var deltaColor: Color = .secondary
    var systemImage: String?
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
            if let delta {
                Text(delta)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(deltaColor)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(deltaColor.opacity(0.12), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(radius: 18, tint: tint)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        AuroraBackground()
        VStack {
            HStack {
                StatTile(title: "Cards", value: "20", systemImage: "rectangle.stack.fill")
                StatTile(title: "Median", value: "2.4 s", delta: "▼ 300 ms", deltaColor: .green, systemImage: "timer", tint: .orange)
            }
            BigButton(title: "Start", systemImage: "play.fill", colors: Subject.music.colors) {}
            BigButton(title: "Disabled", systemImage: "play.fill") {}.disabled(true)
        }
        .padding()
    }
}
