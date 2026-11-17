/// A single prompt the user answers. Identity (and statistics) is carried by `key`.
public struct Card: Identifiable, Hashable, Sendable {
    public var id: ItemKey { key }
    public let key: ItemKey
    public let deckID: DeckID
    public let content: CardContent

    public init(key: ItemKey, deckID: DeckID, content: CardContent) {
        self.key = key
        self.deckID = deckID
        self.content = content
    }

    /// Same identity, new content (used at presentation time).
    public func with(_ content: CardContent) -> Card {
        Card(key: key, deckID: deckID, content: content)
    }
}

/// The renderable payload of a card. Cards are never persisted, so cases may evolve freely.
public enum CardContent: Hashable, Sendable {
    case fretboardNote(FretboardNotePrompt)
    case vocab(VocabPrompt)
    case fretboardPosition(FretboardPositionPrompt)
    case findAll(FindAllPrompt)
    case interval(IntervalPrompt)
    case earInterval(EarIntervalPrompt)
    case chord(ChordCardPrompt)
    case triad(TriadPrompt)
    case arpeggio(ArpeggioPrompt)
    case scale(ScalePrompt)
    case keySignature(KeySignaturePrompt)
    case diatonic(DiatonicPrompt)
    case progression(ProgressionPrompt)
    case circle(CirclePrompt)
    case hangulReading(HangulReadingPrompt)
    case particle(ParticlePrompt)
    case conjugation(ConjugationPrompt)
}

/// "Play {note} on string {n}".
public struct FretboardNotePrompt: Hashable, Sendable {
    /// 1 = high E … 6 = low E (standard guitar numbering).
    public let stringNumber: Int
    public let pitchClass: PitchClass
    /// Display spelling chosen at generation/presentation time.
    public let spelling: NoteSpelling
    /// All frets in the configured range producing `pitchClass` on `stringNumber`.
    public let answerFrets: [Int]
    public let tuning: TuningID

    public init(stringNumber: Int, pitchClass: PitchClass, spelling: NoteSpelling, answerFrets: [Int], tuning: TuningID = .standard) {
        self.stringNumber = stringNumber
        self.pitchClass = pitchClass
        self.spelling = spelling
        self.answerFrets = answerFrets
        self.tuning = tuning
    }

    /// Same prompt with a different display spelling (key-neutral).
    public func respelled(_ spelling: NoteSpelling) -> FretboardNotePrompt {
        FretboardNotePrompt(stringNumber: stringNumber, pitchClass: pitchClass, spelling: spelling, answerFrets: answerFrets, tuning: tuning)
    }
}

/// "Which note is this?" — a single position is shown.
public struct FretboardPositionPrompt: Hashable, Sendable {
    public let position: FretPosition
    public let pitchClass: PitchClass
    public let spelling: NoteSpelling
    public let tuning: TuningID

    public init(position: FretPosition, pitchClass: PitchClass, spelling: NoteSpelling, tuning: TuningID) {
        self.position = position
        self.pitchClass = pitchClass
        self.spelling = spelling
        self.tuning = tuning
    }

    public var midi: Int { Fretboard.midi(string: position.string, fret: position.fret, tuning: .preset(tuning)) }
}

/// "Find every A" within a set of strings and a fret range.
public struct FindAllPrompt: Hashable, Sendable {
    public let pitchClass: PitchClass
    public let spelling: NoteSpelling
    public let tuning: TuningID
    /// Included strings, high → low numbering sorted descending (6…1).
    public let strings: [Int]
    public let fretRange: ClosedRange<Int>
    /// Every matching position, low string first.
    public let positions: [FretPosition]

    public init(pitchClass: PitchClass, spelling: NoteSpelling, tuning: TuningID, strings: [Int], fretRange: ClosedRange<Int>, positions: [FretPosition]) {
        self.pitchClass = pitchClass
        self.spelling = spelling
        self.tuning = tuning
        self.strings = strings
        self.fretRange = fretRange
        self.positions = positions
    }
}

/// "Play a major 3rd above C" from a root position.
public struct IntervalPrompt: Hashable, Sendable {
    public let interval: Interval
    public let root: FretPosition
    public let rootSpelling: NoteSpelling
    public let targetSpelling: NoteSpelling
    public let tuning: TuningID
    /// Target positions in the playable window around the root.
    public let targets: [FretPosition]
    /// The nearest / typical shape among `targets`.
    public let primary: FretPosition?

