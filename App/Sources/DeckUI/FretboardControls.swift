import MemoriseCore
import SwiftUI

/// Tuning menu picker.
struct TuningPicker: View {
    @Binding var tuning: TuningID

    var body: some View {
        Picker("Tuning", selection: $tuning) {
            ForEach(Tuning.presets) { t in Text(t.name).tag(t.id) }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("tuningPicker")
    }
}

/// Multi-select string chips, labelled from the tuning ("6 · D").
struct StringChips: View {
    @Binding var strings: Set<Int>
    let tuning: Tuning

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tuning.stringNumbers, id: \.self) { s in
                let on = strings.contains(s)
                Button {
                    withAnimation(Theme.spring) {
                        if on { if strings.count > 1 { strings.remove(s) } } else { strings.insert(s) }
                    }
                } label: {
                    VStack(spacing: 0) {
                        Text("\(s)").font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
                        Text(tuning.openNoteName(s)).font(.system(size: 10, weight: .semibold, design: .rounded))
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        Capsule().fill(on ? AnyShapeStyle(Subject.music.gradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                            .shadow(color: on ? Theme.indigo.opacity(0.35) : .clear, radius: 5, y: 3)
                    }
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .scaleEffect(on ? 1 : 0.92)
                }
                .buttonStyle(PressableStyle(scale: 0.88))
                .accessibilityLabel("String \(s), \(tuning.stringName(s))")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Fret-range upper bound picker.
struct MaxFretPicker: View {
    @Binding var range: ClosedRange<Int>
    var title = "Max fret"

    var body: some View {
        Picker(title, selection: Binding(
            get: { range.upperBound },
            set: { range = min(range.lowerBound, $0)...$0 }
        )) {
            ForEach(FretboardOptions.maxFretPresets, id: \.self) { Text("\($0)").tag($0) }
        }
    }
}

/// Setup section for `FretboardOptions` (Notes, Name the Note, Find All).
struct FretboardOptionsSection: View {
    @Binding var options: FretboardOptions

    var body: some View {
        Section {
            TuningPicker(tuning: $options.tuning)
            StringChips(strings: $options.strings, tuning: options.tuningPreset)
        } header: {
            Text("Tuning & strings")
        }
        Section("Notes") {
            Picker("Notes", selection: $options.noteSet) {
                Text("Naturals").tag(FretboardOptions.NoteSet.naturals)
                Text("All notes").tag(FretboardOptions.NoteSet.all)
            }
            .pickerStyle(.segmented)
            if options.noteSet == .all {
                AccidentalPicker(spelling: $options.accidentalSpelling)
            }
            MaxFretPicker(range: $options.fretRange)
        }
    }
}

struct AccidentalPicker: View {
    @Binding var spelling: AccidentalSpelling

    var body: some View {
        Picker("Accidentals", selection: $spelling) {
            Text("Sharps").tag(AccidentalSpelling.sharps)
            Text("Flats").tag(AccidentalSpelling.flats)
            Text("Mixed").tag(AccidentalSpelling.mixed)
        }
        .pickerStyle(.segmented)
    }
}

/// Multi-select interval chips.
struct IntervalChips: View {
    @Binding var intervals: Set<Interval>

    private let columns = [GridItem(.adaptive(minimum: 52), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Interval.allCases, id: \.self) { i in
                let on = intervals.contains(i)
                Button {
                    withAnimation(Theme.spring) {
                        if on { if intervals.count > 1 { intervals.remove(i) } } else { intervals.insert(i) }
                    }
                } label: {
                    Text(i.shortName)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            Capsule().fill(on ? AnyShapeStyle(Subject.music.gradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                        }
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel(i.longName)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// Stats section with a tuning menu; content is rebuilt for the selected tuning.
struct TunedStatsSection<Content: View>: View {
    let title: String
    let initialTuning: TuningID
    @ViewBuilder let content: (Tuning) -> Content

    @State private var tuning: TuningID?

    var body: some View {
        let current = Tuning.preset(tuning ?? initialTuning)
        Section {
            content(current)
        } header: {
            HStack {
                Text(title)
                Spacer()
                Menu {
                    Picker("Tuning", selection: Binding(get: { current.id }, set: { tuning = $0 })) {
                        ForEach(Tuning.presets) { Text($0.name).tag($0.id) }
                    }
                } label: {
                    Label(current.name, systemImage: "tuningfork").font(.caption.weight(.semibold))
                }
                .textCase(nil)
            }
        }
    }
}

/// Shared fretboard rendering settings.
extension AppSettings {
    func board(maxFret: Int, tuning: Tuning, marks: [FretMark], highlight: Set<Int> = []) -> FretboardView {
        FretboardView(
            stringCount: tuning.stringCount, maxFret: maxFret, marks: marks, highlightedStrings: highlight,
            leftHanded: leftHanded, highEOnTop: highEOnTop
        )
    }

    func board(window: ClosedRange<Int>, tuning: Tuning = .standard, marks: [FretMark], highlight: Set<Int> = []) -> FretboardView {
        FretboardView(
            stringCount: tuning.stringCount, fretWindow: window, marks: marks, highlightedStrings: highlight,
            leftHanded: leftHanded, highEOnTop: highEOnTop
        )
    }

    /// Dot text for an M3 note, per the "Dot labels" setting.
    func dotLabel(_ n: FretNote) -> String { dotLabels == .degrees ? n.degree : n.spelling.displayName }

    /// Marks for generated notes: roots as `.answer`, other tones `.secondary`.
    func marks(_ notes: [FretNote], badges: Bool = false, emphasiseFirst: Bool = false) -> [FretMark] {
        notes.enumerated().map { i, n in
            FretMark(string: n.position.string, fret: n.position.fret, label: dotLabel(n),
                     style: n.isRoot ? .answer : .secondary, badge: badges ? "\(i + 1)" : nil,
                     emphasised: emphasiseFirst && i == 0)
        }
    }
}
