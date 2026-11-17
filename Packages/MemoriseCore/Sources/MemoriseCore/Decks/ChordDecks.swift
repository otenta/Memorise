/// Raw-sorted array for deterministic option encoding.
func sortedRaw<T: RawRepresentable>(_ s: Set<T>) -> [T] where T.RawValue == String {
    s.sorted { $0.rawValue < $1.rawValue }
}

/// Options shared by Play the Chord and Name the Chord.
public struct ChordOptions: Hashable, Codable, Sendable {
    public var families: Set<ShapeFamily>
    public var qualities: Set<ChordQuality>
    /// Root pitch classes (spelled per `RootNames`).
    public var roots: Set<PitchClass>
    public var maxFret: Int

    public init(
        families: Set<ShapeFamily> = Set(ShapeFamily.allCases),
        qualities: Set<ChordQuality> = Set(ChordQuality.allCases),
        roots: Set<PitchClass> = RootNames.all,
        maxFret: Int = 12
    ) {
        self.families = families
        self.qualities = qualities
        self.roots = roots
        self.maxFret = maxFret
    }

    private enum CodingKeys: String, CodingKey { case families, qualities, roots, maxFret }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ChordOptions()
        families = c.tolerant(Set<ShapeFamily>.self, .families, d.families)
        qualities = c.tolerant(Set<ChordQuality>.self, .qualities, d.qualities)
        roots = c.tolerant(Set<PitchClass>.self, .roots, d.roots)
        maxFret = c.tolerant(Int.self, .maxFret, d.maxFret)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sortedRaw(families), forKey: .families)
        try c.encode(sortedRaw(qualities), forKey: .qualities)
        try c.encode(roots.sorted(), forKey: .roots)
        try c.encode(maxFret, forKey: .maxFret)
    }
}

/// Card generation shared by the two chord decks.
enum ChordCards {
    static func cards(options: DeckOptions, deckID: DeckID, prefix: String, library: ChordShapeLibrary) -> [Card] {
        guard case let .chords(o) = options else { return [] }
        var result: [Card] = []
        for shape in library.shapes where o.families.contains(shape.family) && o.qualities.contains(shape.quality) {
            if !shape.movable {
                guard let root = shape.rootSpelling, o.roots.contains(root.pitchClass),
                      let v = shape.voicing(root: root, maxFret: o.maxFret) else { continue }
                result.append(Card(key: ItemKey("\(prefix):\(shape.id)"), deckID: deckID, content: .chord(ChordCardPrompt(shape: shape, voicing: v))))
                continue
            }
            for pc in o.roots.sorted() {
                guard let chord = Chord.spelled(pc, shape.quality, preferFlat: RootNames.preferFlat(pc)),
                      let v = shape.voicing(root: chord.root, maxFret: o.maxFret) else { continue }
                result.append(Card(key: ItemKey("\(prefix):\(shape.id):\(chord.root.ascii)"), deckID: deckID,
                                   content: .chord(ChordCardPrompt(shape: shape, voicing: v))))
            }
        }
        return result
    }

    /// Same shape ×0.35; same root ×0.5.
    static func penalty(_ candidate: Card, _ recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.chord, let p = recent.back(0)?.chord else { return 1 }
        var penalty = 1.0
        if c.shape.id == p.shape.id { penalty *= 0.35 }
        if c.chord.root.pitchClass == p.chord.root.pitchClass { penalty *= 0.5 }
        return penalty
    }
}

/// "Play B♭m7 (A-shape barre)".
public struct ChordsPlayDeck: Deck {
    public static let deckID: DeckID = "music.chords.play"

    public let id: DeckID = ChordsPlayDeck.deckID
    public let kind = DeckKind.chordsPlay
    public let title = "Play the Chord"
    public let subtitle = "See the symbol, finger the shape"
    public let subject = Subject.music
    public let group = DeckGroup.chords
    let library: ChordShapeLibrary

    public init(library: ChordShapeLibrary = .shared) { self.library = library }

