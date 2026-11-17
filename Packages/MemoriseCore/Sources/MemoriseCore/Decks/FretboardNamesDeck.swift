/// Reverse cards: a fretboard position is shown, name the note.
public struct FretboardNamesDeck: Deck {
    public static let deckID: DeckID = "music.fretboard.names"

    public let id: DeckID = FretboardNamesDeck.deckID
    public let kind = DeckKind.fretboardNames
    public let title = "Name the Note"
    public let subtitle = "See a fret, say the note"
    public let subject = Subject.music

    public init() {}

    public var defaultOptions: DeckOptions { .fretboard(FretboardOptions()) }

    /// `"fretname:s6:f5"`, `"fretname@dropD:s6:f5"`.
    public static func itemKey(_ p: FretPosition, tuning: TuningID = .standard) -> ItemKey {
        ItemKey("\(FretboardKeys.scheme("fretname", tuning: tuning)):s\(p.string):f\(p.fret)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .fretboard(o) = options else { return [] }
        let tuning = o.tuningPreset
        let allowed = Set(o.noteSet.pitchClasses)
        var result: [Card] = []
        result.reserveCapacity(o.strings.count * o.fretRange.count)
        for s in tuning.stringNumbers where o.strings.contains(s) {
            for f in o.fretRange {
                let pc = Fretboard.pitchClass(string: s, fret: f, tuning: tuning)
                guard allowed.contains(pc) else { continue }
                let pos = FretPosition(string: s, fret: f)
                let prompt = FretboardPositionPrompt(position: pos, pitchClass: pc, spelling: o.accidentalSpelling.baseSpelling(pc), tuning: o.tuning)
                result.append(Card(key: Self.itemKey(pos, tuning: o.tuning), deckID: id, content: .fretboardPosition(prompt)))
            }
        }
        return result
    }

    public func present(_ card: Card, options: DeckOptions, using rng: inout SplitMix64) -> Card {
        guard let p = card.fretboardPosition, let o = options.fretboard, o.accidentalSpelling == .mixed else { return card }
        let spelling = o.accidentalSpelling.presentationSpelling(p.pitchClass, using: &rng)
        return card.with(.fretboardPosition(FretboardPositionPrompt(position: p.position, pitchClass: p.pitchClass, spelling: spelling, tuning: p.tuning)))
    }

    /// Same string ×0.35; same fret ×0.5; same pitch class ×0.35 (vs. previous card).
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.fretboardPosition, let prev = recent.back(0)?.fretboardPosition else { return 1 }
        var penalty = 1.0
        if prev.position.string == c.position.string { penalty *= 0.35 }
        if prev.position.fret == c.position.fret { penalty *= 0.5 }
        if prev.pitchClass == c.pitchClass { penalty *= 0.35 }
        return penalty
    }
}

/// "Find every A on the neck."
public struct FindAllDeck: Deck {
    public static let deckID: DeckID = "music.fretboard.findall"

    public let id: DeckID = FindAllDeck.deckID
    public let kind = DeckKind.fretboardFindAll
    public let title = "Find All"
    public let subtitle = "Every A on the neck"
    public let subject = Subject.music

    public init() {}

    public var defaultOptions: DeckOptions { .fretboard(FretboardOptions()) }

    /// `"findall:A"`, `"findall@dropD:C#"`. The string set does not change the key.
    public static func itemKey(_ pc: PitchClass, tuning: TuningID = .standard) -> ItemKey {
        ItemKey("\(FretboardKeys.scheme("findall", tuning: tuning)):\(pc.canonicalSharpName)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .fretboard(o) = options else { return [] }
        let tuning = o.tuningPreset
        let strings = o.strings.sorted(by: >)
        return o.noteSet.pitchClasses.compactMap { pc in
            let positions = Fretboard.positions(of: pc, strings: o.strings, tuning: tuning, fretRange: o.fretRange)
            guard !positions.isEmpty else { return nil }
            let prompt = FindAllPrompt(
                pitchClass: pc, spelling: o.accidentalSpelling.baseSpelling(pc), tuning: o.tuning,
                strings: strings, fretRange: o.fretRange, positions: positions
            )
            return Card(key: Self.itemKey(pc, tuning: o.tuning), deckID: id, content: .findAll(prompt))
        }
    }

    public func present(_ card: Card, options: DeckOptions, using rng: inout SplitMix64) -> Card {
        guard let p = card.findAll, let o = options.fretboard, o.accidentalSpelling == .mixed else { return card }
        let spelling = o.accidentalSpelling.presentationSpelling(p.pitchClass, using: &rng)
        return card.with(.findAll(FindAllPrompt(
            pitchClass: p.pitchClass, spelling: spelling, tuning: p.tuning,
            strings: p.strings, fretRange: p.fretRange, positions: p.positions
        )))
    }

    /// A fifth-related previous note ×0.7 (same note is already prevented by cooldown).
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.findAll, let prev = recent.back(0)?.findAll else { return 1 }
        let d = PitchClass(c.pitchClass.value - prev.pitchClass.value).value
        return d == 5 || d == 7 ? 0.7 : 1
    }
}
