/// A chord or scale degree: letter steps and semitones above the root, plus its label.
public struct Degree: Hashable, Sendable {
    public let letters: Int
    public let semitones: Int
    /// "R", "♭3", "5", "♭7", "𝄫7" …
    public let label: String

    public init(_ letters: Int, _ semitones: Int, _ label: String) {
        self.letters = letters
        self.semitones = semitones
        self.label = label
    }

    public static let root = Degree(0, 0, "R")
    public static let flat2 = Degree(1, 1, "♭2")
    public static let second = Degree(1, 2, "2")
    public static let ninth = Degree(1, 2, "9")
    public static let flat3 = Degree(2, 3, "♭3")
    public static let third = Degree(2, 4, "3")
    public static let fourth = Degree(3, 5, "4")
    public static let sharp4 = Degree(3, 6, "♯4")
    public static let flat5 = Degree(4, 6, "♭5")
    public static let fifth = Degree(4, 7, "5")
    public static let sharp5 = Degree(4, 8, "♯5")
    public static let flat6 = Degree(5, 8, "♭6")
    public static let sixth = Degree(5, 9, "6")
    public static let dim7 = Degree(6, 9, "𝄫7")
    public static let flat7 = Degree(6, 10, "♭7")
    public static let seventh = Degree(6, 11, "7")
}

/// Degree labels by semitone distance from the root (R, ♭2, 2, ♭3, 3, 4, ♭5, 5, ♯5, 6, ♭7, 7).
public enum DegreeLabel {
    private static let labels = ["R", "♭2", "2", "♭3", "3", "4", "♭5", "5", "♯5", "6", "♭7", "7"]

    public static func text(semitones: Int) -> String { labels[PitchClass(semitones).value] }

    public static func text(interval: Interval) -> String { interval == .P8 ? "R" : text(semitones: interval.semitones) }
}

/// Chord quality. Raw values appear in `ItemKey`s — **never change them**.
public enum ChordQuality: String, Codable, Sendable, CaseIterable, Hashable {
    case maj, min, dim, aug, sus2, sus4, pow5, dom7, maj7, min7, m7b5, dim7, six, min6, add9

    /// Suffix after the root: "", "m", "°", "+", "7", "maj7", "m7♭5" …
    public var symbol: String {
        switch self {
        case .maj: ""
        case .min: "m"
        case .dim: "°"
        case .aug: "+"
        case .sus2: "sus2"
        case .sus4: "sus4"
        case .pow5: "5"
        case .dom7: "7"
        case .maj7: "maj7"
        case .min7: "m7"
        case .m7b5: "m7♭5"
        case .dim7: "°7"
        case .six: "6"
        case .min6: "m6"
        case .add9: "add9"
        }
    }

    /// "minor seventh"
    public var longName: String {
        switch self {
        case .maj: "major"
        case .min: "minor"
        case .dim: "diminished"
        case .aug: "augmented"
        case .sus2: "suspended second"
        case .sus4: "suspended fourth"
        case .pow5: "power chord"
        case .dom7: "dominant seventh"
        case .maj7: "major seventh"
        case .min7: "minor seventh"
        case .m7b5: "half-diminished seventh"
        case .dim7: "diminished seventh"
        case .six: "sixth"
        case .min6: "minor sixth"
        case .add9: "added ninth"
        }
    }

    /// Short chip label for settings ("maj", "m7"…).
    public var chipLabel: String { self == .maj ? "maj" : symbol }

    /// Degrees including the root, in chord order.
    public var degrees: [Degree] {
        switch self {
        case .maj: [.root, .third, .fifth]
        case .min: [.root, .flat3, .fifth]
        case .dim: [.root, .flat3, .flat5]
        case .aug: [.root, .third, .sharp5]
        case .sus2: [.root, .second, .fifth]
        case .sus4: [.root, .fourth, .fifth]
        case .pow5: [.root, .fifth]
        case .dom7: [.root, .third, .fifth, .flat7]
        case .maj7: [.root, .third, .fifth, .seventh]
        case .min7: [.root, .flat3, .fifth, .flat7]
        case .m7b5: [.root, .flat3, .flat5, .flat7]
        case .dim7: [.root, .flat3, .flat5, .dim7]
        case .six: [.root, .third, .fifth, .sixth]
        case .min6: [.root, .flat3, .fifth, .sixth]
        case .add9: [.root, .third, .fifth, .ninth]
        }
    }

