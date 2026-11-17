/// Options shared by the fretboard decks (Notes, Name the Note, Find All).
public struct FretboardOptions: Hashable, Codable, Sendable {
    public enum NoteSet: String, Codable, Sendable, CaseIterable {
        /// 7 per string.
        case naturals
        /// 12 per string.
        case all

        public var pitchClasses: [PitchClass] { self == .naturals ? PitchClass.naturals : PitchClass.allCases }
    }

    /// Kept for source compatibility; the type is shared by all fretboard decks.
    public typealias AccidentalSpelling = MemoriseCore.AccidentalSpelling

    public static let maxFretPresets = [12, 15, 17, 19, 22, 24]

    public var strings: Set<Int>
    public var noteSet: NoteSet
    public var accidentalSpelling: AccidentalSpelling
    public var fretRange: ClosedRange<Int>
    public var tuning: TuningID

    public init(
        strings: Set<Int> = [1, 2, 3, 4, 5, 6],
        noteSet: NoteSet = .naturals,
        accidentalSpelling: AccidentalSpelling = .sharps,
        fretRange: ClosedRange<Int> = 0...12,
        tuning: TuningID = .standard
    ) {
        self.strings = strings
        self.noteSet = noteSet
        self.accidentalSpelling = accidentalSpelling
        self.fretRange = fretRange
        self.tuning = tuning
    }

    private enum CodingKeys: String, CodingKey {
        case strings, noteSet, accidentalSpelling, fretRange, tuning
    }

    /// Tolerant decoding: every property falls back to its default when missing or unreadable.
    /// M1 data has no `tuning` key and decodes as `.standard`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FretboardOptions()
        strings = c.tolerant(Set<Int>.self, .strings, d.strings)
        noteSet = c.tolerant(NoteSet.self, .noteSet, d.noteSet)
        accidentalSpelling = c.tolerant(AccidentalSpelling.self, .accidentalSpelling, d.accidentalSpelling)
        fretRange = c.tolerant(ClosedRange<Int>.self, .fretRange, d.fretRange)
        tuning = c.tolerant(TuningID.self, .tuning, d.tuning)
    }

    /// `strings` is written sorted for deterministic output.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(strings.sorted(), forKey: .strings)
        try c.encode(noteSet, forKey: .noteSet)
        try c.encode(accidentalSpelling, forKey: .accidentalSpelling)
        try c.encode(fretRange, forKey: .fretRange)
        try c.encode(tuning, forKey: .tuning)
    }

    public var tuningPreset: Tuning { .preset(tuning) }
}

/// Generated deck: "Play {note} on string {n}".
public struct FretboardNotesDeck: Deck {
    public static let deckID: DeckID = "music.fretboard.notes"

    public let id: DeckID = FretboardNotesDeck.deckID
    public let kind = DeckKind.fretboardNotes
    public let title = "Fretboard Notes"
    public let subtitle = "Find any note on any string"
    public let subject = Subject.music

    public init() {}

    public var defaultOptions: DeckOptions { .fretboard(FretboardOptions()) }

    /// Stable stats key: `"fret:s6:A"`, `"fret@dropD:s3:C#"` (spelling-independent).
    public static func itemKey(string: Int, pitchClass: PitchClass, tuning: TuningID = .standard) -> ItemKey {
        ItemKey("\(FretboardKeys.scheme("fret", tuning: tuning)):s\(string):\(pitchClass.canonicalSharpName)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .fretboard(o) = options else { return [] }
        let tuning = o.tuningPreset
        let pitchClasses = o.noteSet.pitchClasses
        var result: [Card] = []
        result.reserveCapacity(o.strings.count * pitchClasses.count)
        for s in tuning.stringNumbers where o.strings.contains(s) {
            for pc in pitchClasses {
                let frets = Fretboard.frets(for: pc, onString: s, tuning: tuning, fretRange: o.fretRange)
                guard !frets.isEmpty else { continue }
                let prompt = FretboardNotePrompt(
                    stringNumber: s, pitchClass: pc, spelling: o.accidentalSpelling.baseSpelling(pc),
                    answerFrets: frets, tuning: o.tuning
                )
                result.append(Card(key: Self.itemKey(string: s, pitchClass: pc, tuning: o.tuning), deckID: id, content: .fretboardNote(prompt)))
            }
        }
        return result
    }

    /// `.mixed` only: spells accidentals ♯ or ♭ at random. `.sharps` / `.flats` are unchanged.
    public func present(_ card: Card, options: DeckOptions, using rng: inout SplitMix64) -> Card {
        guard let p = card.fretboardNote, let o = options.fretboard, o.accidentalSpelling == .mixed else { return card }
        return card.with(.fretboardNote(p.respelled(o.accidentalSpelling.presentationSpelling(p.pitchClass, using: &rng))))
    }

    /// Same string as previous ×0.35; same pitch class as previous ×0.35; same string as 2-back ×0.7.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.fretboardNote else { return 1 }
        var penalty = 1.0
        if let prev = recent.back(0)?.fretboardNote {
            if prev.stringNumber == c.stringNumber { penalty *= 0.35 }
            if prev.pitchClass == c.pitchClass { penalty *= 0.35 }
        }
        if let back2 = recent.back(1)?.fretboardNote, back2.stringNumber == c.stringNumber {
            penalty *= 0.7
        }
        return penalty
    }

    // MARK: Display helpers

    /// Formatted note name for the prompt.
    public func noteText(_ prompt: FretboardNotePrompt, settings: MusicDisplaySettings) -> String {
        NoteFormatter.format(prompt.spelling, settings: settings)
    }

    /// "string 6 (low E)" / "string 6".
    public func stringText(_ prompt: FretboardNotePrompt, settings: MusicDisplaySettings) -> String {
        settings.showStringHint
            ? "string \(prompt.stringNumber) (\(Tuning.preset(prompt.tuning).stringName(prompt.stringNumber)))"
            : "string \(prompt.stringNumber)"
    }

    /// Full prompt sentence, e.g. "Play A (La) on string 6 (low E)".
    public func promptText(_ prompt: FretboardNotePrompt, settings: MusicDisplaySettings) -> String {
        "Play \(noteText(prompt, settings: settings)) on \(stringText(prompt, settings: settings))"
    }

    /// Answer caption, e.g. "Fret 5 (also 17)", "Open string (also 12)".
    public static func answerText(frets: [Int]) -> String {
        guard let first = frets.first else { return "Not in range" }
        let head = first == 0 ? "Open string" : "Fret \(first)"
        guard frets.count > 1 else { return head }
        return "\(head) (also \(frets.dropFirst().map(String.init).joined(separator: ", ")))"
    }
}
