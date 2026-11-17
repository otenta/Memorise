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
    /// Raw values are persisted — append only.
    case natural, sharp, flat, doubleFlat, doubleSharp

    public var semitones: Int {
        switch self {
        case .natural: 0
        case .sharp: 1
        case .flat: -1
        case .doubleFlat: -2
        case .doubleSharp: 2
        }
    }

    /// Accidental for a signed semitone offset (−2…2).
    public init?(semitones: Int) {
        switch semitones {
        case 0: self = .natural
        case 1: self = .sharp
        case -1: self = .flat
        case -2: self = .doubleFlat
        case 2: self = .doubleSharp
        default: return nil
        }
    }

    public var isDouble: Bool { self == .doubleFlat || self == .doubleSharp }

    /// ASCII form used in `ItemKey`s (`#`, `b`, `bb`, `x`). Never change.
    public var ascii: String {
        switch self {
        case .natural: ""
        case .sharp: "#"
        case .flat: "b"
        case .doubleFlat: "bb"
        case .doubleSharp: "x"
        }
    }

    /// Spoken form: "flat", "sharp"…
    public var spoken: String {
        switch self {
        case .natural: ""
        case .sharp: "sharp"
        case .flat: "flat"
        case .doubleFlat: "double flat"
        case .doubleSharp: "double sharp"
        }
    }

    /// Unicode display symbol (`♯`, `♭`, or empty).
    public var symbol: String {
        switch self {
        case .natural: ""
        case .sharp: "♯"
        case .flat: "♭"
        case .doubleFlat: "𝄫"
        case .doubleSharp: "𝄪"
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

    /// ASCII spelling used in `ItemKey`s, e.g. `"Bb"`, `"F#"`. Never change.
    public var ascii: String { letter.name + accidental.ascii }

    /// "B flat"
    public var spokenName: String { accidental == .natural ? letter.name : "\(letter.name) \(accidental.spoken)" }

    /// Parses an ASCII spelling (`"C"`, `"Bb"`, `"F#"`, `"Ebb"`, `"Fx"`).
    public init?(ascii: String) {
        guard let first = ascii.first, let letter = NoteLetter.allCases.first(where: { $0.name == String(first) }) else { return nil }
        guard let acc = Accidental.allCases.first(where: { $0.ascii == String(ascii.dropFirst()) }) else { return nil }
        self.init(letter, acc)
    }

    /// The note `letters` letter steps and `semitones` above this one, spelled on the target
    /// letter; `nil` if that needs more than a double accidental (or any double when not allowed).
    public func adding(letters: Int, semitones: Int, allowDouble: Bool = false) -> NoteSpelling? {
        let all = NoteLetter.allCases
        let target = all[((letter.rawValue + letters) % 7 + 7) % 7]
        let wanted = pitchClass.transposed(by: semitones)
        var diff = (wanted.value - target.pitchClass.value) % 12
        if diff > 6 { diff -= 12 }
        if diff < -6 { diff += 12 }
        guard let acc = Accidental(semitones: diff), allowDouble || !acc.isDouble else { return nil }
        return NoteSpelling(target, acc)
    }

    /// The other common single-accidental spelling of this pitch class (C♯ ⇄ D♭), if any.
    public var enharmonic: NoteSpelling? {
        let pc = pitchClass
        if NoteLetter(naturalPitchClass: pc) != nil, accidental == .natural { return nil }
        switch accidental {
        case .sharp, .doubleSharp: return NoteSpelling.preferred(for: pc, preferFlat: true)
        default: return NoteSpelling.preferred(for: pc, preferFlat: false)
        }
    }

    /// Preferred spelling: naturals stay natural, otherwise sharp or flat as requested.
    public static func preferred(for pc: PitchClass, preferFlat: Bool) -> NoteSpelling {
        if let natural = NoteLetter(naturalPitchClass: pc) { return NoteSpelling(natural) }
        return preferFlat
            ? NoteSpelling(NoteLetter(naturalPitchClass: pc.transposed(by: 1))!, .flat)
            : NoteSpelling(NoteLetter(naturalPitchClass: pc.transposed(by: -1))!, .sharp)
    }
}
