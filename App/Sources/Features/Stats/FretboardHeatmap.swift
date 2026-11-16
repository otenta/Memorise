import MemoriseCore
import SwiftUI

/// Strings × pitch classes grid colored by response-time EWMA (§11.6).
struct FretboardHeatmap: View {
    let stats: [ItemKey: ItemStats]
    @Environment(AppEnvironment.self) private var env
    @State private var selected: Cell?

    struct Cell: Identifiable, Hashable {
        let string: Int
        let pitchClass: PitchClass
        var id: ItemKey { FretboardNotesDeck.itemKey(string: string, pitchClass: pitchClass) }
    }

    private var reference: Double {
        Statistics.median(stats.values.compactMap(\.ewmaResponseMs)) ?? SchedulerConstants.standard.fallbackReferenceMs
    }

    var body: some View {
        let strings = env.settings.highEOnTop ? Array(1...6) : Array((1...6).reversed())
        let ref = reference
        VStack(alignment: .leading, spacing: 8) {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                GridRow {
                    Text("")
                    ForEach(PitchClass.allCases, id: \.self) { pc in
                        Text(NoteSpelling.preferred(for: pc, preferFlat: false).displayName)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                ForEach(strings, id: \.self) { s in
                    GridRow {
                        Text("\(s)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        ForEach(PitchClass.allCases, id: \.self) { pc in
                            cell(Cell(string: s, pitchClass: pc), reference: ref)
                        }
                    }
                }
            }
            legend
        }
        .padding(.vertical, 6)
    }

    private func cell(_ c: Cell, reference: Double) -> some View {
        let s = stats[c.id]
        let color: Color = if let t = s?.ewmaResponseMs { Palette.heat(ratio: t / reference) } else { Color.gray.opacity(0.25) }
        return RoundedRectangle(cornerRadius: 3)
            .fill(color)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if (s?.ewmaError ?? 0) > 0.3 {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                }
            }
            .onTapGesture { selected = c }
            .popover(item: Binding(get: { selected == c ? selected : nil }, set: { selected = $0 })) { cell in
                CellDetail(cell: cell, stats: stats[cell.id])
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityElement()
            .accessibilityLabel("String \(c.string), \(NoteSpelling.preferred(for: c.pitchClass, preferFlat: false).displayName)")
            .accessibilityValue(s?.ewmaResponseMs.map { Fmt.seconds($0) } ?? "not seen")
            .accessibilityAddTraits(.isButton)
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("fast").font(.caption2)
            LinearGradient(colors: [Palette.heat(ratio: 0.5), Palette.heat(ratio: 1), Palette.heat(ratio: 2)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 6).clipShape(Capsule())
            Text("slow").font(.caption2)
            RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.25)).frame(width: 10, height: 10)
            Text("unseen").font(.caption2)
            Image(systemName: "xmark").font(.caption2)
            Text("often wrong").font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}

private struct CellDetail: View {
    let cell: FretboardHeatmap.Cell
    let stats: ItemStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(NoteSpelling.preferred(for: cell.pitchClass, preferFlat: false).displayName) on string \(cell.string)")
                .font(.headline)
            if let s = stats, s.attempts > 0 {
                LabeledContent("Attempts", value: "\(s.attempts)")
                LabeledContent("Accuracy", value: Fmt.percent(s.accuracy))
                LabeledContent("Typical time", value: Fmt.seconds(s.ewmaResponseMs))
                LabeledContent("Best", value: s.bestResponseMs.map { Fmt.seconds($0) } ?? "–")
            } else {
                Text("Not practised yet").foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding()
        .frame(minWidth: 220)
    }
}

#Preview {
    let stats: [ItemKey: ItemStats] = Dictionary(uniqueKeysWithValues: (1...6).flatMap { s in
        PitchClass.naturals.map { pc in
            let key = FretboardNotesDeck.itemKey(string: s, pitchClass: pc)
            return (key, ItemStats(itemKey: key, deckID: FretboardNotesDeck.deckID, attempts: 3, correctCount: 2,
                                   ewmaResponseMs: Double(800 + (s * 700 + pc.value * 311) % 4_000), ewmaError: Double(pc.value % 5) / 8))
        }
    })
    return List { FretboardHeatmap(stats: stats) }.environment(AppEnvironment.preview())
}
