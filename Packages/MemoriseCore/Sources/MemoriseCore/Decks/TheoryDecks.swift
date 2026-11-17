// MARK: - Key signatures

public struct KeySigOptions: Hashable, Codable, Sendable {
    public var modes: Set<KeyMode>
    public var directions: Set<KeySigDirection>

    public init(modes: Set<KeyMode> = Set(KeyMode.allCases), directions: Set<KeySigDirection> = Set(KeySigDirection.allCases)) {
        self.modes = modes
        self.directions = directions
    }

    private enum CodingKeys: String, CodingKey { case modes, directions }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KeySigOptions()
        modes = c.tolerant(Set<KeyMode>.self, .modes, d.modes)
        directions = c.tolerant(Set<KeySigDirection>.self, .directions, d.directions)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sortedRaw(modes), forKey: .modes)
        try c.encode(sortedRaw(directions), forKey: .directions)
    }
}

/// "How many sharps in E major?" ⇄ "Which major key has 3 flats?"
public struct KeySignaturesDeck: Deck {
    public static let deckID: DeckID = "music.theory.keysig"

    public let id: DeckID = KeySignaturesDeck.deckID
    public let kind = DeckKind.keySignatures
    public let title = "Key Signatures"
    public let subtitle = "Sharps and flats of every key"
    public let subject = Subject.music
    public let group = DeckGroup.theory

    public init() {}

    public var defaultOptions: DeckOptions { .keySignatures(KeySigOptions()) }

    public static func itemKey(_ key: Key, _ direction: KeySigDirection) -> ItemKey {
        ItemKey("keysig:\(key.tonic.ascii):\(key.mode.rawValue):\(direction.rawValue)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .keySignatures(o) = options else { return [] }
        var result: [Card] = []
        for mode in KeyMode.allCases where o.modes.contains(mode) {
            for key in mode == .major ? Key.majors : Key.minors {
                for dir in KeySigDirection.allCases where o.directions.contains(dir) {
                    result.append(Card(key: Self.itemKey(key, dir), deckID: id, content: .keySignature(KeySignaturePrompt(key: key, direction: dir))))
                }
            }
        }
        return result
    }

    /// Same signature count back-to-back ×0.5.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.keySignature, let p = recent.back(0)?.keySignature else { return 1 }
        return c.key.signature.count == p.key.signature.count ? 0.5 : 1
    }

    /// Fewer accidentals first.
    public func introductionRank(of card: Card) -> Int? { card.keySignature.map { $0.key.signature.count } }
}

// MARK: - Diatonic chords

public enum DiatonicChordSize: String, Codable, Sendable, CaseIterable, Hashable {
    case triads, sevenths, both

    var sizes: [DiatonicSize] {
        switch self {
        case .triads: [.triad]
        case .sevenths: [.seventh]
        case .both: [.triad, .seventh]
        }
    }
}

public struct DiatonicOptions: Hashable, Codable, Sendable {
    public var modes: Set<KeyMode>
    public var chordSize: DiatonicChordSize
    public var directions: Set<DiatonicDirection>
    /// Major tonics (ASCII, e.g. "Bb"); minor keys use their relatives.
    public var keys: Set<String>

    public static let allKeys: Set<String> = Set(Key.majors.map(\.tonic.ascii))

    public init(
        modes: Set<KeyMode> = [.major],
        chordSize: DiatonicChordSize = .triads,
        directions: Set<DiatonicDirection> = Set(DiatonicDirection.allCases),
        keys: Set<String> = DiatonicOptions.allKeys
    ) {
        self.modes = modes
        self.chordSize = chordSize
        self.directions = directions
        self.keys = keys
    }

    private enum CodingKeys: String, CodingKey { case modes, chordSize, directions, keys }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DiatonicOptions()
        modes = c.tolerant(Set<KeyMode>.self, .modes, d.modes)
        chordSize = c.tolerant(DiatonicChordSize.self, .chordSize, d.chordSize)
        directions = c.tolerant(Set<DiatonicDirection>.self, .directions, d.directions)
        keys = c.tolerant(Set<String>.self, .keys, d.keys)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sortedRaw(modes), forKey: .modes)
        try c.encode(chordSize, forKey: .chordSize)
        try c.encode(sortedRaw(directions), forKey: .directions)
        try c.encode(keys.sorted(), forKey: .keys)
    }
}

/// "iii in G major?" ⇄ "Bm is which degree in G?"
public struct DiatonicDeck: Deck {
    public static let deckID: DeckID = "music.theory.diatonic"

    public let id: DeckID = DiatonicDeck.deckID
    public let kind = DeckKind.diatonic
    public let title = "Diatonic Chords"
    public let subtitle = "Roman numerals in every key"
    public let subject = Subject.music
    public let group = DeckGroup.theory

