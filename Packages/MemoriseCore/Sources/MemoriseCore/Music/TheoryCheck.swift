/// Startup guard (DEBUG) for the M2 theory primitives. Not a test target: runs at app launch.
public enum TheoryCheck {
    /// Returns human-readable errors (empty = OK).
    public static func run() -> [String] {
        var errors: [String] = []
        func expect(_ s: NoteSpelling, _ i: Interval, _ want: NoteSpelling?) {
            let got = s.transposed(by: i)
            if got != want {
                errors.append("\(s.displayName) + \(i.rawValue) = \(got?.displayName ?? "nil"), want \(want?.displayName ?? "nil")")
            }
        }
        expect(NoteSpelling(.c), .M3, NoteSpelling(.e))
        expect(NoteSpelling(.e), .M3, NoteSpelling(.g, .sharp))
        expect(NoteSpelling(.b, .flat), .P4, NoteSpelling(.e, .flat))
        expect(NoteSpelling(.f), .TT, NoteSpelling(.b))
        expect(NoteSpelling(.a, .sharp), .M3, nil)

        for letter in NoteLetter.allCases {
            let root = NoteSpelling(letter)
            for i in Interval.allCases {
                guard let t = root.transposed(by: i) else { continue }
                if t.pitchClass != root.pitchClass.transposed(by: i.semitones) {
                    errors.append("\(root.displayName) + \(i.rawValue) has wrong pitch class \(t.displayName)")
                }
            }
        }

        if abs(Pitch(midi: 69).frequency - 440) > 1e-9 { errors.append("MIDI 69 ≠ 440 Hz") }
        if Pitch(midi: 60).octave != 4 { errors.append("MIDI 60 is not C4") }
        if Pitch.nearest(toFrequency: 110).pitch.midi != 45 { errors.append("110 Hz is not A2") }
        if Fretboard.midi(string: 6, fret: 5) != 45 { errors.append("string 6 fret 5 is not A2") }
        if Fretboard.frets(for: PitchClass(4), onString: 6, tuning: .dropD, fretRange: 0...15) != [2, 14] {
            errors.append("Drop D: E on string 6 is not frets 2 and 14")
        }
        return errors
    }
}
