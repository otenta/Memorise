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
}

/// The renderable payload of a card. Extensible: add a case per new card type.
public enum CardContent: Hashable, Sendable {
    case fretboardNote(FretboardNotePrompt)
    case vocab(VocabPrompt)
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
    /// When true, the deck may re-spell accidentals (♯/♭) at random at presentation time (`.mixed`).
    public let randomizeSpelling: Bool

    public init(stringNumber: Int, pitchClass: PitchClass, spelling: NoteSpelling, answerFrets: [Int], randomizeSpelling: Bool = false) {
        self.stringNumber = stringNumber
        self.pitchClass = pitchClass
        self.spelling = spelling
        self.answerFrets = answerFrets
        self.randomizeSpelling = randomizeSpelling
    }

    /// Same prompt with a different display spelling (key-neutral).
    public func respelled(_ spelling: NoteSpelling) -> FretboardNotePrompt {
        FretboardNotePrompt(
            stringNumber: stringNumber, pitchClass: pitchClass, spelling: spelling,
            answerFrets: answerFrets, randomizeSpelling: randomizeSpelling
        )
    }
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
    /// Fretboard payload, if this is a fretboard card.
    var fretboardNote: FretboardNotePrompt? {
        if case let .fretboardNote(p) = content { return p }
        return nil
    }

    /// Vocab payload, if this is a vocab card.
    var vocab: VocabPrompt? {
        if case let .vocab(p) = content { return p }
        return nil
    }
}