    public init() {}

    public var defaultOptions: DeckOptions { .diatonic(DiatonicOptions()) }

    public static func itemKey(_ key: Key, _ size: DiatonicSize, degree: Int, _ dir: DiatonicDirection) -> ItemKey {
        ItemKey("diatonic:\(key.tonic.ascii):\(key.mode.rawValue):\(size.rawValue):\(degree):\(dir.rawValue)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .diatonic(o) = options else { return [] }
        var result: [Card] = []
        for mode in KeyMode.allCases where o.modes.contains(mode) {
            for major in Key.majors where o.keys.contains(major.tonic.ascii) {
                let key = mode == .major ? major : major.relative
                for size in o.chordSize.sizes {
                    // Minor keys use the harmonic-minor V / V7.
                    let row = size == .triad ? key.diatonicTriads(harmonicV: mode == .minor) : key.diatonicSevenths(harmonicV: mode == .minor)
                    for chord in row {
                        for dir in DiatonicDirection.allCases where o.directions.contains(dir) {
                            result.append(Card(key: Self.itemKey(key, size, degree: chord.degree, dir), deckID: id,
                                               content: .diatonic(DiatonicPrompt(key: key, size: size, direction: dir, chord: chord, row: row))))
                        }
                    }
                }
            }
        }
        return result
    }

    /// Same key ×0.5; same degree ×0.5.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.diatonic, let p = recent.back(0)?.diatonic else { return 1 }
        var penalty = 1.0
        if c.key == p.key { penalty *= 0.5 }
        if c.chord.degree == p.chord.degree { penalty *= 0.5 }
        return penalty
    }

    /// Keys with fewer accidentals first.
    public func introductionRank(of card: Card) -> Int? { card.diatonic.map { $0.key.signature.count } }
}

// MARK: - Circle of fifths

public struct CircleOptions: Hashable, Codable, Sendable {
    public var questions: Set<CircleQuestion>

    public init(questions: Set<CircleQuestion> = Set(CircleQuestion.allCases)) { self.questions = questions }

    private enum CodingKeys: String, CodingKey { case questions }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        questions = c.tolerant(Set<CircleQuestion>.self, .questions, CircleOptions().questions)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sortedRaw(questions), forKey: .questions)
    }
}

/// "Fifth above D?"
public struct CircleOfFifthsDeck: Deck {
    public static let deckID: DeckID = "music.theory.circle"

    public let id: DeckID = CircleOfFifthsDeck.deckID
    public let kind = DeckKind.circleOfFifths
    public let title = "Circle of Fifths"
    public let subtitle = "Fifths, fourths and relative keys"
    public let subject = Subject.music
    public let group = DeckGroup.theory

    public init() {}

    public var defaultOptions: DeckOptions { .circle(CircleOptions()) }

    public static func itemKey(_ q: CircleQuestion, from: NoteSpelling) -> ItemKey {
        ItemKey("cof:\(q.rawValue):\(from.ascii)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .circle(o) = options else { return [] }
        var result: [Card] = []
        for q in CircleQuestion.allCases where o.questions.contains(q) {
            for i in 0..<12 {
                let prompt = Self.prompt(q, index: i)
                result.append(Card(key: Self.itemKey(q, from: prompt.from), deckID: id, content: .circle(prompt)))
            }
        }
        return result
    }

    static func prompt(_ q: CircleQuestion, index i: Int) -> CirclePrompt {
        let majors = CircleOfFifths.order, minors = CircleOfFifths.minors
        let from: NoteSpelling, answer: NoteSpelling, answerIndex: Int, exact: NoteSpelling?
        switch q {
        case .fifthAbove:
            from = majors[i]; answerIndex = (i + 1) % 12; answer = majors[answerIndex]
            exact = from.transposed(by: .P5)
        case .fourthAbove:
            from = majors[i]; answerIndex = (i + 11) % 12; answer = majors[answerIndex]
            exact = from.transposed(by: .P4)
        case .relativeMinor:
            from = majors[i]; answerIndex = i; answer = minors[i]
            exact = from.adding(letters: 5, semitones: 9)
        case .relativeMajor:
            from = minors[i]; answerIndex = i; answer = majors[i]
            exact = from.adding(letters: 2, semitones: 3)
        }
        return CirclePrompt(question: q, from: from, answer: answer, fromIndex: i, answerIndex: answerIndex,
                            exactSpelling: exact == answer ? nil : exact)
    }

    /// Same question ×0.6; same starting note ×0.4.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.circle, let p = recent.back(0)?.circle else { return 1 }
        var penalty = 1.0
        if c.question == p.question { penalty *= 0.6 }
        if c.fromIndex == p.fromIndex { penalty *= 0.4 }
        return penalty
    }
}
