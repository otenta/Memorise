/// Scale types. Raw values appear in `ItemKey`s — **never change them**.
public enum ScaleType: String, Codable, Sendable, CaseIterable, Hashable {
    case major, naturalMinor, harmonicMinor, melodicMinor
    case majorPentatonic, minorPentatonic, blues
    case ionian, dorian, phrygian, lydian, mixolydian, aeolian, locrian

    public var title: String {
        switch self {
        case .major: "major"
        case .naturalMinor: "natural minor"
        case .harmonicMinor: "harmonic minor"
        case .melodicMinor: "melodic minor"
        case .majorPentatonic: "major pentatonic"
        case .minorPentatonic: "minor pentatonic"
        case .blues: "blues"
        case .ionian: "Ionian"
        case .dorian: "Dorian"
        case .phrygian: "Phrygian"
        case .lydian: "Lydian"
        case .mixolydian: "Mixolydian"
        case .aeolian: "Aeolian"
        case .locrian: "Locrian"
        }
    }

    public var degrees: [Degree] {
        switch self {
        case .major, .ionian: [.root, .second, .third, .fourth, .fifth, .sixth, .seventh]
        case .naturalMinor, .aeolian: [.root, .second, .flat3, .fourth, .fifth, .flat6, .flat7]
        case .harmonicMinor: [.root, .second, .flat3, .fourth, .fifth, .flat6, .seventh]
        case .melodicMinor: [.root, .second, .flat3, .fourth, .fifth, .sixth, .seventh]
        case .dorian: [.root, .second, .flat3, .fourth, .fifth, .sixth, .flat7]
        case .phrygian: [.root, .flat2, .flat3, .fourth, .fifth, .flat6, .flat7]
        case .lydian: [.root, .second, .third, .sharp4, .fifth, .sixth, .seventh]
        case .mixolydian: [.root, .second, .third, .fourth, .fifth, .sixth, .flat7]
        case .locrian: [.root, .flat2, .flat3, .fourth, .flat5, .flat6, .flat7]
        case .majorPentatonic: [.root, .second, .third, .fifth, .sixth]
        case .minorPentatonic: [.root, .flat3, .fourth, .fifth, .flat7]
        case .blues: [.root, .flat3, .fourth, .flat5, .fifth, .flat7]
        }
    }

    public var degreeLabels: [String] { degrees.map(\.label) }

    /// Seven notes, one letter per degree.
    public var isHeptatonic: Bool { degrees.count == 7 }

    public var isMode: Bool { [.ionian, .dorian, .phrygian, .lydian, .mixolydian, .aeolian, .locrian].contains(self) }

    /// The degrees a pentatonic/blues box is built from (blues = minor pentatonic + ♭5).
    var boxDegrees: [Degree] { self == .blues ? ScaleType.minorPentatonic.degrees : degrees }

    /// Introduction order: pentatonic/blues, then major/minor, then modes, then the rest.
    public var introductionTier: Int {
        switch self {
        case .minorPentatonic, .majorPentatonic, .blues: 0
        case .major, .naturalMinor: 1
        case .ionian, .dorian, .phrygian, .lydian, .mixolydian, .aeolian, .locrian: 2
        case .harmonicMinor, .melodicMinor: 3
        }
    }
}

/// A spelled scale.
public struct Scale: Hashable, Sendable {
    public let tonic: NoteSpelling
    public let type: ScaleType
    public let notes: [NoteSpelling]

    /// `nil` if any note needs a double accidental.
    public init?(tonic: NoteSpelling, type: ScaleType) {
        guard !tonic.accidental.isDouble else { return nil }
        var notes: [NoteSpelling] = []
        for d in type.degrees {
            guard let n = tonic.adding(letters: d.letters, semitones: d.semitones) else { return nil }
            notes.append(n)
        }
        self.tonic = tonic
        self.type = type
        self.notes = notes
    }

    /// Tries the given spelling, then its enharmonic.
    public static func spelled(_ pc: PitchClass, _ type: ScaleType) -> Scale? {
        let first = RootNames.spelling(pc)
        if let s = Scale(tonic: first, type: type) { return s }
        return first.enharmonic.flatMap { Scale(tonic: $0, type: type) }
    }

    /// "A minor pentatonic"
    public var name: String { "\(tonic.displayName) \(type.title)" }

    public var notesText: String { notes.map(\.displayName).joined(separator: " ") }

    public var pitchClasses: [PitchClass] { notes.map(\.pitchClass) }

    public func degreeLabel(for pc: PitchClass) -> String? {
        zip(notes, type.degrees).first { $0.0.pitchClass == pc }?.1.label
    }

    public func spelling(for pc: PitchClass) -> NoteSpelling? { notes.first { $0.pitchClass == pc } }
}
