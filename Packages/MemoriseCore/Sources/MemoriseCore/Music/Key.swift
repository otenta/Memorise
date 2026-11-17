/// Major or minor tonality. Raw values appear in `ItemKey`s — **never change them**.
public enum KeyMode: String, Codable, Sendable, CaseIterable, Hashable {
    case major, minor

    public var title: String { rawValue }
}

/// A key signature: a count of sharps or flats.
public struct KeySignature: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case none, sharps, flats }

    public let kind: Kind
    public let count: Int

    public static let sharpOrder: [NoteSpelling] = [
        .init(.f, .sharp), .init(.c, .sharp), .init(.g, .sharp), .init(.d, .sharp),
        .init(.a, .sharp), .init(.e, .sharp), .init(.b, .sharp),
    ]
    public static let flatOrder: [NoteSpelling] = [
        .init(.b, .flat), .init(.e, .flat), .init(.a, .flat), .init(.d, .flat),
        .init(.g, .flat), .init(.c, .flat), .init(.f, .flat),
    ]

    /// Positive = sharps, negative = flats.
    public init(fifths: Int) {
        count = abs(fifths)
        kind = fifths == 0 ? .none : (fifths > 0 ? .sharps : .flats)
    }

    /// Signed: sharps positive, flats negative.
    public var fifths: Int { kind == .flats ? -count : count }

    /// Accidentals in signature order.
    public var accidentals: [NoteSpelling] {
        switch kind {
        case .none: []
        case .sharps: Array(Self.sharpOrder.prefix(count))
        case .flats: Array(Self.flatOrder.prefix(count))
        }
    }

    /// "4♯", "3♭", "no sharps or flats"
    public var shortText: String {
        switch kind {
        case .none: "no ♯/♭"
        case .sharps: "\(count)♯"
        case .flats: "\(count)♭"
        }
    }

    /// "4 sharps", "1 flat"
    public var longText: String {
        switch kind {
        case .none: "no sharps or flats"
        case .sharps: count == 1 ? "1 sharp" : "\(count) sharps"
        case .flats: count == 1 ? "1 flat" : "\(count) flats"
        }
    }
}

/// A diatonic chord with its Roman numeral.
public struct DiatonicChord: Hashable, Sendable {
    /// 1…7
    public let degree: Int
    public let numeral: String
    public let chord: Chord
}

/// A tonality limited to the 15 standard major signatures and their relative minors.
public struct Key: Hashable, Sendable {
    public let tonic: NoteSpelling
    public let mode: KeyMode
    public let signature: KeySignature

    /// Major tonics in signature order (−7…7 fifths).
    public static let majorTonicsByFifths: [(fifths: Int, tonic: NoteSpelling)] = [
        (-7, .init(.c, .flat)), (-6, .init(.g, .flat)), (-5, .init(.d, .flat)), (-4, .init(.a, .flat)),
        (-3, .init(.e, .flat)), (-2, .init(.b, .flat)), (-1, .init(.f)), (0, .init(.c)), (1, .init(.g)),
        (2, .init(.d)), (3, .init(.a)), (4, .init(.e)), (5, .init(.b)), (6, .init(.f, .sharp)), (7, .init(.c, .sharp)),
    ]

    /// The 15 major keys in display order (C G D A E B F♯ C♯ F B♭ E♭ A♭ D♭ G♭ C♭).
    public static let majors: [Key] = {
        let order = [0, 1, 2, 3, 4, 5, 6, 7, -1, -2, -3, -4, -5, -6, -7]
        return order.map { f in Key(majorFifths: f) }
    }()

    /// The 15 relative minors in the same order.
    public static let minors: [Key] = majors.map(\.relative)

    public static let all: [Key] = majors + minors

    private init(majorFifths f: Int) {
        tonic = Self.majorTonicsByFifths.first { $0.fifths == f }!.tonic
        mode = .major
        signature = KeySignature(fifths: f)
    }

    private init(tonic: NoteSpelling, mode: KeyMode, signature: KeySignature) {
        self.tonic = tonic
        self.mode = mode
        self.signature = signature
    }

    /// Looks a key up by its tonic and mode; `nil` outside the 30 standard keys.
    public init?(tonic: NoteSpelling, mode: KeyMode) {
        guard let k = (mode == .major ? Self.majors : Self.minors).first(where: { $0.tonic == tonic }) else { return nil }
        self = k
    }

    /// Major key from an ASCII tonic ("Bb").
    public static func major(ascii: String) -> Key? {
        NoteSpelling(ascii: ascii).flatMap { Key(tonic: $0, mode: .major) }
    }

    /// Relative major/minor (same signature).
    public var relative: Key {
        switch mode {
        case .major:
            Key(tonic: tonic.adding(letters: 5, semitones: 9)!, mode: .minor, signature: signature)
        case .minor:
            Key(tonic: tonic.adding(letters: 2, semitones: 3)!, mode: .major, signature: signature)
        }
    }

