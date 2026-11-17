/// How progression diagrams are chosen. Raw values are persisted — **never change them**.
public enum VoicingStyle: String, Codable, Sendable, CaseIterable, Hashable {
    /// Open shapes where available, else the lowest barre.
    case open
    /// E-/A-shape barre chords.
    case barre
    /// Any movable shape, each chord nearest to the previous one.
    case caged

    public var title: String {
        switch self {
        case .open: "Open"
        case .barre: "Barre"
        case .caged: "Nearest (CAGED)"
        }
    }
}

public struct ProgressionOptions: Hashable, Codable, Sendable {
    public var progressions: Set<Progression>
    /// Major tonics (ASCII); minor progressions use their relative minors.
    public var keys: Set<String>
    public var voicingStyle: VoicingStyle
    /// Play only the first 4 bars of the 12-bar blues.
    public var bluesFourBars: Bool

    public init(
        progressions: Set<Progression> = Set(Progression.allCases),
        keys: Set<String> = DiatonicOptions.allKeys,
        voicingStyle: VoicingStyle = .open,
        bluesFourBars: Bool = false
    ) {
        self.progressions = progressions
        self.keys = keys
        self.voicingStyle = voicingStyle
        self.bluesFourBars = bluesFourBars
    }

    private enum CodingKeys: String, CodingKey { case progressions, keys, voicingStyle, bluesFourBars }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ProgressionOptions()
        progressions = c.tolerant(Set<Progression>.self, .progressions, d.progressions)
        keys = c.tolerant(Set<String>.self, .keys, d.keys)
        voicingStyle = c.tolerant(VoicingStyle.self, .voicingStyle, d.voicingStyle)
        bluesFourBars = c.tolerant(Bool.self, .bluesFourBars, d.bluesFourBars)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sortedRaw(progressions), forKey: .progressions)
        try c.encode(keys.sorted(), forKey: .keys)
        try c.encode(voicingStyle, forKey: .voicingStyle)
        try c.encode(bluesFourBars, forKey: .bluesFourBars)
    }
}

/// "Play ii–V–I in G".
public struct ProgressionsDeck: Deck {
    public static let deckID: DeckID = "music.progressions"

    public let id: DeckID = ProgressionsDeck.deckID
    public let kind = DeckKind.progressions
    public let title = "Progressions"
    public let subtitle = "Roman numerals to chords in any key"
    public let subject = Subject.music
    public let group = DeckGroup.chords
    let library: ChordShapeLibrary

    static let searchMaxFret = 15

    public init(library: ChordShapeLibrary = .shared) { self.library = library }

    public var defaultOptions: DeckOptions { .progressions(ProgressionOptions()) }

    public static func itemKey(_ p: Progression, tonic: NoteSpelling) -> ItemKey {
        ItemKey("prog:\(p.rawValue):\(tonic.ascii)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .progressions(o) = options else { return [] }
        var result: [Card] = []
        for p in Progression.allCases where o.progressions.contains(p) {
            for major in Key.majors where o.keys.contains(major.tonic.ascii) {
                let key = p.mode == .major ? major : major.relative
                guard let chords = p.realize(in: key) else { continue }
                result.append(Card(key: Self.itemKey(p, tonic: key.tonic), deckID: id,
                                   content: .progression(ProgressionPrompt(progression: p, key: key, chords: chords,
                                                                           voicings: voicings(for: chords, style: o.voicingStyle),
                                                                           playCount: p == .blues12 && o.bluesFourBars ? 4 : chords.count))))
            }
        }
        return result
    }

    /// One voicing per chord in the chosen style.
    func voicings(for chords: [Chord], style: VoicingStyle) -> [Voicing?] {
        let maxFret = Self.searchMaxFret
        func all(_ c: Chord, families: Set<ShapeFamily>) -> [Voicing] {
            library.shapes.filter { $0.quality == c.quality && families.contains($0.family) }
                .flatMap { $0.voicings(root: c.root, maxFret: maxFret) }
        }
        func lowest(_ vs: [Voicing]) -> Voicing? { vs.min { ($0.lowestFret, $0.shapeID) < ($1.lowestFret, $1.shapeID) } }

        switch style {
        case .open:
            return chords.map { c in
                lowest(all(c, families: [.open])) ?? lowest(all(c, families: [.barre])) ?? lowest(all(c, families: [.caged, .other, .power]))
            }
        case .barre:
            return chords.map { c in lowest(all(c, families: [.barre])) ?? lowest(all(c, families: [.caged, .other, .power])) }
        case .caged:
            var result: [Voicing?] = []
            var previous: Voicing?
            for c in chords {
                let candidates = all(c, families: [.barre, .caged, .other, .power])
                let pick: Voicing?
                if let previous {
                    pick = candidates.min { a, b in
                        (abs(a.centre - previous.centre), a.shapeID) < (abs(b.centre - previous.centre), b.shapeID)
                    }
                } else {
                    pick = lowest(candidates)
                }
                result.append(pick)
                previous = pick ?? previous
            }
            return result
        }
    }

    /// Same progression ×0.4; same key ×0.5.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.progression, let p = recent.back(0)?.progression else { return 1 }
        var penalty = 1.0
        if c.progression == p.progression { penalty *= 0.4 }
        if c.key.tonic == p.key.tonic { penalty *= 0.5 }
        return penalty
    }

    /// Simple keys first.
    public func introductionRank(of card: Card) -> Int? { card.progression.map { $0.key.signature.count } }
}
