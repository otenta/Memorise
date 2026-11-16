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
        VStack(alignment: .leading, spacing: 12) {
            Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    Text("")
                    ForEach(PitchClass.allCases, id: \.self) { pc in
                        Text(NoteSpelling.preferred(for: pc, preferFlat: false).displayName)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                ForEach(Array(strings.enumerated()), id: \.element) { row, s in
                    GridRow {
                        Text("\(s)")
                            .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Subject.music.gradient, in: Circle())
                        ForEach(Array(PitchClass.allCases.enumerated()), id: \.element) { col, pc in
                            cell(Cell(string: s, pitchClass: pc), reference: ref, order: row + col)
                        }
                    }
                }
            }
            legend
        }
        .padding(.vertical, 8)
        .onAppear { appeared = true }
    }

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func cell(_ c: Cell, reference: Double, order: Int) -> some View {
        let s = stats[c.id]
        let seen = s?.ewmaResponseMs != nil
        let color: Color = if let t = s?.ewmaResponseMs { Palette.heat(ratio: t / reference) } else { Color.gray.opacity(0.18) }
        let isSelected = selected == c
        let shown = appeared || reduceMotion
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(seen ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if (s?.ewmaError ?? 0) > 0.3 {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .black)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.primary, lineWidth: isSelected ? 2 : 0)
            }
            .shadow(color: seen ? color.opacity(0.35) : .clear, radius: 3, y: 1)
            .scaleEffect(isSelected ? 1.18 : (shown ? 1 : 0.3))
            .opacity(shown ? 1 : 0)
            .zIndex(isSelected ? 1 : 0)
            .animation(reduceMotion ? nil : Theme.spring.delay(appeared ? 0 : Double(order) * 0.018), value: appeared)
            .animation(Theme.spring, value: isSelected)
            .onTapGesture { selected = c }
            .popover(item: Binding(get: { selected == c ? selected : nil }, set: { selected = $0 })) { cell in
                CellDetail(cell: cell, stats: stats[cell.id], reference: reference)
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityElement()
            .accessibilityLabel("String \(c.string), \(NoteSpelling.preferred(for: c.pitchClass, preferFlat: false).displayName)")
            .accessibilityValue(s?.ewmaResponseMs.map { Fmt.seconds($0) } ?? "not seen")
            .accessibilityAddTraits(.isButton)
    }

    private var legend: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hare.fill")
                LinearGradient(colors: [Palette.heat(ratio: 0.5), Palette.heat(ratio: 1), Palette.heat(ratio: 2)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 56, height: 6).clipShape(Capsule())
                Image(systemName: "tortoise.fill")
            }
            .legendChip()
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.25)).frame(width: 10, height: 10)
                Text("unseen")
            }
            .legendChip()
            HStack(spacing: 4) {
                Image(systemName: "xmark").fontWeight(.black)
                Text("often wrong")
            }
            .legendChip()
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }
}

private extension View {
    func legendChip() -> some View {
        padding(.horizontal, 8).padding(.vertical, 5)
            .background(.primary.opacity(0.06), in: Capsule())
    }
}

private struct CellDetail: View {
    let cell: FretboardHeatmap.Cell
    let stats: ItemStats?
    let reference: Double

    var body: some View {
        let name = NoteSpelling.preferred(for: cell.pitchClass, preferFlat: false).displayName
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(name)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Subject.music.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name) on string \(cell.string)").font(.headline)
                    if let s = stats, s.attempts > 0 {
                        Text("\(s.attempts) attempt\(s.attempts == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let s = stats, s.attempts > 0 {
                HStack(spacing: 16) {
                    ZStack {
                        RingGauge(value: s.accuracy ?? 0, lineWidth: 6)
                        Text(Fmt.percent(s.accuracy)).font(.caption.weight(.bold).monospacedDigit())
                    }
                    .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 6) {
                        metric("timer", "Typical", Fmt.seconds(s.ewmaResponseMs),
                               color: s.ewmaResponseMs.map { Palette.heat(ratio: $0 / reference) } ?? .secondary)
                        metric("trophy.fill", "Best", s.bestResponseMs.map { Fmt.seconds($0) } ?? "–", color: Theme.amber)
                    }
                }
            } else {
                Label("Not practised yet", systemImage: "sparkles").foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding()
        .frame(minWidth: 240)
    }

    private func metric(_ icon: String, _ title: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
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