    /// Whether a voicing must contain a 3rd.
    public var needsThird: Bool { ![.sus2, .sus4, .pow5].contains(self) }

    /// Whether a voicing must contain the 7th.
    public var isSeventh: Bool { [.dom7, .maj7, .min7, .m7b5, .dim7].contains(self) }

    public static let triadQualities: [ChordQuality] = [.maj, .min, .dim, .aug]

    /// Identifies a stacked-thirds chord from its semitone set (used for diatonic harmony).
    static func fromStack(_ semis: [Int]) -> ChordQuality? {
        switch semis {
        case [4, 7]: .maj
        case [3, 7]: .min
        case [3, 6]: .dim
        case [4, 8]: .aug
        case [4, 7, 11]: .maj7
        case [4, 7, 10]: .dom7
        case [3, 7, 10]: .min7
        case [3, 6, 10]: .m7b5
        case [3, 6, 9]: .dim7
        default: nil
        }
    }
}

/// A spelled chord: root plus quality.
public struct Chord: Hashable, Sendable {
    public let root: NoteSpelling
    public let quality: ChordQuality
    /// One letter per chord degree, in chord order.
    public let tones: [NoteSpelling]

    /// `nil` if any tone needs a double accidental (only `dim7`'s 7th may be a double flat).
    public init?(root: NoteSpelling, quality: ChordQuality) {
        guard !root.accidental.isDouble else { return nil }
        var tones: [NoteSpelling] = []
        for d in quality.degrees {
            let allowDouble = quality == .dim7 && d == .dim7
            guard let t = root.adding(letters: d.letters, semitones: d.semitones, allowDouble: allowDouble) else { return nil }
            tones.append(t)
        }
        self.root = root
        self.quality = quality
        self.tones = tones
    }

    /// Spells the chord on `pc`, trying the preferred spelling first, then its enharmonic.
    public static func spelled(_ pc: PitchClass, _ quality: ChordQuality, preferFlat: Bool) -> Chord? {
        let first = NoteSpelling.preferred(for: pc, preferFlat: preferFlat)
        if let c = Chord(root: first, quality: quality) { return c }
        return first.enharmonic.flatMap { Chord(root: $0, quality: quality) }
    }

    /// "B♭m7"
    public var symbol: String { root.displayName + quality.symbol }

    /// "B flat minor seventh"
    public var longName: String { "\(root.spokenName) \(quality.longName)" }

    public var pitchClasses: [PitchClass] { tones.map(\.pitchClass) }

    /// Degree label for a sounding pitch class ("R", "♭3"…), if it's a chord tone.
    public func degreeLabel(for pc: PitchClass) -> String? {
        zip(tones, quality.degrees).first { $0.0.pitchClass == pc }?.1.label
    }

    /// Spelling for a sounding pitch class, if it's a chord tone.
    public func spelling(for pc: PitchClass) -> NoteSpelling? {
        tones.first { $0.pitchClass == pc }
    }

    /// "B♭ D♭ F A♭"
    public var tonesText: String { tones.map(\.displayName).joined(separator: " ") }

    /// "R ♭3 5 ♭7"
    public var degreesText: String { quality.degrees.map(\.label).joined(separator: " ") }
}

/// The 12 roots used by M3 decks, spelled per PLAN_M3 §3.1/§3.3 (B♭, E♭, A♭, D♭, F♯).
public enum RootNames {
    public static let preferFlat: [Int: Bool] = [1: true, 3: true, 6: false, 8: true, 10: true]

    /// Default spelling for a pitch class.
    public static func spelling(_ pc: PitchClass) -> NoteSpelling {
        .preferred(for: pc, preferFlat: preferFlat[pc.value] ?? false)
    }

    public static func preferFlat(_ pc: PitchClass) -> Bool { preferFlat[pc.value] ?? false }

    public static let all: Set<PitchClass> = Set(PitchClass.allCases)
}
