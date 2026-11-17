/// Broad subject a deck belongs to (used for grouping in the UI).
public enum Subject: String, Codable, Sendable, CaseIterable {
    case music, korean
}

/// The kind of a deck: selects its UI provider. Several decks may share a kind (e.g. vocab).
public struct DeckKind: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let fretboardNotes = DeckKind(rawValue: "fretboardNotes")
    public static let vocab = DeckKind(rawValue: "vocab")
    public static let fretboardNames = DeckKind(rawValue: "fretboardNames")
    public static let fretboardFindAll = DeckKind(rawValue: "fretboardFindAll")
    public static let fretboardIntervals = DeckKind(rawValue: "fretboardIntervals")
    public static let earIntervals = DeckKind(rawValue: "earIntervals")
    public static let chordsPlay = DeckKind(rawValue: "chordsPlay")
    public static let chordsName = DeckKind(rawValue: "chordsName")
    public static let triads = DeckKind(rawValue: "triads")
    public static let arpeggios = DeckKind(rawValue: "arpeggios")
    public static let scales = DeckKind(rawValue: "scales")
    public static let keySignatures = DeckKind(rawValue: "keySignatures")
    public static let diatonic = DeckKind(rawValue: "diatonic")
    public static let progressions = DeckKind(rawValue: "progressions")
    public static let circleOfFifths = DeckKind(rawValue: "circleOfFifths")
    public static let hangulReading = DeckKind(rawValue: "hangulReading")
    public static let koreanParticles = DeckKind(rawValue: "koreanParticles")
    public static let koreanConjugation = DeckKind(rawValue: "koreanConjugation")
}

/// Display-only Home sub-headers (PLAN_M3 §3.4). Not persisted.
public enum DeckGroup {
    public static let fretboard = "Fretboard"
    public static let ear = "Ear"
    public static let chords = "Chords & shapes"
    public static let scales = "Scales"
    public static let theory = "Theory"
}

/// Deck-specific options. Each deck accepts exactly one case.
///
/// **Persisted format — frozen.** Wire shape: `{"<case>":{"_0":{…}}}` (the legacy synthesised
/// shape, now hand-written). Do not rename cases or change payloads without adding a legacy decode
/// path and updating `PersistedFormatCheck`. New cases are fine.
public enum DeckOptions: Hashable, Codable, Sendable {
    case fretboard(FretboardOptions)
    case vocab(VocabOptions)
    case intervals(IntervalOptions)
    case earIntervals(EarIntervalOptions)
    case chords(ChordOptions)
    case triads(TriadOptions)
    case arpeggios(ArpeggioOptions)
    case scales(ScaleOptions)
    case keySignatures(KeySigOptions)
    case diatonic(DiatonicOptions)
    case progressions(ProgressionOptions)
    case circle(CircleOptions)
    case hangulReading(HangulReadingOptions)
    case particles(ParticleOptions)
    case conjugation(ConjugationOptions)

