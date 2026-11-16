import SwiftUI

/// Large, full-width action button (≥ 60 pt tall).
struct BigButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.title2.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .tint(tint)
    }
}

/// Compact metric tile with an optional delta line.
struct StatTile: View {
    let title: String
    let value: String
    var delta: String?
    var deltaColor: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
            if let delta {
                Text(delta).font(.caption.monospacedDigit()).foregroundStyle(deltaColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack {
        HStack {
            StatTile(title: "Cards", value: "20")
            StatTile(title: "Median", value: "2.4 s", delta: "▼ 300 ms", deltaColor: .green)
        }
        BigButton(title: "OK", systemImage: "checkmark") {}
    }
    .padding()
}
