/// Broad subject a deck belongs to (used for grouping in the UI).
public enum Subject: String, Codable, Sendable, CaseIterable {
    case music, korean
}

/// Deck-specific options. Each deck accepts exactly one case.
///
/// **Persisted format — frozen.** Wire shape: `{"fretboard":{"_0":{…}}}` / `{"vocab":{"_0":{…}}}`
/// (the legacy synthesised shape, now hand-written). Do not rename cases or change payloads without
/// adding a legacy decode path and updating `PersistedFormatCheck`. New cases are fine.
public enum DeckOptions: Hashable, Codable, Sendable {
    case fretboard(FretboardOptions)
    case vocab(VocabOptions)

    private enum CodingKeys: String, CodingKey { case fretboard, vocab }
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
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .fretboard(o):
            var p = c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .fretboard)
            try p.encode(o, forKey: ._0)
        case let .vocab(o):
            var p = c.nestedContainer(keyedBy: PayloadKeys.self, forKey: .vocab)
            try p.encode(o, forKey: ._0)
        }
    }

    public var fretboard: FretboardOptions? {
        if case let .fretboard(o) = self { return o }
        return nil
    }

    public var vocab: VocabOptions? {
        if case let .vocab(o) = self { return o }
        return nil
    }

    /// Default options for a deck id, used when persisted options can't be decoded.
    /// Temporary closed switch; replaced by a deck registry in M2 (F10).
    public static func fallback(for id: DeckID) -> DeckOptions {
        id == FretboardNotesDeck.deckID ? .fretboard(FretboardOptions()) : .vocab(VocabOptions())
    }
}

/// A source of cards. Generators (fretboard) and loaders (vocab JSON) both conform.
public protocol Deck: Sendable {
    var id: DeckID { get }
    var title: String { get }
    var subtitle: String { get }
    var subject: Subject { get }
    /// Options used when the user has never configured this deck.
    var defaultOptions: DeckOptions { get }
    /// All cards available under the given options.
    func cards(options: DeckOptions) -> [Card]
    /// Anti-pattern penalty in (0, 1]; 1 = no penalty. `recent` is oldest → newest.
    func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double
    /// Introduction ordering for unseen cards (lower first). `nil` = no gating.
    func introductionRank(of card: Card) -> Int?
    /// Final presentation tweak right before a card is shown (e.g. random accidental spelling).
    func present(_ card: Card, using rng: inout SplitMix64) -> Card
}

public extension Deck {
    func introductionRank(of card: Card) -> Int? { nil }
    func present(_ card: Card, using rng: inout SplitMix64) -> Card { card }
}
