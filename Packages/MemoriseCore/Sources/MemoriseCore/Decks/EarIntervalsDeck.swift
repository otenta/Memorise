/// Options for the interval ear-training deck.
public struct EarIntervalOptions: Hashable, Codable, Sendable {
    public var intervals: Set<Interval>
    public var mode: EarMode
    /// MIDI range of the lower note.
    public var rootRange: ClosedRange<Int>

    public init(intervals: Set<Interval> = Interval.defaultSet, mode: EarMode = .ascending, rootRange: ClosedRange<Int> = 48...67) {
        self.intervals = intervals
        self.mode = mode
        self.rootRange = rootRange
    }

    private enum CodingKeys: String, CodingKey { case intervals, mode, rootRange }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EarIntervalOptions()
        intervals = c.tolerant(Set<Interval>.self, .intervals, d.intervals)
        mode = c.tolerant(EarMode.self, .mode, d.mode)
        rootRange = c.tolerant(ClosedRange<Int>.self, .rootRange, d.rootRange)
    }

    /// `intervals` is written sorted for deterministic output.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(intervals.sorted(), forKey: .intervals)
        try c.encode(mode, forKey: .mode)
        try c.encode(rootRange, forKey: .rootRange)
    }
}

/// "Hear it, name it."
public struct EarIntervalsDeck: Deck {
    public static let deckID: DeckID = "music.ear.intervals"

    public let id: DeckID = EarIntervalsDeck.deckID
    public let kind = DeckKind.earIntervals
    public let title = "Interval Ear"
    public let subtitle = "Hear it, name it"
    public let subject = Subject.music

    public init() {}

    public var defaultOptions: DeckOptions { .earIntervals(EarIntervalOptions()) }

    /// `"ear:M3:asc"`.
    public static func itemKey(_ interval: Interval, mode: EarMode) -> ItemKey {
        ItemKey("ear:\(interval.rawValue):\(mode.rawValue)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .earIntervals(o) = options, !o.rootRange.isEmpty else { return [] }
        return o.intervals.sorted().map { i in
            Card(key: Self.itemKey(i, mode: o.mode), deckID: id,
                 content: .earInterval(EarIntervalPrompt(interval: i, mode: o.mode, rootMidi: o.rootRange.lowerBound)))
        }
    }

    /// Random root in `rootRange`.
    public func present(_ card: Card, options: DeckOptions, using rng: inout SplitMix64) -> Card {
        guard let p = card.earInterval, let o = options.earIntervals, !o.rootRange.isEmpty else { return card }
        return card.with(.earInterval(EarIntervalPrompt(interval: p.interval, mode: p.mode, rootMidi: Int.random(in: o.rootRange, using: &rng))))
    }

    /// Same interval as previous ×0.35.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.earInterval, let prev = recent.back(0)?.earInterval else { return 1 }
        return prev.interval == c.interval ? 0.35 : 1
    }
}
