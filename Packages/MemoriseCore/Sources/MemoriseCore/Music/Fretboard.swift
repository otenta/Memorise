/// Stable identifier of a tuning preset. Raw values appear in `ItemKey`s and persisted
/// options — **never change them**.
public enum TuningID: String, Codable, Sendable, CaseIterable, Hashable {
    case standard, dropD, halfDown, dadgad, openG
}

/// Open-string pitches of a fretted instrument.
public struct Tuning: Hashable, Sendable, Identifiable {
    public let id: TuningID
    public let name: String
    /// MIDI numbers ordered from string N → 1 (for guitar: string 6 → 1, low to high).
    public let openMidi: [Int]
    /// Whether string names use flats (E♭ standard).
    public let prefersFlatNames: Bool

    public init(id: TuningID, name: String, openMidi: [Int], prefersFlatNames: Bool = false) {
        self.id = id
        self.name = name
        self.openMidi = openMidi
        self.prefersFlatNames = prefersFlatNames
    }

    /// E2 A2 D3 G3 B3 E4.
    public static let standard = Tuning(id: .standard, name: "Standard", openMidi: [40, 45, 50, 55, 59, 64])
    public static let dropD = Tuning(id: .dropD, name: "Drop D", openMidi: [38, 45, 50, 55, 59, 64])
    public static let halfDown = Tuning(id: .halfDown, name: "E♭ standard", openMidi: [39, 44, 49, 54, 58, 63], prefersFlatNames: true)
    public static let dadgad = Tuning(id: .dadgad, name: "DADGAD", openMidi: [38, 45, 50, 55, 57, 62])
    public static let openG = Tuning(id: .openG, name: "Open G", openMidi: [38, 43, 50, 55, 59, 62])

    public static let presets: [Tuning] = [.standard, .dropD, .halfDown, .dadgad, .openG]

    public static func preset(_ id: TuningID) -> Tuning {
        switch id {
        case .standard: .standard
        case .dropD: .dropD
        case .halfDown: .halfDown
        case .dadgad: .dadgad
        case .openG: .openG
        }
    }

    public var stringCount: Int { openMidi.count }

    /// String numbers from the lowest-pitched to highest (6…1 on guitar).
    public var stringNumbers: [Int] { Array((1...stringCount).reversed()) }

    @inlinable func index(ofString n: Int) -> Int { stringCount - n }

    /// Open MIDI pitch of string `n` (1-based, 1 = highest).
    public func openMidi(string n: Int) -> Int { openMidi[index(ofString: n)] }

    public func openPitchClass(string n: Int) -> PitchClass { PitchClass(openMidi(string: n)) }

    /// Open-string note name, e.g. "E", "E♭".
    public func openNoteName(_ n: Int) -> String {
        NoteSpelling.preferred(for: openPitchClass(string: n), preferFlat: prefersFlatNames).displayName
    }

    /// Human name of string `n`: lowest string "low X", highest "high X", others "X".
    public func stringName(_ n: Int) -> String {
        let note = openNoteName(n)
        if n == stringCount { return "low \(note)" }
        if n == 1 { return "high \(note)" }
        return note
    }
}

/// A position on the neck.
public struct FretPosition: Hashable, Sendable, Codable {
    /// 1 = highest string.
    public let string: Int
    /// 0 = open.
    public let fret: Int

    public init(string: Int, fret: Int) {
        self.string = string
        self.fret = fret
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

    /// Every position of `pitchClass` on `strings` within `fretRange`, low string first, then fret.
    public static func positions(
        of pitchClass: PitchClass,
        strings: some Collection<Int>,
        tuning: Tuning = .standard,
        fretRange: ClosedRange<Int>
    ) -> [FretPosition] {
        var result: [FretPosition] = []
        for s in tuning.stringNumbers where strings.contains(s) {
            for f in frets(for: pitchClass, onString: s, tuning: tuning, fretRange: fretRange) {
                result.append(FretPosition(string: s, fret: f))
            }
        }
        return result
    }

    /// MIDI pitch at a position.
    @inlinable public static func midi(string n: Int, fret: Int, tuning: Tuning = .standard) -> Int {
        tuning.openMidi(string: n) + fret
    }

    /// Pitch class at a position.
    public static func pitchClass(string n: Int, fret: Int, tuning: Tuning = .standard) -> PitchClass {
        PitchClass(tuning.openMidi(string: n) + fret)
    }
}
