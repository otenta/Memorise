/// Options for Scales & modes.
public struct ScaleOptions: Hashable, Codable, Sendable {
    public static let defaultTypes: Set<ScaleType> = [
        .major, .naturalMinor, .majorPentatonic, .minorPentatonic, .blues,
        .ionian, .dorian, .phrygian, .lydian, .mixolydian, .aeolian, .locrian,
    ]

    public var types: Set<ScaleType>
    public var systems: Set<ScaleSystem>
    public var tonics: Set<PitchClass>
    public var maxFret: Int

    public init(
        types: Set<ScaleType> = ScaleOptions.defaultTypes,
        systems: Set<ScaleSystem> = Set(ScaleSystem.allCases),
        tonics: Set<PitchClass> = RootNames.all,
        maxFret: Int = 17
    ) {
        self.types = types
        self.systems = systems
        self.tonics = tonics
        self.maxFret = maxFret
    }

    private enum CodingKeys: String, CodingKey { case types, systems, tonics, maxFret }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScaleOptions()
        types = c.tolerant(Set<ScaleType>.self, .types, d.types)
        systems = c.tolerant(Set<ScaleSystem>.self, .systems, d.systems)
        tonics = c.tolerant(Set<PitchClass>.self, .tonics, d.tonics)
        maxFret = c.tolerant(Int.self, .maxFret, d.maxFret)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sortedRaw(types), forKey: .types)
        try c.encode(sortedRaw(systems), forKey: .systems)
        try c.encode(tonics.sorted(), forKey: .tonics)
        try c.encode(maxFret, forKey: .maxFret)
    }
}

/// "A minor pentatonic · box 1" / "D Dorian · 3NPS position 2".
public struct ScalesDeck: Deck {
    public static let deckID: DeckID = "music.scales"

    public let id: DeckID = ScalesDeck.deckID
    public let kind = DeckKind.scales
    public let title = "Scales & Modes"
    public let subtitle = "Boxes and 3-notes-per-string positions"
    public let subject = Subject.music
    public let group = DeckGroup.scales

    public init() {}

    public var defaultOptions: DeckOptions { .scales(ScaleOptions()) }

    public static func itemKey(_ type: ScaleType, _ system: ScaleSystem, position: Int, tonic: NoteSpelling) -> ItemKey {
        ItemKey("scale:\(type.rawValue):\(system.rawValue):p\(position):\(tonic.ascii)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .scales(o) = options else { return [] }
        var result: [Card] = []
        for type in ScaleType.allCases where o.types.contains(type) {
            let system: ScaleSystem = type.isHeptatonic ? .threeNPS : .box
            guard o.systems.contains(system) else { continue }
            let positions = system == .box ? 5 : 7
            for pc in o.tonics.sorted() {
                guard let scale = Scale.spelled(pc, type) else { continue }
                for n in 1...positions {
                    let notes = system == .box ? Self.box(scale, position: n) : Self.threeNPS(scale, position: n)
                    guard let notes, notes.allSatisfy({ $0.position.fret <= o.maxFret }) else { continue }
                    result.append(Card(key: Self.itemKey(type, system, position: n, tonic: scale.tonic), deckID: id,
                                       content: .scale(ScalePrompt(scale: scale, system: system, position: n, notes: notes))))
                }
            }
        }
        return result
    }

    // MARK: Generators

    /// `perString` consecutive scale notes per string, starting on degree `position` on string 6.
    static func positionNotes(_ scale: Scale, pcs: [PitchClass], position: Int, perString: Int, tuning: Tuning = .standard) -> [FretNote]? {
        guard position >= 1, position <= pcs.count else { return nil }
        let set = Set(pcs)
        let open6 = tuning.openMidi(string: 6)
        var midi = open6 + PitchClass(pcs[position - 1].value - open6).value
        var placed: [(string: Int, midi: Int)] = []
        for s in stride(from: 6, through: 1, by: -1) {
            for _ in 0..<perString {
                placed.append((s, midi))
                repeat { midi += 1 } while !set.contains(PitchClass(midi))
            }
        }
        var frets = placed.map { $0.midi - tuning.openMidi(string: $0.string) }
        if frets.contains(where: { $0 < 0 }) {
            frets = frets.map { $0 + 12 }
            placed = placed.map { ($0.string, $0.midi + 12) }
        }
        return zip(placed, frets).map { p, f in
            let pc = PitchClass(p.midi)
            return FretNote(position: FretPosition(string: p.string, fret: f), midi: p.midi,
                            spelling: scale.spelling(for: pc) ?? scale.tonic, degree: scale.degreeLabel(for: pc) ?? "")
        }
    }

    /// Pentatonic/blues box: 2 notes per string; blues adds the ♭5 inside the box.
    static func box(_ scale: Scale, position: Int, tuning: Tuning = .standard) -> [FretNote]? {
        let pcs = scale.type.boxDegrees.map { scale.tonic.pitchClass.transposed(by: $0.semitones) }
        guard var notes = positionNotes(scale, pcs: pcs, position: position, perString: 2, tuning: tuning) else { return nil }
        if scale.type == .blues {
            let b5 = scale.tonic.pitchClass.transposed(by: 6)
            let frets = notes.map(\.position.fret)
            let window = frets.min()!...frets.max()!
            for s in 1...6 {
                for f in window where Fretboard.pitchClass(string: s, fret: f, tuning: tuning) == b5 {
                    let midi = Fretboard.midi(string: s, fret: f, tuning: tuning)
                    notes.append(FretNote(position: FretPosition(string: s, fret: f), midi: midi,
                                          spelling: scale.spelling(for: b5) ?? scale.tonic, degree: "♭5"))
                }
            }
            notes.sort { ($0.midi, -$0.position.string) < ($1.midi, -$1.position.string) }
        }
        return notes
    }

    /// Three consecutive scale notes per string.
    static func threeNPS(_ scale: Scale, position: Int, tuning: Tuning = .standard) -> [FretNote]? {
        positionNotes(scale, pcs: scale.pitchClasses, position: position, perString: 3, tuning: tuning)
    }

    /// Same type ×0.4; same tonic ×0.5; same position ×0.6.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.scale, let p = recent.back(0)?.scale else { return 1 }
        var penalty = 1.0
        if c.scale.type == p.scale.type { penalty *= 0.4 }
        if c.scale.tonic.pitchClass == p.scale.tonic.pitchClass { penalty *= 0.5 }
        if c.position == p.position { penalty *= 0.6 }
        return penalty
    }

    /// Pentatonic first, then major/minor, then modes; lower positions first.
    public func introductionRank(of card: Card) -> Int? {
        guard let s = card.scale else { return nil }
        return s.scale.type.introductionTier * 10 + s.position
    }
}