    private enum CodingKeys: String, CodingKey { case fretboard, vocab, intervals, earIntervals, chords, triads, arpeggios, scales, keySignatures, diatonic, progressions, circle, hangulReading, particles, conjugation }
    private enum PayloadKeys: String, CodingKey { case _0 }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.allKeys.count == 1, let key = c.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "DeckOptions needs exactly one case key"))
        }
        let payload = try c.nestedContainer(keyedBy: PayloadKeys.self, forKey: key)
        switch key {
        case .fretboard: self = .fretboard(try payload.decode(FretboardOptions.self, forKey: ._0))
        case .vocab: self = .vocab(try payload.decode(VocabOptions.self, forKey: ._0))
        case .intervals: self = .intervals(try payload.decode(IntervalOptions.self, forKey: ._0))
        case .earIntervals: self = .earIntervals(try payload.decode(EarIntervalOptions.self, forKey: ._0))
        case .chords: self = .chords(try payload.decode(ChordOptions.self, forKey: ._0))
        case .triads: self = .triads(try payload.decode(TriadOptions.self, forKey: ._0))
        case .arpeggios: self = .arpeggios(try payload.decode(ArpeggioOptions.self, forKey: ._0))
        case .scales: self = .scales(try payload.decode(ScaleOptions.self, forKey: ._0))
        case .keySignatures: self = .keySignatures(try payload.decode(KeySigOptions.self, forKey: ._0))
        case .diatonic: self = .diatonic(try payload.decode(DiatonicOptions.self, forKey: ._0))
        case .progressions: self = .progressions(try payload.decode(ProgressionOptions.self, forKey: ._0))
        case .circle: self = .circle(try payload.decode(CircleOptions.self, forKey: ._0))
        case .hangulReading: self = .hangulReading(try payload.decode(HangulReadingOptions.self, forKey: ._0))
        case .particles: self = .particles(try payload.decode(ParticleOptions.self, forKey: ._0))
        case .conjugation: self = .conjugation(try payload.decode(ConjugationOptions.self, forKey: ._0))
        }
    }

    /// The one place that maps a case to its wire key and payload (R4-8). `encode` and `caseKey`
    /// both derive from it, so a case can't be written under another case's key.
    private var payload: (key: CodingKeys, value: any Encodable) {
        switch self {
        case let .fretboard(o): (.fretboard, o)
        case let .vocab(o): (.vocab, o)
        case let .intervals(o): (.intervals, o)
        case let .earIntervals(o): (.earIntervals, o)
        case let .chords(o): (.chords, o)
        case let .triads(o): (.triads, o)
        case let .arpeggios(o): (.arpeggios, o)
        case let .scales(o): (.scales, o)
        case let .keySignatures(o): (.keySignatures, o)
        case let .diatonic(o): (.diatonic, o)
        case let .progressions(o): (.progressions, o)
        case let .circle(o): (.circle, o)
        case let .hangulReading(o): (.hangulReading, o)
        case let .particles(o): (.particles, o)
        case let .conjugation(o): (.conjugation, o)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let (key, value) = payload
        var p = c.nestedContainer(keyedBy: PayloadKeys.self, forKey: key)
        try p.encode(value, forKey: ._0)
    }

    public var fretboard: FretboardOptions? {
        if case let .fretboard(o) = self { return o }
        return nil
    }

    public var vocab: VocabOptions? {
        if case let .vocab(o) = self { return o }
        return nil
    }

    public var intervals: IntervalOptions? {
        if case let .intervals(o) = self { return o }
        return nil
    }

    public var earIntervals: EarIntervalOptions? {
        if case let .earIntervals(o) = self { return o }
        return nil
    }

    public var chords: ChordOptions? {
        if case let .chords(o) = self { return o }
        return nil
    }

    public var triads: TriadOptions? {
        if case let .triads(o) = self { return o }
        return nil
    }

    public var arpeggios: ArpeggioOptions? {
        if case let .arpeggios(o) = self { return o }
        return nil
    }

    public var scales: ScaleOptions? {
        if case let .scales(o) = self { return o }
        return nil
    }

    public var keySignatures: KeySigOptions? {
        if case let .keySignatures(o) = self { return o }
        return nil
    }

    public var diatonic: DiatonicOptions? {
        if case let .diatonic(o) = self { return o }
        return nil
    }

    public var progressions: ProgressionOptions? {
        if case let .progressions(o) = self { return o }
        return nil
    }

    public var circle: CircleOptions? {
        if case let .circle(o) = self { return o }
        return nil
    }

    public var hangulReading: HangulReadingOptions? {
        if case let .hangulReading(o) = self { return o }
        return nil
    }

    public var particles: ParticleOptions? {
        if case let .particles(o) = self { return o }
        return nil
    }

    public var conjugation: ConjugationOptions? {
        if case let .conjugation(o) = self { return o }
        return nil
    }

    private var caseKey: CodingKeys { payload.key }

    /// Wire key of this case (`"fretboard"`, `"vocab"`, …), e.g. for round-trip checks.
    public var wireKey: String { caseKey.stringValue }

    /// Whether both values are the same case (payloads ignored).
    public func sameCase(as other: DeckOptions) -> Bool { caseKey == other.caseKey }

    /// Tuning of fretboard-based options, if any.
    public var tuning: TuningID? {
        switch self {
        case let .fretboard(o): o.tuning
        case let .intervals(o): o.tuning
        default: nil
        }
    }

    /// Default options for a deck id, used when persisted options can't be decoded.
    public static func fallback(for id: DeckID) -> DeckOptions {
        BuiltInDecks.defaultOptions(for: id)
    }
}

/// A source of cards. Generators (fretboard) and loaders (vocab JSON) both conform.
public protocol Deck: Sendable {
    var id: DeckID { get }
    var kind: DeckKind { get }
    var title: String { get }
    var subtitle: String { get }
    var subject: Subject { get }
    /// Home sub-header (display only; `""` = none).
    var group: String { get }
    /// Options used when the user has never configured this deck.
    var defaultOptions: DeckOptions { get }
    /// All cards available under the given options.
    func cards(options: DeckOptions) -> [Card]
    /// Anti-pattern penalty in (0, 1]; 1 = no penalty. `recent` is oldest → newest.
    func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double
    /// Introduction ordering for unseen cards (lower first). `nil` = no gating.
    func introductionRank(of card: Card) -> Int?
    /// Unseen cards allowed per session (`nil` = no limit).
    func newPerSession(options: DeckOptions) -> Int?
    /// Final presentation step right before a card is shown (random spelling, root fret…).
    /// Must not change the card's key.
    func present(_ card: Card, options: DeckOptions, using rng: inout SplitMix64) -> Card
    /// Other cards that test the same thing (e.g. a vocab entry's other directions). The engine
    /// treats them as shown / resting together with `card` (R7-F1). Default: none.
    func siblingKeys(of card: Card) -> [ItemKey]
}

public extension Deck {
    /// Default kind: the deck id itself (R4-8). Real decks set a shared kind explicitly; the
    /// default keeps simple conformers (test doubles, previews) compiling. An unknown kind falls
    /// back to the generic UI provider.
    var kind: DeckKind { DeckKind(rawValue: id.raw) }
    var group: String { "" }
    func introductionRank(of card: Card) -> Int? { nil }
    func newPerSession(options: DeckOptions) -> Int? { nil }
    func present(_ card: Card, options: DeckOptions, using rng: inout SplitMix64) -> Card { card }
    func siblingKeys(of card: Card) -> [ItemKey] { [] }
}

extension ArraySlice {
    /// Element `n` positions before the last (0 = last), if present.
    @inlinable func back(_ n: Int) -> Element? {
        count > n ? self[index(endIndex, offsetBy: -1 - n)] : nil
    }
}
