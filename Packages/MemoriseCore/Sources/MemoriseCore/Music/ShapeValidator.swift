/// Load-time checks for chord shapes (runs in every configuration, like `DeckValidator`).
/// Failing shapes are dropped and reported.
public enum ShapeValidator {
    public static func validate(_ shapes: [ChordShape], tuning: Tuning = .standard) -> (valid: [ChordShape], warnings: [String]) {
        var seen: Set<String> = []
        var valid: [ChordShape] = []
        var warnings: [String] = []
        for shape in shapes {
            var problems: [String] = []
            if !seen.insert(shape.id).inserted { problems.append("duplicate id") }
            problems += check(shape, tuning: tuning)
            if problems.isEmpty {
                valid.append(shape)
            } else {
                warnings.append("Shape \(shape.id): " + problems.joined(separator: "; "))
            }
        }
        return (valid, warnings)
    }

    static func check(_ shape: ChordShape, tuning: Tuning) -> [String] {
        guard shape.frets.count == 6, shape.fingers.count == 6 else { return ["needs 6 frets and 6 fingers"] }
        guard (1...6).contains(shape.rootString), shape.frets[ChordShape.index(ofString: shape.rootString)] != nil else {
            return ["root string is muted or invalid"]
        }
        var problems: [String] = []

        // Root-relative semitones of every sounded string (root-invariant for movable shapes).
        let rootPitch: Int
        if shape.movable {
            rootPitch = tuning.openMidi(string: shape.rootString) + shape.frets[ChordShape.index(ofString: shape.rootString)]!
        } else {
            guard let root = shape.rootSpelling else { return ["open shape without a root"] }
            rootPitch = tuning.openMidi(string: shape.rootString) + shape.frets[ChordShape.index(ofString: shape.rootString)]!
            if PitchClass(rootPitch) != root.pitchClass { problems.append("root string doesn't sound \(root.displayName)") }
            if shape.frets.contains(where: { ($0 ?? 0) < 0 }) { problems.append("negative fret") }
        }
        var sounded: [(string: Int, midi: Int, fret: Int)] = []
        for (i, f) in shape.frets.enumerated() {
            guard let f else { continue }
            let s = 6 - i
            sounded.append((s, tuning.openMidi(string: s) + f, f))
        }
        let intervals = Set(sounded.map { PitchClass($0.midi - rootPitch).value })
        let degrees = shape.quality.degrees
        let allowed = Set(degrees.map { PitchClass($0.semitones).value })
        if !intervals.isSubset(of: allowed) { problems.append("sounds non-chord tones") }
        if !intervals.contains(0) { problems.append("no root") }
        if shape.quality.needsThird, let third = degrees.first(where: { $0.letters == 2 }), !intervals.contains(third.semitones) {
            problems.append("no 3rd")
        }
        if shape.quality.isSeventh, let seventh = degrees.first(where: { $0.letters == 6 }), !intervals.contains(PitchClass(seventh.semitones).value) {
            problems.append("no 7th")
        }
        if let lowest = sounded.min(by: { $0.midi < $1.midi }), PitchClass(lowest.midi - rootPitch).value != 0 {
            problems.append("lowest note isn't the root")
        }
        // Fingers for fretted notes. Open shapes: fret 0 is open (no finger); movable: all fretted.
        for (i, f) in shape.frets.enumerated() {
            guard let f else { continue }
            let fretted = shape.movable || f > 0
            if fretted && shape.fingers[i] == nil { problems.append("string \(6 - i) has no finger") }
        }
        let fretted = shape.movable ? sounded.map(\.fret) : sounded.map(\.fret).filter { $0 > 0 }
        if let lo = fretted.min(), let hi = fretted.max(), hi - lo > 3 {
            problems.append("span > 4 frets")
        }
        return problems
    }
}
