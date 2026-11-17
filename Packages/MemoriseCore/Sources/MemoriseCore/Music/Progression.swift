/// Common chord progressions. Raw values appear in `ItemKey`s — **never change them**.
public enum Progression: String, Codable, Sendable, CaseIterable, Hashable {
    case oneFourFive = "I-IV-V"
    case twoFiveOne = "ii-V-I"
    case popAxis = "I-V-vi-IV"
    case sixFourOneFive = "vi-IV-I-V"
    case fifties = "I-vi-IV-V"
    case oneFourSixFive = "I-IV-vi-V"
    case blues12
    case minorTwoFiveOne = "ii-V-i"
    case minorOneFourFive = "i-iv-v"
    case minorOneSixThreeSeven = "i-VI-III-VII"
    case andalusian = "i-VII-VI-V"

    public struct Step: Hashable, Sendable {
        /// 1…7 within the key's (natural) scale.
        public let degree: Int
        public let quality: ChordQuality

        public init(_ degree: Int, _ quality: ChordQuality) {
            self.degree = degree
            self.quality = quality
        }

        public var numeral: String { RomanNumeral.text(degree: degree, quality: quality) }
    }

    public var mode: KeyMode {
        switch self {
        case .minorTwoFiveOne, .minorOneFourFive, .minorOneSixThreeSeven, .andalusian: .minor
        default: .major
        }
    }

    public var steps: [Step] {
        switch self {
        case .oneFourFive: [.init(1, .maj), .init(4, .maj), .init(5, .maj)]
        case .twoFiveOne: [.init(2, .min7), .init(5, .dom7), .init(1, .maj7)]
        case .popAxis: [.init(1, .maj), .init(5, .maj), .init(6, .min), .init(4, .maj)]
        case .sixFourOneFive: [.init(6, .min), .init(4, .maj), .init(1, .maj), .init(5, .maj)]
        case .fifties: [.init(1, .maj), .init(6, .min), .init(4, .maj), .init(5, .maj)]
        case .oneFourSixFive: [.init(1, .maj), .init(4, .maj), .init(6, .min), .init(5, .maj)]
        case .blues12:
            [1, 1, 1, 1, 4, 4, 1, 1, 5, 4, 1, 5].map { .init($0, .dom7) }
        case .minorTwoFiveOne: [.init(2, .m7b5), .init(5, .dom7), .init(1, .min)]
        case .minorOneFourFive: [.init(1, .min), .init(4, .min), .init(5, .min)]
        case .minorOneSixThreeSeven: [.init(1, .min), .init(6, .maj), .init(3, .maj), .init(7, .maj)]
        case .andalusian: [.init(1, .min), .init(7, .maj), .init(6, .maj), .init(5, .maj)]
        }
    }

    /// "ii–V–I", "12-bar blues"
    public var title: String {
        switch self {
        case .blues12: "12-bar blues"
        case .andalusian: "Andalusian i–VII–VI–V"
        default: steps.map(\.numeral).joined(separator: "–")
        }
    }

    /// "ii7 – V7 – Imaj7"
    public var numeralsText: String { steps.map(\.numeral).joined(separator: " – ") }

    /// Chords in `key`; `nil` if the key's mode doesn't match or a chord can't be spelled.
    public func realize(in key: Key) -> [Chord]? {
        guard key.mode == mode else { return nil }
        let notes = key.scale.notes
        var chords: [Chord] = []
        for s in steps {
            guard let c = Chord(root: notes[s.degree - 1], quality: s.quality) else { return nil }
            chords.append(c)
        }
        return chords
    }
}