    public var defaultOptions: DeckOptions { .chords(ChordOptions()) }

    /// `chord:<shapeId>` (open) · `chord:<shapeId>:<root>` (movable).
    public static func itemKey(shapeID: String, root: NoteSpelling?) -> ItemKey {
        ItemKey("chord:\(shapeID)" + (root.map { ":\($0.ascii)" } ?? ""))
    }

    public func cards(options: DeckOptions) -> [Card] {
        ChordCards.cards(options: options, deckID: id, prefix: "chord", library: library)
    }

    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double { ChordCards.penalty(candidate, recent) }

    /// Open chords first, then barre/power, then the rest.
    public func introductionRank(of card: Card) -> Int? { ChordsPlayDeck.rank(card) }

    static func rank(_ card: Card) -> Int? {
        guard let c = card.chord else { return nil }
        let family = switch c.shape.family {
        case .open: 0
        case .power: 1
        case .barre: 2
        case .caged: 3
        case .other: 4
        }
        let quality = ChordQuality.allCases.firstIndex(of: c.shape.quality) ?? 0
        return family * 100 + quality
    }
}

/// "Name this chord" (diagram shown).
public struct ChordsNameDeck: Deck {
    public static let deckID: DeckID = "music.chords.name"

    public let id: DeckID = ChordsNameDeck.deckID
    public let kind = DeckKind.chordsName
    public let title = "Name the Chord"
    public let subtitle = "See the diagram, name the chord"
    public let subject = Subject.music
    public let group = DeckGroup.chords
    let library: ChordShapeLibrary

    public init(library: ChordShapeLibrary = .shared) { self.library = library }

    public var defaultOptions: DeckOptions { .chords(ChordOptions()) }

    /// `chordname:<shapeId>[:<root>]`.
    public static func itemKey(shapeID: String, root: NoteSpelling?) -> ItemKey {
        ItemKey("chordname:\(shapeID)" + (root.map { ":\($0.ascii)" } ?? ""))
    }

    public func cards(options: DeckOptions) -> [Card] {
        ChordCards.cards(options: options, deckID: id, prefix: "chordname", library: library)
    }

    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double { ChordCards.penalty(candidate, recent) }

    public func introductionRank(of card: Card) -> Int? { ChordsPlayDeck.rank(card) }
}

/// Multiple-choice options for Name the Chord (PLAN_M3 M3-3 item 2).
public enum ChordChoices {
    /// Four distinct chords, shuffled: the answer, the same root with another quality, the same
    /// quality on another root, and one random chord. Qualities prefer the session's selection.
    public static func options(for answer: Chord, qualities: Set<ChordQuality>, using rng: inout SplitMix64) -> [Chord] {
        var result = [answer]
        var symbols: Set<String> = [answer.symbol]
        func add(_ c: Chord?) -> Bool {
            guard let c, symbols.insert(c.symbol).inserted else { return false }
            result.append(c)
            return true
        }
        let preferFlat = answer.root.accidental == .flat
        let rootPC = answer.root.pitchClass
        let otherQualities = (qualities.count > 1 ? qualities : Set(ChordQuality.allCases)).subtracting([answer.quality])
        for q in otherQualities.sorted(by: { $0.rawValue < $1.rawValue }).shuffled(using: &rng)
        where add(Chord.spelled(rootPC, q, preferFlat: RootNames.preferFlat(rootPC) || preferFlat)) { break }
        for pc in PitchClass.allCases.filter({ $0 != rootPC }).shuffled(using: &rng)
        where add(Chord.spelled(pc, answer.quality, preferFlat: RootNames.preferFlat(pc))) { break }
        var attempts = 0
        while result.count < 4, attempts < 50 {
            attempts += 1
            let pc = PitchClass.allCases.randomElement(using: &rng)!
            let q = ChordQuality.allCases.randomElement(using: &rng)!
            _ = add(Chord.spelled(pc, q, preferFlat: RootNames.preferFlat(pc)))
        }
        return result.shuffled(using: &rng)
    }
}