    /// The parent major key (itself for major keys).
    public var majorKey: Key { mode == .major ? self : relative }

    /// "E major", "C♯ minor"
    public var name: String { "\(tonic.displayName) \(mode.title)" }

    /// "Em" style short name for minor keys, "E" for major keys.
    public var shortName: String { tonic.displayName + (mode == .minor ? "m" : "") }

    /// Major or natural-minor scale.
    public var scale: Scale { Scale(tonic: tonic, type: mode == .major ? .major : .naturalMinor)! }

    /// I ii iii IV V vi vii° / i ii° III iv v VI VII (or V with `harmonicV`).
    public func diatonicTriads(harmonicV: Bool = false) -> [DiatonicChord] {
        diatonic(size: 3, harmonicV: harmonicV)
    }

    /// Imaj7 ii7 iii7 IVmaj7 V7 vi7 viiø7 / i7 iiø7 IIImaj7 iv7 v7 VImaj7 VII7 (V7 with `harmonicV`).
    public func diatonicSevenths(harmonicV: Bool = false) -> [DiatonicChord] {
        diatonic(size: 4, harmonicV: harmonicV)
    }

    private func diatonic(size: Int, harmonicV: Bool) -> [DiatonicChord] {
        let notes = scale.notes
        var result: [DiatonicChord] = []
        for i in 0..<7 {
            let root = notes[i]
            var quality: ChordQuality?
            if harmonicV && mode == .minor && i == 4 {
                quality = size == 3 ? .maj : .dom7
            } else {
                let semis = (1..<size).map { k in
                    PitchClass(notes[(i + 2 * k) % 7].pitchClass.value - root.pitchClass.value).value
                }
                quality = ChordQuality.fromStack(semis)
            }
            guard let quality, let chord = Chord(root: root, quality: quality) else { continue }
            result.append(DiatonicChord(degree: i + 1, numeral: RomanNumeral.text(degree: i + 1, quality: quality), chord: chord))
        }
        return result
    }
}

/// Roman-numeral formatting.
public enum RomanNumeral {
    static let upper = ["I", "II", "III", "IV", "V", "VI", "VII"]

    /// Case from the quality's 3rd; suffix from the quality ("vii°", "V7", "Imaj7", "iiø7").
    public static func text(degree: Int, quality: ChordQuality) -> String {
        let base = upper[(degree - 1) % 7]
        let minorish: Set<ChordQuality> = [.min, .dim, .min7, .m7b5, .dim7, .min6]
        let numeral = minorish.contains(quality) ? base.lowercased() : base
        let suffix = switch quality {
        case .maj, .min: ""
        case .dim: "°"
        case .aug: "+"
        case .dom7, .min7: "7"
        case .maj7: "maj7"
        case .m7b5: "ø7"
        case .dim7: "°7"
        case .six, .min6: "6"
        case .sus2: "sus2"
        case .sus4: "sus4"
        case .pow5: "5"
        case .add9: "add9"
        }
        return numeral + suffix
    }
}

/// Circle-of-fifths positions with the PLAN_M3 §3.1 spellings.
public enum CircleOfFifths {
    /// C G D A E B F♯ D♭ A♭ E♭ B♭ F (clockwise).
    public static let order: [NoteSpelling] = [
        .init(.c), .init(.g), .init(.d), .init(.a), .init(.e), .init(.b),
        .init(.f, .sharp), .init(.d, .flat), .init(.a, .flat), .init(.e, .flat), .init(.b, .flat), .init(.f),
    ]

    /// Relative minors of `order`, same positions.
    public static let minors: [NoteSpelling] = [
        .init(.a), .init(.e), .init(.b), .init(.f, .sharp), .init(.c, .sharp), .init(.g, .sharp),
        .init(.d, .sharp), .init(.b, .flat), .init(.f), .init(.c), .init(.g), .init(.d),
    ]

    public static func index(ofMajor s: NoteSpelling) -> Int? { order.firstIndex(of: s) }
    public static func index(ofMinor s: NoteSpelling) -> Int? { minors.firstIndex(of: s) }

    public static func fifthAbove(_ s: NoteSpelling) -> NoteSpelling? {
        index(ofMajor: s).map { order[($0 + 1) % 12] }
    }

    public static func fourthAbove(_ s: NoteSpelling) -> NoteSpelling? {
        index(ofMajor: s).map { order[($0 + 11) % 12] }
    }

    public static func relativeMinor(_ s: NoteSpelling) -> NoteSpelling? {
        index(ofMajor: s).map { minors[$0] }
    }

    public static func relativeMajor(_ s: NoteSpelling) -> NoteSpelling? {
        index(ofMinor: s).map { order[$0] }
    }
}
