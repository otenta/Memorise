/// Options for the Arpeggios deck.
public struct ArpeggioOptions: Hashable, Codable, Sendable {
    public static let defaultQualities: Set<ChordQuality> = [.maj, .min, .dom7, .maj7, .min7, .m7b5]

    public var qualities: Set<ChordQuality>
    public var rootStrings: Set<Int>
    public var roots: Set<PitchClass>
    public var span: ArpeggioSpan
    public var maxFret: Int

    public init(
        qualities: Set<ChordQuality> = ArpeggioOptions.defaultQualities,
        rootStrings: Set<Int> = [5, 6],
        roots: Set<PitchClass> = RootNames.all,
        span: ArpeggioSpan = .twoOctaves,
        maxFret: Int = 15
    ) {
        self.qualities = qualities
        self.rootStrings = rootStrings
        self.roots = roots
        self.span = span
        self.maxFret = maxFret
    }

    private enum CodingKeys: String, CodingKey { case qualities, rootStrings, roots, span, maxFret }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ArpeggioOptions()
        qualities = c.tolerant(Set<ChordQuality>.self, .qualities, d.qualities)
        rootStrings = c.tolerant(Set<Int>.self, .rootStrings, d.rootStrings)
        roots = c.tolerant(Set<PitchClass>.self, .roots, d.roots)
        span = c.tolerant(ArpeggioSpan.self, .span, d.span)
        maxFret = c.tolerant(Int.self, .maxFret, d.maxFret)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sortedRaw(qualities), forKey: .qualities)
        try c.encode(rootStrings.sorted(), forKey: .rootStrings)
        try c.encode(roots.sorted(), forKey: .roots)
        try c.encode(span, forKey: .span)
        try c.encode(maxFret, forKey: .maxFret)
    }
}

/// "A m7 arpeggio · root on string 6 · 2 octaves".
public struct ArpeggiosDeck: Deck {
    public static let deckID: DeckID = "music.arpeggios"

    public let id: DeckID = ArpeggiosDeck.deckID
    public let kind = DeckKind.arpeggios
    public let title = "Arpeggios"
    public let subtitle = "Chord tones, one note at a time"
    public let subject = Subject.music
    public let group = DeckGroup.chords

    public init() {}

    public var defaultOptions: DeckOptions { .arpeggios(ArpeggioOptions()) }

    public static func itemKey(_ q: ChordQuality, rootString: Int, root: NoteSpelling) -> ItemKey {
        ItemKey("arp:\(q.rawValue):s\(rootString):\(root.ascii)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .arpeggios(o) = options else { return [] }
        var result: [Card] = []
        for q in ChordQuality.allCases where o.qualities.contains(q) {
            for s in [6, 5] where o.rootStrings.contains(s) {
                for pc in o.roots.sorted() {
                    guard let chord = Chord.spelled(pc, q, preferFlat: RootNames.preferFlat(pc)),
                          let notes = Self.notes(chord, rootString: s, span: o.span, maxFret: o.maxFret) else { continue }
                    result.append(Card(key: Self.itemKey(q, rootString: s, root: chord.root), deckID: id,
                                       content: .arpeggio(ArpeggioPrompt(chord: chord, rootString: s, span: o.span, notes: notes))))
                }
            }
        }
        return result
    }

    /// Chord tones ascending from the root, within a box of root fret −1…+4, moving to higher strings.
    static func notes(_ chord: Chord, rootString: Int, span: ArpeggioSpan, maxFret: Int, tuning: Tuning = .standard) -> [FretNote]? {
        let open = tuning.openMidi(string: rootString)
        var f = PitchClass(chord.root.pitchClass.value - open).value
        let pcs = Set(chord.pitchClasses)
        while f <= maxFret {
            let box = max(0, f - 1)...min(maxFret, f + 4)
            let rootMidi = open + f
            let top = rootMidi + 12 * span.octaves
            var last = rootMidi - 1
            var result: [FretNote] = []
            for s in stride(from: rootString, through: 1, by: -1) {
                for fret in box {
                    let midi = tuning.openMidi(string: s) + fret
                    let pc = PitchClass(midi)
                    guard pcs.contains(pc), midi > last, midi <= top else { continue }
                    if s == rootString && result.isEmpty && midi != rootMidi { continue }
                    result.append(FretNote(position: FretPosition(string: s, fret: fret), midi: midi,
                                           spelling: chord.spelling(for: pc) ?? chord.root, degree: chord.degreeLabel(for: pc) ?? ""))
                    last = midi
                }
            }
            if result.count >= chord.tones.count + 1 { return result }
            f += 12
        }
        return nil
    }

    /// Same quality ×0.5; same root ×0.5.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.arpeggio, let p = recent.back(0)?.arpeggio else { return 1 }
        var penalty = 1.0
        if c.chord.quality == p.chord.quality { penalty *= 0.5 }
        if c.chord.root.pitchClass == p.chord.root.pitchClass { penalty *= 0.5 }
        return penalty
    }
}
