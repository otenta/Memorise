/// Options for Triads on string sets.
public struct TriadOptions: Hashable, Codable, Sendable {
    public var qualities: Set<ChordQuality>
    public var inversions: Set<TriadInversion>
    public var stringSets: Set<StringSet>
    public var roots: Set<PitchClass>
    public var maxFret: Int

    public init(
        qualities: Set<ChordQuality> = Set(ChordQuality.triadQualities),
        inversions: Set<TriadInversion> = Set(TriadInversion.allCases),
        stringSets: Set<StringSet> = Set(StringSet.allCases),
        roots: Set<PitchClass> = RootNames.all,
        maxFret: Int = 15
    ) {
        self.qualities = qualities
        self.inversions = inversions
        self.stringSets = stringSets
        self.roots = roots
        self.maxFret = maxFret
    }

    private enum CodingKeys: String, CodingKey { case qualities, inversions, stringSets, roots, maxFret }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TriadOptions()
        qualities = c.tolerant(Set<ChordQuality>.self, .qualities, d.qualities)
        inversions = c.tolerant(Set<TriadInversion>.self, .inversions, d.inversions)
        stringSets = c.tolerant(Set<StringSet>.self, .stringSets, d.stringSets)
        roots = c.tolerant(Set<PitchClass>.self, .roots, d.roots)
        maxFret = c.tolerant(Int.self, .maxFret, d.maxFret)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sortedRaw(qualities), forKey: .qualities)
        try c.encode(sortedRaw(inversions), forKey: .inversions)
        try c.encode(sortedRaw(stringSets), forKey: .stringSets)
        try c.encode(roots.sorted(), forKey: .roots)
        try c.encode(maxFret, forKey: .maxFret)
    }
}

/// "C major, 1st inversion, strings 3-2-1".
public struct TriadsDeck: Deck {
    public static let deckID: DeckID = "music.triads"

    public let id: DeckID = TriadsDeck.deckID
    public let kind = DeckKind.triads
    public let title = "Triads"
    public let subtitle = "Inversions on string sets"
    public let subject = Subject.music
    public let group = DeckGroup.chords

    public init() {}

    public var defaultOptions: DeckOptions { .triads(TriadOptions()) }

    public static func itemKey(_ q: ChordQuality, _ inv: TriadInversion, _ set: StringSet, root: NoteSpelling) -> ItemKey {
        ItemKey("triad:\(q.rawValue):\(inv.rawValue):\(set.rawValue):\(root.ascii)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .triads(o) = options else { return [] }
        var result: [Card] = []
        for q in ChordQuality.triadQualities where o.qualities.contains(q) {
            for inv in TriadInversion.allCases where o.inversions.contains(inv) {
                for set in StringSet.allCases where o.stringSets.contains(set) {
                    for pc in o.roots.sorted() {
                        guard let chord = Chord.spelled(pc, q, preferFlat: RootNames.preferFlat(pc)),
                              let notes = Self.voice(chord, inv, set, maxFret: o.maxFret) else { continue }
                        result.append(Card(key: Self.itemKey(q, inv, set, root: chord.root), deckID: id,
                                           content: .triad(TriadPrompt(chord: chord, inversion: inv, stringSet: set, notes: notes))))
                    }
                }
            }
        }
        return result
    }

    /// Close-position voicing at the lowest fret where every note is in 0…maxFret and the span ≤ 4 frets.
    static func voice(_ chord: Chord, _ inv: TriadInversion, _ set: StringSet, maxFret: Int, tuning: Tuning = .standard) -> [FretNote]? {
        let tones = inv.order.map { chord.tones[$0] }
        let strings = set.strings
        let open0 = tuning.openMidi(string: strings[0])
        var f0 = PitchClass(tones[0].pitchClass.value - open0).value
        while f0 <= maxFret {
            var midis = [open0 + f0]
            for t in tones.dropFirst() {
                let prev = midis.last!
                var step = PitchClass(t.pitchClass.value - prev).value
                if step == 0 { step = 12 }
                midis.append(prev + step)
            }
            let frets = zip(strings, midis).map { $1 - tuning.openMidi(string: $0) }
            if frets.allSatisfy({ (0...maxFret).contains($0) }), frets.max()! - frets.min()! <= 3 {
                return zip(zip(strings, frets), zip(midis, tones)).map { sf, mt in
                    FretNote(position: FretPosition(string: sf.0, fret: sf.1), midi: mt.0, spelling: mt.1,
                             degree: chord.degreeLabel(for: mt.1.pitchClass) ?? "")
                }
            }
            f0 += 12
        }
        return nil
    }

    /// Same string set ×0.5; same inversion ×0.6; same root ×0.5.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.triad, let p = recent.back(0)?.triad else { return 1 }
        var penalty = 1.0
        if c.stringSet == p.stringSet { penalty *= 0.5 }
        if c.inversion == p.inversion { penalty *= 0.6 }
        if c.chord.root.pitchClass == p.chord.root.pitchClass { penalty *= 0.5 }
        return penalty
    }

    /// Major/minor root position first, then inversions, then dim/aug.
    public func introductionRank(of card: Card) -> Int? {
        guard let t = card.triad else { return nil }
        let q = ChordQuality.triadQualities.firstIndex(of: t.chord.quality) ?? 0
        let inv = TriadInversion.allCases.firstIndex(of: t.inversion) ?? 0
        return (q >= 2 ? 10 : 0) + inv * 2 + q
    }
}
