import MemoriseCore
import SwiftUI

/// Strings × columns grid coloured by response-time EWMA (§11.6). Columns are pitch classes
/// (Fretboard Notes) or frets (Name the Note).
struct HeatmapGrid: View {
    struct Column: Hashable, Identifiable {
        let id: Int
        let label: String
    }

    struct Cell: Identifiable, Hashable {
        let string: Int
        let column: Int
        let key: ItemKey
        var id: ItemKey { key }
    }

    /// String numbers, top row first.
    let rows: [Int]
    let columns: [Column]
    let stats: [ItemKey: ItemStats]
    let key: (_ string: Int, _ column: Int) -> ItemKey
    /// Popover title, e.g. "A on string 6".
    let title: (_ string: Int, _ column: Int) -> String
    /// Large badge text in the popover, e.g. "A" or "5".
    let badge: (_ string: Int, _ column: Int) -> String

    @State private var selected: Cell?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reference: Double {
        Statistics.median(stats.values.compactMap(\.ewmaResponseMs)) ?? SchedulerConstants.standard.fallbackReferenceMs
    }

    var body: some View {
        let ref = reference
        let scrolls = columns.count > 13
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if scrolls {
                    ScrollView(.horizontal, showsIndicators: false) { grid(ref, cellSize: 22) }
                } else {
                    grid(ref, cellSize: nil)
                }
            }
            legend
        }
        .padding(.vertical, 8)
        .onAppear { appeared = true }
    }

    private func grid(_ ref: Double, cellSize: CGFloat?) -> some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                Text("")
                ForEach(columns) { col in
                    Text(col.label)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(width: cellSize)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.element) { row, s in
                GridRow {
                    Text("\(s)")
                        .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Subject.music.gradient, in: Circle())
                    ForEach(Array(columns.enumerated()), id: \.element) { idx, col in
                        cell(Cell(string: s, column: col.id, key: key(s, col.id)), reference: ref, order: row + idx)
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }

    private func cell(_ c: Cell, reference: Double, order: Int) -> some View {
        let s = stats[c.key]
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
            .animation(reduceMotion ? nil : Theme.spring.delay(appeared ? 0 : Double(min(order, 30)) * 0.018), value: appeared)
            .animation(Theme.spring, value: isSelected)
            .onTapGesture { selected = c }
            .popover(item: Binding(get: { selected == c ? selected : nil }, set: { selected = $0 })) { cell in
                CellDetail(badge: badge(cell.string, cell.column), title: title(cell.string, cell.column),
                           stats: stats[cell.key], reference: reference)
                    .presentationCompactAdaptation(.popover)
            }
            .accessibilityElement()
            .accessibilityLabel(title(c.string, c.column))
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

extension HeatmapGrid {
    /// Strings × pitch classes (Fretboard Notes).
    static func notes(stats: [ItemKey: ItemStats], tuning: Tuning, highEOnTop: Bool) -> HeatmapGrid {
        func name(_ pc: Int) -> String { NoteSpelling.preferred(for: PitchClass(pc), preferFlat: false).displayName }
        return HeatmapGrid(
            rows: highEOnTop ? Array(tuning.stringNumbers.reversed()) : tuning.stringNumbers,
            columns: PitchClass.allCases.map { Column(id: $0.value, label: name($0.value)) },
            stats: stats,
            key: { s, pc in FretboardNotesDeck.itemKey(string: s, pitchClass: PitchClass(pc), tuning: tuning.id) },
            title: { s, pc in "\(name(pc)) on string \(s)" },
            badge: { _, pc in name(pc) }
        )
    }

    /// Strings × frets (Name the Note).
    static func positions(stats: [ItemKey: ItemStats], tuning: Tuning, frets: ClosedRange<Int>, highEOnTop: Bool) -> HeatmapGrid {
        func name(_ s: Int, _ f: Int) -> String {
            NoteSpelling.preferred(for: Fretboard.pitchClass(string: s, fret: f, tuning: tuning), preferFlat: false).displayName
        }
        return HeatmapGrid(
            rows: highEOnTop ? Array(tuning.stringNumbers.reversed()) : tuning.stringNumbers,
            columns: frets.map { Column(id: $0, label: "\($0)") },
            stats: stats,
            key: { s, f in FretboardNamesDeck.itemKey(FretPosition(string: s, fret: f), tuning: tuning.id) },
            title: { s, f in "String \(s), fret \(f) · \(name(s, f))" },
            badge: { s, f in name(s, f) }
        )
    }
}

private extension View {
    func legendChip() -> some View {
        padding(.horizontal, 8).padding(.vertical, 5)
            .background(.primary.opacity(0.06), in: Capsule())
    }
}

private struct CellDetail: View {
    let badge: String
    let title: String
    let stats: ItemStats?
    let reference: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(badge)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(width: 52, height: 52)
                    .background(Subject.music.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
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

/// Generic per-item stats list (Find All, Intervals, Interval Ear): slowest/weakest first.
struct ItemStatsList: View {
    struct Item: Identifiable {
        let key: ItemKey
        let label: String
        var id: ItemKey { key }
    }

    let title: String
    let items: [Item]
    let stats: [ItemKey: ItemStats]

    var body: some View {
        let calc = WeightCalculator(pool: [], stats: stats, focus: .normal, now: .now)
        let ranked = items.sorted { a, b in
            calc.baseWeight(stats[a.key]) > calc.baseWeight(stats[b.key])
        }
        Section(title) {
            ForEach(ranked) { item in
                let s = stats[item.key]
                HStack {
                    Text(item.label).font(.headline)
                    Spacer()
                    if let s, s.attempts > 0 {
                        Text("\(Fmt.percent(s.accuracy)) · \(Fmt.seconds(s.ewmaResponseMs))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    } else {
                        Text("new").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
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
    return List { HeatmapGrid.notes(stats: stats, tuning: .standard, highEOnTop: true) }.environment(AppEnvironment.preview())
}
