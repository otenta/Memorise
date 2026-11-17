/// Options for the fretboard Intervals deck.
public struct IntervalOptions: Hashable, Codable, Sendable {
    public var intervals: Set<Interval>
    /// Root strings.
    public var strings: Set<Int>
    /// Root frets.
    public var fretRange: ClosedRange<Int>
    public var tuning: TuningID
    public var accidentalSpelling: AccidentalSpelling

    public init(
        intervals: Set<Interval> = Interval.defaultSet,
        strings: Set<Int> = [1, 2, 3, 4, 5, 6],
        fretRange: ClosedRange<Int> = 0...12,
        tuning: TuningID = .standard,
        accidentalSpelling: AccidentalSpelling = .sharps
    ) {
        self.intervals = intervals
        self.strings = strings
        self.fretRange = fretRange
        self.tuning = tuning
        self.accidentalSpelling = accidentalSpelling
    }

    private enum CodingKeys: String, CodingKey {
        case intervals, strings, fretRange, tuning, accidentalSpelling
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = IntervalOptions()
        intervals = c.tolerant(Set<Interval>.self, .intervals, d.intervals)
        strings = c.tolerant(Set<Int>.self, .strings, d.strings)
        fretRange = c.tolerant(ClosedRange<Int>.self, .fretRange, d.fretRange)
        tuning = c.tolerant(TuningID.self, .tuning, d.tuning)
        accidentalSpelling = c.tolerant(AccidentalSpelling.self, .accidentalSpelling, d.accidentalSpelling)
    }

    /// Sets are written sorted for deterministic output.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(intervals.sorted(), forKey: .intervals)
        try c.encode(strings.sorted(), forKey: .strings)
        try c.encode(fretRange, forKey: .fretRange)
        try c.encode(tuning, forKey: .tuning)
        try c.encode(accidentalSpelling, forKey: .accidentalSpelling)
    }
}

/// "Play a major 3rd above C."
public struct IntervalsDeck: Deck {
    public static let deckID: DeckID = "music.fretboard.intervals"

    public let id: DeckID = IntervalsDeck.deckID
    public let kind = DeckKind.fretboardIntervals
    public let title = "Intervals"
    public let subtitle = "Play a 3rd above this note"
    public let subject = Subject.music

    /// Highest fret ever used for answer positions.
    static let maxBoardFret = 24

    public init() {}

    public var defaultOptions: DeckOptions { .intervals(IntervalOptions()) }

    /// `"int:M3:s6"`, `"int@dropD:M3:s6"`.
    public static func itemKey(_ interval: Interval, string: Int, tuning: TuningID = .standard) -> ItemKey {
        ItemKey("\(FretboardKeys.scheme("int", tuning: tuning)):\(interval.rawValue):s\(string)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .intervals(o) = options, !o.fretRange.isEmpty else { return [] }
        let tuning = Tuning.preset(o.tuning)
        var result: [Card] = []
        for interval in o.intervals.sorted() {
            for s in tuning.stringNumbers where o.strings.contains(s) {
                // Base content (lowest root fret); `present` picks the real root.
                let root = FretPosition(string: s, fret: o.fretRange.lowerBound)
                let pc = Fretboard.pitchClass(string: s, fret: root.fret, tuning: tuning)
                let prompt = Self.prompt(interval: interval, root: root, rootSpelling: o.accidentalSpelling.baseSpelling(pc), tuning: tuning)
                    ?? Self.prompt(interval: interval, root: root, rootSpelling: .preferred(for: pc, preferFlat: true), tuning: tuning)
                guard let prompt else { continue }
                result.append(Card(key: Self.itemKey(interval, string: s, tuning: o.tuning), deckID: id, content: .interval(prompt)))
            }
        }
        return result
    }

    /// Picks a random root fret in range; re-rolls (max 10) when the target would need a double
    /// accidental, then falls back to a natural root.
    public func present(_ card: Card, options: DeckOptions, using rng: inout SplitMix64) -> Card {
        guard let p = card.interval, let o = options.intervals else { return card }
        let tuning = Tuning.preset(o.tuning)
        let s = p.root.string
        for _ in 0..<10 {
            let fret = Int.random(in: o.fretRange, using: &rng)
            let pc = Fretboard.pitchClass(string: s, fret: fret, tuning: tuning)
            let spelling = o.accidentalSpelling.presentationSpelling(pc, using: &rng)
            if let prompt = Self.prompt(interval: p.interval, root: FretPosition(string: s, fret: fret), rootSpelling: spelling, tuning: tuning) {
                return card.with(.interval(prompt))
            }
        }
        for fret in o.fretRange {
            guard let natural = NoteLetter(naturalPitchClass: Fretboard.pitchClass(string: s, fret: fret, tuning: tuning)),
                  let prompt = Self.prompt(interval: p.interval, root: FretPosition(string: s, fret: fret), rootSpelling: NoteSpelling(natural), tuning: tuning)
            else { continue }
            return card.with(.interval(prompt))
        }
        return card
    }

    /// Same interval ×0.35; same root string ×0.6 (vs. previous card).
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.interval, let prev = recent.back(0)?.interval else { return 1 }
        var penalty = 1.0
        if prev.interval == c.interval { penalty *= 0.35 }
        if prev.root.string == c.root.string { penalty *= 0.6 }
        return penalty
    }

    // MARK: Construction

    /// Builds a prompt for a root position, or `nil` if the target needs a double accidental.
    static func prompt(interval: Interval, root: FretPosition, rootSpelling: NoteSpelling, tuning: Tuning) -> IntervalPrompt? {
        guard let target = rootSpelling.transposed(by: interval) else { return nil }
        let targetMidi = Fretboard.midi(string: root.string, fret: root.fret, tuning: tuning) + interval.semitones
        let (targets, primary) = targetPositions(midi: targetMidi, root: root, tuning: tuning)
        return IntervalPrompt(interval: interval, root: root, rootSpelling: rootSpelling, targetSpelling: target,
                              tuning: tuning.id, targets: targets, primary: primary)
    }

    /// Target positions in the playable window (same string or the next 1–2 higher strings,
    /// root fret −4…+5). Falls back to the same string, then anywhere on the neck.
    static func targetPositions(midi: Int, root: FretPosition, tuning: Tuning) -> ([FretPosition], FretPosition?) {
        func fret(on s: Int) -> Int? {
            let f = midi - tuning.openMidi(string: s)
            return (0...maxBoardFret).contains(f) ? f : nil
        }
        let window = (root.fret - 4)...(root.fret + 5)
        var targets: [FretPosition] = []
        for s in [root.string, root.string - 1, root.string - 2] where (1...tuning.stringCount).contains(s) {
            if let f = fret(on: s), window.contains(f) { targets.append(FretPosition(string: s, fret: f)) }
        }
        if targets.isEmpty, let f = fret(on: root.string) { targets.append(FretPosition(string: root.string, fret: f)) }
        if targets.isEmpty {
            for s in tuning.stringNumbers { if let f = fret(on: s) { targets.append(FretPosition(string: s, fret: f)) } }
        }
        // Typical shape: smallest fret distance, preferring the adjacent string.
        let primary = targets.min { a, b in
            let da = abs(a.fret - root.fret) * 2 + abs(root.string - 1 - a.string)
            let db = abs(b.fret - root.fret) * 2 + abs(root.string - 1 - b.string)
            return da < db
        }
        return (targets, primary)
    }
}
