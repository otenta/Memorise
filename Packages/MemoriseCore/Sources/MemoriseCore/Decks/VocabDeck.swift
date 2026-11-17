/// A vocabulary deck backed by a `VocabDeckFile`.
public struct VocabDeck: Deck {
    public let id: DeckID
    public let kind = DeckKind.vocab
    public let title: String
    public let subtitle: String
    public let subject: Subject
    /// Visible entries in rank order (hidden duplicates excluded, R7-F7).
    public let entries: [VocabEntry]
    /// Entry ids hidden because an earlier deck owns the same headword (R7-F7). The JSON and ids
    /// are untouched; their stats stay in the store, unused.
    public let hiddenEntryIDs: Set<String>
    /// Every distinct tag, sorted.
    public let allTags: [String]

    public init(file: VocabDeckFile) { self.init(file: file, hiddenEntryIDs: []) }

    public init(file: VocabDeckFile, hiddenEntryIDs: Set<String>) {
        id = DeckID(file.deckId)
        title = file.title
        subtitle = file.subtitle
        subject = file.subject
        self.hiddenEntryIDs = hiddenEntryIDs
        let visible = hiddenEntryIDs.isEmpty ? file.entries : file.entries.filter { !hiddenEntryIDs.contains($0.id) }
        entries = visible.sorted { $0.rank < $1.rank }
        allTags = Array(Set(visible.flatMap(\.tags))).sorted()
    }

    public var defaultOptions: DeckOptions { .vocab(VocabOptions()) }

    /// `"<entryId>#<direction>"`.
    public static func itemKey(entryID: String, direction: VocabDirection) -> ItemKey {
        ItemKey("\(entryID)#\(direction.rawValue)")
    }

    public func cards(options: DeckOptions) -> [Card] {
        guard case let .vocab(o) = options else { return [] }
        let directions = o.direction.directions
        var result: [Card] = []
        result.reserveCapacity(entries.count * directions.count)
        for entry in entries where o.tags.isEmpty || entry.tags.contains(where: o.tags.contains) {
            for d in directions {
                result.append(Card(
                    key: Self.itemKey(entryID: entry.id, direction: d),
                    deckID: id,
                    content: .vocab(VocabPrompt(entry: entry, direction: d))
                ))
            }
        }
        return result
    }

    public func introductionRank(of card: Card) -> Int? { card.vocab?.entry.rank }

    public func newPerSession(options: DeckOptions) -> Int? { options.vocab?.newPerSession }

    /// The entry's other directions (R7-F1).
    public func siblingKeys(of card: Card) -> [ItemKey] {
        guard let v = card.vocab else { return [] }
        return VocabDirection.allCases.compactMap {
            $0 == v.direction ? nil : Self.itemKey(entryID: v.entry.id, direction: $0)
        }
    }

    /// Same entry (other direction) as previous ×0.1; tag shared with both of the previous 2 cards ×0.7.
    public func patternPenalty(candidate: Card, recent: ArraySlice<Card>) -> Double {
        guard let c = candidate.vocab else { return 1 }
        var penalty = 1.0
        guard let prev = recent.last?.vocab else { return penalty }
        if prev.entry.id == c.entry.id { penalty *= 0.1 }
        if recent.count >= 2, !c.entry.tags.isEmpty,
           let back2 = recent[recent.index(recent.endIndex, offsetBy: -2)].vocab,
           c.entry.tags.contains(where: { prev.entry.tags.contains($0) && back2.entry.tags.contains($0) }) {
            penalty *= 0.7
        }
        return penalty
    }
}

/// Stable FNV-1a 64-bit hash (never `hashValue`, which is randomised per launch).
@inlinable func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 {
        h ^= UInt64(b)
        h &*= 0x0000_0100_0000_01b3
    }
    return h
}

/// Introduction order for decks derived from vocab decks (R7-F7): round-robin across source decks,
/// each source in a fixed shuffle seeded from the derived deck's id, so derived decks don't all
/// start with Core 1's top words. Stable across launches and builds.
enum DerivedIntroductionOrder {
    /// `groups` are the source decks' words, in source order. Returns all words, interleaved.
    static func interleave<T>(_ groups: [(sourceID: String, items: [T])], derivedID: DeckID) -> [T] {
        let shuffled = groups.map { g -> [T] in
            var rng = SplitMix64(seed: stableHash(derivedID.raw + "|" + g.sourceID))
            return fixedShuffle(g.items, using: &rng)
        }
        var out: [T] = []
        out.reserveCapacity(shuffled.reduce(0) { $0 + $1.count })
        let longest = shuffled.map(\.count).max() ?? 0
        for i in 0..<longest {
            for g in shuffled where i < g.count { out.append(g[i]) }
        }
        return out
    }

    /// Fisher–Yates with our own index draw, so the order never depends on the standard library's
    /// shuffle implementation.
    static func fixedShuffle<T>(_ items: [T], using rng: inout SplitMix64) -> [T] {
        var a = items
        guard a.count > 1 else { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            let j = Int(rng.next().multipliedFullWidth(by: UInt64(i + 1)).high)
            a.swapAt(i, j)
        }
        return a
    }
}
