/// One of the 12 pitch classes, `C = 0` … `B = 11`. Arithmetic is modulo 12.
public struct PitchClass: Hashable, Comparable, Codable, Sendable, CaseIterable {
    public let value: Int

    /// Normalises any integer into 0…11.
    @inlinable public init(_ value: Int) {
        let m = value % 12
        self.value = m < 0 ? m + 12 : m
    }

    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(Int.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }

    public static let allCases: [PitchClass] = (0..<12).map(PitchClass.init)
    /// The 7 natural pitch classes (C D E F G A B).
    public static let naturals: [PitchClass] = NoteLetter.allCases.map(\.pitchClass)

    @inlinable public func transposed(by semitones: Int) -> PitchClass { PitchClass(value + semitones) }

    public var isNatural: Bool { NoteLetter(naturalPitchClass: self) != nil }

    /// ASCII canonical sharp name used in `ItemKey`s (`"C#"`). Never change.
    public var canonicalSharpName: String { Self.asciiSharpNames[value] }

    private static let asciiSharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    public static func < (lhs: PitchClass, rhs: PitchClass) -> Bool { lhs.value < rhs.value }
}

/// Natural note letters.
public enum NoteLetter: Int, Codable, Sendable, CaseIterable {
    case c, d, e, f, g, a, b

    public var pitchClass: PitchClass {
        switch self {
        case .c: PitchClass(0)
        case .d: PitchClass(2)
        case .e: PitchClass(4)
        case .f: PitchClass(5)
        case .g: PitchClass(7)
        case .a: PitchClass(9)
        case .b: PitchClass(11)
        }
    }

    public var name: String {
        switch self {
        case .c: "C"
        case .d: "D"
        case .e: "E"
        case .f: "F"
        case .g: "G"
        case .a: "A"
        case .b: "B"
        }
    }

    /// The letter whose natural is `pc`, if any.
    public init?(naturalPitchClass pc: PitchClass) {
        switch pc.value {
        case 0: self = .c
        case 2: self = .d
        case 4: self = .e
        case 5: self = .f
        case 7: self = .g
        case 9: self = .a
        case 11: self = .b
        default: return nil
        }
    }
}

/// Accidental applied to a letter.
public enum Accidental: Int, Codable, Sendable, CaseIterable {
    case natural, sharp, flat

    public var semitones: Int {
        switch self {
        case .natural: 0
        case .sharp: 1
        case .flat: -1
        }
    }

    /// Unicode display symbol (`♯`, `♭`, or empty).
    public var symbol: String {
        switch self {
        case .natural: ""
        case .sharp: "♯"
        case .flat: "♭"
        }
    }
}

/// How a pitch class is written (e.g. C♯ vs D♭).
public struct NoteSpelling: Hashable, Codable, Sendable {
    public let letter: NoteLetter
    public let accidental: Accidental

    public init(_ letter: NoteLetter, _ accidental: Accidental = .natural) {
        self.letter = letter
        self.accidental = accidental
    }

    public var pitchClass: PitchClass { letter.pitchClass.transposed(by: accidental.semitones) }

    /// Display with Unicode accidentals, e.g. `"C♯"`.
    public var displayName: String { letter.name + accidental.symbol }

    /// Preferred spelling: naturals stay natural, otherwise sharp or flat as requested.
    public static func preferred(for pc: PitchClass, preferFlat: Bool) -> NoteSpelling {
        if let natural = NoteLetter(naturalPitchClass: pc) { return NoteSpelling(natural) }
        return preferFlat
            ? NoteSpelling(NoteLetter(naturalPitchClass: pc.transposed(by: 1))!, .flat)
            : NoteSpelling(NoteLetter(naturalPitchClass: pc.transposed(by: -1))!, .sharp)
    }
}