    public init(interval: Interval, root: FretPosition, rootSpelling: NoteSpelling, targetSpelling: NoteSpelling,
                tuning: TuningID, targets: [FretPosition], primary: FretPosition?) {
        self.interval = interval
        self.root = root
        self.rootSpelling = rootSpelling
        self.targetSpelling = targetSpelling
        self.tuning = tuning
        self.targets = targets
        self.primary = primary
    }

    public var rootMidi: Int { Fretboard.midi(string: root.string, fret: root.fret, tuning: .preset(tuning)) }
    public var targetMidi: Int { rootMidi + interval.semitones }
}

/// How an ear-training interval is played.
public enum EarMode: String, Codable, Sendable, CaseIterable, Hashable {
    /// Raw values appear in `ItemKey`s — never change them.
    case ascending = "asc", descending = "desc", harmonic = "harm"

    public var title: String {
        switch self {
        case .ascending: "Ascending"
        case .descending: "Descending"
        case .harmonic: "Harmonic"
        }
    }
}

/// "Hear two notes, name the interval."
public struct EarIntervalPrompt: Hashable, Sendable {
    public let interval: Interval
    public let mode: EarMode
    /// Lower note of the pair.
    public let rootMidi: Int

    public init(interval: Interval, mode: EarMode, rootMidi: Int) {
        self.interval = interval
        self.mode = mode
        self.rootMidi = rootMidi
    }

    public var upperMidi: Int { rootMidi + interval.semitones }

    /// Notes in playback order with their start offsets in seconds.
    public func sequence(gap: Double = 0.6) -> [(midi: Int, delay: Double)] {
        switch mode {
        case .ascending: [(rootMidi, 0), (upperMidi, gap)]
        case .descending: [(upperMidi, 0), (rootMidi, gap)]
        case .harmonic: [(rootMidi, 0), (upperMidi, 0)]
        }
    }

    /// Offset of the second note's start (when the response timer should start).
    public func secondNoteDelay(gap: Double = 0.6) -> Double { mode == .harmonic ? 0 : gap }
}

/// A vocabulary entry asked in one direction.
public struct VocabPrompt: Hashable, Sendable {
    public let entry: VocabEntry
    public let direction: VocabDirection

    public init(entry: VocabEntry, direction: VocabDirection) {
        self.entry = entry
        self.direction = direction
    }
}

public extension Card {
    var fretboardNote: FretboardNotePrompt? {
        if case let .fretboardNote(p) = content { return p }
        return nil
    }

    var vocab: VocabPrompt? {
        if case let .vocab(p) = content { return p }
        return nil
    }

    var fretboardPosition: FretboardPositionPrompt? {
        if case let .fretboardPosition(p) = content { return p }
        return nil
    }

    var findAll: FindAllPrompt? {
        if case let .findAll(p) = content { return p }
        return nil
    }

    var interval: IntervalPrompt? {
        if case let .interval(p) = content { return p }
        return nil
    }

    var earInterval: EarIntervalPrompt? {
        if case let .earInterval(p) = content { return p }
        return nil
    }

    var chord: ChordCardPrompt? {
        if case let .chord(p) = content { return p }
        return nil
    }

    var triad: TriadPrompt? {
        if case let .triad(p) = content { return p }
        return nil
    }

    var arpeggio: ArpeggioPrompt? {
        if case let .arpeggio(p) = content { return p }
        return nil
    }

    var scale: ScalePrompt? {
        if case let .scale(p) = content { return p }
        return nil
    }

    var keySignature: KeySignaturePrompt? {
        if case let .keySignature(p) = content { return p }
        return nil
    }

    var diatonic: DiatonicPrompt? {
        if case let .diatonic(p) = content { return p }
        return nil
    }

    var progression: ProgressionPrompt? {
        if case let .progression(p) = content { return p }
        return nil
    }

    var circle: CirclePrompt? {
        if case let .circle(p) = content { return p }
        return nil
    }

    var hangulReading: HangulReadingPrompt? {
        if case let .hangulReading(p) = content { return p }
        return nil
    }

    var particle: ParticlePrompt? {
        if case let .particle(p) = content { return p }
        return nil
    }

    var conjugation: ConjugationPrompt? {
        if case let .conjugation(p) = content { return p }
        return nil
    }
}
