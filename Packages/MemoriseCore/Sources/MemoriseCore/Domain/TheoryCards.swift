/// One note of a generated fretboard shape (triad, arpeggio, scale).
public struct FretNote: Hashable, Sendable {
    public let position: FretPosition
    public let midi: Int
    public let spelling: NoteSpelling
    /// "R", "♭3" …
    public let degree: String

    public init(position: FretPosition, midi: Int, spelling: NoteSpelling, degree: String) {
        self.position = position
        self.midi = midi
        self.spelling = spelling
        self.degree = degree
    }

    public var isRoot: Bool { degree == "R" }
}

public extension Collection where Element == FretNote {
    /// The smallest fret window containing every note (at least 4 frets wide).
    var fretWindow: ClosedRange<Int> {
        let frets = map(\.position.fret)
        let lo = frets.min() ?? 0, hi = frets.max() ?? 4
        let start = lo <= 1 ? 0 : lo - 1
        return start...Swift.max(hi + 1, start + 4)
    }
}

/// "Play B♭m7 (A-shape barre)" / "Name this chord".
public struct ChordCardPrompt: Hashable, Sendable {
    public let shape: ChordShape
    public let voicing: Voicing
    public var chord: Chord { voicing.chord }

    public init(shape: ChordShape, voicing: Voicing) {
        self.shape = shape
        self.voicing = voicing
    }
}

/// Triad inversion. Raw values appear in `ItemKey`s — **never change them**.
public enum TriadInversion: String, Codable, Sendable, CaseIterable, Hashable {
    case root, first, second

    public var title: String {
        switch self {
        case .root: "root position"
        case .first: "1st inversion"
        case .second: "2nd inversion"
        }
    }

    /// Chord-tone indices bottom → top.
    var order: [Int] {
        switch self {
        case .root: [0, 1, 2]
        case .first: [1, 2, 0]
        case .second: [2, 0, 1]
        }
    }
}

/// Adjacent three-string set. Raw values appear in `ItemKey`s — **never change them**.
public enum StringSet: String, Codable, Sendable, CaseIterable, Hashable {
    case s123 = "123", s234 = "234", s345 = "345", s456 = "456"

    /// Strings low → high (e.g. 3, 2, 1).
    public var strings: [Int] {
        switch self {
        case .s123: [3, 2, 1]
        case .s234: [4, 3, 2]
        case .s345: [5, 4, 3]
        case .s456: [6, 5, 4]
        }
    }

    /// "3-2-1"
    public var title: String { strings.map(String.init).joined(separator: "-") }
}

public struct TriadPrompt: Hashable, Sendable {
    public let chord: Chord
    public let inversion: TriadInversion
    public let stringSet: StringSet
    /// Low → high.
    public let notes: [FretNote]
}

/// Arpeggio length. Raw values are persisted — **never change them**.
public enum ArpeggioSpan: String, Codable, Sendable, CaseIterable, Hashable {
    case oneOctave, twoOctaves

    public var octaves: Int { self == .oneOctave ? 1 : 2 }
    public var title: String { self == .oneOctave ? "1 octave" : "2 octaves" }
}

public struct ArpeggioPrompt: Hashable, Sendable {
    public let chord: Chord
    public let rootString: Int
    public let span: ArpeggioSpan
    /// In playing order (ascending).
    public let notes: [FretNote]
}

/// Scale fingering system. Raw values appear in `ItemKey`s — **never change them**.
public enum ScaleSystem: String, Codable, Sendable, CaseIterable, Hashable {
    case box, threeNPS = "3nps"

    public var title: String { self == .box ? "box" : "3NPS" }
}

public struct ScalePrompt: Hashable, Sendable {
    public let scale: Scale
    public let system: ScaleSystem
    /// 1-based.
    public let position: Int
    /// Ascending.
    public let notes: [FretNote]

    /// "box 1", "3NPS position 2"
    public var positionText: String { system == .box ? "box \(position)" : "3NPS position \(position)" }
}

/// Key-signature question direction. Raw values appear in `ItemKey`s — **never change them**.
public enum KeySigDirection: String, Codable, Sendable, CaseIterable, Hashable {
    case keyToSig, sigToKey

    public var title: String { self == .keyToSig ? "Key → signature" : "Signature → key" }
}

public struct KeySignaturePrompt: Hashable, Sendable {
    public let key: Key
    public let direction: KeySigDirection
}

/// Diatonic chord size. Raw values appear in `ItemKey`s — **never change them**.
public enum DiatonicSize: String, Codable, Sendable, CaseIterable, Hashable {
    case triad, seventh
}

/// Diatonic question direction. Raw values appear in `ItemKey`s — **never change them**.
public enum DiatonicDirection: String, Codable, Sendable, CaseIterable, Hashable {
    case degreeToChord, chordToDegree

    public var title: String { self == .degreeToChord ? "Numeral → chord" : "Chord → numeral" }
}

public struct DiatonicPrompt: Hashable, Sendable {
    public let key: Key
    public let size: DiatonicSize
    public let direction: DiatonicDirection
    public let chord: DiatonicChord
    /// The whole key's chords, I → vii.
    public let row: [DiatonicChord]
}

public struct ProgressionPrompt: Hashable, Sendable {
    public let progression: Progression
    public let key: Key
    public let chords: [Chord]
    /// One diagram per chord (nil when no shape exists for it).
    public let voicings: [Voicing?]
    /// Chords to play on 🔊 (the 12-bar blues may be cut to 4 bars).
    public let playCount: Int
}

/// Circle-of-fifths question. Raw values appear in `ItemKey`s — **never change them**.
public enum CircleQuestion: String, Codable, Sendable, CaseIterable, Hashable {
    case fifthAbove, fourthAbove, relativeMinor, relativeMajor

    public var title: String {
        switch self {
        case .fifthAbove: "Fifth above"
        case .fourthAbove: "Fourth above"
        case .relativeMinor: "Relative minor"
        case .relativeMajor: "Relative major"
        }
    }

    public var rule: String {
        switch self {
        case .fifthAbove: "Clockwise = up a fifth"
        case .fourthAbove: "Anticlockwise = up a fourth"
        case .relativeMinor: "Inner ring, same position (down a minor 3rd)"
        case .relativeMajor: "Outer ring, same position (up a minor 3rd)"
        }
    }
}

public struct CirclePrompt: Hashable, Sendable {
    public let question: CircleQuestion
    public let from: NoteSpelling
    public let answer: NoteSpelling
    /// Circle index (0 = C) of the question and the answer.
    public let fromIndex: Int
    public let answerIndex: Int
    public var fromIsMinor: Bool { question == .relativeMajor }
    public var answerIsMinor: Bool { question == .relativeMinor }
    /// The strictly correct interval spelling when the circle shows its enharmonic (F♯ + P5 = C♯, shown D♭).
    public let exactSpelling: NoteSpelling?
}
