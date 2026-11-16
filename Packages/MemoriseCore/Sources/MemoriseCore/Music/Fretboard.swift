/// Open-string pitches of a fretted instrument.
public struct Tuning: Hashable, Codable, Sendable {
    public let name: String
    /// MIDI numbers ordered from the lowest-numbered-last string, i.e. string N → 1
    /// (for guitar: string 6 → 1).
    public let openMidi: [Int]
    /// Optional human names, same order as `openMidi`.
    public let stringNames: [String]?

    public init(name: String, openMidi: [Int], stringNames: [String]? = nil) {
        precondition(stringNames == nil || stringNames!.count == openMidi.count)
        self.name = name
        self.openMidi = openMidi
        self.stringNames = stringNames
    }

    /// E2 A2 D3 G3 B3 E4.
    public static let standard = Tuning(
        name: "Standard",
        openMidi: [40, 45, 50, 55, 59, 64],
        stringNames: ["low E", "A", "D", "G", "B", "high E"]
    )

    public var stringCount: Int { openMidi.count }

    /// String numbers from the lowest-pitched to highest (6…1 on guitar).
    public var stringNumbers: [Int] { Array((1...stringCount).reversed()) }

    @inlinable func index(ofString n: Int) -> Int { stringCount - n }

    /// Open MIDI pitch of string `n` (1-based, 1 = highest).
    public func openMidi(string n: Int) -> Int { openMidi[index(ofString: n)] }

    public func openPitchClass(string n: Int) -> PitchClass { PitchClass(openMidi(string: n)) }

    /// Human name of string `n` (e.g. "low E").
    public func stringName(_ n: Int) -> String {
        if let names = stringNames { return names[index(ofString: n)] }
        return NoteSpelling.preferred(for: openPitchClass(string: n), preferFlat: false).displayName
    }
}

/// Fretboard geometry helpers.
public enum Fretboard {
    /// All frets in `fretRange` on string `n` that produce `pitchClass`, ascending.
    public static func frets(
        for pitchClass: PitchClass,
        onString n: Int,
        tuning: Tuning = .standard,
        fretRange: ClosedRange<Int>
    ) -> [Int] {
        let open = tuning.openPitchClass(string: n)
        // Smallest non-negative fret producing the pitch class, then every octave.
        var f = PitchClass(pitchClass.value - open.value).value
        if f < fretRange.lowerBound { f += ((fretRange.lowerBound - f + 11) / 12) * 12 }
        guard f <= fretRange.upperBound else { return [] }
        return Array(stride(from: f, through: fretRange.upperBound, by: 12))
    }

    /// Pitch class at a position.
    public static func pitchClass(string n: Int, fret: Int, tuning: Tuning = .standard) -> PitchClass {
        PitchClass(tuning.openMidi(string: n) + fret)
    }
}
