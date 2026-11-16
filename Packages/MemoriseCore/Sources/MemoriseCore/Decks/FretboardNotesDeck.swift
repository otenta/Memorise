/// Options for the Fretboard Notes deck.
public struct FretboardOptions: Hashable, Codable, Sendable {
    public enum NoteSet: String, Codable, Sendable, CaseIterable {
        /// 7 per string.
        case naturals
        /// 12 per string.
        case all
    }

    public enum AccidentalSpelling: String, Codable, Sendable, CaseIterable {
        case sharps, flats, mixed
    }

    public static let maxFretPresets = [12, 15, 17, 19, 22, 24]

    public var strings: Set<Int>
    public var noteSet: NoteSet
    public var accidentalSpelling: AccidentalSpelling
    public var fretRange: ClosedRange<Int>

    public init(
        strings: Set<Int> = [1, 2, 3, 4, 5, 6],
        noteSet: NoteSet = .naturals,
        accidentalSpelling: AccidentalSpelling = .sharps,
        fretRange: ClosedRange<Int> = 0...12
    ) {
        self.strings = strings
        self.noteSet = noteSet
        self.accidentalSpelling = accidentalSpelling
        self.fretRange = fretRange
    }

    private enum CodingKeys: String, CodingKey {
        case strings, noteSet, accidentalSpelling, fretRange
    }

    /// Tolerant decoding: every property falls back to its default when missing or unreadable.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FretboardOptions()
        strings = (try? c.decodeIfPresent(Set<Int>.self, forKey: .strings)) ?? d.strings
        noteSet = (try? c.decodeIfPresent(NoteSet.self, forKey: .noteSet)) ?? d.noteSet
        accidentalSpelling = (try? c.decodeIfPresent(AccidentalSpelling.self, forKey: .accidentalSpelling)) ?? d.accidentalSpelling
        fretRange = (try? c.decodeIfPresent(ClosedRange<Int>.self, forKey: .fretRange)) ?? d.fretRange
    }

    /// Same keys as the synthesised format; `strings` is written sorted for deterministic output.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(strings.sorted(), forKey: .strings)
        try c.encode(noteSet, forKey: .noteSet)
        try c.encode(accidentalSpelling, forKey: .accidentalSpelling)
        try c.encode(fretRange, forKey: .fretRange)
    }
}

/// Generated deck: "Play {note} on string {n}".
public struct FretboardNotesDeck: Deck {
    public static let deckID: DeckID = "music.fretboard.notes"

    public let id: DeckID = FretboardNotesDeck.deckID
    public let title = "Fretboard Notes"
    public let subtitle = "Find any note on any string"
    public let subject = Subject.music
    public let tuning: Tuning

    public init(tuning: Tuning = .standard) {
        self.tuning = tuning
    }

    public var defaultOptions: DeckOptions { .fretboard(FretboardOptions()) }

    /// Stable stats key: `"fret:s6:A"`, `"fret:s3:C#"` (spelling-independent).
    public static func itemKey(string: Int, pitchClass: PitchClass) -> ItemKey {
        ItemKey("fret:s\(string):\(pitchClass.canonicalSharpName)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .fretboard(o) = options else { return [] }
        let pitchClasses = o.noteSet == .naturals ? PitchClass.naturals : PitchClass.allCases
        let preferFlat = o.accidentalSpelling == .flats
        var result: [Card] = []
        result.reserveCapacity(o.strings.count * pitchClasses.count)
        for s in tuning.stringNumbers where o.strings.contains(s) {
            for pc in pitchClasses {
                let frets = Fretboard.frets(for: pc, onString: s, tuning: tuning, fretRange: o.fretRange)
                guard !frets.isEmpty else { continue }
                let prompt = FretboardNotePrompt(
                    stringNumber: s,
                    pitchClass: pc,
                    spelling: .preferred(for: pc, preferFlat: preferFlat),
                    answerFrets: frets,
                    randomizeSpelling: o.accidentalSpelling == .mixed
                )
                result.append(Card(key: Self.itemKey(string: s, pitchClass: pc), deckID: id, content: .fretboardNote(prompt)))
            }
        }
        return result
    }

    /// `.mixed` only: re-spells a sharp-spelled accidental as its flat with probability ½.
    /// `.sharps` / `.flats` cards are returned unchanged.
    public func present(_ card: Card, using rng: inout SplitMix64) -> Card {
        guard let p = card.fretboardNote, p.randomizeSpelling, p.spelling.accidental == .sharp,
              Bool.random(using: &rng) else { return card }
        return Card(key: card.key, deckID: card.deckID, content: .fretboardNote(p.respelled(.preferred(for: p.pitchClass, preferFlat: true))))
    }

    /// Same string as previous ×0.35; same pitch class as previous ×0.35; same string as 2-back ×0.7.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.fretboardNote else { return 1 }
        var penalty = 1.0
        if let prev = recent.last?.fretboardNote {
            if prev.stringNumber == c.stringNumber { penalty *= 0.35 }
            if prev.pitchClass == c.pitchClass { penalty *= 0.35 }
        }
        if recent.count >= 2, let back2 = recent[recent.index(recent.endIndex, offsetBy: -2)].fretboardNote,
           back2.stringNumber == c.stringNumber {
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
            ? "string \(prompt.stringNumber) (\(tuning.stringName(prompt.stringNumber)))"
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
